import "."
import QtQuick
import qs.Commons
import qs.Ui

// Cinema Focused Single-Camera Live View
Item {
  id: cinema

  property string focusedId: ""
  property int streamFps: 15
  property bool isAudioOn: false
  property var cameraList: []
  property int totalCount: 0
  property var visionService: null

  signal prevCamera()
  signal nextCamera()
  signal selectCamera(string cameraId)

  // Background canvas
  Rectangle {
    anchors.fill: parent
    color: Color.background
  }

  // Live Frame Display
  FrameImage {
    id: focusedFrame
    anchors.fill: parent
    anchors.margins: Style.space(16)
    anchors.bottomMargin: Style.space(88)
    cameraId: cinema.focusedId
    fps: cinema.streamFps
    fillMode: Image.PreserveAspectFit
    baseUrl: cinema.visionService ? cinema.visionService.frameUrl(cinema.focusedId) : ""
    state: cinema.visionService ? cinema.visionService.stateFor(cinema.focusedId) : null
  }

  // Top-Left Stream HUD Badge
  StreamHudBadge {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.margins: Style.space(24)
    title: focusedFrame.state && focusedFrame.state.name ? focusedFrame.state.name : cinema.focusedId
    streamFps: cinema.streamFps
    isAudioOn: cinema.isAudioOn
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
