import "."
import QtQuick
import qs.Commons
import qs.Ui

// Offline or loading state placeholder for camera tile
Column {
  id: placeholder

  property bool online: false
  property string cameraId: ""
  property string errorText: ""

  width: parent ? Math.min(parent.width - 24, 280) : 200
  spacing: 8

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    width: 48
    height: 48
    radius: 24
    color: !placeholder.online ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.15) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
    border.width: 1
    border.color: !placeholder.online ? Color.urgent : Color.popups.border

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: placeholder.errorText !== "" ? "󰅚" : (!placeholder.online ? "󰅚" : "󰑐")
      font.pixelSize: 20
      color: !placeholder.online ? Color.urgent : Color.muted
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    textFormat: Text.PlainText
    text: placeholder.cameraId.toUpperCase()
    font.pixelSize: 13
    font.bold: true
    font.letterSpacing: 0.8
    color: Color.foreground
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    width: placeholder.width
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    horizontalAlignment: Text.AlignHCenter
    maximumLineCount: 2
    elide: Text.ElideRight
    text: placeholder.errorText !== "" ? placeholder.errorText : (!placeholder.online ? "Camera Offline" : "Fetching Snapshot…")
    font.pixelSize: 11
    color: Color.muted
  }
}
