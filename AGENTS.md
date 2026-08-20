# AGENTS.md

Omarchy (Quickshell) plugin providing live RTSP IP camera monitoring via a top-bar health widget and a floating multi-camera live-view window. NOT a Node app — the UI runtime is QML / Quickshell, backed by an asynchronous Ruby daemon.

## Architecture

- `manifest.json`: Plugin descriptor; kinds: `["service", "bar-widget", "panel"]`.
- `VisionService.qml`: Long-lived headless service managing the background Ruby daemon process lifecycle (`Process` + `SplitParser`) and state broadcasting.
- `VisionWidget.qml`: Top bar widget displaying aggregate camera health (`󰹗 online/total`), tooltips, and click gestures.
- `VisionApp.qml`: Floating desktop window (`FloatingWindow`) rendering a configurable camera grid (substreams) and a focused single-camera view (mainstream).
- `daemon.rb`: CLI daemon entrypoint reading JSON-lines commands over stdin and running supervision ticks.
- `lib/vision_hub/`: Pure Ruby background engine (Ruby 3.4+):
  - `camera.rb`: Non-secret camera definition value object and URL builder.
  - `config.rb`: Validation and parsing of `cameras.json`.
  - `secret_store.rb`: Secure password lookup from gnome-keyring via `secret-tool`.
  - `health_probe.rb`: Non-blocking TCP reachability probing.
  - `frame_pump.rb`: Crash-isolated `ffmpeg` child process supervision with exponential backoff.
  - `child_process.rb`: Process lifecycle management, PID tracking, and signal handling.
  - `clock.rb`: Monotonic clock abstraction for deterministic testing.
  - `ipc.rb`: Newline-delimited JSON-lines framing, size limits, and decoding error handling.
  - `supervisor.rb`: High-level orchestrator coordinating config, health probes, frame pumps, and IPC dispatch.

## Critical Runtime Constraints

- **Process Crash Isolation**: Video decoding must never execute in the long-running shell process. Each active camera stream is decoded by an isolated `ffmpeg` child process owned by the Ruby daemon.
- **tmpfs Frame Buffer**: `ffmpeg` writes overwritten JPEGs into `$XDG_RUNTIME_DIR/vision-hub` (RAM-backed tmpfs). QML reloads frames asynchronously with cache-busting timestamps.
- **Credential Security**: Passwords reside exclusively in gnome-keyring (`secret-tool`). Secrets are never written to disk, never logged to stdout/stderr, and never committed to `shell.json`.
- **Clean Process Teardown**: Every `ffmpeg` child process terminates immediately when unneeded or when the daemon exits; the daemon terminates when the shell unloads the service. No orphan processes across reloads.
- **No Symlinks**: `omarchy plugin validate` rejects symlinks anywhere within the plugin folder. Bundled gems and vendor files must live outside the plugin directory (`~/.local/share/tobiasz-p.vision-hub/bundle`).

## Coding Practices & Guidelines

- **Names carry the meaning**: Use clear, domain-specific names (`frame_pump`, `health_probe`, `stream_url`). Avoid non-standard abbreviations.
- **Single responsibility per file**: Keep logic cohesive and focused.
- **Make invalid states unrepresentable**: Validate input at the system boundary (e.g. `Config.load`) so internal domain objects are always valid.
- **Actionable error messages**: Error messages should clearly state what failed and what command or action resolves it.
- **Dependency injection over mocking**: Constructor-inject external I/O collaborators (spawner, clock, secret runner, sockets) with sensible defaults. Unit tests must run with zero network access and no external dependencies.
- **Fail loudly at boundaries, degrade gracefully in UI**: Surface errors with actionable diagnostic text in the UI rather than failing silently or hanging.
- **Never log a secret**: Passwords must never appear in logs, debug statements, exception messages, or `inspect` strings.

## Workflow Conventions

- Contributions follow Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `chore:`) and a strictly linear history (rebase, no merge commits).
- Always verify all test suites and linter checks pass before committing:
  ```sh
  bundle exec rake && omarchy plugin validate ~/.config/omarchy/plugins/tobiasz-p.vision-hub
  ```
- Widget settings are configured via `omarchy bar set tobiasz-p.vision-hub <key> <value>`.

## Releasing

- Merge all PRs **before** tagging. The marketplace verifies exact commit snapshots, which are immutable once published.
- Semver from Conventional Commits: `fix:` → patch, `feat:` → minor, breaking → major.
- Bump `version` in `manifest.json`, commit as `chore: bump version to X.Y.Z`, then tag without the `v` prefix and push both:
  ```sh
  git tag -a X.Y.Z -m "X.Y.Z" && git push origin main X.Y.Z
  ```
- Create the GitHub release:
  ```sh
  gh release create X.Y.Z --title "X.Y.Z" --notes "..."
  ```
- Ask for marketplace verification with a `[Verify]` issue on `HANCORE-linux/omarchy-plugin-marketplace`.
