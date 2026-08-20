import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// VisionHub live-view window: a grid of camera tiles plus a focused
// single-camera view.
//
// Frames come from the daemon's continuously-overwritten JPEGs on tmpfs;
// each tile re-resolves its file:// URL on its own timer (cache-busted) so
// decoding happens entirely inside this window process, never in the shell's
// compositor surface. Closing the window unfocuses any main stream so the
// daemon tears the high-fps ffmpeg down immediately.
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

  readonly property string pluginId: manifest ? manifest.id : "tobiasz-p.vision-hub"
  readonly property var visionService: service

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
    window.visible = true
    if (payload.camera) root.showFocused(String(payload.camera))
    windowContent.forceActiveFocus()
  }

  function close() {
    root.showGrid()
    closingFromHost = true
    window.visible = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(root.pluginId)
    else close()
  }

  function showFocused(cameraId) {
    if (!cameraId) return
    root.focusedId = cameraId
    if (root.visionService) root.visionService.focus(cameraId)
  }

  function showGrid() {
    if (root.focusedId !== "" && root.visionService) root.visionService.unfocus()
    root.focusedId = ""
  }

  // ---- window -----------------------------------------------------------------
  FloatingWindow {
    id: window

    title: "VisionHub" + (root.focusedId !== "" ? " — " + root.focusedId : "")
    color: Color.background
    implicitWidth: 980
    implicitHeight: 660
    minimumSize: Qt.size(560, 420)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost) {
        // Closed by the WM or a close button: keep the shell's open-panel map
        // consistent so `toggle` works next time.
        if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
        else root.close()
      }
      if (visible) windowContent.forceActiveFocus()
    }

    FocusScope {
      id: windowContent
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: {
        if (root.focusedId !== "") root.showGrid()
        else root.requestClose()
      }

      // ---- focused single-camera view -------------------------------------
      Loader {
        id: focusedLoader
        anchors.fill: parent
        active: root.focusedId !== ""

        sourceComponent: Component {
          Item {
            anchors.fill: parent

            FrameImage {
              id: focusedFrame
              anchors.fill: parent
              anchors.margins: Style.space(10)
              cameraId: root.focusedId
              fps: root.visionService ? root.visionService.mainFps : 10
              baseUrl: root.visionService ? root.visionService.frameUrl(root.focusedId) : ""
              state: root.visionService ? root.visionService.stateFor(root.focusedId) : null
            }

            Row {
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.margins: Style.space(14)
              spacing: Style.space(8)

              WidgetButton {
                bar: null
                text: "← Grid"
                onPressed: function(mouseButton) {
                  root.showGrid()
                }
              }
            }
          }
        }
      }

      // ---- grid --------------------------------------------------------------
      GridView {
        id: grid
        anchors.fill: parent
        anchors.margins: Style.space(8)
        visible: root.focusedId === ""
        clip: true
        cellWidth: Math.floor(width / Math.max(1, root.columns))
        cellHeight: Math.floor(cellWidth * 9 / 16)

        model: root.visionService ? root.visionService.cameraIds : []

        delegate: Item {
          id: delegateRoot

          required property string modelData
          width: grid.cellWidth
          height: grid.cellHeight

          CameraTile {
            anchors.fill: parent
            anchors.margins: Style.space(4)
            cameraId: delegateRoot.modelData
            fps: root.visionService ? root.visionService.subFps : 5
            baseUrl: root.visionService ? root.visionService.frameUrl(delegateRoot.modelData) : ""
            state: root.visionService ? root.visionService.stateFor(delegateRoot.modelData) : null

            onTap: function(tappedCameraId) {
              root.showFocused(tappedCameraId)
            }
          }
        }
      }

      // Empty state: no daemon state yet or no cameras configured.
      Column {
        anchors.centerIn: parent
        visible: root.focusedId === "" && (root.visionService === null || root.visionService.cameraIds.length === 0)
        spacing: Style.space(8)

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: {
            if (!root.visionService || !root.visionService.sessionReady)
              return "Connecting to vision-hub daemon…"
            if (root.visionService.configError !== "")
              return "Config problem: " + root.visionService.configError
            return "No cameras configured"
          }
          color: Color.foreground
          font.pixelSize: Style.font.body
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Create ~/.config/vision-hub/cameras.json and store passwords with secret-tool"
          color: Color.muted
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // ---- components ---------------------------------------------------------------

  // Repeatedly re-resolves one overwritten JPEG. The tick suffix defeats the
  // image cache; `asynchronous` keeps decode stalls out of the UI thread.
  component FrameImage: Image {
    id: frame

    property string cameraId: ""
    property int fps: 5
    property string baseUrl: ""
    property var state: null
    property int tick: 0

    function bump() {
      if (baseUrl === "") return
      frame.tick += 1
    }

    source: baseUrl !== "" ? baseUrl + "?t=" + frame.tick : ""
    cache: false
    asynchronous: true
    fillMode: Image.PreserveAspectCrop
    visible: status === Image.Ready

    Timer {
      interval: Math.max(100, Math.floor(1000 / Math.max(1, frame.fps)))
      repeat: true
      running: frame.visible && window.visible
      triggeredOnStart: true
      onTriggered: frame.bump()
    }
  }

  component CameraTile: Rectangle {
    id: tile

    signal tap(string cameraId)

    property string cameraId: ""
    property int fps: 5
    property string baseUrl: ""
    property var state: null

    readonly property bool online: state ? state.online === true : false
    readonly property bool streaming: state ? state.streaming === true : false
    readonly property string errorText: state && state.error ? String(state.error) : ""

    color: Color.background
    radius: Style.cornerRadius
    border.width: 1
    border.color: online ? (streaming ? Color.accent : Color.muted) : Color.urgent

    FrameImage {
      id: tileFrame
      anchors.fill: parent
      cameraId: tile.cameraId
      fps: tile.fps
      baseUrl: tile.baseUrl
      visible: tile.online && status === Image.Ready
    }

    // Offline / unconfigured placeholder
    Column {
      anchors.centerIn: parent
      spacing: Style.space(4)
      visible: !tile.online || tileFrame.status === Image.Error

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.errorText !== "" ? "" : (tile.online === false ? "" : "?")
        font.pixelSize: Style.font.heading
        color: tile.online === false ? Color.urgent : Color.muted
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.cameraId
        font.pixelSize: Style.font.body
        color: Color.foreground
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.errorText
        font.pixelSize: Style.font.caption
        color: Color.muted
        visible: tile.errorText !== ""
      }
    }

    // Name badge over a live frame.
    Rectangle {
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.margins: Style.space(6)
      radius: Style.cornerRadius
      color: Qt.rgba(0, 0, 0, 0.55)
      visible: tileFrame.visible

      Text {
        anchors.margins: Style.space(3)
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        text: tile.cameraId
        color: "#ffffff"
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: function(mouse) {
        tile.tap(tile.cameraId)
      }
    }
  }
}
