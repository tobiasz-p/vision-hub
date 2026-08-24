import "."
import QtQuick
import qs.Commons
import qs.Ui

// Reusable action / toggle pill button with responsive text label collapsing
Rectangle {
  id: btn

  property string icon: ""
  property string label: ""
  property bool active: false
  property bool collapseOnNarrow: false
  property int parentWidth: 1000
  property int collapseBreakpoint: Theme.screens.lg
  property color activeColor: Color.accent
  property color activeBg: Theme.colors.accentStrong
  property color inactiveBg: btnHover.containsMouse ? Theme.colors.surfaceHover : Theme.colors.surfaceMuted

  signal clicked()

  readonly property bool showLabel: !collapseOnNarrow || parentWidth >= collapseBreakpoint

  height: Theme.components.buttonHeight
  width: showLabel && label !== "" ? btnRow.implicitWidth + 20 : Theme.components.buttonHeight
  radius: Theme.radius.pill
  color: active ? activeBg : inactiveBg
  border.width: 1
  border.color: active ? activeColor : Color.popups.border

  Row {
    id: btnRow
    anchors.centerIn: parent
    spacing: 6

    Text {
      visible: btn.icon !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: btn.icon
      font.pixelSize: 13
      color: btn.active ? btn.activeColor : Color.muted
      verticalAlignment: Text.AlignVCenter
    }

    Text {
      visible: btn.showLabel && btn.label !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: btn.label
      font.pixelSize: 11
      font.bold: btn.active
      color: Color.foreground
      verticalAlignment: Text.AlignVCenter
    }
  }

  MouseArea {
    id: btnHover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: btn.clicked()
  }
}
