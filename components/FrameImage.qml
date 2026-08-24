import "."
import QtQuick

// Double-buffered frame loader: ping-pongs between two Image elements with Z-index
// to eliminate blank-frame flicker during asynchronous JPEG decoding.
// Preserves camera aspect ratio without cropping (PreserveAspectFit by default).
Item {
  id: frame

  property string cameraId: ""
  property int fps: 0
  property int fillMode: Image.PreserveAspectFit
  property string baseUrl: ""
  property var state: null
  property bool active: true

  property int tick: 0
  property bool frontIsA: true
  readonly property bool hasFrame: imgA.status === Image.Ready || imgB.status === Image.Ready

  function bump() {
    if (baseUrl === "") return
    frame.tick += 1
    var nextUrl = baseUrl + "?t=" + frame.tick
    if (frame.frontIsA) {
      if (imgB.status !== Image.Loading) {
        imgB.source = nextUrl
      }
    } else {
      if (imgA.status !== Image.Loading) {
        imgA.source = nextUrl
      }
    }
  }

  Image {
    id: imgA
    anchors.fill: parent
    cache: false
    asynchronous: true
    fillMode: frame.fillMode
    visible: status === Image.Ready
    onStatusChanged: {
      if (status === Image.Ready && !frame.frontIsA) {
        imgA.z = 2
        imgB.z = 1
        frame.frontIsA = true
      }
    }
  }

  Image {
    id: imgB
    anchors.fill: parent
    cache: false
    asynchronous: true
    fillMode: frame.fillMode
    visible: status === Image.Ready
    onStatusChanged: {
      if (status === Image.Ready && frame.frontIsA) {
        imgB.z = 2
        imgA.z = 1
        frame.frontIsA = false
      }
    }
  }

  Timer {
    interval: Math.max(Theme.animation.minFrameIntervalMs, Math.floor(1000 / Math.max(1, frame.fps)))
    repeat: true
    running: frame.active && frame.baseUrl !== "" && frame.fps > 0
    onTriggered: frame.bump()
  }

  Component.onCompleted: {
    if (baseUrl !== "") bump()
  }

  onBaseUrlChanged: {
    if (baseUrl !== "") bump()
  }

  onFpsChanged: {
    if (baseUrl !== "" && fps > 0) bump()
  }
}
