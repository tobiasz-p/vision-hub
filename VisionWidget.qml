import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"

// VisionHub bar widget — camera health at a glance.
//
// Shows one glyph plus an "n/m" online counter when cameras are configured.
// Left click opens the live-view window; right click asks the daemon to
// re-probe everything now; middle click force refreshes.
BarWidget {
  id: root
  moduleName: Theme.pluginId

  function parseBool(value, fallback) {
    if (value === true || value === "true" || value === 1 || value === "1") return true
    if (value === false || value === "false" || value === 0 || value === "0") return false
    return fallback
  }

  // ---- settings (shell.json layout entry via `omarchy bar set`) ----------
  readonly property int subFps: clampInt(setting("targetFps", 5), 1, 15)
  readonly property int mainFps: clampInt(setting("mainFps", 10), 1, 30)
  readonly property bool hwaccel: parseBool(setting("hwaccel", true), true)
  readonly property bool defaultAudio: parseBool(setting("audioEnabled", false), false)
  readonly property int gridColumns: clampInt(setting("gridColumns", 3), 1, 6)
  readonly property string snapshotDir: setting("snapshotDir", "Pictures/VisionHub")
  readonly property string defaultView: {
    var v = String(setting("defaultView", "grid")).toLowerCase()
    return (v === "hero" || v === "cinema") ? v : "grid"
  }

  function clampInt(value, min, max) {
    var n = parseInt(value, 10)
    if (!isFinite(n)) n = min
    return Math.max(min, Math.min(max, n))
  }

  // ---- service link ---------------------------------------------------------
  readonly property var visionService: bar && bar.shell ? bar.shell.serviceFor(Theme.pluginId) : null

  function pushSettings() {
    if (!visionService) return
    visionService.applySettings({
      subFps: root.subFps,
      mainFps: root.mainFps,
      hwaccel: root.hwaccel,
      audioEnabled: root.defaultAudio,
      snapshotDir: root.snapshotDir
    })
  }

  Component.onCompleted: root.pushSettings()
  onVisionServiceChanged: root.pushSettings()
  onSettingsChanged: root.pushSettings()
  onDefaultAudioChanged: root.pushSettings()
  onSubFpsChanged: root.pushSettings()
  onMainFpsChanged: root.pushSettings()
  onHwaccelChanged: root.pushSettings()
  onSnapshotDirChanged: root.pushSettings()

  // ---- derived state -----------------------------------------------------------
  readonly property var states: visionService ? visionService.cameraStates : ({})
  readonly property int totalCameras: {
    var count = 0
    for (var id in states) count += 1
    return count
  }
  readonly property int onlineCameras: {
    var count = 0
    for (var id in states) if (states[id].online === true) count += 1
    return count
  }
  readonly property bool configured: totalCameras > 0
  readonly property bool anyOffline: configured && onlineCameras < totalCameras

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button

    anchors.fill: parent
    bar: root.bar
    text: root.configured ? "󰹗 " + root.onlineCameras + "/" + root.totalCameras : "󰹗"
    labelVisible: true
    hasVisualContent: true
    dimmed: !root.configured
    active: root.anyOffline
    useActiveColor: true
    tooltipText: root.tooltipLine

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) {
        if (root.visionService) root.visionService.refresh()
        else if (root.bar && root.bar.shell) root.bar.shell.toggle(Theme.pluginId, "{}")
        return
      }
      if (mouseButton === Qt.MiddleButton) {
        if (root.visionService) root.visionService.refresh()
        return
      }
      if (root.bar && root.bar.shell) {
        root.bar.shell.toggle(Theme.pluginId, JSON.stringify({
          columns: root.gridColumns,
          view: root.defaultView
        }))
      }
    }
  }

  readonly property string tooltipLine: {
    var lines = []
    if (!root.configured) {
      lines.push("VisionHub — no cameras configured")
      lines.push("Add ~/.config/vision-hub/cameras.json")
      return lines.join("\n")
    }
    var service = root.visionService
    for (var id in root.states) {
      var state = root.states[id]
      var mark = state.online === true ? "●" : (state.online === false ? "✕" : "○")
      var line = mark + " " + id
      if (state.error) line += " (" + state.error + ")"
      else if (state.online === false) line += " (offline)"
      else if (state.streaming) line += " (live)"
      lines.push(line)
    }
    if (service && service.configError !== "") lines.push("Config: " + service.configError)
    if (service && service.daemonError !== "") lines.push(service.daemonError)
    lines.push("Left-click: open grid · Right-click: re-probe")
    return lines.join("\n")
  }
}
