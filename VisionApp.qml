import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "components"

// VisionHub modern surveillance live-view window:
// Next-gen multi-camera grid and cinema single-camera live view with dynamic theme integration.
Item {
  id: root

  // ---- host injections ------------------------------------------------------
  property var shell: null
  property var manifest: null
  property var service: null

  // ---- shape contract ---------------------------------------------------------
  property bool opened: window.visible
  property bool closingFromHost: false
  property string focusedId: ""
  property int columns: 3
  property bool patrolMode: false
  property int streamFps: visionService ? visionService.mainFps : 15
  property bool fpsDropdownOpen: false
  readonly property bool isAudioOn: visionService ? visionService.audioEnabled : false

  readonly property var fpsOptions: [5, 10, 15, 20, 25, 30]

  readonly property string pluginId: manifest ? manifest.id : Theme.pluginId
  readonly property var visionService: service || (shell && typeof shell.serviceFor === "function" ? shell.serviceFor(root.pluginId) : null)

  readonly property var cameraList: visionService ? visionService.cameraIds : []
  readonly property int totalCount: cameraList.length
  readonly property int onlineCount: {
    var count = 0
    if (!visionService) return 0
    for (var i = 0; i < cameraList.length; i++) {
      var st = visionService.stateFor(cameraList[i])
      if (st && st.online === true) count += 1
    }
    return count
  }

  readonly property int currentCameraIndex: {
    if (focusedId === "" || cameraList.length === 0) return -1
    for (var i = 0; i < cameraList.length; i++) {
      if (cameraList[i] === focusedId) return i
    }
    return -1
  }

  function open(payloadJson) {
    var payload = {}
    try {
      payload = JSON.parse(payloadJson || "{}") || {}
    } catch (e) {
      payload = {}
    }
    if (payload.columns !== undefined) {
      var n = parseInt(payload.columns, 10)
      root.columns = isFinite(n) && n >= 1 && n <= 6 ? n : 3
    }
    closingFromHost = false
    root.fpsDropdownOpen = false
    window.visible = true
    if (payload.camera) root.showFocused(String(payload.camera))
    windowContent.forceActiveFocus()
  }

  function close() {
    root.showGrid()
    root.patrolMode = false
    root.fpsDropdownOpen = false
    closingFromHost = true
    window.visible = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(root.pluginId)
    else close()
  }

  function showFocused(cameraId) {
    if (!cameraId) return
    root.fpsDropdownOpen = false
    root.focusedId = cameraId
    if (root.visionService && typeof root.visionService.focusCamera === "function") {
      root.visionService.focusCamera(cameraId, root.streamFps)
    }
  }

  function showGrid() {
    root.patrolMode = false
    root.fpsDropdownOpen = false
    if (root.focusedId !== "" && root.visionService && typeof root.visionService.unfocusCamera === "function") {
      root.visionService.unfocusCamera()
    }
    root.focusedId = ""
  }

  function showNextCamera() {
    if (cameraList.length === 0) return
    var idx = currentCameraIndex
    var nextIdx = (idx + 1) % cameraList.length
    showFocused(cameraList[nextIdx])
  }

  function showPrevCamera() {
    if (cameraList.length === 0) return
    var idx = currentCameraIndex
    var prevIdx = (idx - 1 + cameraList.length) % cameraList.length
    showFocused(cameraList[prevIdx])
  }

  // Patrol / Auto-Cycle Timer (cycles cameras in focused mode)
  Timer {
    interval: Theme.animation.patrolIntervalMs
    repeat: true
    running: window.visible && root.patrolMode && root.focusedId !== "" && root.cameraList.length > 1
    onTriggered: root.showNextCamera()
  }

  // ---- window -----------------------------------------------------------------
  FloatingWindow {
    id: window

    readonly property var focusedState: root.visionService ? root.visionService.stateFor(root.focusedId) : null
    title: "VisionHub" + (root.focusedId !== "" ? " — " + (focusedState && focusedState.name ? focusedState.name : root.focusedId) : "")
    color: Color.background
    implicitWidth: Theme.screens.defaultWindowWidth
    implicitHeight: Theme.screens.defaultWindowHeight
    minimumSize: Qt.size(Theme.screens.minWindowWidth, Theme.screens.minWindowHeight)

    onVisibleChanged: {
      if (root.visionService && typeof root.visionService.setWindowState === "function") {
        root.visionService.setWindowState(visible)
      }
      if (!visible && !root.closingFromHost) {
        if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
        else root.close()
      }
      if (visible) windowContent.forceActiveFocus()
    }

    FocusScope {
      id: windowContent
      anchors.fill: parent
      focus: true

      Shortcut {
        sequences: [StandardKey.Close, "Ctrl+W"]
        onActivated: root.requestClose()
      }

      Keys.onEscapePressed: {
        if (root.focusedId !== "") root.showGrid()
        else root.requestClose()
      }

      Keys.onLeftPressed: {
        if (root.focusedId !== "") root.showPrevCamera()
      }

      Keys.onRightPressed: {
        if (root.focusedId !== "") root.showNextCamera()
      }

      Keys.onSpacePressed: {
        if (root.focusedId !== "") root.patrolMode = !root.patrolMode
      }

      Keys.onDigit1Pressed: if (root.cameraList.length >= 1) root.showFocused(root.cameraList[0])
      Keys.onDigit2Pressed: if (root.cameraList.length >= 2) root.showFocused(root.cameraList[1])
      Keys.onDigit3Pressed: if (root.cameraList.length >= 3) root.showFocused(root.cameraList[2])
      Keys.onDigit4Pressed: if (root.cameraList.length >= 4) root.showFocused(root.cameraList[3])
      Keys.onDigit5Pressed: if (root.cameraList.length >= 5) root.showFocused(root.cameraList[4])

      Keys.onPressed: function(event) {
        if ((event.key === Qt.Key_M || event.text === "m" || event.text === "M") && root.focusedId !== "") {
          if (root.visionService && typeof root.visionService.toggleAudio === "function") {
            root.visionService.toggleAudio(root.focusedId)
          }
          event.accepted = true
        }
      }

      // Modern Glass Header Bar
      HeaderBar {
        id: headerBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        focusedId: root.focusedId
        onlineCount: root.onlineCount
        totalCount: root.totalCount
        columns: root.columns
        streamFps: root.streamFps
        fpsOptions: root.fpsOptions
        isAudioOn: root.isAudioOn
        patrolMode: root.patrolMode
        focusedState: window.focusedState
        fpsDropdownOpen: root.fpsDropdownOpen

        onShowGrid: root.showGrid()
        onShowCinema: {
          if (root.focusedId === "" && root.cameraList.length > 0) {
            root.showFocused(root.cameraList[0])
          }
        }
        onSelectColumns: (cols) => root.columns = cols
        onSelectFps: (fps) => {
          root.streamFps = fps
          if (root.visionService && typeof root.visionService.setMainFps === "function") {
            root.visionService.setMainFps(fps)
          }
        }
        onToggleAudio: {
          if (root.visionService && typeof root.visionService.toggleAudio === "function") {
            root.visionService.toggleAudio(root.focusedId)
          }
        }
        onTogglePatrol: root.patrolMode = !root.patrolMode
      }

      // Content Area
      Item {
        anchors.top: headerBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // Cinema Focused Single-Camera Live View
        Loader {
          anchors.fill: parent
          active: root.focusedId !== ""
          sourceComponent: Component {
            CinemaView {
              focusedId: root.focusedId
              streamFps: root.streamFps
              isAudioOn: root.isAudioOn
              cameraList: root.cameraList
              totalCount: root.totalCount
              visionService: root.visionService
              onPrevCamera: root.showPrevCamera()
              onNextCamera: root.showNextCamera()
              onSelectCamera: (camId) => root.showFocused(camId)
            }
          }
        }

        // Modern Multi-Camera Grid View
        CameraGridView {
          anchors.fill: parent
          anchors.margins: Style.space(14)
          visible: root.focusedId === "" && root.totalCount > 0
          cameraList: root.cameraList
          columns: root.columns
          visionService: root.visionService
          onSelectCamera: (camId) => root.showFocused(camId)
        }

        // Empty state
        EmptyState {
          anchors.centerIn: parent
          visible: root.focusedId === "" && (root.visionService === null || root.totalCount === 0)
          visionService: root.visionService
        }
      }
    }
  }
}
