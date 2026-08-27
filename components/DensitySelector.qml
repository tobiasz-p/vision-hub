import "."
import QtQuick
import qs.Commons
import qs.Ui

// Grid column density selector (1×, 2×, 3×, 4×)
Rectangle {
  id: density

  property int columns: 3
  signal selectColumns(int cols)

  height: 32
  width: colBoxRow.implicitWidth + 6
  radius: 16
  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
  border.width: 1
  border.color: Color.popups.border

  Row {
    id: colBoxRow
    anchors.centerIn: parent
    spacing: 2

    Repeater {
      model: [1, 2, 3, 4]
      delegate: Rectangle {
        required property int modelData
        width: 28
        height: 26
        radius: 13
        color: density.columns === modelData ? Color.accent : (cHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : "transparent")

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: parent.modelData + "×"
          font.pixelSize: 10
          font.bold: density.columns === parent.modelData
          color: density.columns === parent.modelData ? Color.background : Color.foreground
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
          id: cHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: density.selectColumns(parent.modelData)
        }
      }
    }
  }
}
