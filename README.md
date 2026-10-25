# DeskNames

A native macOS menu bar app for naming, finding, switching, and managing desktops.

## Features

- Name desktops and personalize them with icons and colors.
- See the current desktop in the menu bar and jump directly to another one.
- Search desktops by name with **⌘0**.
- Cycle through recent desktops with **⌥Tab**, using arrows or the mouse.
- Create a desktop with **⇧⌘0** and choose its name, icon, and color.
- Customize shortcuts and enable **Open at Login** in Settings.

## Installation

Requires an **Apple Silicon Mac (M1 or later)** running **macOS 13 or later**.

**[Download DeskNames.dmg](https://github.com/abrahamalfie41/DeskNames/releases/latest/download/DeskNames.dmg)**

> **First launch — macOS security warning:** DeskNames is locally signed and is not Apple-notarized. If macOS says Apple could not verify it, click **Done** rather than **Move to Trash**. After moving the app to Applications and trying to open it, go to **System Settings → Privacy & Security**, scroll to **Security**, click **Open Anyway**, and confirm **Open**. Only do this if you trust the download. This adds an exception for DeskNames; you do not need to disable Gatekeeper. [Apple’s instructions](https://support.apple.com/en-us/102445).

1. Open the downloaded disk image.
2. Drag **DeskNames** onto **Applications** in the installer window.
3. Launch **DeskNames** from Applications. Its desktop name and icon appear in the menu bar.
4. Open **System Settings → Privacy & Security → Accessibility** and enable **DeskNames**. If it is missing, click **+** and choose DeskNames from Applications. Quit and reopen the app if access does not take effect immediately.

No build tools or terminal commands are needed. Download **DeskNames.dmg** to install the app.

### Desktop switching setup

If a direct jump fails, check **System Settings → Keyboard → Keyboard Shortcuts → Mission Control** and assign a shortcut to the relevant **Switch to Desktop N** action. DeskNames respects custom assignments and temporarily enables a disabled shortcut only while sending the jump.

## Quick start

| Action | Default control |
| --- | --- |
| Open the desktop panel | Click DeskNames in the menu bar |
| Search desktops | **⌘0**, type a name, then Return |
| Cycle recent desktops | Hold **⌥**, press **Tab**, release **⌥** to switch |
| Navigate the switcher | Tab / Shift–Tab, arrows, or mouse |
| Create a desktop | **⇧⌘0** |
| Edit a desktop | Click its pencil in the panel |
| Configure shortcuts or startup | **⋯ → Settings** |
| Read setup instructions | **⋯ → DeskNames Help** |

## Compatibility

Direct switching supports regular desktops 1–16. Full-screen app Spaces remain managed through Mission Control.

DeskNames uses private macOS APIs to read Spaces and configured desktop shortcuts. macOS updates may affect compatibility. On multiple displays, keep the pointer on the display you want to switch.

See the [project documentation](docs/DEVELOPMENT.md) for implementation details and verification commands.

## Repository layout

```text
Sources/DeskNames/       App code and feature checks
Resources/              App icon source
Package.swift           Swift package definition
tools/                  Release packaging tools
.github/workflows/      Automated build and DMG release
docs/                   Development documentation
dist/                   Generated app and installers (ignored by Git)
work/                   Local caches and temporary files (ignored by Git)
```
