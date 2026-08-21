import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// VisionHub live-view window: a multi-camera grid plus focused single-camera view.
//
// Frames come from the daemon's continuously-overwritten JPEGs on tmpfs;
// each tile uses double-buffering to eliminate any flicker, and preserves
// the camera's native aspect ratio.
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

  readonly property var cameraList: visionService ? visionService.cameraIds : []
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

  // ---- window -----------------------------------------------------------------
  FloatingWindow {
    id: window

    title: "VisionHub" + (root.focusedId !== "" ? " — " + root.focusedId : "")
    color: Color.background
    implicitWidth: 1040
    implicitHeight: 700
    minimumSize: Qt.size(580, 420)

    onVisibleChanged: {
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

      Keys.onEscapePressed: {
        if (root.focusedId !== "") root.showGrid()
        else root.requestClose()
      }

      // ---- Window Header Bar ----------------------------------------------
      Rectangle {
        id: headerBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 52
        color: Qt.rgba(Color.surface.r, Color.surface.g, Color.surface.b, 0.4)
        border.width: 1
        border.color: Color.border
        z: 10

        // Left Header Section
        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(10)

          // Grid / Back Button
          WidgetButton {
            visible: root.focusedId !== ""
            bar: null
            text: "← Grid"
            onPressed: function(mouseButton) {
              root.showGrid()
            }
          }

          // App / View Title
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(8)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.focusedId !== "" ? root.focusedId : "VisionHub"
              font.pixelSize: Style.font.body
              font.bold: true
              color: Color.foreground
            }

            // Live Status Pill
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              height: 22
              width: statusRow.implicitWidth + Style.space(12)
              radius: Style.cornerRadius
              color: Qt.rgba(0, 0, 0, 0.4)
              border.width: 1
              border.color: {
                if (root.visionService && root.visionService.configError !== "") return Color.urgent
                return Color.border
              }

              Row {
                id: statusRow
                anchors.centerIn: parent
                spacing: Style.space(5)

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 8
                  height: 8
                  radius: 4
                  color: {
                    if (root.focusedId !== "") {
                      var st = root.visionService ? root.visionService.stateFor(root.focusedId) : null
                      return st && st.online ? Color.accent : Color.urgent
                    }
                    return Color.accent
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: {
                    if (root.focusedId !== "") return "MAIN STREAM"
                    var total = root.cameraList.length
                    return total + " Camera" + (total === 1 ? "" : "s")
                  }
                  font.pixelSize: Style.font.caption
                  color: Color.foreground
                }
              }
            }
          }
        }

        // Right Header Section (Tools & Layouts)
        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(8)

          // Column selector (only in grid view)
          Row {
            visible: root.focusedId === "" && root.cameraList.length > 1
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            Repeater {
              model: [1, 2, 3, 4]
              delegate: Rectangle {
                required property int modelData
                width: 28
                height: 28
                radius: Style.cornerRadius
                color: root.columns === modelData ? Color.accent : Qt.rgba(Color.surface.r, Color.surface.g, Color.surface.b, 0.5)
                border.width: 1
                border.color: root.columns === modelData ? Color.accent : Color.border

                Text {
                  anchors.centerIn: parent
                  text: parent.modelData
                  font.pixelSize: Style.font.caption
                  font.bold: root.columns === parent.modelData
                  color: root.columns === parent.modelData ? Color.background : Color.foreground
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: function(mouse) {
                    root.columns = parent.modelData
                  }
                }
              }
            }
          }

          // Carousel Navigation (focused view)
          Row {
            visible: root.focusedId !== "" && root.cameraList.length > 1
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            WidgetButton {
              bar: null
              text: "‹ Prev"
              onPressed: function(mouseButton) {
                root.showPrevCamera()
              }
            }

            WidgetButton {
              bar: null
              text: "Next ›"
              onPressed: function(mouseButton) {
                root.showNextCamera()
              }
            }
          }

          // Refresh Button
          WidgetButton {
            bar: null
            text: "󰑐 Refresh"
            onPressed: function(mouseButton) {
              if (root.visionService) root.visionService.refresh()
            }
          }

          // Close Button
          WidgetButton {
            bar: null
            text: "✕"
            onPressed: function(mouseButton) {
              root.requestClose()
            }
          }
        }
      }

      // ---- Content Area ----------------------------------------------------
      Item {
        anchors.top: headerBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

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
                anchors.margins: Style.space(8)
                cameraId: root.focusedId
                fps: root.visionService ? root.visionService.mainFps : 10
                baseUrl: root.visionService ? root.visionService.frameUrl(root.focusedId) : ""
                state: root.visionService ? root.visionService.stateFor(root.focusedId) : null
              }

              // Floating Carousel Arrows on Sides
              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 44
                radius: 22
                color: prevHover.containsMouse ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(0, 0, 0, 0.45)
                visible: root.cameraList.length > 1

                Text {
                  anchors.centerIn: parent
                  text: "‹"
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  color: "#ffffff"
                }

                MouseArea {
                  id: prevHover
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: function(mouse) {
                    root.showPrevCamera()
                  }
                }
              }

              Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                width: 44
                height: 44
                radius: 22
                color: nextHover.containsMouse ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(0, 0, 0, 0.45)
                visible: root.cameraList.length > 1

                Text {
                  anchors.centerIn: parent
                  text: "›"
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  color: "#ffffff"
                }

                MouseArea {
                  id: nextHover
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: function(mouse) {
                    root.showNextCamera()
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
          visible: root.focusedId === "" && root.cameraList.length > 0
          clip: true
          cellWidth: Math.floor(width / Math.max(1, root.columns))
          cellHeight: Math.floor(cellWidth * 9 / 16)

          model: root.cameraList

          delegate: Item {
            id: delegateRoot

            required property string modelData
            width: grid.cellWidth
            height: grid.cellHeight

            CameraTile {
              anchors.fill: parent
              anchors.margins: Style.space(4)
              cameraId: delegateRoot.modelData
              fps: 0
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
          visible: root.focusedId === "" && (root.visionService === null || root.cameraList.length === 0)
          spacing: Style.space(12)

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 56
            height: 56
            radius: 28
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)

            Text {
              anchors.centerIn: parent
              text: "󰹗"
              font.pixelSize: Style.font.heading
              color: Color.accent
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
              if (!root.visionService || !root.visionService.sessionReady)
                return "Connecting to vision-hub daemon…"
              if (root.visionService.configError !== "")
                return "Config Error: " + root.visionService.configError
              return "No cameras configured"
            }
            color: Color.foreground
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Create ~/.config/vision-hub/cameras.json and store credentials in keyring"
            color: Color.muted
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // ---- components ---------------------------------------------------------------

  // Double-buffered frame loader: ping-pongs between two Image elements to
  // eliminate any blank-frame flicker during asynchronous JPEG decoding.
  // Preserves camera aspect ratio without cropping (PreserveAspectFit).
  component FrameImage: Item {
    id: frame

    property string cameraId: ""
    property int fps: 5
    property string baseUrl: ""
    property var state: null
    property int tick: 0
    property int activeIndex: 0
    readonly property bool hasFrame: imgA.status === Image.Ready || imgB.status === Image.Ready

    function bump() {
      if (baseUrl === "") return
      frame.tick += 1
      var nextUrl = baseUrl + "?t=" + frame.tick
      if (frame.activeIndex === 0) {
        imgB.source = nextUrl
      } else {
        imgA.source = nextUrl
      }
    }

    Image {
      id: imgA
      anchors.fill: parent
      cache: false
      asynchronous: true
      fillMode: Image.PreserveAspectFit
      visible: (frame.activeIndex === 0 && status === Image.Ready) || (frame.activeIndex === 1 && imgB.status !== Image.Ready && status === Image.Ready)

      onStatusChanged: {
        if (status === Image.Ready && frame.activeIndex === 1) {
          frame.activeIndex = 0
        }
      }
    }

    Image {
      id: imgB
      anchors.fill: parent
      cache: false
      asynchronous: true
      fillMode: Image.PreserveAspectFit
      visible: (frame.activeIndex === 1 && status === Image.Ready) || (frame.activeIndex === 0 && imgA.status !== Image.Ready && status === Image.Ready)

      onStatusChanged: {
        if (status === Image.Ready && frame.activeIndex === 0) {
          frame.activeIndex = 1
        }
      }
    }

    Timer {
      interval: Math.max(100, Math.floor(1000 / Math.max(1, frame.fps)))
      repeat: true
      running: window.visible && frame.baseUrl !== "" && frame.fps > 0
      onTriggered: frame.bump()
    }

    Component.onCompleted: frame.bump()
    onBaseUrlChanged: frame.bump()
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

    color: Color.surface
    radius: Style.cornerRadius
    border.width: tileMouse.containsMouse ? 2 : 1
    border.color: {
      if (tileMouse.containsMouse) return Color.accent
      if (!online) return Color.urgent
      return Color.border
    }

    FrameImage {
      id: tileFrame
      anchors.fill: parent
      anchors.margins: Style.space(2)
      cameraId: tile.cameraId
      fps: tile.fps
      baseUrl: tile.baseUrl
      visible: tile.online
    }

    // Offline / unconfigured placeholder
    Column {
      anchors.centerIn: parent
      spacing: Style.space(4)
      visible: !tile.online || !tileFrame.hasFrame

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.errorText !== "" ? "󰅚" : (tile.online === false ? "󰅚" : "󰑐")
        font.pixelSize: Style.font.heading
        color: tile.online === false ? Color.urgent : Color.muted
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.cameraId
        font.pixelSize: Style.font.body
        font.bold: true
        color: Color.foreground
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.errorText !== "" ? tile.errorText : (tile.online === false ? "Offline" : "Connecting…")
        font.pixelSize: Style.font.caption
        color: Color.muted
        visible: true
      }
    }

    // Live Status Badge on Top Right
    Rectangle {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(6)
      height: 20
      width: liveBadgeRow.implicitWidth + Style.space(10)
      radius: Style.cornerRadius
      color: Qt.rgba(0, 0, 0, 0.65)
      visible: tile.online && tileFrame.hasFrame

      Row {
        id: liveBadgeRow
        anchors.centerIn: parent
        spacing: Style.space(4)

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 6
          height: 6
          radius: 3
          color: Color.accent
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "LIVE"
          font.pixelSize: 10
          font.bold: true
          color: "#ffffff"
        }
      }
    }

    // Name badge on Bottom Left
    Rectangle {
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.margins: Style.space(6)
      radius: Style.cornerRadius
      color: Qt.rgba(0, 0, 0, 0.65)
      visible: tile.online && tileFrame.hasFrame

      Text {
        anchors.margins: Style.space(4)
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        text: tile.cameraId
        color: "#ffffff"
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    // Focus overlay hint on hover
    Rectangle {
      anchors.centerIn: parent
      width: focusHintRow.implicitWidth + Style.space(14)
      height: 26
      radius: 13
      color: Qt.rgba(0, 0, 0, 0.75)
      border.width: 1
      border.color: Color.accent
      visible: tileMouse.containsMouse && tile.online && tileFrame.hasFrame

      Row {
        id: focusHintRow
        anchors.centerIn: parent
        spacing: Style.space(4)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰍉 Focus"
          font.pixelSize: Style.font.caption
          font.bold: true
          color: Color.accent
        }
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        tile.tap(tile.cameraId)
      }
    }
  }
}
