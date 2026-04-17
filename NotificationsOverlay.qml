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

    NotificationServer {
        id: notifServer
        keepOnReload: true
        onNotification: function(notif) {
            console.log("Notification received:", notif.summary, "tracked:", notif.tracked)
            notif.tracked = true
            console.log("Notification tracked set to true, count:", notifServer.trackedNotifications.values.length)
        }
    }

    Column {
        id: toastCol
        width: parent.width
        spacing: 8

        Repeater {
            model: notifServer.trackedNotifications.values

            delegate: Rectangle {
                required property var modelData

                id: toast
                width:  toastCol.width
                height: toastLayout.implicitHeight + 20
                radius: 10
                color:  Qt.rgba(0.141, 0.157, 0.220, 0.96)
                border.width: 1
                border.color: {
                    if (modelData.urgency === NotificationUrgency.Critical) return "#f7768e"
                    if (modelData.urgency === NotificationUrgency.Low)      return "#444b6a"
                    return sysState.colAccent
                }

                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: 3; radius: 10
                    color: toast.border.color
                }

                ColumnLayout {
                    id: toastLayout
                    anchors { left: parent.left; right: parent.right; top: parent.top
                              leftMargin: 16; rightMargin: 12; topMargin: 10 }
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            visible: modelData.appName !== ""
                            text: modelData.appName.toUpperCase()
                            color: "#555b77"
                            font { pixelSize: 10; family: "JetBrainsMono Nerd Font"; bold: true; letterSpacing: 1 }
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: "✕"; color: "#555b77"
                            font { pixelSize: 11; family: "JetBrainsMono Nerd Font" }
                            MouseArea {
                                anchors.fill: parent; anchors.margins: -6
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modelData.dismiss()
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

                // expireTimeout is in seconds
                Timer {
                    interval: modelData.expireTimeout > 0 ? modelData.expireTimeout * 1000 : 5000
                    running: true; repeat: false
                    onTriggered: modelData.expire()
                }

                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: modelData.dismiss()
                }

                opacity: 0
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Component.onCompleted: opacity = 1
            }
        }
    }
}
