import "."
import QtQuick
import qs.Commons
import qs.Ui

// Segmented View Mode Switcher (Grid vs Hero vs Cinema)
Rectangle {
  id: switcher

  property string viewMode: isCinema ? "cinema" : "grid"
  property bool isCinema: false

  signal showGrid()
  signal showHero()
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
      readonly property bool active: switcher.viewMode === "grid"
      width: 70
      height: 28
      radius: 14
      color: active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (gridTabHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent")
      border.width: active ? 1 : 0
      border.color: Color.accent

      Row {
        anchors.centerIn: parent
        spacing: 5
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "󰕰"
          font.pixelSize: 12
          color: parent.parent.active ? Color.accent : Color.muted
          verticalAlignment: Text.AlignVCenter
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Grid"
          font.pixelSize: 11
          font.bold: parent.parent.active
          color: parent.parent.active ? Color.foreground : Color.muted
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

    // Hero Tab
    Rectangle {
      readonly property bool active: switcher.viewMode === "hero"
      width: 72
      height: 28
      radius: 14
      color: active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (heroTabHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent")
      border.width: active ? 1 : 0
      border.color: Color.accent

      Row {
        anchors.centerIn: parent
        spacing: 5
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "󰕯"
          font.pixelSize: 12
          color: parent.parent.active ? Color.accent : Color.muted
          verticalAlignment: Text.AlignVCenter
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Hero"
          font.pixelSize: 11
          font.bold: parent.parent.active
          color: parent.parent.active ? Color.foreground : Color.muted
          verticalAlignment: Text.AlignVCenter
        }
      }

      MouseArea {
        id: heroTabHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: switcher.showHero()
      }
    }

    // Cinema Focus Tab
    Rectangle {
      readonly property bool active: switcher.viewMode === "cinema"
      width: 78
      height: 28
      radius: 14
      color: active ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (focusTabHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent")
      border.width: active ? 1 : 0
      border.color: Color.accent

      Row {
        anchors.centerIn: parent
        spacing: 5
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "󰍉"
          font.pixelSize: 12
          color: parent.parent.active ? Color.accent : Color.muted
          verticalAlignment: Text.AlignVCenter
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "Cinema"
          font.pixelSize: 11
          font.bold: parent.parent.active
          color: parent.parent.active ? Color.foreground : Color.muted
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
