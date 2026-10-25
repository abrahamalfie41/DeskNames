"""Create and verify a styled drag-to-Applications disk image on macOS.

Release-only dependencies: Pillow, ds-store, and mac-alias.
"""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

from ds_store import DSStore
from mac_alias import Alias
from PIL import Image, ImageDraw, ImageFont


def run(*args):
    return subprocess.run([str(arg) for arg in args], check=True, capture_output=True)


def background(path):
    scale = 2
    image = Image.new("RGB", (640 * scale, 400 * scale), "#edf1f7")
    draw = ImageDraw.Draw(image)
    font_path = "/System/Library/Fonts/Supplemental/Arial.ttf"
    def text(value, y, size, color):
        font = ImageFont.truetype(font_path, size * scale)
        box = draw.textbbox((0, 0), value, font=font)
        draw.text(((image.width - box[2]) / 2, y * scale), value, fill=color, font=font)
    text("DeskNames", 36, 30, "#28364d")
    text("Drag DeskNames to Applications", 83, 17, "#52627b")
    draw.line([(280 * scale, 190 * scale), (359 * scale, 190 * scale)], fill="#7387a7", width=4 * scale)
    draw.line([(346 * scale, 177 * scale), (359 * scale, 190 * scale), (346 * scale, 203 * scale)], fill="#7387a7", width=4 * scale)
    text("Then open DeskNames from Applications.", 329, 14, "#52627b")
    image.save(path, dpi=(144, 144))


def attach(image, mount, readonly=False):
    args = ["hdiutil", "attach", "-nobrowse", "-noautoopen", "-mountpoint", mount]
    if readonly:
        args.append("-readonly")
    run(*args, image)


def verify(image, mount):
    run("hdiutil", "verify", image)
    attach(image, mount, readonly=True)
    try:
        assert (mount / "Applications").is_symlink()
        assert os.readlink(mount / "Applications") == "/Applications"
        run("codesign", "--verify", "--verbose", mount / "DeskNames.app")
        run("plutil", "-lint", mount / "DeskNames.app/Contents/Info.plist")
        with DSStore.open(str(mount / ".DS_Store"), "r") as store:
            assert store["DeskNames.app"]["Iloc"] == (170, 190)
            assert store["Applications"]["Iloc"] == (470, 190)
            assert store["."]["icvp"]["backgroundType"] == 2
        assert (mount / ".background/install.png").is_file()
        visible = {p.name for p in mount.iterdir() if not p.name.startswith(".")}
        assert visible == {"DeskNames.app", "Applications"}, visible
        assert not list((mount / "DeskNames.app").rglob("*.sh"))
    finally:
        run("hdiutil", "detach", mount)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    output = args.output.resolve()
    run("codesign", "--verify", "--verbose", app)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="desknames-dmg-") as temporary:
        folder = Path(temporary)
        staging = folder / "staging"
        staging.mkdir()
        run("ditto", app, staging / "DeskNames.app")
        (staging / "Applications").symlink_to("/Applications")
        (staging / ".background").mkdir()
        background(staging / ".background/install.png")
        rw_image = folder / "DeskNames-rw.dmg"
        mount = folder / "mounted"
        mount.mkdir()
        run("hdiutil", "create", "-srcfolder", staging, "-volname", "DeskNames", "-fs", "HFS+", "-format", "UDRW", rw_image)
        attach(rw_image, mount)
        try:
            alias = Alias.for_file(str(mount / ".background/install.png")).to_bytes()
            with DSStore.open(str(mount / ".DS_Store"), "w+") as store:
                store["."]["vstl"] = ("type", b"icnv")
                store["."]["bwsp"] = {
                    "WindowBounds": "{{200, 160}, {640, 400}}",
                    "ShowToolbar": False, "ShowStatusBar": False,
                    "ShowSidebar": False, "ShowPathbar": False, "ShowTabView": False,
                    "ContainerShowSidebar": False,
                }
                store["."]["icvp"] = {
                    "viewOptionsVersion": 1, "backgroundType": 2,
                    "backgroundImageAlias": alias, "iconSize": 96.0,
                    "textSize": 13.0, "gridSpacing": 100.0, "arrangeBy": "none",
                    "labelOnBottom": True, "showItemInfo": False, "showIconPreview": False,
                    "scrollPositionX": 0.0, "scrollPositionY": 0.0,
                }
                store["DeskNames.app"]["Iloc"] = (170, 190)
                store["Applications"]["Iloc"] = (470, 190)
        finally:
            run("hdiutil", "detach", mount)
        compressed = folder / "DeskNames.dmg"
        run("hdiutil", "convert", rw_image, "-format", "UDZO", "-imagekey", "zlib-level=9", "-o", compressed)
        verify(compressed, mount)
        run("ditto", compressed, output)
    print(f"Created and verified {output} ({output.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
