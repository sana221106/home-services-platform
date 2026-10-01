"""Optional AI fault classification (§82-§84, §128, §135).

Rules that are not negotiable:

* the client never talks to a model provider — Flutter → FastAPI → provider;
* no provider key ever lives in Flutter;
* the service degrades to an explicit ``available=False`` result instead of
  raising, because the app must work with AI down;
* AI never sets a price, dispatches a technician, moves money or closes a
  complaint (§84);
* every prediction is persisted with both the model output and the later human
  decision, never overwritten (§69).
"""

from __future__ import annotations

import json
import re
import uuid
from dataclasses import dataclass
from decimal import Decimal
from typing import Any

import httpx
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import IntegrationUnavailableError
from app.core.logging import get_logger
from app.db.models.catalog import ProblemType, ServiceCategory
from app.db.models.intelligence import AiClassification, MaintenanceRecord
from app.utils.time import now_utc

log = get_logger(__name__)

AI_SYSTEM_PROMPT = (
    "You classify home-maintenance requests. Reply with STRICT JSON only, no prose. "
    "Schema: {\"predicted_category\": str, \"predicted_problem\": str, \"confidence\": float, "
    "\"inspection_recommended\": bool}. "
    "Use only these categories: plumbing, electrical, painting. "
    "Never output a price, a technician name, or a payment decision."
)

_CONFIDENCE_RE = re.compile(r"(-?\d+(?:\.\d+)?)")


@dataclass(frozen=True, slots=True)
class ClassificationResult:
    predicted_category: str
    predicted_problem: str
    confidence: float
    inspection_recommended: bool
    model_provider: str
    model_name: str
    model_version: str | None
    available: bool
    reason_ar: str | None = None


def is_configured() -> bool:
    return settings.ai_configured


def _known_categories(session: Session) -> list[dict[str, Any]]:
    rows = session.execute(
        select(ServiceCategory, ProblemType)
        .join(ProblemType, ProblemType.category_id == ServiceCategory.id, isouter=True)
        .where(ServiceCategory.is_active.is_(True))
    ).all()
    return [
        {
            "category_code": category.code,
            "category_name_ar": category.name_ar,
            "problem_code": problem.code if problem is not None else None,
            "problem_name_ar": problem.name_ar if problem is not None else None,
        }
        for category, problem in rows
    ]


def _history_context(session: Session, *, property_id: uuid.UUID | None, limit: int = 5) -> str:
    if property_id is None:
        return ""
    rows = session.execute(
        select(MaintenanceRecord)
        .where(MaintenanceRecord.property_id == property_id)
        .order_by(MaintenanceRecord.served_on.desc())
        .limit(limit)
    ).scalars()
    if not rows:
        return ""
    lines = [
        f"- {record.served_on.date()} | {record.category_code}/{record.problem_code or '-'}"
        f" | {record.resolution or record.customer_description or ''}"
        for record in rows
    ]
    return "\n".join(lines)


def _parse_response(payload: Any) -> dict[str, Any]:
    """Validate the provider response against the expected schema (§84)."""
    if isinstance(payload, dict):
        choices = payload.get("choices")
        if isinstance(choices, list) and choices:
            message = choices[0].get("message") or {}
            content = message.get("content") or choices[0].get("text") or ""
        else:
            content = payload.get("output_text") or payload.get("content") or ""
    else:
        content = str(payload)

    if not isinstance(content, str):
        raise IntegrationUnavailableError("AI provider returned an unexpected payload.")

    match = re.search(r"\{.*\}", content, re.DOTALL)
    if match is None:
        raise IntegrationUnavailableError("AI provider did not return JSON.")

    try:
        data = json.loads(match.group(0))
    except json.JSONDecodeError as exc:
        raise IntegrationUnavailableError("AI provider returned malformed JSON.") from exc

    category = str(data.get("predicted_category") or "").strip().lower()
    problem = str(data.get("predicted_problem") or "").strip().lower()
    if not category or not problem:
        raise IntegrationUnavailableError("AI provider response is missing required fields.")

    raw_confidence = data.get("confidence", 0)
    try:
        confidence = float(raw_confidence)
    except (TypeError, ValueError):
        found = _CONFIDENCE_RE.search(str(raw_confidence))
        confidence = float(found.group(1)) if found else 0.0
    confidence = min(max(confidence, 0.0), 1.0)

    return {
        "predicted_category": category[:64],
        "predicted_problem": problem[:64],
        "confidence": confidence,
        "inspection_recommended": bool(data.get("inspection_recommended")),
    }


def classify(
    session: Session,
    *,
    problem_description: str,
    request_id: uuid.UUID | None = None,
    customer_id: uuid.UUID | None = None,
    property_id: uuid.UUID | None = None,
    category_code: str | None = None,
    problem_code: str | None = None,
    include_history: bool = True,
) -> tuple[ClassificationResult, AiClassification | None]:
    """Always returns. Never raises for an AI outage (§82)."""
    catalogue = _known_categories(session)
    payload_lines = [
        f"Problem description: {problem_description.strip()[:2000]}",
        f"Customer-selected category: {category_code or 'unknown'}",
        f"Customer-selected problem: {problem_code or 'unknown'}",
        "Available taxonomy:",
        json.dumps(catalogue, ensure_ascii=False),
    ]
    if include_history:
        history = _history_context(session, property_id=property_id)
        if history:
            payload_lines.append(f"Property maintenance history:\n{history}")

    record = AiClassification(
        request_id=request_id,
        customer_id=customer_id,
        input_text_reference=problem_description[:4000],
        input_media_references=None,
        model_provider=settings.ai_provider,
        model_name=settings.ai_model,
    )

    if not is_configured():
        record.error_code = "AI_NOT_CONFIGURED"
        session.add(record)
        session.flush()
        return (
            ClassificationResult(
                predicted_category="unknown",
                predicted_problem="unknown",
                confidence=0.0,
                inspection_recommended=False,
                model_provider="none",
                model_name="none",
                model_version=None,
                available=False,
                reason_ar="خدمة التصنيف الذكي غير مفعّلة حاليًا. يمكنك المتابعة بدونها.",
            ),
            record,
        )

    try:
        parsed = _call_provider("\n".join(payload_lines))
    except (httpx.HTTPError, IntegrationUnavailableError) as exc:
        log.warning("ai_classify_failed", error=str(exc)[:200])
        record.error_code = "AI_PROVIDER_ERROR"
        session.add(record)
        session.flush()
        return (
            ClassificationResult(
                predicted_category="unknown",
                predicted_problem="unknown",
                confidence=0.0,
                inspection_recommended=False,
                model_provider=settings.ai_provider,
                model_name=settings.ai_model,
                model_version=None,
                available=False,
                reason_ar="تعذر الوصول لخدمة التحليل الذكي. يمكنك المتابعة بدونه.",
            ),
            record,
        )

    record.predicted_category = parsed["predicted_category"]
    record.predicted_problem = parsed["predicted_problem"]
    record.confidence = Decimal(str(parsed["confidence"]))
    record.inspection_recommended = parsed["inspection_recommended"]
    session.add(record)
    session.flush()

    return (
        ClassificationResult(
            predicted_category=parsed["predicted_category"],
            predicted_problem=parsed["predicted_problem"],
            confidence=parsed["confidence"],
            inspection_recommended=parsed["inspection_recommended"],
            model_provider=settings.ai_provider,
            model_name=settings.ai_model,
            model_version=None,
            available=True,
        ),
        record,
    )


def _call_provider(prompt: str) -> dict[str, Any]:
    """Provider adapter. OpenAI-compatible chat-completions shape by default."""
    if settings.ai_base_url:
        url = f"{settings.ai_base_url.rstrip('/')}/chat/completions"
    else:
        url = "https://api.openai.com/v1/chat/completions"

    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {settings.ai_api_key.get_secret_value() if settings.ai_api_key else ''}",
    }
    body = {
        "model": settings.ai_model,
        "temperature": 0,
        "response_format": {"type": "json_object"},
        "messages": [
            {"role": "system", "content": AI_SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
    }
    with httpx.Client(timeout=httpx.Timeout(20.0, connect=5.0)) as client:
        response = client.post(url, headers=headers, json=body)
        response.raise_for_status()
        return _parse_response(response.json())


def apply_human_decision(
    session: Session,
    *,
    classification: AiClassification,
    staff_id: uuid.UUID,
    approved_category: str,
    approved_problem: str | None,
) -> AiClassification:
    """Preserve both the model's output and the human decision (§69)."""
    classification.human_approved_category = approved_category
    classification.human_approved_problem = approved_problem
    classification.reviewed_by_id = staff_id
    classification.reviewed_at = now_utc()
    classification.was_corrected = (
        approved_category != (classification.predicted_category or "")
        or (approved_problem or "") != (classification.predicted_problem or "")
    )
    session.flush()
    return classification


def latest_for_request(
    session: Session, *, request_id: uuid.UUID
) -> AiClassification | None:
    return session.execute(
        select(AiClassification)
        .where(AiClassification.request_id == request_id)
        .order_by(AiClassification.created_at.desc())
        .limit(1)
    ).scalar_one_or_none()
