import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: root

    required property var targetScreen
    required property var sysState

    screen: targetScreen
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "huginnNotifications"
    exclusionMode: ExclusionMode.Ignore

    anchors.top:   true
    anchors.right: true
    margins.top:   48
    margins.right: 16

    // Always give the window some width/height so Wayland creates the surface
    implicitWidth:  360
    implicitHeight: Math.max(toastCol.implicitHeight, 1)
    color: "transparent"

    function urgencyGlyph(u) {
        if (u === NotificationUrgency.Critical) return "ᚼ"  // Hagalaz - destruction/chaos
        if (u === NotificationUrgency.Low)      return "ᛟ"  // Othala - settled/passive
        return "ᚱ"                                          // Raedo - journey/thought
    }
    function urgencyLabel(u) {
        if (u === NotificationUrgency.Critical) return "CRIT"
        if (u === NotificationUrgency.Low)      return "LOW"
        return "INFO"
    }
    function urgencyColor(u) {
        if (u === NotificationUrgency.Critical) return "#f7768e"
        if (u === NotificationUrgency.Low)      return "#767c9c"
        return sysState.colAccent
    }
    function urgencyBg(u) {
        if (u === NotificationUrgency.Critical) return "#2e1420"
        if (u === NotificationUrgency.Low)      return "#1c1e2c"
        return "#1c1c42"
    }

    NotificationServer {
        id: notifServer
        keepOnReload: true
        onNotification: function(notif) {
            notif.tracked = true
        }
    }

    Column {
        id: toastCol
        width: parent.width
        spacing: 10

        Repeater {
            model: notifServer.trackedNotifications.values

            delegate: Rectangle {
                required property var modelData

                id: toast
                width:  toastCol.width
                height: toastLayout.implicitHeight + 22
                radius: 14
                color:  Qt.rgba(0.141, 0.157, 0.220, 0.94)
                clip:   false
                border.width: 1
                border.color: root.urgencyColor(modelData.urgency)

                property string pendingAction: ""
                transform: Translate { id: driftOffset; y: 0 }
                scale: 0.92
                opacity: 0

                // Igniting ring — flashes on arrival then fades
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -5
                    radius: parent.radius + 5
                    color: "transparent"
                    border.width: 2
                    border.color: toast.border.color
                    opacity: 0
                    z: -1
                    id: glowRing
                }

                // Faint rune watermark — subtle mythic touch
                Text {
                    text: "ᚱ"  // Raedo — journey/thought
                    font.family: "Noto Sans Runic"
                    font.pixelSize: 40
                    color: sysState.colGold
                    opacity: 0.05
                    rotation: -8
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -4
                }

                ColumnLayout {
                    id: toastLayout
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: 14; rightMargin: 12; topMargin: 11 }
                    spacing: 5

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 7

                        Rectangle {
                            id: badge
                            radius: 3
                            color: root.urgencyBg(modelData.urgency)
                            implicitWidth:  badgeRow.implicitWidth + 10
                            implicitHeight: 16

                            RowLayout {
                                id: badgeRow
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: root.urgencyGlyph(modelData.urgency)
                                    color: root.urgencyColor(modelData.urgency)
                                    font { pixelSize: 12; family: "Noto Sans Runic" }
                                }
                                Text {
                                    text: root.urgencyLabel(modelData.urgency)
                                    color: root.urgencyColor(modelData.urgency)
                                    font { pixelSize: 9; family: "JetBrainsMono Nerd Font"; bold: true; letterSpacing: 0.6 }
                                }
                            }
                        }

                        Text {
                            visible: modelData.appName !== ""
                            text: modelData.appName.toUpperCase()
                            color: "#555b77"
                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font"; bold: true; letterSpacing: 1 }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "×"; color: "#555b77"
                            font { pixelSize: 15; family: "JetBrainsMono Nerd Font" }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: toast.startExit("dismiss")
                            }
                            HoverHandler {
                                onHoveredChanged: parent.color = hovered ? "#a0a0d8" : "#555b77"
                            }
                        }
                    }

                    Text {
                        visible: modelData.summary !== ""
                        Layout.fillWidth: true
                        text: modelData.summary
                        color: "#c0caf5"
                        font { pixelSize: 13; family: "JetBrainsMono Nerd Font"; bold: true }
                        wrapMode: Text.Wrap
                    }

                    Text {
                        visible: modelData.body !== ""
                        Layout.fillWidth: true; text: modelData.body
                        color: "#a9b1d6"
                        font { pixelSize: 12; family: "JetBrainsMono Nerd Font" }
                        wrapMode: Text.Wrap
                        Layout.bottomMargin: 6
                    }
                }

                // Animated countdown underline
                Rectangle {
                    id: timeoutFill
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 1
                    anchors.bottomMargin: 1
                    height: 2
                    radius: 1
                    color: toast.border.color
                    opacity: 0.55
                    width: toast.width - 2
                }

                NumberAnimation {
                    target: timeoutFill; property: "width"
                    from: toast.width - 2; to: 0
                    duration: modelData.expireTimeout > 0 ? modelData.expireTimeout * 1000 : 5000
                    running: true
                }

                Timer {
                    interval: modelData.expireTimeout > 0 ? modelData.expireTimeout * 1000 : 5000
                    running: true; repeat: false
                    onTriggered: toast.startExit("expire")
                }

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: toast.startExit("dismiss")
                }

                function startExit(action) {
                    if (exitAnim.running) return
                    toast.pendingAction = action
                    exitAnim.start()
                }

                ParallelAnimation {
                    id: enterAnim
                    NumberAnimation { target: toast; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutQuad }
                    NumberAnimation { target: toast; property: "scale";   to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    NumberAnimation { target: driftOffset; property: "y"; from: -14; to: 0; duration: 380; easing.type: Easing.OutQuart }
                    NumberAnimation { target: glowRing; property: "opacity"; from: 0.65; to: 0; duration: 550; easing.type: Easing.OutQuad }
                }

                ParallelAnimation {
                    id: exitAnim
                    NumberAnimation { target: toast; property: "opacity"; to: 0; duration: 240; easing.type: Easing.InQuad }
                    NumberAnimation { target: toast; property: "scale";   to: 0.9; duration: 240; easing.type: Easing.InQuad }
                    NumberAnimation { target: driftOffset; property: "y"; to: -10; duration: 240; easing.type: Easing.InQuad }
                    onFinished: {
                        if (toast.pendingAction === "dismiss") modelData.dismiss()
                        else modelData.expire()
                    }
                }

                Component.onCompleted: enterAnim.start()
            }
        }
    }
}
