import "."
import QtQuick
import qs.Commons
import qs.Ui

// Floating glass circle navigation button
Rectangle {
  id: navBtn

  property string icon: "󰅁"
  signal clicked()

  width: 48
  height: 48
  radius: 24
  color: navHover.containsMouse ? Color.popups.background : Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.65)
  border.width: 1.5
  border.color: navHover.containsMouse ? Color.accent : Color.popups.border
  z: 20

  Text {
    anchors.centerIn: parent
    text: navBtn.icon
    font.pixelSize: 24
    color: navHover.containsMouse ? Color.accent : Color.foreground
    verticalAlignment: Text.AlignVCenter
    horizontalAlignment: Text.AlignHCenter
  }

  MouseArea {
    id: navHover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: navBtn.clicked()
  }
}
