import "."
import QtQuick
import qs.Commons
import qs.Ui

// Top-left camera name overlay pill for tile
Rectangle {
  id: badge

  property string name: ""

  height: Theme.components.badgeHeight
  width: nameRow.implicitWidth + 20
  radius: Theme.radius.badge
  color: Color.popups.background
  border.width: 1
  border.color: Color.popups.border

  Row {
    id: nameRow
    anchors.centerIn: parent
    spacing: 6

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: "󰹗"
      font.pixelSize: 12
      color: Color.accent
      verticalAlignment: Text.AlignVCenter
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: badge.name.toUpperCase()
      color: Color.foreground
      font.pixelSize: 11
      font.bold: true
      font.letterSpacing: 0.5
      verticalAlignment: Text.AlignVCenter
    }
  }
}
