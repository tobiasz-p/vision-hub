import "."
import QtQuick
import qs.Commons
import qs.Ui

// VisionHub Brand Logo and Stream Subtitle
Row {
  id: brand

  property string focusedId: ""
  property var focusedState: null
  property int onlineCount: 0
  property int totalCount: 0

  spacing: Style.space(12)

  // Brand Glyph Box
  Rectangle {
    width: 36
    height: 36
    radius: 10
    color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
    border.width: 1
    border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4)

    Text {
      anchors.centerIn: parent
      text: "󰹗"
      font.pixelSize: 18
      color: Color.accent
    }
  }

  // Brand Title & Info
  Column {
    spacing: 2

    Row {
      spacing: 4
      Text {
        text: "VISION"
        font.pixelSize: 14
        font.bold: true
        font.letterSpacing: 1.2
        color: Color.foreground
      }
      Text {
        text: "HUB"
        font.pixelSize: 14
        font.bold: true
        font.letterSpacing: 1.2
        color: Color.accent
      }
    }

    Text {
      text: brand.focusedId !== "" ? "STREAM · " + (brand.focusedState && brand.focusedState.name ? brand.focusedState.name.toUpperCase() : brand.focusedId.toUpperCase()) : brand.onlineCount + "/" + brand.totalCount + " CAMERAS ONLINE"
      font.pixelSize: 10
      font.bold: true
      font.letterSpacing: 0.5
      color: Color.muted
    }
  }
}
