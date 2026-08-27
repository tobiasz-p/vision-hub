import "."
import QtQuick
import qs.Commons
import qs.Ui

// Live Stream Status Capsule (Healthy Green / Alert Red with pulsing indicator)
Rectangle {
  id: capsule

  property string focusedId: ""
  property int streamFps: 15
  property int onlineCount: 0
  property int totalCount: 0

  readonly property bool isHealthy: capsule.focusedId !== "" || capsule.onlineCount === capsule.totalCount

  height: 24
  width: liveRow.implicitWidth + 18
  radius: 12
  color: {
    if (capsule.focusedId !== "") return Theme.colors.healthyMuted
    return isHealthy ? Theme.colors.healthySubtle : Theme.colors.urgentMuted
  }
  border.width: 1
  border.color: isHealthy ? Theme.colors.healthy : Color.urgent

  Row {
    id: liveRow
    anchors.centerIn: parent
    spacing: 6

    StatusDot {
      anchors.verticalCenter: parent.verticalCenter
      dotColor: capsule.isHealthy ? Theme.colors.healthy : Color.urgent
      pulsing: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: {
        if (capsule.focusedId !== "") return "LIVE " + capsule.streamFps + " FPS"
        return capsule.onlineCount === capsule.totalCount ? "ALL HEALTHY" : (capsule.totalCount - capsule.onlineCount) + " OFFLINE"
      }
      font.pixelSize: 10
      font.bold: true
      font.letterSpacing: 0.4
      color: capsule.isHealthy ? Theme.colors.healthyText : Color.urgent
      verticalAlignment: Text.AlignVCenter
    }
  }
}
