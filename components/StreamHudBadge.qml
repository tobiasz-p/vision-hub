import "."
import QtQuick
import qs.Commons
import qs.Ui

// Top-Left Stream HUD Badge for Cinema View
Rectangle {
  id: hud

  property string title: ""
  property int streamFps: 15
  property bool isAudioOn: false

  height: 30
  width: streamHudRow.implicitWidth + 20
  radius: 15
  color: Color.popups.background
  border.width: 1
  border.color: Color.popups.border
  z: 15

  Row {
    id: streamHudRow
    anchors.centerIn: parent
    spacing: 8

    StatusDot {
      anchors.verticalCenter: parent.verticalCenter
      dotColor: "#10b981"
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: (hud.title !== "" ? hud.title.toUpperCase() : "STREAM") + " · LIVE RTSP"
      font.pixelSize: 11
      font.bold: true
      font.letterSpacing: 0.5
      color: Color.foreground
      verticalAlignment: Text.AlignVCenter
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      height: 12
      width: 1
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: hud.streamFps + " FPS HW"
      font.pixelSize: 10
      font.bold: true
      color: Color.accent
      verticalAlignment: Text.AlignVCenter
    }

    Rectangle {
      visible: hud.isAudioOn
      anchors.verticalCenter: parent.verticalCenter
      height: 12
      width: 1
      color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
    }

    Text {
      visible: hud.isAudioOn
      anchors.verticalCenter: parent.verticalCenter
      text: "󰕾 AUDIO"
      font.pixelSize: 10
      font.bold: true
      color: Theme.colors.healthy
      verticalAlignment: Text.AlignVCenter
    }
  }
}
