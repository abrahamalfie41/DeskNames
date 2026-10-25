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

1. [Download **DeskNames.dmg**](https://github.com/abrahamalfie41/DeskNames/releases/latest/download/DeskNames.dmg).
2. Open the downloaded disk image.
3. Drag **DeskNames** onto **Applications** in the installer window.
4. Eject the DeskNames disk image, then launch **DeskNames** from Applications. Its desktop name and icon appear in the menu bar.
5. Open **System Settings → Privacy & Security → Accessibility** and enable **DeskNames**. If it is missing, click **+** and choose DeskNames from Applications. Quit and reopen the app if access does not take effect immediately.

No build tools or terminal commands are needed. For updates, quit DeskNames before replacing the app in Applications. The GitHub source-code archives are for developers; download **DeskNames.dmg** to install the app.

### If macOS blocks the first launch

The build is locally signed and is not Apple-notarized. If you trust the source, first try opening the app, then go to **System Settings → Privacy & Security → Open Anyway** and confirm. See [Apple's instructions](https://support.apple.com/en-us/102445). Do not disable Gatekeeper globally.

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

Direct switching supports regular desktops 1–16. Full-screen app Spaces remain managed through Mission Control. Names are shown in DeskNames; they do not rename Mission Control's labels.

DeskNames uses private macOS APIs to read Spaces and configured desktop shortcuts. macOS updates may affect compatibility. On multiple displays, keep the pointer on the display you want to switch.

See the [project documentation](outputs/DeskNames/README.md) for implementation details and verification commands.
