# VisionHub — Future Ideas & Roadmap

This document collects enhancement ideas, layout explorations, and architectural improvements for upcoming iterations of VisionHub.

---

## 1. Advanced Multi-Camera Grid Layouts

- **4+1 Hero Layout**:
  - 1 large primary/hero stream (mainstream, high FPS) taking up 70% of the screen.
  - 4 smaller grid tiles (substreams, low FPS) arranged vertically along the side or horizontally along the bottom.
  - Click any small tile to instantly swap it into the primary hero position.
- **1+N Security Wall Layouts**:
  - `1+5`, `1+7`, or `2+4` asymmetric CCTV monitor views.
- **Auto-Fit Layouts**:
  - Dynamic grid packing that automatically optimizes aspect ratio and tile layout based on active camera count (`1x1`, `2x1`, `2x2`, `3x2`, `3x3`, `4x2`).
- **Tile Drag & Drop / Reordering**:
  - Ability to rearrange camera tile order in the grid on the fly.

---

## 2. Settings Architecture & Defaults

- **Unified Schema Defaults**:
  - Automatic injection of `manifest.json` schema defaults directly into service and panel state without requiring explicit duplicate fallback definitions in QML.
- **Per-Camera Overrides in `cameras.json`**:
  - Custom FPS, hardware acceleration flag, or custom stream paths per camera (e.g. higher FPS for gate/driveway, lower for garden).
- **Settings GUI Modal**:
  - Interactive settings panel within VisionApp to adjust FPS, grid layout, hardware acceleration, and audio preferences without CLI commands.

---

## 3. Playback & Surveillance Features

- **One-Click 4K Snapshot Capture**:
  - Camera snapshot button in Cinema View and Grid to save a full-resolution JPEG directly to `~/Pictures/Screenshots/VisionHub_<camera>_<timestamp>.jpg` with desktop notification.
- **Fullscreen Kiosk Mode**:
  - <kbd>F11</kbd> / <kbd>F</kbd> toggle for borderless, immersive multi-camera monitoring on dedicated surveillance displays.
- **PTZ (Pan-Tilt-Zoom) Control**:
  - On-screen directional arrows and keyboard shortcuts (<kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> / <kbd>+</kbd><kbd>-</kbd>) to send ONVIF / RTSP PTZ commands to supported cameras.
- **Motion & Alert Integration**:
  - Visual border highlight (e.g. pulsing Amber/Red) when motion or line-crossing is detected via camera events or webhook integration.
