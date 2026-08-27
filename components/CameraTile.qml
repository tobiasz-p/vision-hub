import "."
import QtQuick
import qs.Commons
import qs.Ui

// Surveillance Card Tile for the Multi-Camera Grid
Rectangle {
  id: tile

  signal tap(string cameraId)

  property string cameraId: ""
  property int fps: 0
  property string baseUrl: ""
  property var state: null

  readonly property bool online: state ? state.online === true : false
  readonly property bool streaming: state ? state.streaming === true : false
  readonly property string errorText: state && state.error ? String(state.error) : ""

  color: Color.background
  radius: 12
  border.width: tileMouse.containsMouse ? 2 : 1
  border.color: {
    if (tileMouse.containsMouse) return Color.accent
    if (!online) return Color.urgent
    return Color.popups.border
  }
  clip: true

  // Inner Frame Viewport
  FrameImage {
    id: tileFrame
    anchors.fill: parent
    anchors.margins: 2
    cameraId: tile.cameraId
    fps: tile.fps
    baseUrl: tile.baseUrl
    visible: tile.online
  }

  // Offline / unconfigured placeholder
  TilePlaceholder {
    anchors.centerIn: parent
    visible: !tile.online || !tileFrame.hasFrame
    online: tile.online
    cameraId: tile.cameraId
    errorText: tile.errorText
  }

  // Top Header Overlay Pills
  // Left: Camera Name Badge
  CameraBadge {
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.margins: 10
    visible: tile.online && tileFrame.hasFrame
    name: tile.state && tile.state.name ? tile.state.name : tile.cameraId
  }

  // Right: Status Tag Badge
  TileStatusBadge {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: 10
    visible: tile.online && tileFrame.hasFrame
  }

  // Hover Action Button (Center Glowing Themed Pill)
  Rectangle {
    anchors.centerIn: parent
    width: focusActionRow.implicitWidth + 24
    height: 38
    radius: 19
    color: Color.popups.background
    border.width: 1.5
    border.color: Color.accent
    visible: tileMouse.containsMouse && tile.online && tileFrame.hasFrame
    z: 15

    Row {
      id: focusActionRow
      anchors.centerIn: parent
      spacing: 8

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "󰍉"
        font.pixelSize: 14
        color: Color.accent
        verticalAlignment: Text.AlignVCenter
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "Open Live Stream"
        font.pixelSize: 12
        font.bold: true
        color: Color.foreground
        verticalAlignment: Text.AlignVCenter
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
