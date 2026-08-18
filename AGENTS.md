# Omarchy Window Shelf Development Guide

This repository is an Omarchy Quattro bar plugin that simulates window
minimization on Hyprland. Keep changes small, event-driven, and explicit about
where windows are moved.

## Repository Map

- `BarWidget.qml`: complete runtime behavior and bar UI
- `manifest.json`: Omarchy plugin identity and marketplace metadata
- `README.md`: installation, behavior, recovery, privacy, and development docs
- `preview.png`: root marketplace preview of centered interactive Peek
- `assets/interactive-peek.png`: README screenshot of the real Peek surface
- `assets/hover-preview.png`: README screenshot of the live hover thumbnail
- `deploy-local.sh`: development-only deployment helper
- `mise.toml`: local restart and validation tasks

The permanent plugin ID is `io.github.gardnmi.window-shelf`. Never change it
after publication.

## Runtime Contract

- `special:omarchy-minimized` is the authoritative minimized-window shelf.
- Minimize only the exact active Hyprland toplevel.
- Restore only the exact address represented by the clicked chip.
- Restore onto `Hyprland.focusedWorkspace` at click time; do not remember or
  infer an original workspace.
- Derive the minimized list from `Hyprland.toplevels.values`; do not poll
  `hyprctl`, persist a second state model, or create a background service.
- A shell restart must reconstruct the same list from Hyprland state.
- Resolve chip icons from local desktop entries with a generic application
  fallback when no reliable match exists.
- Hover previews use `ScreencopyView` with the exact toplevel as their capture
  source. They must not move, focus, or activate the window.
- Interactive Peek may move only one exact client at a time onto
  `special:omarchy-window-peek`. It floats, sizes, and centers the real client,
  then returns it to the shelf or restores it permanently.
- Preserve whether the client was tiled or floating before Peek. Previously
  floating clients also recover their prior size and position.

## Safety Invariants

- Never toggle the shelf workspace during normal minimize or restore flows.
  Moving by exact address keeps parked windows hidden until requested.
- Do not move a client when its address or destination workspace is missing.
- Do not close windows, synthesize input, save window frames, or expose preview
  content outside the transient in-process hover popup.
- Serialize every Peek move, float, resize, center, and special-workspace toggle.
  Never leave an empty Peek workspace visible after a normal close or restore.
- Omarchy hides special workspaces during normal workspace changes. That path
  must return the Peek client to the shelf without toggling the already-hidden
  workspace back open.
- Before the final Peek cleanup toggle, inspect `hyprctl -j monitors`; toggle
  only when `special:omarchy-window-peek` is still visible on a monitor.
- Do not modify Hyprland or Omarchy user configuration from plugin code. The
  optional `SUPER + M` binding belongs in documentation and user config.
- Removing the plugin can leave applications parked. Keep the recovery command
  and removal warning accurate in `README.md`.

## UI Conventions

- Keep the first button as the mouse-accessible animated minimize action.
- Render one chip for every parked window; do not silently hide overflow.
- Show an application icon in every chip and retain the title on horizontal
  bars. Use the local icon theme and a generic executable fallback.
- Use Omarchy `qs.Ui` controls and `Style.space(...)` values.
- Follow the active bar foreground, font, orientation, and tooltip host.
- Horizontal chips show bounded titles. Vertical chips use a compact initial
  only when an application icon cannot be resolved.
- Open previews after a short delay so crossing the bar does not create popup
  churn. Closing a preview must stop its live capture immediately.
- Right-click toggles interactive Peek. Left-click always restores permanently,
  including while Peek is open. `SUPER + M` from the Peek client and a normal
  workspace change both dismiss Peek and must restore prior layout state.
- Keep all user-visible strings and source files ASCII unless an existing file
  requires otherwise.

## Validation

Run all of these before committing:

```bash
omarchy plugin validate .
qmllint -I /usr/share/omarchy/shell BarWidget.qml
bash -n deploy-local.sh
mise run test
git diff --check
```

For a live smoke test:

```bash
mise run restart
```

Then minimize a disposable window, verify its workspace is
`special:omarchy-minimized`, restore it from the chip, and confirm it lands on
the currently focused workspace. Inspect the running Quickshell log for QML
errors after both transitions.

`mise run restart` stops Quickshell, copies the complete runtime plugin, and
restarts the shell to avoid partial hot-reload races. Repository files are the
source of truth; do not develop in the installed plugin directory.

## Screenshots

- Screenshots must come from the real plugin UI and be owned by the project.
- Keep the marketplace image at `preview.png` in the repository root.
- Use disposable windows with generic titles so screenshots do not expose
  private application, document, workspace, or terminal information.
- Redeploy the unmodified repository source after any temporary screenshot
  setup.

## Release Checklist

- Update `manifest.json` semantically: patch for fixes/docs, minor for new
  features, and major for incompatible behavior.
- Keep the workspace name, optional binding, install URL, recovery command,
  privacy statement, and runtime behavior synchronized with `BarWidget.qml`.
- Confirm `preview.png`, `assets/interactive-peek.png`, and
  `assets/hover-preview.png` still match the released behavior.
- Confirm the public default branch contains the final commit before marketplace
  submission; validation inspects the current public commit.
- Recommended marketplace category: `Compositor`.
- Recommended tags: `Bar`, `Hyprland`, `Productivity`, `Windows`.
