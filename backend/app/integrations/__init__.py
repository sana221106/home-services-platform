"""Outbound third-party adapters.

Everything in this package talks to a system the platform does not own. Each
adapter is imported lazily from the service that needs it so that a missing or
unconfigured integration degrades to an explicit "not configured" state instead
of breaking application start-up (§135).

Adapters must never raise at import time, must never log credentials, and must
not be reachable from the Flutter client: the mobile app only ever talks to
FastAPI, and FastAPI is the sole holder of privileged credentials.
"""