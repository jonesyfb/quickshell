import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Per-monitor top bar.
// Variants in shell.qml injects `modelData` (the screen) automatically.
PanelWindow {
    id: bar

    required property var modelData   // injected by Variants
    property var sysState             // SystemState instance
    property var niriState            // Niri instance

    screen: modelData
    property bool isPrimary: Quickshell.screens.length === 0 || modelData.name === Quickshell.screens[0].name

    anchors { top: true; left: true; right: true }
    implicitHeight: 30
    color: sysState.colBg

    // ── Huginn widget – primary monitor, left side ───────────────────────────
    Row {
        id: huginnWidget
        visible: bar.isPrimary
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        spacing: 5

        property bool huginnVisible: false

        Process {
            id: huginnToggle
            command: ["bash", "/home/nate/dotfiles/huginn/scripts/huginn-toggle.sh"]
        }

        Process {
            id: huginnVisChecker
            command: ["sh", "-c", "[ -f /tmp/huginn-visible ] && echo 'true' || echo 'false'"]
            stdout: SplitParser {
                onRead: function(data) { huginnWidget.huginnVisible = (data.trim() === "true") }
            }
        }

        Timer { interval: 200; running: true; repeat: true; onTriggered: huginnVisChecker.running = true }

        MouseArea {
            implicitWidth:  runeText.implicitWidth + 8
            implicitHeight: bar.implicitHeight
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: huginnToggle.running = true
            onEntered:  runeText.color = "#f7c95e"
            onExited:   runeText.color = huginnWidget.huginnVisible ? "#f7c95e" : sysState.colMuted

            Text {
                id: runeText
                anchors.centerIn: parent
                text: "ᚱ"
                color: huginnWidget.huginnVisible ? "#f7c95e" : sysState.colMuted
                font.pixelSize: 16
                font.family: "JetBrainsMono Nerd Font"

                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }

    // ── Now playing – primary monitor, left side (beside rune) ──────────────
    Row {
        visible: bar.isPrimary && sysState.nowPlaying !== ""
        anchors.left: huginnWidget.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10
        spacing: 5

        Text {
            text: "♪"
            color: sysState.colGreen
            font.pixelSize: sysState.fontSize
            font.family: sysState.fontFamily
        }
        Text {
            text: sysState.nowPlaying
            color: sysState.colFg
            font.pixelSize: sysState.fontSize
            font.family: sysState.fontFamily
            elide: Text.ElideRight
            maximumLineCount: 1
            width: Math.min(implicitWidth, 280)
        }
    }

    // ── Right-side stats row ──────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: 8

        Item { Layout.fillWidth: true }

        // Network traffic – primary only
        RowLayout {
            visible: bar.isPrimary
            spacing: 4

            Text { text: "↓"; color: sysState.colGreen; font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily; font.bold: true }
            Text {
                text: {
                    var s = sysState.downloadSpeed
                    return s >= 1024 ? (s / 1024).toFixed(1) + " MB/s" : s.toFixed(1) + " KB/s"
                }
                color: sysState.colGreen; font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily
            }
            Text { text: "↑"; color: sysState.colRed; font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily; font.bold: true }
            Text {
                text: {
                    var s = sysState.uploadSpeed
                    return s >= 1024 ? (s / 1024).toFixed(1) + " MB/s" : s.toFixed(1) + " KB/s"
                }
                color: sysState.colRed; font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily
            }
        }

        Rectangle { visible: bar.isPrimary; width: 1; height: 16; color: sysState.colMuted }

        // VPN – primary only
        // MouseArea is the layout child; Row sits inside it to avoid anchors-on-layout conflict
        MouseArea {
            visible: bar.isPrimary
            implicitWidth: vpnRow.implicitWidth
            implicitHeight: vpnRow.implicitHeight
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked:  sysState.vpnConnected ? sysState.disconnectVpn() : sysState.connectVpn()
            onEntered:  vpnLabel.color = sysState.colCyan
            onExited:   vpnLabel.color = sysState.vpnConnected ? sysState.colGreen : sysState.colMuted

            Row {
                id: vpnRow
                spacing: 4

                Text {
                    text: sysState.vpnConnected ? " " : " "
                    color: sysState.vpnConnected ? sysState.colGreen : sysState.colMuted
                    font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily
                }
                Text {
                    id: vpnLabel
                    text: sysState.vpnConnected ? sysState.vpnLocation.toUpperCase() : "VPN"
                    color: sysState.vpnConnected ? sysState.colGreen : sysState.colMuted
                    font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily
                    font.bold: sysState.vpnConnected
                }
            }
        }

        Rectangle { visible: bar.isPrimary; width: 1; height: 16; color: sysState.colMuted }

        // WireGuard home tunnel
        Row {
            visible: bar.isPrimary
            spacing: 4

            Text {
                text: ""
                color: sysState.wg0Connected ? sysState.colOrange : sysState.colMuted
                font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily
                Behavior on color { ColorAnimation { duration: 150 } }
            }
            Text {
                text: sysState.wg0Connected ? "HOME" : "WG"
                color: sysState.wg0Connected ? sysState.colOrange : sysState.colMuted
                font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily
                font.bold: sysState.wg0Connected
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        Rectangle { visible: bar.isPrimary; width: 1; height: 16; color: sysState.colMuted }

        Text {
            visible: bar.isPrimary
            text: "CPU: " + sysState.cpuUsage + "%"
            color: sysState.colYellow
            font { family: sysState.fontFamily; pixelSize: sysState.fontSize; bold: true }
        }

        Rectangle { visible: bar.isPrimary; width: 1; height: 16; color: sysState.colMuted }

        Text {
            visible: bar.isPrimary && sysState.gpuUsage >= 0
            text: "GPU: " + sysState.gpuUsage + "%"
            color: sysState.colGreen
            font { family: sysState.fontFamily; pixelSize: sysState.fontSize; bold: true }
        }

        Rectangle { visible: bar.isPrimary && sysState.gpuUsage >= 0; width: 1; height: 16; color: sysState.colMuted }

        Text {
            visible: bar.isPrimary
            text: "Mem: " + sysState.memUsage + "%"
            color: sysState.colCyan
            font { family: sysState.fontFamily; pixelSize: sysState.fontSize; bold: true }
        }

        Rectangle { visible: bar.isPrimary; width: 1; height: 16; color: sysState.colMuted }

        Text {
            visible: bar.isPrimary
            text: "Vol: " + sysState.volumeLevel + "%"
            color: sysState.colPurple
            font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily; font.bold: true
            Layout.rightMargin: 8
        }

        Rectangle { visible: bar.isPrimary; width: 1; height: 16; color: sysState.colMuted }

        // Battery – primary only, hidden on desktop (batteryPercent stays 0)
        RowLayout {
            visible: bar.isPrimary && sysState.batteryPercent > 0
            spacing: 4

            Text {
                text: "Bat:"
                color: sysState.batteryCharging ? sysState.colGreen
                     : sysState.batteryPercent <= 10 ? sysState.colRed
                     : sysState.batteryPercent <= 25 ? sysState.colYellow
                     : sysState.colGreen
                font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily; font.bold: true
            }
            Text {
                text: sysState.batteryCharging ? "" : ""
                color: sysState.batteryCharging ? sysState.colGreen
                     : sysState.batteryPercent <= 10 ? sysState.colRed
                     : sysState.batteryPercent <= 25 ? sysState.colYellow
                     : sysState.colGreen
                font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily
            }
            Text {
                text: sysState.batteryPercent + "%"
                color: sysState.batteryCharging ? sysState.colGreen
                     : sysState.batteryPercent <= 10 ? sysState.colRed
                     : sysState.batteryPercent <= 25 ? sysState.colYellow
                     : sysState.colGreen
                font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily; font.bold: true
            }
        }

        Rectangle { visible: bar.isPrimary && sysState.batteryPercent > 0; width: 1; height: 16; color: sysState.colMuted }

        // Clock – every monitor, click to toggle calendar
        Text {
            id: clockText
            text: Qt.formatDateTime(new Date(), "ddd, MMM dd - hh:mm AP")
            color: sysState.calendarVisible ? sysState.colAccent : sysState.colBlue
            font.pixelSize: sysState.fontSize; font.family: sysState.fontFamily; font.bold: true
            Layout.rightMargin: 8

            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: clockText.text = Qt.formatDateTime(new Date(), "ddd, MMM dd - hh:mm AP")
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sysState.toggleCalendar()
            }
        }
    }

    // ── Workspace indicator – this monitor only ───────────────────────────────
    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Repeater {
            model: niriState.workspaces

            Text {
                required property int    index
                required property bool   isFocused
                required property int    id
                required property string output

                // Row skips invisible children automatically
                visible: output === bar.modelData.name
                text: sysState.toRoman(index)
                color: isFocused ? sysState.colAccent : sysState.colBlue
                font.pixelSize: 14; font.bold: true

                MouseArea {
                    anchors.fill: parent
                    onClicked: niriState.focusWorkspaceById(id)
                }
            }
        }
    }
}
