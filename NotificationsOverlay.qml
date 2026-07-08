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

    // Restrict pointer input to the toasts themselves — otherwise this
    // Overlay-layer surface eats clicks over its whole box (even the empty
    // padding sliver left when there are no notifications), which sits above
    // fullscreen game surfaces and blocks clicks in that corner.
    mask: Region {
        item: toastCol
    }

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
        spacing: 20
        topPadding: notifServer.trackedNotifications.values.length > 0 ? 16 : 0

        Repeater {
            model: notifServer.trackedNotifications.values

            delegate: Item {
                required property var modelData

                id: toastRoot
                width:  toastCol.width
                height: toast.height
                property string pendingAction: ""

                function startExit(action) {
                    if (exitAnim.running) return
                    toastRoot.pendingAction = action
                    exitAnim.start()
                }

                // ── The unrolling scroll itself ─────────────────────────────
                Rectangle {
                    id: toast
                    anchors.top: parent.top
                    width: parent.width
                    radius: 14
                    color:  Qt.rgba(0.141, 0.157, 0.220, 0.94)
                    clip:   true
                    border.width: 1
                    border.color: root.urgencyColor(modelData.urgency)

                    property real targetHeight: toastLayout.implicitHeight + 26
                    property real revealHeight: 0
                    height: revealHeight

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
                                  leftMargin: 16; rightMargin: 12; topMargin: 22 }
                        spacing: 5

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 7

                            Text {
                                text: root.urgencyLabel(modelData.urgency)
                                color: root.urgencyColor(modelData.urgency)
                                font { pixelSize: 9; family: "JetBrainsMono Nerd Font"; bold: true; letterSpacing: 1.2 }
                            }
                            Text {
                                visible: modelData.appName !== ""
                                text: "· " + modelData.appName.toUpperCase()
                                color: "#555b77"
                                font { pixelSize: 9; family: "JetBrainsMono Nerd Font"; bold: true; letterSpacing: 1 }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: "×"; color: "#555b77"
                                font { pixelSize: 15; family: "JetBrainsMono Nerd Font" }
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -6
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: toastRoot.startExit("dismiss")
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
                        onTriggered: toastRoot.startExit("expire")
                    }

                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: toastRoot.startExit("dismiss")
                    }
                }

                // ── Wax rune-seal — stamps the scroll shut, cracks to release it ──
                Item {
                    id: sealBox
                    width: 32; height: 32
                    anchors.top: toast.top
                    anchors.left: toast.left
                    anchors.topMargin: -15
                    anchors.leftMargin: 16
                    z: 5

                    Rectangle {
                        id: sealFlash
                        anchors.centerIn: parent
                        width: parent.width + 16; height: parent.height + 16
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: root.urgencyColor(modelData.urgency)
                        opacity: 0
                    }

                    Rectangle {
                        id: sealBase
                        anchors.fill: parent
                        radius: width / 2
                        color: root.urgencyColor(modelData.urgency)

                        Rectangle {
                            width: 10; height: 6; radius: 3
                            x: 6; y: 6; rotation: -30
                            color: "#ffffff"; opacity: 0.18
                        }
                    }

                    Text {
                        id: sealGlyph
                        anchors.centerIn: parent
                        text: root.urgencyGlyph(modelData.urgency)
                        color: "#161722"
                        font { pixelSize: 14; family: "Noto Sans Runic" }
                    }
                }

                // ── Enter: seal stamps down, scroll unrolls beneath it ─────
                ParallelAnimation {
                    id: enterAnim
                    NumberAnimation { target: sealBox; property: "scale";    from: 1.6; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.7 }
                    NumberAnimation { target: sealBox; property: "rotation"; from: -18; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.7 }
                    NumberAnimation { target: sealFlash; property: "opacity"; from: 0.85; to: 0; duration: 420; easing.type: Easing.OutQuad }
                    SequentialAnimation {
                        PauseAnimation { duration: 90 }
                        NumberAnimation { target: toast; property: "revealHeight"; from: 0; to: toast.targetHeight; duration: 380; easing.type: Easing.OutQuart }
                    }
                }

                // ── Exit: seal lifts and fades, scroll rolls back up ───────
                ParallelAnimation {
                    id: exitAnim
                    NumberAnimation { target: toast; property: "revealHeight"; to: 0; duration: 300; easing.type: Easing.InQuad }
                    NumberAnimation { target: toast; property: "opacity";      to: 0; duration: 300; easing.type: Easing.InQuad }
                    NumberAnimation { target: sealBox; property: "scale";    to: 0.5; duration: 260; easing.type: Easing.InQuad }
                    NumberAnimation { target: sealBox; property: "rotation"; to: 22;  duration: 260; easing.type: Easing.InQuad }
                    NumberAnimation { target: sealBox; property: "opacity"; to: 0;   duration: 260; easing.type: Easing.InQuad }
                    onFinished: {
                        if (toastRoot.pendingAction === "dismiss") modelData.dismiss()
                        else modelData.expire()
                    }
                }

                Component.onCompleted: enterAnim.start()
            }
        }
    }
}
