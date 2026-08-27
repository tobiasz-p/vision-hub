import "."
import QtQuick
import qs.Commons
import qs.Ui

// Empty state: no daemon state yet or no cameras configured
Column {
  id: emptyState

  property var visionService: null

  spacing: 16

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    width: 72
    height: 72
    radius: 36
    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
    border.width: 1
    border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3)

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: "󰹗"
      font.pixelSize: 32
      color: Color.accent
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    textFormat: Text.PlainText
    text: {
      if (emptyState.visionService && emptyState.visionService.configError !== "") {
        return emptyState.visionService.configError
      }
      if (emptyState.visionService && emptyState.visionService.daemonError !== "") {
        return emptyState.visionService.daemonError
      }
      return "No Cameras Configured"
    }
    color: Color.foreground
    font.pixelSize: 18
    font.bold: true
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    textFormat: Text.PlainText
    text: "Create ~/.config/vision-hub/cameras.json and store credentials in gnome-keyring"
    color: Color.muted
    font.pixelSize: 13
  }
}
