import "."
import QtQuick
import qs.Commons
import qs.Ui

// Framerate selector pill button with popup menu
Item {
  id: root

  property int streamFps: 15
  property var fpsOptions: [5, 10, 15, 20, 25, 30]
  property bool isOpen: false

  signal selectFps(int fps)

  width: fpsBtnRect.width
  height: 32
  z: 50

  Rectangle {
    id: fpsBtnRect
    height: 32
    width: fpsBtnRow.implicitWidth + 20
    radius: 16
    color: root.isOpen ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (fpsBtnHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05))
    border.width: 1
    border.color: root.isOpen ? Color.accent : Color.popups.border

    Row {
      id: fpsBtnRow
      anchors.centerIn: parent
      spacing: 6

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "󰑖"
        font.pixelSize: 12
        color: Color.accent
        verticalAlignment: Text.AlignVCenter
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.streamFps + " FPS"
        font.pixelSize: 11
        font.bold: true
        color: Color.foreground
        verticalAlignment: Text.AlignVCenter
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.isOpen ? "▴" : "▾"
        font.pixelSize: 10
        color: Color.muted
        verticalAlignment: Text.AlignVCenter
      }
    }

    MouseArea {
      id: fpsBtnHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.isOpen = !root.isOpen
    }
  }

  // Floating Dropdown Menu
  Rectangle {
    visible: root.isOpen
    anchors.top: fpsBtnRect.bottom
    anchors.topMargin: 6
    anchors.right: fpsBtnRect.right
    width: 106
    height: fpsListCol.implicitHeight + 10
    radius: 12
    color: Color.popups.background
    border.width: 1
    border.color: Color.popups.border
    z: 100

    Column {
      id: fpsListCol
      anchors.centerIn: parent
      spacing: 2

      Repeater {
        model: root.fpsOptions
        delegate: Rectangle {
          id: fpsOptionItem
          required property int modelData
          readonly property bool isSelected: root.streamFps === modelData
          width: 94
          height: 28
          radius: 8
          color: isSelected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : (optHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent")

          Row {
            anchors.centerIn: parent
            spacing: 6

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: fpsOptionItem.modelData + " FPS"
              font.pixelSize: 11
              font.bold: fpsOptionItem.isSelected
              color: fpsOptionItem.isSelected ? Color.accent : Color.foreground
              verticalAlignment: Text.AlignVCenter
            }

            Text {
              visible: fpsOptionItem.isSelected
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "✓"
              font.pixelSize: 10
              font.bold: true
              color: Color.accent
              verticalAlignment: Text.AlignVCenter
            }
          }

          MouseArea {
            id: optHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.isOpen = false
              root.selectFps(fpsOptionItem.modelData)
            }
          }
        }
      }
    }
  }
}
