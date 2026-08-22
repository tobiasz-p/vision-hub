import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// VisionHub modern surveillance live-view window:
// Next-gen multi-camera grid and cinema single-camera live view with dynamic theme integration.
Item {
  id: root

  // ---- host injections ------------------------------------------------------
  property var shell: null
  property var manifest: null
  property var service: null

  // ---- shape contract ---------------------------------------------------------
  property bool opened: window.visible
  property bool closingFromHost: false
  property string focusedId: ""
  property int columns: 3
  property bool patrolMode: false
  property int streamFps: visionService ? visionService.mainFps : 15
  property bool fpsDropdownOpen: false
  property bool fillAspect: false
  readonly property bool isAudioOn: visionService ? visionService.audioEnabled : false

  readonly property var fpsOptions: [5, 10, 15, 20, 25, 30]

  readonly property string pluginId: manifest ? manifest.id : "tobiasz-p.vision-hub"
  readonly property var visionService: service || (shell && typeof shell.serviceFor === "function" ? shell.serviceFor(root.pluginId) : null)

  readonly property var cameraList: visionService ? visionService.cameraIds : []
  readonly property int totalCount: cameraList.length
  readonly property int onlineCount: {
    var count = 0
    if (!visionService) return 0
    for (var i = 0; i < cameraList.length; i++) {
      var st = visionService.stateFor(cameraList[i])
      if (st && st.online === true) count += 1
    }
    return count
  }

  readonly property int currentCameraIndex: {
    if (focusedId === "" || cameraList.length === 0) return -1
    for (var i = 0; i < cameraList.length; i++) {
      if (cameraList[i] === focusedId) return i
    }
    return -1
  }

  function open(payloadJson) {
    var payload = {}
    try {
      payload = JSON.parse(payloadJson || "{}") || {}
    } catch (e) {
      payload = {}
    }
    if (payload.columns !== undefined) {
      var n = parseInt(payload.columns, 10)
      root.columns = isFinite(n) && n >= 1 && n <= 6 ? n : 3
    }
    closingFromHost = false
    root.fpsDropdownOpen = false
    window.visible = true
    if (payload.camera) root.showFocused(String(payload.camera))
    windowContent.forceActiveFocus()
  }

  function close() {
    root.showGrid()
    root.patrolMode = false
    root.fpsDropdownOpen = false
    closingFromHost = true
    window.visible = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(root.pluginId)
    else close()
  }

  function showFocused(cameraId) {
    if (!cameraId) return
    root.fpsDropdownOpen = false
    root.focusedId = cameraId
    if (root.visionService && typeof root.visionService.focusCamera === "function") {
      root.visionService.focusCamera(cameraId, root.streamFps)
    }
  }

  function showGrid() {
    root.patrolMode = false
    root.fpsDropdownOpen = false
    if (root.focusedId !== "" && root.visionService && typeof root.visionService.unfocusCamera === "function") {
      root.visionService.unfocusCamera()
    }
    root.focusedId = ""
  }

  function showNextCamera() {
    if (cameraList.length === 0) return
    var idx = currentCameraIndex
    var nextIdx = (idx + 1) % cameraList.length
    showFocused(cameraList[nextIdx])
  }

  function showPrevCamera() {
    if (cameraList.length === 0) return
    var idx = currentCameraIndex
    var prevIdx = (idx - 1 + cameraList.length) % cameraList.length
    showFocused(cameraList[prevIdx])
  }

  // Patrol / Auto-Cycle Timer (cycles cameras every 6s in focused mode)
  Timer {
    interval: 6000
    repeat: true
    running: window.visible && root.patrolMode && root.focusedId !== "" && root.cameraList.length > 1
    onTriggered: root.showNextCamera()
  }

  // ---- window -----------------------------------------------------------------
  FloatingWindow {
    id: window

    title: "VisionHub" + (root.focusedId !== "" ? " — " + root.focusedId : "")
    color: Color.background
    implicitWidth: 1120
    implicitHeight: 740
    minimumSize: Qt.size(680, 480)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost) {
        if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
        else root.close()
      }
      if (visible) windowContent.forceActiveFocus()
    }

    FocusScope {
      id: windowContent
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: {
        if (root.focusedId !== "") root.showGrid()
        else root.requestClose()
      }

      Keys.onLeftPressed: {
        if (root.focusedId !== "") root.showPrevCamera()
      }

      Keys.onRightPressed: {
        if (root.focusedId !== "") root.showNextCamera()
      }

      Keys.onSpacePressed: {
        if (root.focusedId !== "") root.patrolMode = !root.patrolMode
      }

      Keys.onDigit1Pressed: if (root.cameraList.length >= 1) root.showFocused(root.cameraList[0])
      Keys.onDigit2Pressed: if (root.cameraList.length >= 2) root.showFocused(root.cameraList[1])
      Keys.onDigit3Pressed: if (root.cameraList.length >= 3) root.showFocused(root.cameraList[2])
      Keys.onDigit4Pressed: if (root.cameraList.length >= 4) root.showFocused(root.cameraList[3])
      Keys.onDigit5Pressed: if (root.cameraList.length >= 5) root.showFocused(root.cameraList[4])

      Keys.onPressed: function(event) {
        if ((event.key === Qt.Key_M || event.text === "m" || event.text === "M") && root.focusedId !== "") {
          if (root.visionService && typeof root.visionService.toggleAudio === "function") {
            root.visionService.toggleAudio(root.focusedId)
          }
          event.accepted = true
        } else if ((event.key === Qt.Key_A || event.text === "a" || event.text === "A") && root.focusedId !== "") {
          root.fillAspect = !root.fillAspect
          event.accepted = true
        }
      }

      // ---- Modern Glass Header Bar ----------------------------------------
      Rectangle {
        id: headerBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56
        color: Color.popups.background
        border.width: 1
        border.color: Color.popups.border
        z: 30

        // Subtle hairline highlight at the top
        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 1
          color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
        }

        // Left Header Section (Brand & Status)
        Row {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(12)

          // Brand Glyph Box (Themed)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            height: 36
            radius: 10
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.16)
            border.width: 1
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.4)

            Text {
              anchors.centerIn: parent
              text: "󰹗"
              font.pixelSize: 18
              color: Color.accent
            }
          }

          // Brand Title & Info
          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1

            Row {
              spacing: 4
              Text {
                text: "VISION"
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 1.2
                color: Color.foreground
              }
              Text {
                text: "HUB"
                font.pixelSize: 13
                font.bold: true
                font.letterSpacing: 1.2
                color: Color.accent
              }
            }

            Text {
              text: root.focusedId !== "" ? "STREAM · " + root.focusedId.toUpperCase() : root.onlineCount + "/" + root.totalCount + " CAMERAS ONLINE"
              font.pixelSize: 10
              font.bold: true
              font.letterSpacing: 0.5
              color: Color.muted
            }
          }

          // Live / Status Capsule (Healthy Green / Alert Red)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: 24
            width: liveRow.implicitWidth + 16
            radius: 12
            color: {
              if (root.focusedId !== "") return Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.18)
              return root.onlineCount === root.totalCount ? Qt.rgba(16 / 255, 185 / 255, 129 / 255, 0.14) : Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.18)
            }
            border.width: 1
            border.color: {
              if (root.focusedId !== "") return "#10b981"
              return root.onlineCount === root.totalCount ? "#10b981" : Color.urgent
            }

            Row {
              id: liveRow
              anchors.centerIn: parent
              spacing: 6

              // Pulsing Live Indicator Dot
              Rectangle {
                id: liveDot
                anchors.verticalCenter: parent.verticalCenter
                width: 7
                height: 7
                radius: 3.5
                color: root.focusedId !== "" || root.onlineCount === root.totalCount ? "#10b981" : Color.urgent

                SequentialAnimation on opacity {
                  running: true
                  loops: Animation.Infinite
                  NumberAnimation { to: 0.3; duration: 900; easing.type: Easing.InOutQuad }
                  NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                  if (root.focusedId !== "") return "LIVE " + root.streamFps + " FPS"
                  return root.onlineCount === root.totalCount ? "ALL HEALTHY" : (root.totalCount - root.onlineCount) + " OFFLINE"
                }
                font.pixelSize: 10
                font.bold: true
                font.letterSpacing: 0.4
                color: root.focusedId !== "" || root.onlineCount === root.totalCount ? "#34d399" : Color.urgent
              }
            }
          }
        }

        // Center Section: View Mode & Camera Switcher Tabs
        Row {
          anchors.centerIn: parent
          spacing: 8

          // Grid vs Focus Segmented Switcher (Themed)
          Rectangle {
            height: 34
            width: segRow.implicitWidth + 6
            radius: 17
            color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
            border.width: 1
            border.color: Color.popups.border

            Row {
              id: segRow
              anchors.centerIn: parent
              spacing: 3

              // Grid Tab
              Rectangle {
                width: 76
                height: 28
                radius: 14
                color: root.focusedId === "" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (gridTabHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent")
                border.width: root.focusedId === "" ? 1 : 0
                border.color: Color.accent

                Row {
                  anchors.centerIn: parent
                  spacing: 5
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰕰"
                    font.pixelSize: 12
                    color: root.focusedId === "" ? Color.accent : Color.muted
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Grid"
                    font.pixelSize: 11
                    font.bold: root.focusedId === ""
                    color: root.focusedId === "" ? Color.foreground : Color.muted
                  }
                }

                MouseArea {
                  id: gridTabHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showGrid()
                }
              }

              // Cinema Focus Tab
              Rectangle {
                width: 84
                height: 28
                radius: 14
                color: root.focusedId !== "" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (focusTabHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08) : "transparent")
                border.width: root.focusedId !== "" ? 1 : 0
                border.color: Color.accent

                Row {
                  anchors.centerIn: parent
                  spacing: 5
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍉"
                    font.pixelSize: 12
                    color: root.focusedId !== "" ? Color.accent : Color.muted
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Cinema"
                    font.pixelSize: 11
                    font.bold: root.focusedId !== ""
                    color: root.focusedId !== "" ? Color.foreground : Color.muted
                  }
                }

                MouseArea {
                  id: focusTabHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.focusedId === "" && root.cameraList.length > 0) {
                      root.showFocused(root.cameraList[0])
                    }
                  }
                }
              }
            }
          }

          // Header Camera Quick Selectors (Themed)
          Row {
            visible: root.focusedId !== "" && root.totalCount > 1
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Repeater {
              model: root.cameraList
              delegate: Rectangle {
                required property string modelData
                readonly property bool isCur: root.focusedId === modelData
                width: 48
                height: 28
                radius: 14
                color: isCur ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25) : (tabCamHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.04))
                border.width: 1
                border.color: isCur ? Color.accent : Color.popups.border

                Text {
                  anchors.centerIn: parent
                  text: parent.modelData
                  font.pixelSize: 11
                  font.bold: parent.isCur
                  color: parent.isCur ? Color.accent : Color.muted
                }

                MouseArea {
                  id: tabCamHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showFocused(parent.modelData)
                }
              }
            }
          }
        }

        // Right Header Section (Tools & Actions)
        Row {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(16)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 8

          // Grid Column Density Selector (Themed)
          Rectangle {
            visible: root.focusedId === "" && root.totalCount > 1
            anchors.verticalCenter: parent.verticalCenter
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
                  color: root.columns === modelData ? Color.accent : (cHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : "transparent")

                  Text {
                    anchors.centerIn: parent
                    text: parent.modelData + "×"
                    font.pixelSize: 10
                    font.bold: root.columns === parent.modelData
                    color: root.columns === parent.modelData ? Color.background : Color.foreground
                  }

                  MouseArea {
                    id: cHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.columns = parent.modelData
                  }
                }
              }
            }
          }

          // Stream FPS Dropdown (in cinema view)
          Item {
            visible: root.focusedId !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: fpsBtnRect.width
            height: 32
            z: 50

            Rectangle {
              id: fpsBtnRect
              height: 32
              width: fpsBtnRow.implicitWidth + 18
              radius: 16
              color: root.fpsDropdownOpen ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (fpsBtnHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05))
              border.width: 1
              border.color: root.fpsDropdownOpen ? Color.accent : Color.popups.border

              Row {
                id: fpsBtnRow
                anchors.centerIn: parent
                spacing: 5

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰑖"
                  font.pixelSize: 11
                  color: Color.accent
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.streamFps + " FPS"
                  font.pixelSize: 11
                  font.bold: true
                  color: Color.foreground
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.fpsDropdownOpen ? "▴" : "▾"
                  font.pixelSize: 10
                  color: Color.muted
                }
              }

              MouseArea {
                id: fpsBtnHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.fpsDropdownOpen = !root.fpsDropdownOpen
              }
            }

            // Floating Dropdown Menu
            Rectangle {
              visible: root.fpsDropdownOpen
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
                        text: fpsOptionItem.modelData + " FPS"
                        font.pixelSize: 11
                        font.bold: fpsOptionItem.isSelected
                        color: fpsOptionItem.isSelected ? Color.accent : Color.foreground
                      }

                      Text {
                        visible: fpsOptionItem.isSelected
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✓"
                        font.pixelSize: 10
                        font.bold: true
                        color: Color.accent
                      }
                    }

                    MouseArea {
                      id: optHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.streamFps = fpsOptionItem.modelData
                        root.fpsDropdownOpen = false
                        if (root.visionService && typeof root.visionService.setMainFps === "function") {
                          root.visionService.setMainFps(fpsOptionItem.modelData)
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // Audio Mute/Unmute Toggle (in cinema view)
          Rectangle {
            visible: root.focusedId !== ""
            anchors.verticalCenter: parent.verticalCenter
            height: 32
            width: audioBtnRow.implicitWidth + 18
            radius: 16
            color: root.isAudioOn ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25) : (audioHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05))
            border.width: 1
            border.color: root.isAudioOn ? Color.accent : Color.popups.border

            Row {
              id: audioBtnRow
              anchors.centerIn: parent
              spacing: 6

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.isAudioOn ? "󰕾" : "󰕿"
                font.pixelSize: 13
                color: root.isAudioOn ? Color.accent : Color.muted
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.isAudioOn ? "Audio ON" : "Muted"
                font.pixelSize: 11
                font.bold: root.isAudioOn
                color: root.isAudioOn ? Color.foreground : Color.foreground
              }
            }

            MouseArea {
              id: audioHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.visionService && typeof root.visionService.toggleAudio === "function") {
                  root.visionService.toggleAudio(root.focusedId)
                }
              }
            }
          }

          // Aspect Ratio (Fit / Fill) Toggle (in cinema view)
          Rectangle {
            visible: root.focusedId !== ""
            anchors.verticalCenter: parent.verticalCenter
            height: 32
            width: aspectBtnRow.implicitWidth + 18
            radius: 16
            color: root.fillAspect ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25) : (aspectHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05))
            border.width: 1
            border.color: root.fillAspect ? Color.accent : Color.popups.border

            Row {
              id: aspectBtnRow
              anchors.centerIn: parent
              spacing: 6

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.fillAspect ? "󰘕" : "󰊓"
                font.pixelSize: 12
                color: root.fillAspect ? Color.accent : Color.muted
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.fillAspect ? "Fill" : "Fit"
                font.pixelSize: 11
                font.bold: root.fillAspect
                color: root.fillAspect ? Color.foreground : Color.foreground
              }
            }

            MouseArea {
              id: aspectHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.fillAspect = !root.fillAspect
            }
          }

          // Patrol Mode Toggle (Themed)
          Rectangle {
            visible: root.focusedId !== "" && root.totalCount > 1
            anchors.verticalCenter: parent.verticalCenter
            height: 32
            width: patrolRow.implicitWidth + 18
            radius: 16
            color: root.patrolMode ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25) : (patrolHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05))
            border.width: 1
            border.color: root.patrolMode ? Color.accent : Color.popups.border

            Row {
              id: patrolRow
              anchors.centerIn: parent
              spacing: 6

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰑖"
                font.pixelSize: 12
                color: root.patrolMode ? Color.accent : Color.muted
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Patrol"
                font.pixelSize: 11
                font.bold: root.patrolMode
                color: root.patrolMode ? Color.foreground : Color.foreground
              }
            }

            MouseArea {
              id: patrolHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.patrolMode = !root.patrolMode
            }
          }

          // Refresh Button (Themed)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            height: 32
            width: refreshBtnRow.implicitWidth + 18
            radius: 16
            color: refreshHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
            border.width: 1
            border.color: Color.popups.border

            Row {
              id: refreshBtnRow
              anchors.centerIn: parent
              spacing: 6

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰑐"
                font.pixelSize: 12
                color: Color.accent
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Refresh"
                font.pixelSize: 11
                font.bold: true
                color: Color.foreground
              }
            }

            MouseArea {
              id: refreshHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.visionService) root.visionService.refresh()
              }
            }
          }

          // Close Button
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 32
            radius: 16
            color: closeHover.containsMouse ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.25) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
            border.width: 1
            border.color: closeHover.containsMouse ? Color.urgent : Color.popups.border

            Text {
              anchors.centerIn: parent
              text: "✕"
              font.pixelSize: 12
              color: closeHover.containsMouse ? Color.urgent : Color.muted
            }

            MouseArea {
              id: closeHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.requestClose()
            }
          }
        }
      }

      // ---- Content Area ----------------------------------------------------
      Item {
        anchors.top: headerBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // ---- Cinema Focused Single-Camera Live View ------------------------
        Loader {
          id: focusedLoader
          anchors.fill: parent
          active: root.focusedId !== ""

          sourceComponent: Component {
            Item {
              anchors.fill: parent

              // Background canvas
              Rectangle {
                anchors.fill: parent
                color: Color.background
              }

              // Live Frame Display
              FrameImage {
                id: focusedFrame
                anchors.fill: parent
                anchors.margins: Style.space(16)
                anchors.bottomMargin: Style.space(88)
                cameraId: root.focusedId
                fps: root.streamFps
                fillMode: root.fillAspect ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                baseUrl: root.visionService ? root.visionService.frameUrl(root.focusedId) : ""
                state: root.visionService ? root.visionService.stateFor(root.focusedId) : null
              }

              // Top-Left Stream HUD Badge
              Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.margins: Style.space(24)
                height: 30
                width: streamHudRow.implicitWidth + 20
                radius: 15
                color: Color.popups.background
                border.width: 1
                border.color: Color.popups.border
                z: 15

                Row {
                  id: streamHudRow
                  anchors.centerIn: parent
                  spacing: 8

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7
                    height: 7
                    radius: 3.5
                    color: "#10b981"
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.focusedId.toUpperCase() + " · LIVE RTSP"
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 0.5
                    color: Color.foreground
                  }

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 12
                    width: 1
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.streamFps + " FPS HW"
                    font.pixelSize: 10
                    font.bold: true
                    color: Color.accent
                  }

                  Rectangle {
                    visible: root.isAudioOn
                    anchors.verticalCenter: parent.verticalCenter
                    height: 12
                    width: 1
                    color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
                  }

                  Text {
                    visible: root.isAudioOn
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰕾 AUDIO"
                    font.pixelSize: 10
                    font.bold: true
                    color: "#10b981"
                  }
                }
              }

              // Side Chevrons (Floating Glass Navigation)
              Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(20)
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -Style.space(40)
                width: 48
                height: 48
                radius: 24
                color: prevHover.containsMouse ? Color.popups.background : Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.65)
                border.width: 1.5
                border.color: prevHover.containsMouse ? Color.accent : Color.popups.border
                visible: root.totalCount > 1
                z: 20

                Text {
                  anchors.centerIn: parent
                  text: "‹"
                  font.pixelSize: 24
                  font.bold: true
                  color: prevHover.containsMouse ? Color.accent : Color.foreground
                }

                MouseArea {
                  id: prevHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showPrevCamera()
                }
              }

              Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(20)
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -Style.space(40)
                width: 48
                height: 48
                radius: 24
                color: nextHover.containsMouse ? Color.popups.background : Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.65)
                border.width: 1.5
                border.color: nextHover.containsMouse ? Color.accent : Color.popups.border
                visible: root.totalCount > 1
                z: 20

                Text {
                  anchors.centerIn: parent
                  text: "›"
                  font.pixelSize: 24
                  font.bold: true
                  color: nextHover.containsMouse ? Color.accent : Color.foreground
                }

                MouseArea {
                  id: nextHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.showNextCamera()
                }
              }

              // Floating Bottom Camera Strip Dock (100% Theme Synced)
              Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(18)
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
                    model: root.cameraList
                    delegate: Rectangle {
                      id: cameraThumbItem
                      required property string modelData
                      readonly property bool isSelected: root.focusedId === modelData
                      width: capsuleRow.implicitWidth + 20
                      height: 36
                      radius: 18

                      color: isSelected ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.22) : (thumbHover.containsMouse ? Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05))
                      border.width: 0

                      Row {
                        id: capsuleRow
                        anchors.centerIn: parent
                        spacing: 7

                        Rectangle {
                          anchors.verticalCenter: parent.verticalCenter
                          width: 7
                          height: 7
                          radius: 3.5
                          color: cameraThumbItem.isSelected ? Color.accent : Color.muted
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: cameraThumbItem.modelData.toUpperCase()
                          font.pixelSize: 11
                          font.bold: true
                          font.letterSpacing: 0.5
                          color: cameraThumbItem.isSelected ? Color.accent : Color.foreground
                        }
                      }

                      MouseArea {
                        id: thumbHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showFocused(parent.modelData)
                      }
                    }
                  }
                }
              }
            }
          }
        }

        // ---- Modern Multi-Camera Grid View ---------------------------------
        GridView {
          id: grid
          anchors.fill: parent
          anchors.margins: Style.space(14)
          visible: root.focusedId === "" && root.totalCount > 0
          clip: true
          cellWidth: Math.floor(width / Math.max(1, root.columns))
          cellHeight: Math.floor(cellWidth * 9 / 16)

          model: root.cameraList

          delegate: Item {
            id: delegateRoot

            required property string modelData
            width: grid.cellWidth
            height: grid.cellHeight

            CameraTile {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              cameraId: delegateRoot.modelData
              fps: 0
              baseUrl: root.visionService ? root.visionService.frameUrl(delegateRoot.modelData) : ""
              state: root.visionService ? root.visionService.stateFor(delegateRoot.modelData) : null

              onTap: function(tappedCameraId) {
                root.showFocused(tappedCameraId)
              }
            }
          }
        }

        // Empty state: no daemon state yet or no cameras configured.
        Column {
          anchors.centerIn: parent
          visible: root.focusedId === "" && (root.visionService === null || root.totalCount === 0)
          spacing: 16

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 72
            height: 72
            radius: 36
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.15)
            border.width: 1
            border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.3)

            Text {
              anchors.centerIn: parent
              text: "󰹗"
              font.pixelSize: 32
              color: Color.accent
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
              if (root.visionService && root.visionService.configError !== "") {
                return root.visionService.configError
              }
              if (root.visionService && root.visionService.daemonError !== "") {
                return root.visionService.daemonError
              }
              return "No Cameras Configured"
            }
            color: Color.foreground
            font.pixelSize: 18
            font.bold: true
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Create ~/.config/vision-hub/cameras.json and store credentials in gnome-keyring"
            color: Color.muted
            font.pixelSize: 13
          }
        }
      }
    }
  }

  // ---- components ---------------------------------------------------------------

  // Double-buffered frame loader: ping-pongs between two Image elements with Z-index
  // to eliminate any blank-frame flicker during asynchronous JPEG decoding.
  // Preserves camera aspect ratio without cropping (PreserveAspectFit).
  component FrameImage: Item {
    id: frame

    property string cameraId: ""
    property int fps: 0
    property int fillMode: Image.PreserveAspectFit
    property string baseUrl: ""
    property var state: null
    property int tick: 0
    property bool frontIsA: true
    readonly property bool hasFrame: imgA.status === Image.Ready || imgB.status === Image.Ready

    function bump() {
      if (baseUrl === "") return
      frame.tick += 1
      var nextUrl = baseUrl + "?t=" + frame.tick
      if (frame.frontIsA) {
        imgB.source = nextUrl
      } else {
        imgA.source = nextUrl
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
      interval: Math.max(30, Math.floor(1000 / Math.max(1, frame.fps)))
      repeat: true
      running: window.visible && frame.baseUrl !== "" && frame.fps > 0
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

  // Next-Gen Surveillance Card Tile (Themed)
  component CameraTile: Rectangle {
    id: tile

    signal tap(string cameraId)

    property string cameraId: ""
    property int fps: 0
    property string baseUrl: ""
    property var state: null

    readonly property bool online: state ? state.online === true : false
    readonly property bool streaming: state ? state.streaming === true : false
    readonly property string errorText: state && state.error ? String(state.error) : ""

    color: Color.background
    radius: 12
    border.width: tileMouse.containsMouse ? 2 : 1
    border.color: {
      if (tileMouse.containsMouse) return Color.accent
      if (!online) return Color.urgent
      return Color.popups.border
    }
    clip: true

    // Inner Frame Viewport
    FrameImage {
      id: tileFrame
      anchors.fill: parent
      anchors.margins: 2
      cameraId: tile.cameraId
      fps: tile.fps
      baseUrl: tile.baseUrl
      visible: tile.online
    }

    // Offline / unconfigured placeholder
    Column {
      anchors.centerIn: parent
      spacing: 8
      visible: !tile.online || !tileFrame.hasFrame

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 48
        height: 48
        radius: 24
        color: tile.online === false ? Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.15) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
        border.width: 1
        border.color: tile.online === false ? Color.urgent : Color.popups.border

        Text {
          anchors.centerIn: parent
          text: tile.errorText !== "" ? "󰅚" : (tile.online === false ? "󰅚" : "󰑐")
          font.pixelSize: 20
          color: tile.online === false ? Color.urgent : Color.muted
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.cameraId.toUpperCase()
        font.pixelSize: 13
        font.bold: true
        font.letterSpacing: 0.8
        color: Color.foreground
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.errorText !== "" ? tile.errorText : (tile.online === false ? "Camera Offline" : "Fetching Snapshot…")
        font.pixelSize: 11
        color: Color.muted
      }
    }

    // Top Header Overlay Pills
    // Left: Camera Name Badge (Themed)
    Rectangle {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.margins: 10
      height: 26
      width: nameRow.implicitWidth + 18
      radius: 13
      color: Color.popups.background
      border.width: 1
      border.color: Color.popups.border
      visible: tile.online && tileFrame.hasFrame

      Row {
        id: nameRow
        anchors.centerIn: parent
        spacing: 5

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰹗"
          font.pixelSize: 12
          color: Color.accent
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: tile.cameraId.toUpperCase()
          color: Color.foreground
          font.pixelSize: 11
          font.bold: true
          font.letterSpacing: 0.5
        }
      }
    }

    // Right: Status Tag Badge (Health Green)
    Rectangle {
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: 10
      height: 26
      width: tileStatusRow.implicitWidth + 18
      radius: 13
      color: Color.popups.background
      border.width: 1
      border.color: Color.popups.border
      visible: tile.online && tileFrame.hasFrame

      Row {
        id: tileStatusRow
        anchors.centerIn: parent
        spacing: 6

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 7
          height: 7
          radius: 3.5
          color: "#10b981"
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "READY"
          font.pixelSize: 10
          font.bold: true
          font.letterSpacing: 0.5
          color: "#34d399"
        }
      }
    }

    // Hover Action Button (Center Glowing Themed Pill)
    Rectangle {
      anchors.centerIn: parent
      width: focusActionRow.implicitWidth + 24
      height: 38
      radius: 19
      color: Color.popups.background
      border.width: 1.5
      border.color: Color.accent
      visible: tileMouse.containsMouse && tile.online && tileFrame.hasFrame
      z: 15

      Row {
        id: focusActionRow
        anchors.centerIn: parent
        spacing: 8

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "󰍉"
          font.pixelSize: 14
          color: Color.accent
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Open Live Stream"
          font.pixelSize: 12
          font.bold: true
          color: Color.foreground
        }
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        tile.tap(tile.cameraId)
      }
    }
  }
}
