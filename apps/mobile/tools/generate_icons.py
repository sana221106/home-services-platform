#!/usr/bin/env python3
"""Generate the canonical SVG icon set (§49).

Every icon is drawn on a 24x24 grid with a 2px stroke, round caps and round
joins, and uses ``currentColor`` so a single file serves both themes.

Run from ``apps/mobile``::

    python tools/generate_icons.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ICON_DIR = Path(__file__).resolve().parents[1] / "assets" / "icons"

TEMPLATE = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
    'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
    'stroke-linejoin="round">\n{body}\n</svg>\n'
)

ICONS: dict[str, str] = {
    "home": '  <path d="M3 10.5 12 3l9 7.5"/>\n  <path d="M5 9.6V20a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V9.6"/>\n  <path d="M9.5 21v-6h5v6"/>',
    "bell": '  <path d="M18 8a6 6 0 1 0-12 0c0 6-2 7-2 7h16s-2-1-2-7"/>\n  <path d="M13.7 20a2 2 0 0 1-3.4 0"/>',
    "faucet": '  <path d="M4 10h5a3 3 0 0 1 3 3v1"/>\n  <path d="M12 14v3a3 3 0 0 0 3 3h1a3 3 0 0 0 3-3v-1"/>\n  <circle cx="6.5" cy="6.5" r="2.5"/>\n  <path d="M9 6.5h4"/>',
    "bolt": '  <path d="M13 2 4.5 13.5H11l-1 8.5 9-12H12z"/>',
    "paint": '  <path d="M4 4h11v6H4z"/>\n  <path d="M9 10v3.5a2.5 2.5 0 0 0 2.5 2.5H15a2 2 0 0 0 2-2V10"/>\n  <path d="M12 21.5c0-1 .8-1.8 1.8-1.8s1.7.8 1.7 1.8c0 1.2-.8 2.2-1.7 2.8"/>',
    "camera": '  <path d="M3 8.5A1.5 1.5 0 0 1 4.5 7H7l1.5-2h7L17 7h2.5A1.5 1.5 0 0 1 21 8.5v10a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5z"/>\n  <circle cx="12" cy="13" r="3.6"/>',
    "pin": '  <path d="M12 21s7-6.2 7-11a7 7 0 1 0-14 0c0 4.8 7 11 7 11"/>\n  <circle cx="12" cy="10" r="2.6"/>',
    "clock": '  <circle cx="12" cy="12" r="9"/>\n  <path d="M12 7v5.2l3.2 2"/>',
    "chat": '  <path d="M21 12a8 8 0 0 1-8 8H8l-4 3v-5.5A8 8 0 0 1 8 4h5a8 8 0 0 1 8 8"/>\n  <path d="M9 11h6M9 14.5h4"/>',
    "orders": '  <path d="M6 3h9l4 4v14H6z"/>\n  <path d="M15 3v4h4"/>\n  <path d="M9.5 12h5M9.5 16h5"/>',
    "user": '  <circle cx="12" cy="8" r="4"/>\n  <path d="M4.5 20.5a7.5 7.5 0 0 1 15 0"/>',
    "back": '  <path d="M19 12H5"/>\n  <path d="M11 6 5 12l6 6"/>',
    "shield": '  <path d="M12 3 4.5 6v6c0 4.4 3.1 8.2 7.5 9 4.4-.8 7.5-4.6 7.5-9V6z"/>\n  <path d="M9 12.2l2.2 2.3L15.5 10"/>',
    "wallet": '  <path d="M3 7.5A2.5 2.5 0 0 1 5.5 5H18a1 1 0 0 1 1 1v2"/>\n  <path d="M3 7.5V18a2 2 0 0 0 2 2h14a1 1 0 0 0 1-1v-3"/>\n  <path d="M20 10.5h-4a1.5 1.5 0 0 0 0 3h4z"/>',
    "star": '  <path d="m12 3.5 2.6 5.5 5.9.8-4.3 4.2 1 6-5.2-2.9-5.2 2.9 1-6L3.5 9.8l5.9-.8z"/>',
    "wrench": '  <path d="M15.5 3a5.5 5.5 0 0 0-5.2 7.2L4 16.5a2 2 0 0 0 2.8 2.8l6.3-6.3A5.5 5.5 0 0 0 20.3 5l-3 3-2.3-.6-.6-2.3z"/>',
    "search": '  <circle cx="11" cy="11" r="7"/>\n  <path d="m20 20-3.6-3.6"/>',
    "check": '  <path d="m4.5 12.5 5 5 10-11"/>',
    "upload": '  <path d="M4 15v3.5A1.5 1.5 0 0 0 5.5 20h13a1.5 1.5 0 0 0 1.5-1.5V15"/>\n  <path d="M12 15.5V4"/>\n  <path d="m7.5 8 4.5-4.5L16.5 8"/>',
    "building": '  <path d="M4 21V4.5A1.5 1.5 0 0 1 5.5 3h8A1.5 1.5 0 0 1 15 4.5V21"/>\n  <path d="M15 10h4.5A1.5 1.5 0 0 1 21 11.5V21"/>\n  <path d="M2.5 21h19"/>\n  <path d="M7.5 7h4M7.5 11h4M7.5 15h4"/>',
    "alert": '  <path d="M12 3.5 21.5 20h-19z"/>\n  <path d="M12 9.5v4.5"/>\n  <circle cx="12" cy="17" r=".6" fill="currentColor"/>',
    "logout": '  <path d="M14 20H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h8"/>\n  <path d="M17 15.5 21.5 12 17 8.5"/>\n  <path d="M21 12H10"/>',
    "phone": '  <path d="M7 3.5h3l1.5 4-2 1.5a11 11 0 0 0 5.5 5.5l1.5-2 4 1.5v3a2 2 0 0 1-2.2 2A16.5 16.5 0 0 1 5 5.7 2 2 0 0 1 7 3.5"/>',
    "photoedit": '  <path d="M4 7.5A1.5 1.5 0 0 1 5.5 6H8l1.4-2h5.2L16 6h2.5A1.5 1.5 0 0 1 20 7.5v11a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18.5z"/>\n  <circle cx="12" cy="13" r="3.2"/>\n  <path d="M16.5 18.5 20 22"/>',
    "notif": '  <circle cx="12" cy="12" r="9"/>\n  <path d="M12 7.5v5"/>\n  <circle cx="12" cy="16.3" r=".7" fill="currentColor"/>',
    "card": '  <rect x="2.5" y="5" width="19" height="14" rx="2.5"/>\n  <path d="M2.5 10h19"/>\n  <path d="M6.5 14.5h4"/>',
    "trash": '  <path d="M4 7h16"/>\n  <path d="M9.5 7V4.5h5V7"/>\n  <path d="M6.5 7l1 13h9l1-13"/>\n  <path d="M10.5 11v5M13.5 11v5"/>',
    "edit": '  <path d="M5 19h3l10-10-3-3L5 16z"/>\n  <path d="M14.5 5.5l3 3"/>',
    "plus": '  <path d="M12 5v14M5 12h14"/>',
    "close": '  <path d="m6 6 12 12M18 6 6 18"/>',
    "history": '  <path d="M3.5 9A9 9 0 1 1 3 12"/>\n  <path d="M3 4.5V9h4.5"/>\n  <path d="M12 7.5V12l3.2 2"/>',
    "calendar": '  <rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/>\n  <path d="M3.5 10h17M8 3.5v3M16 3.5v3"/>',
    "doc": '  <path d="M6 3h8l4.5 4.5V21H6z"/>\n  <path d="M14 3v4.5h4.5"/>\n  <path d="M9 13h6M9 17h4"/>',
    "truck": '  <path d="M2.5 7h10v9h-10z"/>\n  <path d="M12.5 10.5h4l3 3V16h-7z"/>\n  <circle cx="6.5" cy="18" r="1.8"/>\n  <circle cx="16.5" cy="18" r="1.8"/>',
    "info": '  <circle cx="12" cy="12" r="9"/>\n  <path d="M12 11v5.5"/>\n  <circle cx="12" cy="7.8" r=".7" fill="currentColor"/>',
    "quote": '  <path d="M9 6.5C6.5 8 5 10 5 13v4.5h5V12H7.8c.3-1.6 1.3-2.8 2.9-3.7z"/>\n  <path d="M19 6.5c-2.5 1.5-4 3.5-4 6.5v4.5h5V12h-2.2c.3-1.6 1.3-2.8 2.9-3.7z"/>',
    "pin_add": '  <path d="M12 21s7-6.2 7-11a7 7 0 1 0-14 0c0 4.8 7 11 7 11"/>\n  <circle cx="12" cy="10" r="2.6"/>\n  <path d="M12 17v6M9 20h6"/>',
    "sparkle": '  <path d="m12 3 1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/>\n  <path d="M18.5 15.5l.7 2 2 .7-2 .7-.7 2-.7-2-2-.7 2-.7z"/>',
    "tool_box": '  <rect x="2.5" y="7.5" width="19" height="13" rx="2"/>\n  <path d="M8.5 7.5V6a2 2 0 0 1 2-2h3a2 2 0 0 1 2 2v1.5"/>\n  <path d="M2.5 12.5h19"/>',
    "image": '  <rect x="3.5" y="4.5" width="17" height="15" rx="2.5"/>\n  <circle cx="8.5" cy="9.5" r="1.6"/>\n  <path d="m4 17 4.5-4.5 3.5 3.5 3-3L20 17"/>',
    "receipt": '  <path d="M5 3.5h14v17l-2.3-1.6-2.3 1.6-2.4-1.6L9.6 20.5 7.3 18.9 5 20.5z"/>\n  <path d="M9 8.5h6M9 12.5h6"/>',
    "send": '  <path d="M21 3 10.5 13.5"/>\n  <path d="M21 3 14.5 21l-4-7.5-7.5-4z"/>',
    "attach": '  <path d="M20 11.5 12 19.5a5 5 0 0 1-7-7l8.5-8.5a3.5 3.5 0 0 1 5 5l-8.5 8.5a2 2 0 0 1-3-3l7.8-7.8"/>',
    "flag": '  <path d="M5 21V4"/>\n  <path d="M5 4.5h12l-2.5 4 2.5 4H5"/>',
    "eye": '  <path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12"/>\n  <circle cx="12" cy="12" r="3"/>',
}


def main() -> int:
    ICON_DIR.mkdir(parents=True, exist_ok=True)
    for name, body in ICONS.items():
        (ICON_DIR / f"{name}.svg").write_text(TEMPLATE.format(body=body), encoding="utf-8")
    print(f"wrote {len(ICONS)} icons to {ICON_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
