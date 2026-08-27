# VisionHub — Omarchy Plugin

[![Ruby](https://img.shields.io/badge/ruby-3.4%2B-red.svg)](https://www.ruby-lang.org)
![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)
[![RuboCop](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://rubocop.org)

Live view and health monitoring of RTSP IP cameras directly in your Omarchy shell bar and desktop. Displays an at-a-glance camera status counter on the top bar and expands into a floating multi-camera grid with single-camera focused view.

---

## Showcase

### Multi-Camera Grid View
Configurable live overview of all surveillance feeds with instant reachability status pills and custom camera naming.

<p align="center">
  <img src="docs/assets/grid.png" alt="Multi-Camera Grid View" width="720" />
</p>

### Focused Cinema Live View
High-framerate focused stream with interactive FPS switcher, live RTSP audio playback toggle, HUD telemetry, and bottom carousel strip navigation.

<p align="center">
  <img src="docs/assets/cinema-garage.png" alt="Focused Cinema Live View" width="720" />
</p>

---

## Features

- **Top Bar Health Widget**: Compact status pill displaying active online camera count (e.g. `󰹗 4/4`), offline warnings, and hover tooltips with detailed status for each configured camera.
- **Floating Live View Window**: Themed desktop window featuring a configurable multi-camera grid, 4+1 Hero hybrid layout, and high-framerate focused Cinema view.
- **4+1 Hero Hybrid Layout**: Primary high-framerate stream accompanied by an interactive bottom live dock showing all cameras; click any camera thumbnail to promote it to Hero instantly.
- **One-Click Instant Snapshot**: Capture full-resolution / live frames directly to `~/Pictures/VisionHub` with thumbnail-rich desktop notifications and shutter flash feedback.
- **Aspect Ratio Fit & Fill (Crop)**: Toggle seamlessly between clean pillarbox/letterbox aspect fit and full-bleed crop modes.
- **Resource Efficient & Isolated**: RTSP streams decode in crash-isolated background `ffmpeg` worker processes managed by an asynchronous Ruby daemon. Only visible cameras consume streaming resources.
- **tmpfs Fast Frame Buffer**: Video frames stream directly into RAM (`$XDG_RUNTIME_DIR/vision-hub`), protecting SSD longevity and ensuring zero latency UI rendering.
- **Hardware Acceleration Support**: Automatic hardware-accelerated video decoding (VAAPI / CUDA / Vulkan / QSV).
- **Secure Credential Storage**: Camera passwords reside safely in your system keyring (`gnome-keyring` / `secret-tool`) and are never written to disk or exposed in configuration files.
- **Non-Blocking TCP Health Probes**: Proactive reachability checks detect offline cameras without stalling the UI.

---

## Requirements

- **Ruby 3.4+** (standard on Arch/Omarchy; verify with `ruby --version`)
- **ffmpeg** (with RTSP protocol support)
- **secret-tool** (`libsecret` / GNOME Keyring)
- **Omarchy Shell** (Quickshell / Hyprland)

---

## Installation & Removal

Enable the plugin:
```bash
omarchy plugin enable tobiasz-p.vision-hub
```

Or place it in a specific bar position:
```bash
omarchy bar put tobiasz-p.vision-hub --section right
```

Disable the plugin:
```bash
omarchy plugin disable tobiasz-p.vision-hub
```

Remove the plugin:
```bash
omarchy plugin remove tobiasz-p.vision-hub
```

---

## Configuration

### 1. Camera Definitions

Create `~/.config/vision-hub/cameras.json`:

```json
{
  "cameras": [
    {
      "id": "front",
      "name": "Front Door",
      "host": "192.168.1.101",
      "port": 554,
      "username": "admin",
      "mainPath": "/Streaming/channels/101",
      "subPath": "/Streaming/channels/102"
    },
    {
      "id": "backyard",
      "name": "Backyard",
      "host": "192.168.1.102",
      "port": 554,
      "username": "admin",
      "mainPath": "/live/ch0",
      "subPath": "/live/ch1"
    }
  ]
}
```

### 2. Store Credentials in Keyring

Camera passwords are stored securely in GNOME Keyring using `secret-tool`.

#### Option A: Single shared password for all cameras
If all cameras share the same password, store a single default entry:

```bash
secret-tool store --label='VisionHub default camera' application tobiasz-p.vision-hub camera default
```

#### Option B: Per-camera passwords
Store specific passwords for individual cameras by matching the `id` defined in `cameras.json` (takes precedence over the default):

```bash
secret-tool store --label='VisionHub camera front' application tobiasz-p.vision-hub camera front
```

```bash
secret-tool store --label='VisionHub camera backyard' application tobiasz-p.vision-hub camera backyard
```

### 3. Widget Settings

Settings can be customized via `omarchy bar set`:

| Setting | Default | Description |
|---|---|---|
| `gridColumns` | `3` | Number of columns in the multi-camera grid (`1` to `6`) |
| `targetFps` | `2` | Target FPS for substream grid tiles (`1` to `10`) |
| `mainFps` | `15` | Target FPS for focused single-camera stream (`1` to `30`) |
| `audioEnabled` | `false` | Play audio by default in cinema view |
| `hwaccel` | `true` | Enable hardware-accelerated video decoding |
| `showOfflineCameras` | `true` | Show offline/unreachable cameras in the grid view |
| `snapshotDir` | `Pictures/VisionHub` | Destination directory for snapshots (`~` or absolute) |
| `defaultView` | `grid` | Default view mode on open (`grid`, `hero`, `cinema`) |

Example:
```bash
omarchy bar set tobiasz-p.vision-hub defaultView hero
omarchy bar set tobiasz-p.vision-hub snapshotDir "Pictures/Surveillance"
```

---

## Gestures & Keyboard Shortcuts

| Action | Shortcut / Control |
|---|---|
| **Toggle Window** | Left-click on Bar Widget |
| **Re-probe Cameras** | Right-click on Bar Widget |
| **Switch to Grid View** | Click `Grid` tab or press <kbd>G</kbd> |
| **Switch to Hero 4+1 View** | Click `Hero` tab or press <kbd>H</kbd> |
| **Switch to Cinema View** | Click `Cinema` tab or press <kbd>C</kbd> |
| **Focus Camera** | Click any Camera Tile in Grid or Thumbnail in Dock |
| **Cycle Cameras** | Press <kbd>←</kbd> / <kbd>→</kbd> Arrow keys |
| **Direct Camera Jump** | Press <kbd>1</kbd>–<kbd>9</kbd> |
| **Toggle Auto-Patrol** | Press <kbd>Space</kbd> or click `Patrol` pill |
| **Capture Snapshot** | Press <kbd>S</kbd> or click `󰄀 Snapshot` (saves to `~/Pictures/VisionHub`) |
| **Toggle Aspect Fit / Fill** | Press <kbd>A</kbd> or click `󰹑 Fit` / `󰹍 Fill` |
| **Toggle Audio** | Press <kbd>M</kbd> or click `Audio` pill |
| **Exit Mode / Close** | Press <kbd>Esc</kbd> or <kbd>Ctrl</kbd>+<kbd>W</kbd> |

---

## Contributing

Contributions are welcome! To help keep the codebase clean and git history maintainable, please follow these guidelines when opening a Pull Request.

### Workflow & Creating a PR

1. **Fork the repository** on GitHub to your personal account.
2. **Clone your fork** and add the upstream repository as a remote:
   ```bash
   git clone https://github.com/<your-username>/vision-hub.git
   cd vision-hub
   git remote add upstream https://github.com/tobiasz-p/vision-hub.git
   ```
3. **Create a feature branch**:
   ```bash
   git checkout -b feat/your-feature-name
   # or
   git checkout -b fix/issue-description
   ```
4. **Make your changes**: Verify test suites and linters pass locally:
   ```bash
   bundle exec rake
   omarchy plugin validate ~/.config/omarchy/plugins/tobiasz-p.vision-hub
   ```
5. **Push to your fork**:
   ```bash
   git push -u origin feat/your-feature-name
   ```
6. **Open a Pull Request**: Submit a PR from your branch against `upstream/main` with a clear description of the changes.

### Commit Guidelines

We follow [Conventional Commits](https://www.conventionalcommits.org/). Write concise, descriptive commit messages in the imperative mood:

```
<type>(<optional scope>): <description>
```

**Common Types:**
- `feat:` A new feature or capability
- `fix:` A bug fix
- `docs:` Documentation updates
- `refactor:` Code changes that neither fix a bug nor add a feature
- `style:` Formatting or UI styling adjustments without logic changes
- `test:` Adding or updating tests
- `chore:` Maintenance tasks, dependency updates, or toolchain configuration

**Examples:**
- `feat: add support for custom stream transport protocols`
- `fix: handle ffmpeg restart edge case during rapid window toggle`
- `docs: update camera configuration examples for ONVIF profiles`

### Meaningful Commits & Linear History

- **Meaningful Commits Only**: Each commit should represent a complete, logical unit of work. Avoid leaving intermediate "WIP", "fix typo", or "checkpoint" commits in the history.
- **Squash Fixups**: Squash or rebase intermediate commits locally (`git rebase -i`) before submitting or finalizing your PR.
- **Linear History**: We maintain a strictly linear git history. PRs will be rebased onto `main` (no merge commits). Make sure your branch is up-to-date with upstream:
   ```bash
   git pull --rebase upstream main
   ```

---

## License

MIT License. Copyright (c) 2026 tobiasz-p.
