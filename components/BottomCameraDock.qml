import "."
import QtQuick
import qs.Commons
import qs.Ui

// Floating Bottom Camera Strip Dock
Rectangle {
  id: dock

  property var cameraList: []
  property string focusedId: ""
  property var visionService: null

  signal selectCamera(string cameraId)

  height: 52
  width: thumbRow.implicitWidth + 24
  radius: 26
  color: Color.popups.background
  border.width: 1
  border.color: Color.popups.border
  z: 20

  Row {
    id: thumbRow
    anchors.centerIn: parent
    spacing: 8

    Repeater {
      model: dock.cameraList
      delegate: Rectangle {
        id: cameraThumbItem
        required property string modelData
        readonly property bool isSelected: dock.focusedId === modelData
        width: capsuleRow.implicitWidth + 20
        height: 36
        radius: 18

        color: isSelected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (thumbHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05))
        border.width: 0

        Row {
          id: capsuleRow
          anchors.centerIn: parent
          spacing: 7

          StatusDot {
            anchors.verticalCenter: parent.verticalCenter
            dotColor: cameraThumbItem.isSelected ? Color.accent : Color.muted
          }

          readonly property var itemState: dock.visionService ? dock.visionService.stateFor(cameraThumbItem.modelData) : null

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: capsuleRow.itemState && capsuleRow.itemState.name ? capsuleRow.itemState.name : cameraThumbItem.modelData.toUpperCase()
            font.pixelSize: 11
            font.bold: true
            font.letterSpacing: 0.5
            color: cameraThumbItem.isSelected ? Color.accent : Color.foreground
            verticalAlignment: Text.AlignVCenter
          }
        }

        MouseArea {
          id: thumbHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: dock.selectCamera(parent.modelData)
        }
      }
    }
  }
}
