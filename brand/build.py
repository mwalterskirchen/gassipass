"""Draws the app icon and the launch image from the mascot, into the asset catalog.

Run it from this folder with `python3 build.py`. It needs rsvg-convert and
ImageMagick (`brew install librsvg imagemagick`), and the SF Pro Display font
for the name on the launch image.
"""

import subprocess
import tempfile
from pathlib import Path

from mascot import poodle, svg

ASSETS = Path(__file__).parent.parent / "doggo" / "Assets.xcassets"
ICON = ASSETS / "AppIcon.appiconset"
LAUNCH = ASSETS / "LaunchMascot.imageset"

# A deep forest green, like the forest paths of many walks.
GREEN = "#2D5B43"

MASCOT = poodle()


def centered(scale):
    return f'<g transform="translate(512 512) scale({scale}) translate(-512 -542)">{MASCOT}</g>'


def launch(text_color):
    """300 x 340 points. The mascot is 240 points wide, with the name below it."""
    s = 240 / 740
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="300" height="340" viewBox="0 0 300 340">'
            f'<g transform="translate(150 110) scale({s:.4f}) translate(-512 -542)">{MASCOT}</g>'
            f'<text x="150" y="300" text-anchor="middle" font-family="SF Pro Display" font-weight="900" '
            f'font-size="72" letter-spacing="-1" fill="{text_color}">DogGo</text></svg>')


def render(source, *args):
    with tempfile.NamedTemporaryFile("w", suffix=".svg") as f:
        f.write(source)
        f.flush()
        subprocess.run(["rsvg-convert", *args, f.name], check=True)


def main():
    # The light icon must have no transparency.
    render(svg(centered(1.0), GREEN), "-w", "1024", "-o", ICON / "AppIcon.png")
    subprocess.run(["magick", ICON / "AppIcon.png", "-background", GREEN, "-alpha", "remove",
                    "-alpha", "off", ICON / "AppIcon.png"], check=True)
    # The system puts the dark and the tinted icon on its own background.
    render(svg(centered(0.95)), "-w", "1024", "-o", ICON / "AppIcon-Dark.png")
    render(svg(centered(0.95)), "-w", "1024", "-o", ICON / "AppIcon-Tinted.png")
    subprocess.run(["magick", ICON / "AppIcon-Tinted.png", "-colorspace", "Gray",
                    ICON / "AppIcon-Tinted.png"], check=True)

    for mode, color in (("light", "#FFFFFF"), ("dark", "#EDA567")):
        for zoom in (2, 3):
            render(launch(color), "-z", str(zoom), "-o", LAUNCH / f"Launch-{mode}@{zoom}x.png")


if __name__ == "__main__":
    main()
