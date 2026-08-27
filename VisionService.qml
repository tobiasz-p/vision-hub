import QtQuick
import Quickshell
import Quickshell.Io

// VisionHub service — owns the Ruby daemon process and exposes camera state
// to the rest of the plugin.
//
// Lifecycle contract: the shell instantiates this once for the enabled plugin
// (keepLoaded) and destroys it on plugin unload/reload. The daemon is a child
// of this process tree; stopping the Process TERMs it, and the daemon's own
// teardown takes every ffmpeg down within its stop-grace window. Nothing video
// related ever runs inside the shell process itself.
Item {
  id: root

  // ---- injected by the shell ------------------------------------------------
  property var shell: null
  property var manifest: null

  // ---- paths -----------------------------------------------------------------
  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string configPath: homeDir !== ""
    ? homeDir + "/.config/vision-hub/cameras.json" : ""

  function resolveLocalPath(qmlFile) {
    var url = Qt.resolvedUrl(qmlFile).toString()
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }

  readonly property string daemonScript: resolveLocalPath("daemon.rb")
  readonly property string runtimeBase: {
    var xdg = Quickshell.env("XDG_RUNTIME_DIR")
    if (xdg && xdg !== "") return xdg
    var user = Quickshell.env("USER") || "user"
    return "/tmp/vision-hub-" + user
  }
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR")
    ? Quickshell.env("XDG_RUNTIME_DIR") + "/vision-hub"
    : runtimeBase

  // ---- daemon knobs (pushed by the bar widget's settings) --------------------
  property int subFps: 5
  property int mainFps: 15
  property bool hwaccel: true
  property string inputStrategy: "argv"
  readonly property string argSignature:
    subFps + "/" + mainFps + "/" + hwaccel + "/" + inputStrategy

  // ---- observed state ----------------------------------------------------------
  // cameraId -> { online: bool|null, streaming: bool, error: string|null }
  property var cameraStates: ({})
  readonly property var cameraIds: {
    var ids = []
    for (var id in cameraStates) ids.push(id)
    ids.sort()
    return ids
  }
  property bool _ready: false
  property string daemonError: ""
  property string configError: ""
  property int restartAttempts: 0
  property string snapshotDir: "Pictures/VisionHub"

  signal statesChanged()
  signal snapshotTaken(string cameraId, string path)

  function frameUrl(cameraId) {
    return "file://" + runtimeDir + "/" + cameraId + ".jpg"
  }

  function takeSnapshot(cameraId) {
    if (!cameraId) return ""
    var src = runtimeDir + "/" + cameraId + ".jpg"
    var d = new Date()
    var pad = function(n) { return n < 10 ? "0" + n : "" + n }
    var ts = d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate()) + "_" +
             pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds())
    var filename = "VisionHub_" + cameraId + "_" + ts + ".jpg"
    var rawFolder = root.snapshotDir || "Pictures/VisionHub"
    var folder = rawFolder.replace(/^~(?=$|\/)/, root.homeDir)
    var destDir = folder.startsWith("/") ? folder : (root.homeDir !== "" ? root.homeDir + "/" + folder : "/tmp/" + folder)
    var destPath = destDir + "/" + filename

    var shCmd = "(mkdir -p '" + destDir + "' && cp '" + src + "' '" + destPath + "' && action=$(notify-send -a 'VisionHub' -i '" + destPath + "' -A 'default=Open' 'VisionHub Snapshot' 'Saved " + filename + "\\nto " + rawFolder + "' 2>/dev/null) && [ \"$action\" = \"default\" ] && xdg-open '" + destPath + "' 2>/dev/null) &"
    snapshotProc.command = ["sh", "-c", shCmd]
    snapshotProc.running = true
    root.snapshotTaken(cameraId, destPath)
    return destPath
  }

  function stateFor(cameraId) {
    return cameraStates[cameraId] || null
  }

  function parseBool(value, fallback) {
    if (value === true || value === "true" || value === 1 || value === "1") return true
    if (value === false || value === "false" || value === 0 || value === "0") return false
    return fallback
  }

  function applySettings(settings) {
    if (settings.subFps !== undefined) {
      var sFps = parseInt(settings.subFps, 10)
      if (isFinite(sFps)) root.subFps = sFps
    }
    if (settings.mainFps !== undefined) {
      var mFps = parseInt(settings.mainFps, 10)
      if (isFinite(mFps)) root.mainFps = mFps
    }
    if (settings.hwaccel !== undefined) {
      root.hwaccel = parseBool(settings.hwaccel, root.hwaccel)
    }
    if (settings.audioEnabled !== undefined) {
      var audio = parseBool(settings.audioEnabled, root.defaultAudio)
      root.defaultAudio = audio
      root.audioEnabled = audio
    }
    if (settings.snapshotDir !== undefined && typeof settings.snapshotDir === "string" && settings.snapshotDir.trim() !== "") {
      root.snapshotDir = settings.snapshotDir.trim()
    }
  }

  // ---- commands toward the daemon ---------------------------------------------
  function send(payload) {
    if (!daemonProc || !daemonProc.running || !root._ready) return false
    daemonProc.write(JSON.stringify(payload) + "\n")
    return true
  }

  property bool defaultAudio: false
  property bool audioEnabled: false

  function focusCamera(cameraId, fps) {
    var targetFps = fps !== undefined ? fps : root.mainFps
    root.audioEnabled = root.defaultAudio
    send({ cmd: "focus", camera: cameraId, fps: targetFps, audio: root.audioEnabled })
  }

  function setMainFps(fps) {
    if (fps !== undefined && isFinite(fps)) root.mainFps = fps
    send({ cmd: "set_fps", fps: root.mainFps })
  }

  function toggleAudio(cameraId) {
    root.audioEnabled = !root.audioEnabled
    send({ cmd: "audio", camera: cameraId, enabled: root.audioEnabled })
    return root.audioEnabled
  }

  function unfocusCamera() {
    root.audioEnabled = false
    send({ cmd: "unfocus" })
  }

  function setWindowState(isOpen) {
    send({ cmd: "window", open: isOpen === true })
  }

  function refresh() {
    send({ cmd: "refresh" })
  }

  // ---- daemon lifecycle --------------------------------------------------------
  function daemonArguments() {
    var argv = ["ruby", root.daemonScript,
      "--config", root.configPath,
      "--runtime-dir", root.runtimeDir,
      "--fps", String(root.subFps),
      "--main-fps", String(root.mainFps)]
    if (!root.hwaccel) argv.push("--no-hwaccel")
    if (root.inputStrategy !== "argv") argv.push("--input", root.inputStrategy)
    return argv
  }

  function startDaemon() {
    if (!root.configPath) return
    if (!daemonProc) return
    if (daemonProc.running) return
    root.daemonError = ""
    daemonProc.command = root.daemonArguments()
    daemonProc.running = true
  }

  function stopDaemon() {
    if (!daemonProc) return
    if (daemonProc.running) daemonProc.running = false
  }

  function restartDaemon() {
    root.restartPending = true
    root.stopDaemon()
  }

  property bool restartPending: false

  Component.onCompleted: {
    ensureRuntimeDir.running = true
    startDaemon()
  }
  Component.onDestruction: stopDaemon()

  Process {
    id: snapshotProc
  }

  // The daemon writes frames into $XDG_RUNTIME_DIR/vision-hub; create it
  // before first spawn so ffmpeg never races the directory into existence.
  Process {
    id: ensureRuntimeDir
    command: ["mkdir", "-p", "-m", "0700", root.runtimeDir]
  }

  Process {
    id: daemonProc
    stdinEnabled: true

    stdout: SplitParser {
      onRead: function(line) {
        root.handleDaemonLine(line)
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var textLine = String(text || "").trim()
        if (textLine !== "") console.warn("[vision-hub daemon]", textLine)
      }
    }

    onStarted: {
      root._ready = false
      root.restartPending = false
    }

    onExited: function(exitCode) {
      root._ready = false
      if (root.restartPending) {
        root.startDaemon()
        return
      }
      // Unexpected exit: retry with a capped schedule. A missing ruby or a
      // bad config keeps failing here, so after several attempts we stop
      // hammering and let the UI show the failure.
      root.restartAttempts += 1
      if (root.restartAttempts <= 5) restartTimer.interval = root.restartAttempts * 2000
      else {
        root.daemonError = "daemon exited (code " + exitCode + "); giving up after " + root.restartAttempts + " attempts"
        return
      }
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: root.startDaemon()
  }

  function handleDaemonLine(line) {
    var msg
    try {
      msg = JSON.parse(line)
    } catch (e) {
      console.warn("[vision-hub] undecodable daemon line:", line)
      return
    }
    if (!msg || typeof msg !== "object") return

    switch (msg.event) {
      case "hello":
        root._ready = true
        root.restartAttempts = 0
        root.configError = ""
        break
      case "camera_state":
        var next = Object.assign({}, root.cameraStates)
        next[msg.id] = {
          name: msg.name || msg.id,
          online: msg.online,
          streaming: msg.streaming === true,
          error: msg.error || null
        }
        root.cameraStates = next
        root.statesChanged()
        break
      case "config_error":
        root.configError = String(msg.message || "cameras.json could not be read")
        break
      case "error":
        console.warn("[vision-hub] daemon:", msg.message || "(no detail)")
        break
      default:
        break
    }
  }

  // Settings flips while the daemon runs come through applySettings; expose
  // argSignature so dev tooling can assert what the daemon was launched with.
  onArgSignatureChanged: {
    if (daemonProc.running) restartDaemon()
  }
}
