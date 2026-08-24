import "."
import QtQuick
import qs.Commons
import qs.Ui

// Modern Multi-Camera Grid View
GridView {
  id: grid

  property var cameraList: []
  property int columns: 3
  property var visionService: null

  signal selectCamera(string cameraId)

  clip: true
  cellWidth: Math.floor(width / Math.max(1, grid.columns))
  cellHeight: Math.floor(cellWidth * 9 / 16)

  model: grid.cameraList

  delegate: Item {
    id: delegateRoot

    required property string modelData
    width: grid.cellWidth
    height: grid.cellHeight

    CameraTile {
      anchors.fill: parent
      anchors.margins: Style.space(6)
      cameraId: delegateRoot.modelData
      fps: grid.visionService ? grid.visionService.subFps : 2
      baseUrl: grid.visionService ? grid.visionService.frameUrl(delegateRoot.modelData) : ""
      state: grid.visionService ? grid.visionService.stateFor(delegateRoot.modelData) : null

      onTap: (tappedCameraId) => grid.selectCamera(tappedCameraId)
    }
  }
}
