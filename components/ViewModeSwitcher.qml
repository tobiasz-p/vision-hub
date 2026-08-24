import "."
import QtQuick
import qs.Commons
import qs.Ui

// Segmented View Mode Switcher (Grid vs Cinema Focus)
Rectangle {
  id: switcher

  property bool isCinema: false

  signal showGrid()
  signal showCinema()

  height: 34
  width: segRow.implicitWidth + 8
  radius: 17
  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
  border.width: 1
  border.color: Color.popups.border

  Row {
    id: segRow
    anchors.centerIn: parent
    spacing: 4

    // Grid Tab
    Rectangle {
      width: 76
      height: 28
      radius: 14
      color: !switcher.isCinema ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (gridTabHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent")
      border.width: !switcher.isCinema ? 1 : 0
      border.color: Color.accent

      Row {
        anchors.centerIn: parent
        spacing: 6
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰕰"
          font.pixelSize: 12
          color: !switcher.isCinema ? Color.accent : Color.muted
          verticalAlignment: Text.AlignVCenter
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Grid"
          font.pixelSize: 11
          font.bold: !switcher.isCinema
          color: !switcher.isCinema ? Color.foreground : Color.muted
          verticalAlignment: Text.AlignVCenter
        }
      }

      MouseArea {
        id: gridTabHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: switcher.showGrid()
      }
    }

    // Cinema Focus Tab
    Rectangle {
      width: 84
      height: 28
      radius: 14
      color: switcher.isCinema ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (focusTabHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent")
      border.width: switcher.isCinema ? 1 : 0
      border.color: Color.accent

      Row {
        anchors.centerIn: parent
        spacing: 6
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰍉"
          font.pixelSize: 12
          color: switcher.isCinema ? Color.accent : Color.muted
          verticalAlignment: Text.AlignVCenter
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Cinema"
          font.pixelSize: 11
          font.bold: switcher.isCinema
          color: switcher.isCinema ? Color.foreground : Color.muted
          verticalAlignment: Text.AlignVCenter
        }
      }

      MouseArea {
        id: focusTabHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: switcher.showCinema()
      }
    }
  }
}
