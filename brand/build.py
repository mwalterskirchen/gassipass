"""Puts the app icon and the launch screen mark into the asset catalog.

Run it from this folder with `python3 build.py`. It needs ImageMagick and librsvg
(`brew install imagemagick librsvg`). The icons are SVG files, and the launch mark
is the icon without its background, so the two always match.
The launch screen itself is ios/gassipass/LaunchScreen.storyboard.
"""

import re
import subprocess
from pathlib import Path

HERE = Path(__file__).parent
ASSETS = HERE.parent / "ios" / "gassipass" / "Assets.xcassets"
ICON = ASSETS / "AppIcon.appiconset"
MARK = ASSETS / "LaunchMark.imageset"

# The square around the outer edge of the stamp ring, in icon units.
MARK_BOX = "123 123 1008 1008"


def main():
    # The icons must have no transparency. ImageMagick's own SVG renderer drops
    # the strokes, so rsvg-convert draws the SVG and ImageMagick removes the alpha.
    for source, target in (("icon", "AppIcon"), ("icon-dark", "AppIcon-Dark"),
                           ("icon-tinted", "AppIcon-Tinted")):
        drawn = subprocess.run(["rsvg-convert", "-w", "1024", "-h", "1024", HERE / f"{source}.svg"],
                               check=True, capture_output=True).stdout
        subprocess.run(["magick", "png:-", "-alpha", "off", ICON / f"{target}.png"], input=drawn, check=True)

    # The launch screen shows the mark on LaunchBackground, which has the colour
    # of the icon background, so the mark leaves out the background square.
    for source, target in (("icon", "Launch-mark-light"), ("icon-dark", "Launch-mark-dark")):
        svg = (HERE / f"{source}.svg").read_text()
        svg = re.sub(r'\s*<rect [^>]*/>', "", svg)
        svg = re.sub(r'viewBox="[^"]*" width="\d+" height="\d+"', f'viewBox="{MARK_BOX}"', svg)
        (MARK / f"{target}.svg").write_text(svg)


if __name__ == "__main__":
    main()
