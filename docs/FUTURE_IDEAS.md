# VisionHub — Future Ideas & Roadmap

This document collects enhancement ideas, layout explorations, and architectural improvements for upcoming iterations of VisionHub.

---

## 1. Advanced Multi-Camera Grid Layouts

- [x] **4+1 Hero Layout** *(Implemented)*:
  - 1 large primary/hero stream taking up the main viewport.
  - Interactive live camera dock with live substream tiles along the bottom.
  - Click any tile to instantly swap it into the primary hero position.
- [ ] **1+N Security Wall Layouts**:
  - `1+5`, `1+7`, or `2+4` asymmetric CCTV monitor views.
- [ ] **Auto-Fit Layouts**:
  - Dynamic grid packing that automatically optimizes aspect ratio and tile layout based on active camera count (`1x1`, `2x1`, `2x2`, `3x2`, `3x3`, `4x2`).
- [ ] **Tile Drag & Drop / Reordering**:
  - Ability to rearrange camera tile order in the grid on the fly.

---

## 2. Settings Architecture & Defaults

- [ ] **Unified Schema Defaults**:
  - Automatic injection of `manifest.json` schema defaults directly into service and panel state without requiring explicit duplicate fallback definitions in QML.
- [ ] **Per-Camera Overrides in `cameras.json`**:
  - Custom FPS, hardware acceleration flag, custom stream paths, and custom location alias names per camera.
- [ ] **Settings GUI Modal**:
  - Interactive settings panel within VisionApp to adjust FPS, grid layout, hardware acceleration, camera names, and audio preferences without CLI commands.

---

## 3. Playback & Surveillance Features

- [x] **One-Click Instant Snapshot Capture** *(Implemented)*:
  - Camera snapshot button in Cinema, Hero, and Grid views saving timestamped JPEGs directly to `~/Pictures/VisionHub/VisionHub_<camera>_<timestamp>.jpg` with shutter flash feedback and desktop notifications.
- [ ] **Fullscreen Kiosk Mode**:
  - <kbd>F11</kbd> / <kbd>F</kbd> toggle for borderless, immersive multi-camera monitoring on dedicated surveillance displays.
- [ ] **PTZ (Pan-Tilt-Zoom) Control**:
  - On-screen directional arrows and keyboard shortcuts (<kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> / <kbd>+</kbd><kbd>-</kbd>) to send ONVIF / RTSP PTZ commands to supported cameras.
- [ ] **Motion & Alert Integration**:
  - Visual border highlight (e.g. pulsing Amber/Red) when motion or line-crossing is detected via camera events or webhook integration.

---

## 4. UI & Visual Polish

- [x] **Aspect Ratio Fit vs Fill (Crop) Mode** *(Implemented)*:
  - Dynamic toggle (<kbd>A</kbd> / header button) to switch between clean pillarbox/letterbox aspect fit and cropped full-bleed view.
- [ ] **Pixel-Perfect Alignment & Typography**:
  - Fine-tune icon-to-text vertical centering across Nerd Font glyphs, badges, and headers.
  - Standardize button padding, pill margins, and icon baseline offsets across all viewport sizes.
  - Polish floating control toolbar and bottom camera dock margins.
