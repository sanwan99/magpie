#!/usr/bin/env python3
"""Generate release-safe theme mascot PNGs into Assets.xcassets.

Usage:
    OPENAI_API_KEY=... Scripts/generate-theme-mascots.py

The Swift theme layer looks up these asset names first and falls back to
programmatic mascots when an asset is absent. Prompts intentionally avoid
direct character names and ask for original mascots that only echo broad color
and role cues.
"""

from __future__ import annotations

import base64
import json
import os
from pathlib import Path
from urllib import error, request


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "Resources" / "Assets.xcassets"
MODEL = os.environ.get("OPENAI_IMAGE_MODEL", "gpt-image-2")
ENDPOINT = os.environ.get("OPENAI_IMAGE_ENDPOINT", "https://api.openai.com/v1/images/generations")
SIZE = os.environ.get("OPENAI_IMAGE_SIZE", "1024x1024")
BACKGROUND = os.environ.get("OPENAI_IMAGE_BACKGROUND", "auto")


SYSTEM_STYLE = (
    "PNG mascot for a macOS clipboard app theme. "
    "Original release-safe character design, not a copy of any existing IP, "
    "no logos, no text, no watermark. Chibi half-body sticker, clean silhouette, "
    "soft cel-shaded vector-like anime influence, readable at 150 px, "
    "centered with padding, subtle rim light, simple quiet background, polished UI asset."
)


ASSETS = [
    (
        "ThemeForestLeft",
        "forest adventurer mascot, green cap silhouette, tunic, leaf charm, brave and quiet, emerald and brass palette",
    ),
    (
        "ThemeForestRight",
        "forest princess mascot, long golden hair, teal ceremonial dress, small geometric tiara, serene expression",
    ),
    (
        "ThemeHuskLeft",
        "tiny masked wanderer mascot, black cloak, ivory mask with small horn shapes, moonlit monochrome palette",
    ),
    (
        "ThemeHuskRight",
        "needle-wielding guardian mascot, crimson cloak, ivory horn-like hair ornaments, elegant agile pose",
    ),
    (
        "ThemeMistLeft",
        "silver-haired traveling mage mascot, sage-green coat, small star wand, calm ancient-fantasy mood",
    ),
    (
        "ThemeMistRight",
        "purple-haired apprentice mage mascot, lavender coat, small spellbook, reserved and observant",
    ),
    (
        "ThemeClubLeft",
        "energetic school club leader mascot, chestnut hair, red ribbon, gold star pin, confident pose",
    ),
    (
        "ThemeClubRight",
        "quiet bookish club member mascot, short blue hair, blue cardigan, small book, minimal expression",
    ),
    (
        "ThemeUnitLeft",
        "fiery pilot mascot, orange swept hair, red technical suit, yellow bolt detail, bold diagonal pose",
    ),
    (
        "ThemeUnitRight",
        "cool pilot mascot, pale blue bob haircut, light blue technical suit, circular scope detail, composed pose",
    ),
    (
        "ThemeInkLeft",
        "sharp-tongued stationery-themed mascot, violet swept hair, dark purple uniform, stapler charm, sleek pose",
    ),
    (
        "ThemeInkRight",
        "gentle bookish mascot, dark bob haircut, lavender outfit, glasses motif, soft paper charm",
    ),
    (
        "ThemeGiltLeft",
        "golden noble mascot, blonde hair, crimson and gold outfit, crown motif, refined confident expression",
    ),
    (
        "ThemeGiltRight",
        "small shadow noble mascot, dark hair, black and gold outfit, ring motif, playful elegant expression",
    ),
]


def asset_contents(filename: str) -> dict:
    return {
        "images": [
            {
                "filename": filename,
                "idiom": "universal",
                "scale": "1x",
            },
            {
                "idiom": "universal",
                "scale": "2x",
            },
            {
                "idiom": "universal",
                "scale": "3x",
            },
        ],
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }


def generate_png(api_key: str, prompt: str) -> bytes:
    payload = {
        "model": MODEL,
        "prompt": prompt,
        "size": SIZE,
        "n": 1,
        "background": BACKGROUND,
        "quality": "high",
        "output_format": "png",
        "response_format": "b64_json",
    }
    body = json.dumps(payload).encode("utf-8")
    req = request.Request(
        ENDPOINT,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )

    try:
        with request.urlopen(req, timeout=180) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"OpenAI image generation failed: {exc.code} {detail}") from exc

    try:
        encoded = data["data"][0]["b64_json"]
    except (KeyError, IndexError, TypeError) as exc:
        raise RuntimeError(f"Unexpected image response: {json.dumps(data)[:1000]}") from exc

    return base64.b64decode(encoded)


def write_asset(name: str, png: bytes) -> None:
    imageset = ASSET_ROOT / f"{name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    filename = f"{name}.png"
    (imageset / filename).write_bytes(png)
    (imageset / "Contents.json").write_text(
        json.dumps(asset_contents(filename), indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise SystemExit("OPENAI_API_KEY is required")

    ASSET_ROOT.mkdir(parents=True, exist_ok=True)
    for name, description in ASSETS:
        prompt = f"{SYSTEM_STYLE} Subject: {description}."
        print(f"Generating {name} with {MODEL}...")
        write_asset(name, generate_png(api_key, prompt))

    print(f"Wrote {len(ASSETS)} mascot assets to {ASSET_ROOT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
