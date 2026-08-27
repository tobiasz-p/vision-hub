import QtQuick

// Camera Shutter Flash overlay for visual feedback on snapshot capture
Rectangle {
  id: flash
  anchors.fill: parent
  color: "#ffffff"
  opacity: 0.0
  z: 60
  visible: opacity > 0

  function trigger() {
    flashAnim.restart()
  }

  NumberAnimation {
    id: flashAnim
    target: flash
    property: "opacity"
    from: 0.85
    to: 0.0
    duration: 320
    easing.type: Easing.OutQuad
  }
}
