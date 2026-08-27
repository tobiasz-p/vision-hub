import "."
import QtQuick
import qs.Commons
import qs.Ui

// Grid column density selector (1×, 2×, 3×, 4×)
Rectangle {
  id: density

  property int columns: 3
  signal selectColumns(int cols)

  height: 34
  width: colBoxRow.implicitWidth + 8
  radius: 17
  color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
  border.width: 1
  border.color: Color.popups.border

  Row {
    id: colBoxRow
    anchors.centerIn: parent
    spacing: 4

    Repeater {
      model: [1, 2, 3, 4]
      delegate: Rectangle {
        id: colItem
        required property int modelData
        readonly property bool isSelected: density.columns === modelData

        width: 32
        height: 28
        radius: 14
        color: isSelected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (cHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent")
        border.width: isSelected ? 1 : 0
        border.color: Color.accent

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: colItem.modelData + "×"
          font.pixelSize: 11
          font.bold: colItem.isSelected
          color: colItem.isSelected ? Color.accent : Color.muted
          verticalAlignment: Text.AlignVCenter
          horizontalAlignment: Text.AlignHCenter
        }

        MouseArea {
          id: cHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: density.selectColumns(colItem.modelData)
        }
      }
    }
  }
}
