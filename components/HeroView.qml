import "."
import QtQuick
import qs.Commons
import qs.Ui

// Hero 4+1 Hybrid View: 1 large primary stream + interactive live multi-camera dock
Item {
  id: hero

  property string focusedId: ""
  property int streamFps: 15
  property int fillMode: Image.PreserveAspectFit
  property bool isAudioOn: false
  property var cameraList: []
  property int totalCount: 0
  property var visionService: null

  signal prevCamera()
  signal nextCamera()
  signal selectCamera(string cameraId)
  signal takeSnapshot(string cameraId)
  signal toggleAspect()

  function triggerFlash() {
    shutterFlash.trigger()
  }

  // Background canvas
  Rectangle {
    anchors.fill: parent
    color: Color.background
  }

  // Top Primary Hero Stream Area
  Item {
    id: heroStreamArea
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: bottomDockArea.top
    anchors.margins: Style.space(12)
    clip: true

    Rectangle {
      anchors.fill: parent
      color: Color.background
      radius: Theme.radius.md
      border.width: 1
      border.color: Color.popups.border
      clip: true

      FrameImage {
        id: heroFrame
        anchors.fill: parent
        anchors.margins: 2
        cameraId: hero.focusedId
        fps: hero.streamFps
        fillMode: hero.fillMode
        baseUrl: hero.visionService ? hero.visionService.frameUrl(hero.focusedId) : ""
        state: hero.visionService ? hero.visionService.stateFor(hero.focusedId) : null
      }

      // Top-Left Stream HUD Badge
      StreamHudBadge {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Style.space(16)
        title: heroFrame.state && heroFrame.state.name ? heroFrame.state.name : hero.focusedId
        streamFps: hero.streamFps
        isAudioOn: hero.isAudioOn
      }

      // Top-Right Quick Action Controls
      Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(16)
        spacing: 8
        z: 20

        // Snapshot Button
        Rectangle {
          id: snapBtn
          width: snapHover.containsMouse ? snapRow.implicitWidth + 20 : 32
          height: 32
          radius: 16
          color: Color.popups.background
          border.width: 1
          border.color: snapHover.containsMouse ? Color.accent : Color.popups.border
          clip: true

          Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

          Row {
            id: snapRow
            anchors.centerIn: parent
            spacing: 6

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "󰄀"
              font.pixelSize: 14
              color: snapHover.containsMouse ? Color.accent : Color.foreground
            }

            Text {
              visible: snapHover.containsMouse
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: "Screenshot"
              font.pixelSize: 11
              font.bold: true
              color: Color.foreground
            }
          }

          MouseArea {
            id: snapHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              hero.takeSnapshot(hero.focusedId)
              hero.triggerFlash()
            }
          }
        }

        // Aspect Ratio Toggle
        Rectangle {
          id: aspectBtn
          width: aspectHover.containsMouse ? aspectRow.implicitWidth + 20 : 32
          height: 32
          radius: 16
          color: Color.popups.background
          border.width: 1
          border.color: aspectHover.containsMouse ? Color.accent : Color.popups.border
          clip: true

          Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }

          Row {
            id: aspectRow
            anchors.centerIn: parent
            spacing: 6

            Text {
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: hero.fillMode === Image.PreserveAspectFit ? "󰹑" : "󰹍"
              font.pixelSize: 14
              color: aspectHover.containsMouse ? Color.accent : Color.foreground
            }

            Text {
              visible: aspectHover.containsMouse
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: hero.fillMode === Image.PreserveAspectFit ? "Fit" : "Fill"
              font.pixelSize: 11
              font.bold: true
              color: Color.foreground
            }
          }

          MouseArea {
            id: aspectHover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hero.toggleAspect()
          }
        }
      }

      // Side Navigation Chevrons
      NavChevronButton {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰅁"
        visible: hero.totalCount > 1
        onClicked: hero.prevCamera()
      }

      NavChevronButton {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(14)
        anchors.verticalCenter: parent.verticalCenter
        icon: "󰅂"
        visible: hero.totalCount > 1
        onClicked: hero.nextCamera()
      }

      // Shutter Flash Overlay
      ShutterFlash {
        id: shutterFlash
      }
    }
  }

  // Bottom Interactive Live Multi-Camera Strip Dock
  Item {
    id: bottomDockArea
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 110
    anchors.leftMargin: Style.space(12)
    anchors.rightMargin: Style.space(12)
    anchors.bottomMargin: Style.space(10)

    Flickable {
      id: dockFlickable
      anchors.fill: parent
      contentWidth: miniCardsRow.implicitWidth
      contentHeight: parent.height
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Row {
        id: miniCardsRow
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        Repeater {
          model: hero.cameraList
          delegate: Rectangle {
            id: miniCard
            required property string modelData
            readonly property bool isSelected: hero.focusedId === modelData
            readonly property var cardState: hero.visionService ? hero.visionService.stateFor(modelData) : null
            readonly property bool isOnline: cardState ? cardState.online === true : false

            width: 148
            height: 94
            radius: 8
            color: Color.background
            border.width: isSelected ? 2 : (cardMouse.containsMouse ? 1.5 : 1)
            border.color: isSelected ? Color.accent : (cardMouse.containsMouse ? Color.popups.border : Theme.colors.hairline)
            clip: true

            FrameImage {
              anchors.fill: parent
              anchors.margins: 2
              cameraId: miniCard.modelData
              fps: hero.visionService ? hero.visionService.subFps : 2
              baseUrl: hero.visionService ? hero.visionService.frameUrl(miniCard.modelData) : ""
              state: miniCard.cardState
              visible: miniCard.isOnline
            }

            TilePlaceholder {
              anchors.centerIn: parent
              visible: !miniCard.isOnline
              online: miniCard.isOnline
              cameraId: miniCard.modelData
              errorText: miniCard.cardState && miniCard.cardState.error ? String(miniCard.cardState.error) : ""
            }

            // Mini Camera Label Pill at bottom
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 22
              color: miniCard.isSelected ? Theme.colors.tint(Color.accent, 0.85) : Theme.colors.tint(Color.popups.background, 0.85)

              Row {
                anchors.centerIn: parent
                spacing: 4

                StatusDot {
                  anchors.verticalCenter: parent.verticalCenter
                  dotColor: miniCard.isOnline ? (miniCard.isSelected ? "#ffffff" : Theme.colors.healthy) : Theme.colors.urgent
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: miniCard.cardState && miniCard.cardState.name ? miniCard.cardState.name : miniCard.modelData.toUpperCase()
                  font.pixelSize: 10
                  font.bold: true
                  color: miniCard.isSelected ? "#ffffff" : Color.foreground
                  elide: Text.ElideRight
                  maximumLineCount: 1
                }
              }
            }

            MouseArea {
              id: cardMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: hero.selectCamera(miniCard.modelData)
            }
          }
        }
      }
    }
  }
}
