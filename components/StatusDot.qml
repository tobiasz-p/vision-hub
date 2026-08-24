import "."
import QtQuick

// Reusable status indicator dot with optional pulsing animation
Rectangle {
  id: dot

  property color dotColor: Theme.colors.healthy
  property bool pulsing: false

  width: Theme.components.dotDiameter
  height: Theme.components.dotDiameter
  radius: Theme.components.dotDiameter / 2
  color: dotColor

  SequentialAnimation on opacity {
    running: dot.pulsing
    loops: Animation.Infinite
    NumberAnimation { to: 0.3; duration: Theme.animation.pulseDurationMs; easing.type: Easing.InOutQuad }
    NumberAnimation { to: 1.0; duration: Theme.animation.pulseDurationMs; easing.type: Easing.InOutQuad }
  }
}
