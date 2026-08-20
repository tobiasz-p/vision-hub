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
  readonly property string runtimeBase: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
  readonly property string runtimeDir: runtimeBase + "/vision-hub"

  // ---- daemon knobs (pushed by the bar widget's settings) --------------------
  property int subFps: 5
  property int mainFps: 10
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
  readonly property bool sessionReady: _ready
  property bool _ready: false
  property string daemonError: ""
  property string configError: ""
  property int restartAttempts: 0

  signal statesChanged()

  function frameUrl(cameraId) {
    return "file://" + runtimeDir + "/" + cameraId + ".jpg"
  }

  function stateFor(cameraId) {
    return cameraStates[cameraId] || null
  }

  function applySettings(settings) {
    var changed = false
    if (settings.subFps !== undefined && settings.subFps !== root.subFps) {
      root.subFps = settings.subFps
      changed = true
    }
    if (settings.mainFps !== undefined && settings.mainFps !== root.mainFps) {
      root.mainFps = settings.mainFps
      changed = true
    }
    if (settings.hwaccel !== undefined && settings.hwaccel !== root.hwaccel) {
      root.hwaccel = settings.hwaccel
      changed = true
    }
    // The actual restart is driven by onArgSignatureChanged so every knob
    // change funnels through one code path.
  }

  // ---- commands toward the daemon ---------------------------------------------
  function send(payload) {
    if (!daemonProc || !daemonProc.running || !root._ready) return false
    daemonProc.write(JSON.stringify(payload) + "\n")
    return true
  }

  function focus(cameraId) {
    send({ cmd: "focus", camera: cameraId })
  }

  function unfocus() {
    send({ cmd: "unfocus" })
  }

  function refresh() {
    send({ cmd: "refresh" })
  }

  function ping(echoToken) {
    return send({ cmd: "ping", echo: echoToken })
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

  // The daemon writes frames into $XDG_RUNTIME_DIR/vision-hub; create it
  // before first spawn so ffmpeg never races the directory into existence.
  Process {
    id: ensureRuntimeDir
    command: ["mkdir", "-p", root.runtimeDir]
  }

  Process {
    id: daemonProc

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
