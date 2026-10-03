"""Puts the app icon and the launch screen images into the asset catalog.

Run it from this folder with `python3 build.py`. It needs ImageMagick
(`brew install imagemagick`). The source images in this folder come from GPT Image.
The launch screen itself is gassipass/LaunchScreen.storyboard.
"""

import subprocess
from pathlib import Path

HERE = Path(__file__).parent
ASSETS = HERE.parent / "gassipass" / "Assets.xcassets"
ICON = ASSETS / "AppIcon.appiconset"
MAP = ASSETS / "LaunchMap.imageset"
MASCOT = ASSETS / "LaunchMascot.imageset"

# The dark map is the light map at this brightness. Its centre then matches
# the dark LaunchBackground colour (#12241A).
DARK = 0.42

# The mascot is 260 points wide on the launch screen.
MASCOT_POINTS = 260


def magick(*args):
    subprocess.run(["magick", *map(str, args)], check=True)


def main():
    # The icons must have no transparency.
    for source, target in (("icon", "AppIcon"), ("icon-dark", "AppIcon-Dark"),
                           ("icon-tinted", "AppIcon-Tinted")):
        magick(HERE / f"{source}.png", "-resize", "1024x1024", "-alpha", "off", ICON / f"{target}.png")

    magick(HERE / "launch-map.png", "-quality", "90", MAP / "Launch-map-light.jpg")
    magick(HERE / "launch-map.png", "-evaluate", "multiply", DARK, "-quality", "90",
           MAP / "Launch-map-dark.jpg")

    for zoom in (2, 3):
        size = MASCOT_POINTS * zoom
        magick(HERE / "launch-mascot.png", "-resize", f"{size}x{size}", MASCOT / f"Launch-mascot@{zoom}x.png")


if __name__ == "__main__":
    main()
