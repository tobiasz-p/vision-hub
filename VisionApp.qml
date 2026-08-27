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
  property string viewMode: "grid"
  property int fillMode: Image.PreserveAspectFit
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

    var targetMode = payload.view || payload.defaultView
    if (payload.camera) {
      if (targetMode === "hero") root.showHero(String(payload.camera))
      else root.showCinema(String(payload.camera))
    } else if (targetMode === "hero") {
      root.showHero()
    } else if (targetMode === "cinema") {
      root.showCinema()
    } else {
      root.showGrid()
    }

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
    showCinema(cameraId)
  }

  function showCinema(cameraId) {
    var targetId = cameraId || root.focusedId || (root.cameraList.length > 0 ? root.cameraList[0] : "")
    if (!targetId) return
    root.fpsDropdownOpen = false
    root.focusedId = targetId
    root.viewMode = "cinema"
    if (root.visionService && typeof root.visionService.focusCamera === "function") {
      root.visionService.focusCamera(targetId, root.streamFps)
    }
  }

  function showHero(cameraId) {
    var targetId = cameraId || root.focusedId || (root.cameraList.length > 0 ? root.cameraList[0] : "")
    if (!targetId) return
    root.fpsDropdownOpen = false
    root.focusedId = targetId
    root.viewMode = "hero"
    if (root.visionService && typeof root.visionService.focusCamera === "function") {
      root.visionService.focusCamera(targetId, root.streamFps)
    }
  }

  function showGrid() {
    root.patrolMode = false
    root.fpsDropdownOpen = false
    root.viewMode = "grid"
    if (root.focusedId !== "" && root.visionService && typeof root.visionService.unfocusCamera === "function") {
      root.visionService.unfocusCamera()
    }
    root.focusedId = ""
  }

  function showNextCamera() {
    if (cameraList.length === 0) return
    var idx = currentCameraIndex
    var nextIdx = (idx + 1) % cameraList.length
    if (root.viewMode === "hero") root.showHero(cameraList[nextIdx])
    else root.showCinema(cameraList[nextIdx])
  }

  function showPrevCamera() {
    if (cameraList.length === 0) return
    var idx = currentCameraIndex
    var prevIdx = (idx - 1 + cameraList.length) % cameraList.length
    if (root.viewMode === "hero") root.showHero(cameraList[prevIdx])
    else root.showCinema(cameraList[prevIdx])
  }

  function toggleAspect() {
    root.fillMode = root.fillMode === Image.PreserveAspectFit ? Image.PreserveAspectCrop : Image.PreserveAspectFit
  }

  function takeSnapshot(cameraId) {
    var targetId = cameraId || root.focusedId
    if (!targetId && root.cameraList.length > 0) targetId = root.cameraList[0]
    if (!targetId || !root.visionService || typeof root.visionService.takeSnapshot !== "function") return ""
    var res = root.visionService.takeSnapshot(targetId)
    if (cinemaLoader.item && typeof cinemaLoader.item.triggerFlash === "function") {
      cinemaLoader.item.triggerFlash()
    }
    if (heroLoader.item && typeof heroLoader.item.triggerFlash === "function") {
      heroLoader.item.triggerFlash()
    }
    return res
  }

  // Patrol / Auto-Cycle Timer (cycles cameras in focused/hero mode)
  Timer {
    interval: Theme.animation.patrolIntervalMs
    repeat: true
    running: window.visible && root.patrolMode && root.focusedId !== "" && root.cameraList.length > 1
    onTriggered: root.showNextCamera()
  }

  // ---- window -----------------------------------------------------------------
  FloatingWindow {
    id: window
    visible: false

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
        if (root.viewMode !== "grid") root.showGrid()
        else root.requestClose()
      }

      Keys.onLeftPressed: {
        if (root.viewMode !== "grid") root.showPrevCamera()
      }

      Keys.onRightPressed: {
        if (root.viewMode !== "grid") root.showNextCamera()
      }

      Keys.onSpacePressed: {
        if (root.viewMode !== "grid") root.patrolMode = !root.patrolMode
      }

      Keys.onDigit1Pressed: if (root.cameraList.length >= 1) (root.viewMode === "hero" ? root.showHero(root.cameraList[0]) : root.showCinema(root.cameraList[0]))
      Keys.onDigit2Pressed: if (root.cameraList.length >= 2) (root.viewMode === "hero" ? root.showHero(root.cameraList[1]) : root.showCinema(root.cameraList[1]))
      Keys.onDigit3Pressed: if (root.cameraList.length >= 3) (root.viewMode === "hero" ? root.showHero(root.cameraList[2]) : root.showCinema(root.cameraList[2]))
      Keys.onDigit4Pressed: if (root.cameraList.length >= 4) (root.viewMode === "hero" ? root.showHero(root.cameraList[3]) : root.showCinema(root.cameraList[3]))
      Keys.onDigit5Pressed: if (root.cameraList.length >= 5) (root.viewMode === "hero" ? root.showHero(root.cameraList[4]) : root.showCinema(root.cameraList[4]))

      Keys.onPressed: function(event) {
        if ((event.key === Qt.Key_M || event.text === "m" || event.text === "M") && root.focusedId !== "") {
          if (root.visionService && typeof root.visionService.toggleAudio === "function") {
            root.visionService.toggleAudio(root.focusedId)
          }
          event.accepted = true
        } else if (event.key === Qt.Key_S || event.text === "s" || event.text === "S") {
          root.takeSnapshot(root.focusedId)
          event.accepted = true
        } else if (event.key === Qt.Key_A || event.text === "a" || event.text === "A") {
          root.toggleAspect()
          event.accepted = true
        } else if (event.key === Qt.Key_G || event.text === "g" || event.text === "G") {
          root.showGrid()
          event.accepted = true
        } else if (event.key === Qt.Key_H || event.text === "h" || event.text === "H") {
          root.showHero()
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
        viewMode: root.viewMode
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
        onShowHero: root.showHero()
        onShowCinema: root.showCinema()
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
          id: cinemaLoader
          anchors.fill: parent
          active: root.viewMode === "cinema" && root.focusedId !== ""
          sourceComponent: Component {
            CinemaView {
              focusedId: root.focusedId
              streamFps: root.streamFps
              fillMode: root.fillMode
              isAudioOn: root.isAudioOn
              cameraList: root.cameraList
              totalCount: root.totalCount
              visionService: root.visionService
              onPrevCamera: root.showPrevCamera()
              onNextCamera: root.showNextCamera()
              onSelectCamera: (camId) => root.showCinema(camId)
              onTakeSnapshot: (snapCamId) => root.takeSnapshot(snapCamId)
              onToggleAspect: root.toggleAspect()
            }
          }
        }

        // Hero 4+1 Multi-Camera Live View
        Loader {
          id: heroLoader
          anchors.fill: parent
          active: root.viewMode === "hero" && root.focusedId !== ""
          sourceComponent: Component {
            HeroView {
              focusedId: root.focusedId
              streamFps: root.streamFps
              fillMode: root.fillMode
              isAudioOn: root.isAudioOn
              cameraList: root.cameraList
              totalCount: root.totalCount
              visionService: root.visionService
              onPrevCamera: root.showPrevCamera()
              onNextCamera: root.showNextCamera()
              onSelectCamera: (camId) => root.showHero(camId)
              onTakeSnapshot: (snapCamId) => root.takeSnapshot(snapCamId)
              onToggleAspect: root.toggleAspect()
            }
          }
        }

        // Modern Multi-Camera Grid View
        CameraGridView {
          anchors.fill: parent
          anchors.margins: Style.space(14)
          visible: root.viewMode === "grid" && root.totalCount > 0
          cameraList: root.cameraList
          columns: root.columns
          visionService: root.visionService
          onSelectCamera: (camId) => root.showCinema(camId)
          onTakeSnapshot: (camId) => root.takeSnapshot(camId)
        }

        // Empty state
        EmptyState {
          anchors.centerIn: parent
          visible: (root.viewMode === "grid" || root.focusedId === "") && (root.visionService === null || root.totalCount === 0)
          visionService: root.visionService
        }
      }
    }
  }
}
