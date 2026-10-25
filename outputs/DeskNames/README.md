# DeskNames

A native macOS menu bar app for naming, finding, switching, and managing desktops.

## Open

Open `DeskNames.app` next to this source folder. The current desktop name appears in the menu bar. Click it to open the desktop panel. Click a row to jump directly, or its pencil button to edit the name, color, and icon. Changes are saved automatically.

For switching, enable **DeskNames** in **System Settings → Privacy & Security → Accessibility**. DeskNames uses the configured **Switch to Desktop N** shortcuts. Disabled shortcuts are enabled only briefly and restored afterward. If a shortcut has no key assigned, assign one under **Keyboard → Keyboard Shortcuts → Mission Control**. You can reach Accessibility from the app menu.

To start at login, turn on **Open at Login** in **⋯ → Settings**. DeskNames registers itself with macOS; if approval is required, the setting shows a **Review…** button. Keep the app at a stable location after granting Accessibility; moving or rebuilding it may require granting access again.

## Behavior

- Uses the native macOS slide animation, with no change to your animation preferences.
- Direct jumps send one numbered desktop shortcut and do not travel through intermediate desktops. Regular desktops 1–16 are supported; full-screen Spaces must be selected through Mission Control.
- Names appear in this app's menu and menu bar. Apple's Mission Control labels remain unchanged.
- Names are stored against Space UUIDs, so desktop reordering preserves them. Recreated desktops receive new identities.
- Full-screen Spaces are listed, but do not have numbered direct-jump commands.
- On multiple monitors, the menu follows the active menu bar's display. Keep the pointer on that display while switching.
- Private SkyLight APIs enumerate desktops and invoke their configured shortcuts. These can change with macOS updates; this app is intended for personal use and is not a Mac App Store build.
- No network access, third-party packages, window capture, or background helper.

## Build and release

Install the app using **DeskNames.dmg** from [GitHub Releases](https://github.com/abrahamalfie41/DeskNames/releases/latest). Open the disk image and drag DeskNames to Applications. The installer contains the app and an Applications shortcut; no build script is distributed to users.

Maintainers build releases with the **Package macOS release** GitHub Actions workflow. It compiles and locally signs the Apple Silicon app, runs feature and routing checks, creates and verifies the styled DMG, and publishes it as a release asset. The release-only packaging dependencies are separate from the app; DeskNames itself has no third-party runtime dependencies. The Swift package remains available for source development.

## Verification

The executable accepts `--diagnose` to print detected Spaces without starting its menu bar interface. Live switching requires the user-granted Accessibility permission and enabled Mission Control shortcuts.

## Direct jumps in 0.1.3

Choosing Desktop 5 from Desktop 1 sends one command for Desktop 5. Numbering follows macOS across displays and skips full-screen Spaces. Custom shortcut assignments are read from macOS at switch time; existing enabled/disabled states are preserved. No sequential-arrow fallback is used.

Run the executable with `--check-routing` for a deterministic check of desktop numbering, reordering, and direct command selection. This check does not post keyboard events.

This locally signed build may need its Accessibility entry re-added after rebuilding because its signature changes. Quit the old process before reopening the rebuilt app.

## Interface in 0.2.0

- A compact desktop panel replaces the plain text menu.
- Desktop icons have one of six selectable accent colors.
- The active desktop has a tinted outline and checkmark.
- Each pencil button opens a name, color, and icon editor with twelve SF Symbols.
- The menu bar shows the active desktop’s chosen icon and name.
- Appearance choices are saved by Space UUID, alongside existing names.
- DeskNames Help, Accessibility settings, and Quit are available in the top-right options menu.

The existing direct-jump backend is retained. Build, signature, and routing checks pass; live visual layout still needs checking in the normal desktop session.

## Search and desktop management in 0.3.0

### Quick Switcher

Press **⌘0** from any app to open desktop search. Type a name or desktop number, use **↑/↓** to select, and press **Return** to jump directly. **Escape** or clicking outside closes the window. Search ignores capitalization and accents, and prioritizes exact names and name prefixes. Full-screen Spaces and desktops beyond the existing 1–16 direct-jump limit are excluded from search.

The panel’s **Search** button also opens the switcher. Open **⋯ → Settings…** to record another shortcut; press Escape to cancel recording. Shortcut conflicts leave the previous binding intact. **Restore Default** returns to ⌘0. The chosen shortcut persists across app restarts. No Input Monitoring permission is required for the global shortcut.

### Add and remove desktops

- **New Desktop** opens a form for the name, icon, and color; **Create Desktop** creates the regular desktop on the original display.
- Use a desktop’s pencil editor or right-click its row to choose **Remove Desktop…**.
- A confirmation explains that macOS moves its windows to another desktop and keeps apps open.
- When removing the active desktop, DeskNames first switches away. The last regular desktop on a display and full-screen app Spaces cannot be removed.
- Changes use Mission Control’s own Accessibility actions, so Mission Control appears briefly. Existing Accessibility access is required.
- DeskNames verifies the change before clearing removed desktop preferences, and rechecks identity/order before acting.

### Checks

The executable supports **--check-features** (search, keyboard navigation, shortcut validation/persistence, and removal safeguards) and **--check-routing** (direct switching and numbering). Both checks pass without registering a global shortcut or changing any desktop. Compilation, bundle validation, and local signature verification pass. Global shortcut delivery, the new windows, and Mission Control add/remove actions still need a live check in the normal desktop session.

## App icon

The app includes a custom white capital D on a muted slate-blue gradient tile, generated with the built-in image generator. The source image is `Resources/AppIcon.png`. The build creates the required icon sizes and ICNS under the ignored `work/` folder and includes the generated icon in the app bundle.

## Help window

**⋯ → DeskNames Help** opens a reusable, non-modal window with short sections for Accessibility, direct switching, search, and desktop organization. It can be resized and left beside System Settings; opening System Settings from its button leaves the help window open. The displayed search shortcut follows your current settings. Permission and switching failures continue to use their specific error dialogs.

## Open at Login

Settings includes an Open at Login toggle backed by `SMAppService.mainApp`. Enabling registers the running app; disabling unregisters it. The toggle reads macOS’s real status when Settings opens and when DeskNames becomes active. A pending approval is labeled explicitly with a Review button, and registration errors restore the actual state and display an inline message. Registration is only changed when the user operates the toggle. The Help window no longer instructs users to add the app manually in System Settings.

Login-item state handling is covered by `--check-features` using an injected simulated service, including enable/disable, failed registrations, pending approval, and external state changes. These checks do not register a real login item or verify launch at the next login.

## New Desktop shortcut

Press **⇧⌘0** (Command–Shift–0) to open the floating New Desktop popup from any app. Enter a name, choose an icon and color with the same controls as the desktop editor, then choose **Create Desktop**. Press Escape, click outside, or choose Cancel to dismiss without changing Spaces. The panel’s New Desktop button opens the same form.

Both global shortcuts are configurable independently in **⋯ → Settings** and have their own Restore Default buttons. Search remains **⌘0**. The recorder rejects assigning the same key combination to both actions, and restores the existing shortcuts on cancellation or conflicts. Both shortcuts are temporarily suspended while recording so either combination can be captured accurately.

The form stays associated with the display it was opened for. Creation is verified before the chosen name and appearance are saved to the one newly added desktop UUID. Reordering does not cause an existing desktop to be customized accidentally; ambiguous concurrent changes produce an error instead. Failed creation keeps the draft for correction or retry.

The feature checks cover creation-name validation, duplicate-submission prevention, separate defaults, shortcut identity, and exact new-desktop identification. Compilation, signing, feature checks, and direct-jump regression checks pass. Actual shortcut delivery and form-driven desktop creation still need a live check in the normal desktop session.

## Desktop switcher

Hold **Option** and press **Tab** to open the desktop switcher. Press Tab again to cycle forward, Shift–Tab to cycle backward, or use the arrow keys. Release Option to jump directly to the highlighted desktop. You can also move the mouse to highlight a desktop and click to switch immediately. Escape or clicking outside cancels.

The current desktop comes first, followed by recently used desktops, then desktops not yet visited. Recency is tracked while DeskNames runs. Only regular desktops supported by direct switching appear. Long lists scroll horizontally as you navigate. A stationary mouse never overrides arrow-key selection.

Change the binding in **Settings → Desktop switcher**. The Shift variant is reserved for reverse cycling. With a custom binding, release any of its primary modifiers (Command, Option, or Control) to confirm. Another app using Option–Tab may require choosing a different shortcut.
