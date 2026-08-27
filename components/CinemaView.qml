import "."
import QtQuick
import qs.Commons
import qs.Ui

// Cinema Focused Single-Camera Live View
Item {
  id: cinema

  property string focusedId: ""
  property int streamFps: 15
  property int fillMode: Image.PreserveAspectFit
  property bool isAudioOn: false
  property var cameraList: []
  property int totalCount: 0
  property var visionService: null

  signal prevCamera()
  signal nextCamera()
  signal selectCamera(string cameraId)
  signal takeSnapshot(string cameraId)
  signal toggleAspect()

  function triggerFlash() {
    shutterFlash.trigger()
  }

  // Background canvas
  Rectangle {
    anchors.fill: parent
    color: Color.background
  }

  // Live Frame Display Area
  Item {
    anchors.fill: parent
    anchors.margins: Style.space(16)
    anchors.bottomMargin: Style.space(88)

    FrameImage {
      id: focusedFrame
      anchors.fill: parent
      cameraId: cinema.focusedId
      fps: cinema.streamFps
      fillMode: cinema.fillMode
      baseUrl: cinema.visionService ? cinema.visionService.frameUrl(cinema.focusedId) : ""
      state: cinema.visionService ? cinema.visionService.stateFor(cinema.focusedId) : null
    }

    // Top-Left Stream HUD Badge
    StreamHudBadge {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.margins: Style.space(8)
      title: focusedFrame.state && focusedFrame.state.name ? focusedFrame.state.name : cinema.focusedId
      streamFps: cinema.streamFps
      isAudioOn: cinema.isAudioOn
    }

    // Top-Right Stream Quick Actions (Snapshot + Aspect Ratio)
    Row {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(8)
      spacing: 8
      z: 20

      // Snapshot Button
      Rectangle {
        id: snapBtn
        width: snapHover.containsMouse ? snapRow.implicitWidth + 20 : 32
        height: 32
        radius: 16
        color: Color.popups.background
        border.width: 1
        border.color: snapHover.containsMouse ? Color.accent : Color.popups.border
        clip: true

        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

        Row {
          id: snapRow
          anchors.centerIn: parent
          spacing: 6

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "󰄀"
            font.pixelSize: 14
            color: snapHover.containsMouse ? Color.accent : Color.foreground
          }

          Text {
            visible: snapHover.containsMouse
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Screenshot"
            font.pixelSize: 11
            font.bold: true
            color: Color.foreground
          }
        }

        MouseArea {
          id: snapHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            cinema.takeSnapshot(cinema.focusedId)
            cinema.triggerFlash()
          }
        }
      }

      // Aspect Ratio Toggle Button
      Rectangle {
        id: aspectBtn
        width: aspectHover.containsMouse ? aspectRow.implicitWidth + 20 : 32
        height: 32
        radius: 16
        color: Color.popups.background
        border.width: 1
        border.color: aspectHover.containsMouse ? Color.accent : Color.popups.border
        clip: true

        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

        Row {
          id: aspectRow
          anchors.centerIn: parent
          spacing: 6

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: cinema.fillMode === Image.PreserveAspectFit ? "󰹑" : "󰹍"
            font.pixelSize: 14
            color: aspectHover.containsMouse ? Color.accent : Color.foreground
          }

          Text {
            visible: aspectHover.containsMouse
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: cinema.fillMode === Image.PreserveAspectFit ? "Fit" : "Fill"
            font.pixelSize: 11
            font.bold: true
            color: Color.foreground
          }
        }

        MouseArea {
          id: aspectHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: cinema.toggleAspect()
        }
      }
    }

    // Shutter Flash Feedback
    ShutterFlash {
      id: shutterFlash
    }
  }

  // Side Chevrons (Floating Glass Navigation)
  NavChevronButton {
    anchors.left: parent.left
    anchors.leftMargin: Style.space(20)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -Style.space(40)
    icon: "󰅁"
    visible: cinema.totalCount > 1
    onClicked: cinema.prevCamera()
  }

  NavChevronButton {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(20)
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -Style.space(40)
    icon: "󰅂"
    visible: cinema.totalCount > 1
    onClicked: cinema.nextCamera()
  }

  // Floating Bottom Camera Strip Dock
  BottomCameraDock {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(18)
    cameraList: cinema.cameraList
    focusedId: cinema.focusedId
    visionService: cinema.visionService
    onSelectCamera: (camId) => cinema.selectCamera(camId)
  }
}
