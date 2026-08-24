import "."
import QtQuick
import qs.Commons
import qs.Ui

// Modern Glass Header Bar with Brand, View Mode Switcher, and Control Actions
Rectangle {
  id: headerBar

  property string focusedId: ""
  property int onlineCount: 0
  property int totalCount: 0
  property int columns: 3
  property int streamFps: 15
  property var fpsOptions: [5, 10, 15, 20, 25, 30]
  property bool isAudioOn: false
  property bool patrolMode: false
  property var focusedState: null
  property bool fpsDropdownOpen: false

  signal showGrid()
  signal showCinema()
  signal selectColumns(int cols)
  signal selectFps(int fps)
  signal toggleAudio()
  signal togglePatrol()

  height: Theme.components.headerHeight
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
    color: Theme.colors.hairline
  }

  // Left Header Section (Brand & Status)
  Row {
    id: leftBrandRow
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(12)

    BrandBlock {
      focusedId: headerBar.focusedId
      focusedState: headerBar.focusedState
      onlineCount: headerBar.onlineCount
      totalCount: headerBar.totalCount
    }

    LiveStatusCapsule {
      visible: headerBar.width >= Theme.screens.md
      anchors.verticalCenter: parent.verticalCenter
      focusedId: headerBar.focusedId
      streamFps: headerBar.streamFps
      onlineCount: headerBar.onlineCount
      totalCount: headerBar.totalCount
    }
  }

  // Center Section: View Mode Switcher
  ViewModeSwitcher {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    visible: headerBar.width > Theme.screens.sm
    isCinema: headerBar.focusedId !== ""
    onShowGrid: headerBar.showGrid()
    onShowCinema: headerBar.showCinema()
  }

  // Right Header Section (Tools & Actions)
  Row {
    anchors.right: parent.right
    anchors.rightMargin: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8

    // Grid Column Density Selector
    DensitySelector {
      visible: headerBar.focusedId === "" && headerBar.totalCount > 1
      anchors.verticalCenter: parent.verticalCenter
      columns: headerBar.columns
      onSelectColumns: (cols) => headerBar.selectColumns(cols)
    }

    // Stream FPS Dropdown (in cinema view)
    FpsDropdown {
      visible: headerBar.focusedId !== ""
      anchors.verticalCenter: parent.verticalCenter
      streamFps: headerBar.streamFps
      fpsOptions: headerBar.fpsOptions
      isOpen: headerBar.fpsDropdownOpen
      onSelectFps: (fps) => headerBar.selectFps(fps)
    }

    // Audio Mute/Unmute Toggle
    PillButton {
      visible: headerBar.focusedId !== ""
      anchors.verticalCenter: parent.verticalCenter
      icon: headerBar.isAudioOn ? "󰕾" : "󰕿"
      label: headerBar.isAudioOn ? "Audio ON" : "Muted"
      active: headerBar.isAudioOn
      collapseOnNarrow: true
      parentWidth: headerBar.width
      onClicked: headerBar.toggleAudio()
    }

    // Patrol Mode Toggle
    PillButton {
      visible: headerBar.focusedId !== "" && headerBar.totalCount > 1
      anchors.verticalCenter: parent.verticalCenter
      icon: "󰑖"
      label: "Patrol"
      active: headerBar.patrolMode
      collapseOnNarrow: true
      parentWidth: headerBar.width
      onClicked: headerBar.togglePatrol()
    }
  }
}

