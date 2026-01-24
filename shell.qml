import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import Niri 0.1

ShellRoot {
    Niri {
        id: niri
        Component.onCompleted: connect()
        onConnected: console.log("Connected to niri")
        onErrorOccurred: function(error) {
            console.error("Error:", error)
        }
    }

    PanelWindow {
        id: root
        property color colBg: "#1a1b26"
        property color colFg: "#a9b1d6"
        property color colMuted: "#444b6a"
        property color colCyan: "#0db9d7"
        property color colBlue: "#7aa2f7"
        property color colPurple: "#ad8ee6"
        property color colYellow: "#e0af68"
        property color colGreen: "#9ece6a"
        property color colRed: "#f7768e"
        property color colOrange: "#ff9e64"
        property string fontFamily: "JetBrainsMono Nerd Font"
        property int fontSize: 14
        property int cpuUsage: 0
        property int memUsage: 0
        property int volumeLevel: 0
        property var lastCpuIdle: 0
        property var lastCpuTotal: 0
        
        // VPN state
        property bool vpnConnected: false
        property string vpnLocation: ""
        property bool vpnGaming: false
        
        // Network traffic
        property real downloadSpeed: 0  // KB/s
        property real uploadSpeed: 0    // KB/s
        property var lastRxBytes: 0
        property var lastTxBytes: 0
        property var lastNetTime: 0

        Process {
            id: cpuProc
            command: ["sh", "-c", "head -1 /proc/stat"]
            stdout: SplitParser {
                onRead: function(data) {
                    if (!data) return
                    var parts = data.trim().split(/\s+/)
                    var user = parseInt(parts[1]) || 0
                    var nice = parseInt(parts[2]) || 0
                    var system = parseInt(parts[3]) || 0
                    var idle = parseInt(parts[4]) || 0
                    var iowait = parseInt(parts[5]) || 0
                    var irq = parseInt(parts[6]) || 0
                    var softirq = parseInt(parts[7]) || 0
                    var total = user + nice + system + idle + iowait + irq + softirq
                    var idleTime = idle + iowait
                    if (root.lastCpuTotal > 0) {
                        var totalDiff = total - root.lastCpuTotal
                        var idleDiff = idleTime - root.lastCpuIdle
                        if (totalDiff > 0) {
                            root.cpuUsage = Math.round(100 * (totalDiff - idleDiff) / totalDiff)
                        }
                    }
                    root.lastCpuTotal = total
                    root.lastCpuIdle = idleTime
                }
            }
            Component.onCompleted: running = true
        }

        Process {
            id: memProc
            command: ["sh", "-c", "free | grep Mem"]
            stdout: SplitParser {
                onRead: function(data) {
                    if (!data) return
                    var parts = data.trim().split(/\s+/)
                    var total = parseInt(parts[1]) || 1
                    var used = parseInt(parts[2]) || 0
                    root.memUsage = Math.round(100 * used / total)
                }
            }
            Component.onCompleted: running = true
        }

        Process {
            id: volProc
            command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
            stdout: SplitParser {
                onRead: function(data) {
                    if (!data) return
                    var match = data.match(/Volume:\s*([\d.]+)/)
                    if (match) {
                        root.volumeLevel = Math.round(parseFloat(match[1]) * 100)
                    }
                }
            }
            Component.onCompleted: running = true
        }

        Process {
            id: netProc
            command: ["sh", "-c", "cat /proc/net/dev | grep -v 'lo:' | awk 'NR>2 {rx+=$2; tx+=$10} END {print rx, tx}'"]
            stdout: SplitParser {
                onRead: function(data) {
                    if (!data) return
                    var parts = data.trim().split(/\s+/)
                    var rxBytes = parseInt(parts[0]) || 0
                    var txBytes = parseInt(parts[1]) || 0
                    var currentTime = Date.now()
                    
                    if (root.lastNetTime > 0) {
                        var timeDiff = (currentTime - root.lastNetTime) / 1000 // seconds
                        if (timeDiff > 0) {
                            var rxDiff = rxBytes - root.lastRxBytes
                            var txDiff = txBytes - root.lastTxBytes
                            root.downloadSpeed = (rxDiff / timeDiff) / 1024 // KB/s
                            root.uploadSpeed = (txDiff / timeDiff) / 1024   // KB/s
                        }
                    }
                    
                    root.lastRxBytes = rxBytes
                    root.lastTxBytes = txBytes
                    root.lastNetTime = currentTime
                }
            }
            Component.onCompleted: running = true
        }

        Process {
            id: vpnStatus
            command: ["bash", "/home/nate/.local/bin/mullvad-cli-manager.sh", "status"]
            stdout: SplitParser {
                onRead: function(data) {
                    if (!data) return
                    console.log("VPN raw output:", data)
                    try {
                        var status = JSON.parse(data)
                        root.vpnConnected = status.connected || false
                        root.vpnLocation = status.location || ""
                        root.vpnGaming = status.gaming || false
                        if (status.error) {
                            console.error("VPN script error:", status.error)
                        }
                    } catch(e) {
                        console.error("VPN status parse error:", e, "Data was:", data)
                    }
                }
            }
            stderr: SplitParser {
                onRead: function(data) {
                    if (data) console.error("VPN script stderr:", data)
                }
            }
            Component.onCompleted: running = true
        }

        Process {
            id: vpnToggle
            command: ["bash", "/home/nate/.local/bin/mullvad-cli-manager.sh", "toggle"]
            onExited: vpnStatus.running = true
        }

        Process {
            id: vpnRandom
            command: ["bash", "/home/nate/.local/bin/mullvad-cli-manager.sh", "random"]
            onExited: vpnStatus.running = true
        }

        Process {
            id: vpnAutoRotate
            command: ["bash", "/home/nate/.local/bin/mullvad-cli-manager.sh", "auto-rotate", "21600"]
            onExited: vpnStatus.running = true
        }

        Timer {
            interval: 2000
            running: true
            repeat: true
            onTriggered: {
                cpuProc.running = true
                memProc.running = true
                volProc.running = true
                netProc.running = true
                vpnStatus.running = true
            }
        }

        // Auto-rotation timer (every 6 hours)
        Timer {
            interval: 21600000 // 6 hours in milliseconds
            running: true
            repeat: true
            onTriggered: vpnAutoRotate.running = true
        }

        anchors {
            top: true
            left: true
            right: true
        }
        height: 30
        color: root.colBg

        RowLayout {
            anchors.fill: parent
            anchors.margins: 8

            // Workspace indicators
            Repeater {
                model: niri.workspaces

                Text {
                    required property int index
                    required property bool isFocused
                    required property int id

                    text: index
                    color: isFocused ? root.colCyan : root.colBlue
                    font.pixelSize: 14
                    font.bold: true

                    MouseArea {
                        anchors.fill: parent
                        onClicked: niri.focusWorkspaceById(id)
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Network Traffic Monitor
            RowLayout {
                spacing: 4

                Text {
                    text: "↓"
                    color: root.colGreen
                    font.pixelSize: root.fontSize
                    font.family: root.fontFamily
                    font.bold: true
                }

                Text {
                    text: {
                        var speed = root.downloadSpeed
                        if (speed >= 1024) {
                            return (speed / 1024).toFixed(1) + " MB/s"
                        } else {
                            return speed.toFixed(1) + " KB/s"
                        }
                    }
                    color: root.colGreen
                    font.pixelSize: root.fontSize
                    font.family: root.fontFamily
                }

                Text {
                    text: "↑"
                    color: root.colRed
                    font.pixelSize: root.fontSize
                    font.family: root.fontFamily
                    font.bold: true
                }

                Text {
                    text: {
                        var speed = root.uploadSpeed
                        if (speed >= 1024) {
                            return (speed / 1024).toFixed(1) + " MB/s"
                        } else {
                            return speed.toFixed(1) + " KB/s"
                        }
                    }
                    color: root.colRed
                    font.pixelSize: root.fontSize
                    font.family: root.fontFamily
                }
            }

            Rectangle { width: 1; height: 16; color: root.colMuted }

            // VPN Status with controls
            RowLayout {
                spacing: 4

                Text {
                    text: root.vpnGaming ? "🎮 " : (root.vpnConnected ? " " : " ")
                    color: root.vpnGaming ? root.colOrange : (root.vpnConnected ? root.colGreen : root.colMuted)
                    font.pixelSize: root.fontSize
                    font.family: root.fontFamily
                }

                Text {
                    id: vpnText
                    text: root.vpnConnected ? root.vpnLocation.toUpperCase() : "VPN"
                    color: root.vpnConnected ? root.colGreen : root.colMuted
                    font.pixelSize: root.fontSize
                    font.family: root.fontFamily
                    font.bold: root.vpnConnected
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    
                    onClicked: function(mouse) {
                        console.log("VPN clicked, button:", mouse.button)
                        if (mouse.button === Qt.LeftButton) {
                            console.log("Starting vpnToggle")
                            vpnToggle.running = true
                        } else if (mouse.button === Qt.RightButton) {
                            console.log("Starting vpnRandom")
                            vpnRandom.running = true
                        }
                    }
                    
                    onEntered: {
                        vpnText.color = root.colCyan
                    }
                    
                    onExited: {
                        vpnText.color = root.vpnConnected ? root.colGreen : root.colMuted
                    }
                }
            }

            Rectangle { width: 1; height: 16; color: root.colMuted }

            Text {
                text: "CPU: " + root.cpuUsage + "%"
                color: root.colYellow
                font { family: root.fontFamily; pixelSize: root.fontSize; bold: true }
            }

            Rectangle { width: 1; height: 16; color: root.colMuted }

            Text {
                text: "Mem: " + root.memUsage + "%"
                color: root.colCyan
                font { family: root.fontFamily; pixelSize: root.fontSize; bold: true }
            }

            Rectangle { width: 1; height: 16; color: root.colMuted }

            Text {
                text: "Vol: " + root.volumeLevel + "%"
                color: root.colPurple
                font.pixelSize: root.fontSize
                font.family: root.fontFamily
                font.bold: true
                Layout.rightMargin: 8
            }

            Rectangle { width: 1; height: 16; color: root.colMuted }

            Text {
                id: clockText
                text: Qt.formatDateTime(new Date(), "ddd, MMM dd - hh:mm AP")
                color: root.colBlue
                font.pixelSize: root.fontSize
                font.family: root.fontFamily
                font.bold: true
                Layout.rightMargin: 8

                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: clockText.text = Qt.formatDateTime(new Date(), "ddd, MMM dd - hh:mm AP")
                }
            }
        }
    }
}
