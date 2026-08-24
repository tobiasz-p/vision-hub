import "."
import QtQuick
import qs.Commons
import qs.Ui

// Top-right status indicator tag pill for camera tile
Rectangle {
  id: tag

  property string label: "READY"
  property color statusColor: Theme.colors.healthy
  property color textColor: Theme.colors.healthyText

  height: Theme.components.badgeHeight
  width: tileStatusRow.implicitWidth + 20
  radius: Theme.radius.badge
  color: Color.popups.background
  border.width: 1
  border.color: Color.popups.border

  Row {
    id: tileStatusRow
    anchors.centerIn: parent
    spacing: 6

    StatusDot {
      anchors.verticalCenter: parent.verticalCenter
      dotColor: tag.statusColor
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: tag.label
      font.pixelSize: 10
      font.bold: true
      font.letterSpacing: 0.5
      color: tag.textColor
      verticalAlignment: Text.AlignVCenter
    }
  }
}
