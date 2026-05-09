#!/usr/bin/env python3
"""Generate deterministic local mascot PNGs for the seven decorative themes.

This is the offline fallback for environments without an OpenAI API key. The
gpt-image-2 generator can overwrite the same asset names later.
"""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "Resources" / "Assets.xcassets"
SIZE = 1024


def rgba(value: str, alpha: int = 255) -> tuple[int, int, int, int]:
    value = value.lstrip("#")
    return (int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16), alpha)


ASSETS = {
    "ThemeForestLeft": dict(skin="#F4D6AC", hair="#366E38", outfit="#217A40", stroke="#C2AD4B", accent="#F2CF42", style="cap", item="leaf", tilt=-10),
    "ThemeForestRight": dict(skin="#F9E7D5", hair="#F2BE51", outfit="#66B88E", stroke="#D6A94E", accent="#F8C73D", style="long", item="tiara", tilt=8),
    "ThemeHuskLeft": dict(skin="#F0EFE8", hair="#19191E", outfit="#202328", stroke="#E5E4D7", accent="#D9D7C4", style="horns", item="ring", tilt=-7),
    "ThemeHuskRight": dict(skin="#F7E8DA", hair="#D82129", outfit="#B30D15", stroke="#F0C6B8", accent="#F7DE9B", style="horns", item="needle", tilt=7),
    "ThemeMistLeft": dict(skin="#F9E7D5", hair="#DDDFC7", outfit="#8FBC84", stroke="#DDD38B", accent="#E9DA80", style="long", item="staff", tilt=-7),
    "ThemeMistRight": dict(skin="#F0D2C7", hair="#715084", outfit="#9B83B5", stroke="#D5BDE8", accent="#EBD58D", style="bob", item="book", tilt=7),
    "ThemeClubLeft": dict(skin="#F9E7D5", hair="#8B4A28", outfit="#C24D38", stroke="#F0CC4B", accent="#F9C941", style="ribbon", item="star", tilt=-8),
    "ThemeClubRight": dict(skin="#F0D2C7", hair="#3A608F", outfit="#5B7AB3", stroke="#C8D5F5", accent="#D9C9F5", style="bob", item="book", tilt=7),
    "ThemeUnitLeft": dict(skin="#F9E7D5", hair="#EB4713", outfit="#C72E1A", stroke="#F7C04A", accent="#F7D13C", style="swept", item="bolt", tilt=-6),
    "ThemeUnitRight": dict(skin="#F0D2C7", hair="#8BC2E0", outfit="#AFC7E6", stroke="#E1F0FF", accent="#B8F2FF", style="bob", item="scope", tilt=6),
    "ThemeInkLeft": dict(skin="#F9E7D5", hair="#60458F", outfit="#4D387A", stroke="#D8B8F5", accent="#DBADF8", style="swept", item="clip", tilt=-8),
    "ThemeInkRight": dict(skin="#F0D2C7", hair="#1F212B", outfit="#B8ABD6", stroke="#EADBF8", accent="#D4BDF5", style="bob", item="glasses", tilt=6),
    "ThemeGiltLeft": dict(skin="#F9E7D5", hair="#F2CC61", outfit="#C74D29", stroke="#F7DA75", accent="#F8D044", style="crown", item="ring", tilt=-7),
    "ThemeGiltRight": dict(skin="#F0D2C7", hair="#151519", outfit="#DFAE52", stroke="#F7DF8E", accent="#F8D044", style="bob", item="ring", tilt=6),
}


def contents_json(filename: str) -> dict:
    return {
        "images": [
            {"filename": filename, "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": {"author": "xcode", "version": 1},
    }


def draw_capsule(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill, outline=None, width: int = 1) -> None:
    draw.rounded_rectangle(box, radius=(box[3] - box[1]) // 2, fill=fill, outline=outline, width=width)


def draw_hair(draw: ImageDraw.ImageDraw, spec: dict, cx: int, cy: int) -> None:
    hair = rgba(spec["hair"])
    accent = rgba(spec["accent"])
    style = spec["style"]
    if style == "cap":
        draw_capsule(draw, (300, 230, 724, 480), hair)
        draw.ellipse((275, 350, 745, 650), fill=hair)
        draw.polygon([(338, 230), (430, 172), (506, 262)], fill=accent)
    elif style == "long":
        draw.rounded_rectangle((250, 195, 774, 780), radius=190, fill=hair)
        draw_capsule(draw, (230, 210, 794, 455), hair)
    elif style == "horns":
        draw.ellipse((285, 240, 739, 632), fill=hair)
        draw.ellipse((170, 192, 335, 430), fill=accent)
        draw.ellipse((689, 192, 854, 430), fill=accent)
        draw.ellipse((215, 240, 340, 450), fill=(0, 0, 0, 0))
    elif style == "bob":
        draw.rounded_rectangle((272, 215, 752, 710), radius=165, fill=hair)
        draw_capsule(draw, (230, 210, 794, 445), hair)
    elif style == "ribbon":
        draw.ellipse((286, 250, 738, 630), fill=hair)
        draw.polygon([(310, 170), (468, 260), (330, 330)], fill=accent)
        draw.polygon([(468, 260), (626, 170), (606, 330)], fill=accent)
        draw.ellipse((444, 236, 506, 298), fill=rgba("#F8E5A0"))
    elif style == "swept":
        draw.ellipse((260, 240, 748, 610), fill=hair)
        draw.polygon([(210, 310), (500, 180), (760, 275), (448, 382)], fill=hair)
        draw.ellipse((640, 385, 795, 725), fill=hair)
    elif style == "crown":
        draw.rounded_rectangle((260, 220, 764, 760), radius=185, fill=hair)
        draw.polygon([(360, 190), (415, 95), (470, 190), (535, 95), (600, 190), (650, 190), (650, 245), (360, 245)], fill=accent)


def draw_item(draw: ImageDraw.ImageDraw, spec: dict) -> None:
    accent = rgba(spec["accent"])
    dark = rgba("#121217")
    item = spec["item"]
    if item == "tiara":
        draw.polygon([(595, 250), (630, 185), (665, 250), (700, 190), (735, 250), (735, 290), (595, 290)], fill=accent)
    elif item == "needle":
        draw.line((625, 650, 820, 420), fill=accent, width=28)
        draw.ellipse((792, 392, 848, 448), outline=accent, width=18)
    elif item == "staff":
        draw.line((690, 290, 785, 720), fill=accent, width=24)
        draw.ellipse((645, 230, 735, 320), fill=accent)
        draw.line((690, 210, 690, 340), fill=rgba("#FFF5C7"), width=10)
        draw.line((625, 275, 755, 275), fill=rgba("#FFF5C7"), width=10)
    elif item == "book":
        draw.rounded_rectangle((625, 620, 820, 770), radius=28, fill=accent, outline=dark, width=10)
        draw.line((722, 628, 722, 762), fill=dark, width=8)
    elif item == "star":
        draw.polygon([(710, 210), (745, 305), (845, 305), (764, 360), (795, 455), (710, 398), (625, 455), (656, 360), (575, 305), (675, 305)], fill=accent)
    elif item == "bolt":
        draw.polygon([(660, 270), (805, 270), (735, 425), (825, 425), (640, 740), (700, 505), (610, 505)], fill=accent)
    elif item == "scope":
        draw.ellipse((625, 565, 825, 765), outline=accent, width=22)
        draw.line((725, 540, 725, 790), fill=accent, width=14)
        draw.line((600, 665, 850, 665), fill=accent, width=14)
    elif item == "clip":
        draw.arc((620, 430, 820, 760), start=80, end=430, fill=accent, width=24)
        draw.arc((675, 485, 765, 690), start=80, end=430, fill=accent, width=18)
    elif item == "glasses":
        draw.ellipse((360, 455, 465, 540), outline=dark, width=15)
        draw.ellipse((560, 455, 665, 540), outline=dark, width=15)
        draw.line((465, 497, 560, 497), fill=dark, width=12)
    elif item == "ring":
        draw.ellipse((650, 610, 805, 765), outline=accent, width=30)
        draw.ellipse((695, 655, 760, 720), outline=rgba("#FFF0A6"), width=12)
    elif item == "leaf":
        draw.ellipse((670, 235, 815, 360), fill=accent)


def render(name: str, spec: dict) -> Image.Image:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img, "RGBA")
    accent = rgba(spec["accent"])
    outfit = rgba(spec["outfit"])
    stroke = rgba(spec["stroke"])
    skin = rgba(spec["skin"])
    dark = rgba("#121217")

    draw.ellipse((150, 150, 874, 874), fill=(*accent[:3], 46))
    draw.rounded_rectangle((185, 250, 839, 825), radius=210, fill=(*rgba("#FFFFFF")[:3], 54), outline=(*stroke[:3], 120), width=10)

    draw_hair(draw, spec, 512, 430)
    draw_capsule(draw, (315, 570, 709, 910), outfit, outline=stroke, width=20)
    draw.ellipse((330, 330, 694, 694), fill=skin, outline=(*dark[:3], 70), width=10)
    draw.ellipse((405, 485, 445, 525), fill=dark)
    draw.ellipse((579, 485, 619, 525), fill=dark)
    draw.rounded_rectangle((468, 585, 556, 610), radius=13, fill=(*dark[:3], 125))
    draw_item(draw, spec)

    if spec["tilt"]:
        rotated = img.rotate(spec["tilt"], resample=Image.Resampling.BICUBIC, expand=False)
        return rotated
    return img


def write_asset(name: str, image: Image.Image) -> None:
    imageset = ASSET_ROOT / f"{name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    filename = f"{name}.png"
    image.save(imageset / filename)
    (imageset / "Contents.json").write_text(
        json.dumps(contents_json(filename), indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    for name, spec in ASSETS.items():
        write_asset(name, render(name, spec))
        print(f"Wrote {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
