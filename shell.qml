import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import Niri 0.1

ShellRoot {
    property bool statsVisible: false
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

            Item { 
                Layout.fillWidth: true
            }

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
        Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    spacing: 8

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
}
    }
    // New stats overlay window
PanelWindow {
    id: statsOverlay
    visible: visibilityState.visible
    WlrLayershell.namespace: "statsOverlay"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore

    // Properties for chart data
    property var cpuHistory: []
    property var memHistory: []
    property int maxHistoryPoints: 30
    property int pingMs: 0
    property int currentFps: 0

    property int gpuUsage: 0
    property int gpuTemp: 0
    property int gpuVram: 0
    property int gpuPower: 0
    property int cpuTemp: 0

    anchors {
        top: true
        left: true
    }

    margins {
        top: 0  // Below your top bar
        left: 0
    }

    width: 250
    height: 260
    color: "transparent"

    QtObject {
        id: visibilityState
        property bool visible: false
        onVisibleChanged: {
        console.log("visibilityState.visible changed to:", visible)
    }
    }

    Process {
        id: visibilityChecker
        command: ["sh", "-c", "[ -f /tmp/quickshell-stats-visible ] && echo 'true' || echo 'false'"]
        stdout: SplitParser {
            onRead: function(data) {
                var result = data.trim()
                console.log("Visibility check result:", result)
                visibilityState.visible = (result === "true")
            }
        }
    }

    // Ping process
    Process {
        id: pingProc
        command: ["sh", "-c", "ping -c 1 -W 1 1.1.1.1 | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}'"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                var ms = parseFloat(data.trim())
                if (!isNaN(ms)) {
                    statsOverlay.pingMs = Math.round(ms)
                }
            }
        }
        Component.onCompleted: running = true
    }

    // FPS counter (reads from /tmp/fps if you have a script writing to it)
    // Alternative: use MangoHud's output or parse compositor stats
    Process {
        id: fpsProc
        command: ["bash", "/home/nate/.local/bin/get-gamescope-fps.sh"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                var fps = parseInt(data.trim())
                if (!isNaN(fps)) {
                    statsOverlay.currentFps = fps
                }
            }
        }
        Component.onCompleted: running = true
    }
    Process {
        id: gpuUsageProc
        command: ["sh", "-c", "cat /sys/class/drm/card1/device/gpu_busy_percent 2>/dev/null || echo 0"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                statsOverlay.gpuUsage = parseInt(data.trim()) || 0
            }
        }
        Component.onCompleted: running = true
    }

    // GPU Temperature
    Process {
        id: gpuTempProc
        command: ["sh", "-c", "sensors -j 2>/dev/null | jq -r '.\"amdgpu-pci-0300\".junction.temp2_input // 0'"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                statsOverlay.gpuTemp = Math.round(parseFloat(data.trim())) || 0
            }
        }
        Component.onCompleted: running = true
    }

    // GPU VRAM Usage
    Process {
        id: gpuVramProc
        command: ["sh", "-c", "cat /sys/class/drm/card1/device/mem_info_vram_used 2>/dev/null || echo 0"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                // Convert bytes to GB
                var bytes = parseInt(data.trim()) || 0
                statsOverlay.gpuVram = Math.round(bytes / 1024 / 1024 / 1024 * 10) / 10
            }
        }
        Component.onCompleted: running = true
    }
    Process {
        id: gpuPowerProc
        command: ["sh", "-c", "sensors -j 2>/dev/null | jq -r '.\"amdgpu-pci-0300\".PPT.power1_average // 0'"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                statsOverlay.gpuPower = Math.round(parseFloat(data.trim())) || 0
            }
        }
        Component.onCompleted: running = true
    }

    // CPU Temperature (using sensors)
    Process {
        id: cpuTempProc
        command: ["sh", "-c", "sensors -j 2>/dev/null | jq -r '.\"k10temp-pci-00c3\".Tctl.temp1_input // 0' || echo 0"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                statsOverlay.cpuTemp = Math.round(parseFloat(data.trim())) || 0
            }
        }
        Component.onCompleted: running = true
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            // Update ping
            pingProc.running = true

            // Update FPS
            fpsProc.running = true

            // Update chart history
            statsOverlay.cpuHistory.push(root.cpuUsage)
            statsOverlay.memHistory.push(root.memUsage)

            if (statsOverlay.cpuHistory.length > statsOverlay.maxHistoryPoints) {
                statsOverlay.cpuHistory.shift()
            }
            if (statsOverlay.memHistory.length > statsOverlay.maxHistoryPoints) {
                statsOverlay.memHistory.shift()
            }

            gpuUsageProc.running = true
            gpuTempProc.running = true
            gpuVramProc.running = true
            cpuTempProc.running = true

            // Force canvas redraws
            cpuChart.requestPaint()
            memChart.requestPaint()
        }
    }
    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            visibilityChecker.running = true
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.102, 0.106, 0.149, 0.5)
        radius: 8
        border.color: "#444b6a"
        border.width: 1

        ColumnLayout {
            anchors {
                fill: parent
                margins: 12
            }
            spacing: 10

            // CPU with chart
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "CPU"
                        color: "#e0af68"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: statsOverlay.cpuTemp + "°C"
                        color: statsOverlay.cpuTemp > 80 ? "#f7768e" :
                               statsOverlay.cpuTemp > 65 ? "#ff9e64" : "#9ece6a"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        Layout.rightMargin: 8
                    }

                    Text {
                        text: root.cpuUsage + "%"
                        color: "#a9b1d6"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                }

                Canvas {
                    id: cpuChart
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        if (statsOverlay.cpuHistory.length < 2) return

                        // Draw grid lines
                        ctx.strokeStyle = "#444b6a"
                        ctx.lineWidth = 0.5
                        for (var i = 0; i <= 4; i++) {
                            var y = (height / 4) * i
                            ctx.beginPath()
                            ctx.moveTo(0, y)
                            ctx.lineTo(width, y)
                            ctx.stroke()
                        }

                        // Draw line
                        ctx.strokeStyle = "#e0af68"
                        ctx.lineWidth = 2
                        ctx.beginPath()

                        var points = statsOverlay.cpuHistory
                        var stepX = width / (statsOverlay.maxHistoryPoints - 1)

                        for (var i = 0; i < points.length; i++) {
                            var x = i * stepX
                            var y = height - (points[i] / 100 * height)

                            if (i === 0) {
                                ctx.moveTo(x, y)
                            } else {
                                ctx.lineTo(x, y)
                            }
                        }
                        ctx.stroke()

                        // Fill area under line
                        ctx.lineTo(width, height)
                        ctx.lineTo(0, height)
                        ctx.closePath()
                        ctx.fillStyle = Qt.rgba(0.878, 0.686, 0.408, 0.2)
                        ctx.fill()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#444b6a"
            }

            // Memory with chart
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "MEMORY"
                        color: "#0db9d7"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: root.memUsage + "%"
                        color: "#a9b1d6"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                }

                Canvas {
                    id: memChart
                    Layout.fillWidth: true
                    Layout.preferredHeight: 30

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        if (statsOverlay.memHistory.length < 2) return

                        // Draw grid lines
                        ctx.strokeStyle = "#444b6a"
                        ctx.lineWidth = 0.5
                        for (var i = 0; i <= 4; i++) {
                            var y = (height / 4) * i
                            ctx.beginPath()
                            ctx.moveTo(0, y)
                            ctx.lineTo(width, y)
                            ctx.stroke()
                        }

                        // Draw line
                        ctx.strokeStyle = "#0db9d7"
                        ctx.lineWidth = 2
                        ctx.beginPath()

                        var points = statsOverlay.memHistory
                        var stepX = width / (statsOverlay.maxHistoryPoints - 1)

                        for (var i = 0; i < points.length; i++) {
                            var x = i * stepX
                            var y = height - (points[i] / 100 * height)

                            if (i === 0) {
                                ctx.moveTo(x, y)
                            } else {
                                ctx.lineTo(x, y)
                            }
                        }
                        ctx.stroke()

                        // Fill area under line
                        ctx.lineTo(width, height)
                        ctx.lineTo(0, height)
                        ctx.closePath()
                        ctx.fillStyle = Qt.rgba(0.051, 0.725, 0.843, 0.2)
                        ctx.fill()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#444b6a"
            }

             // GPU Stats
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "GPU"
                    color: "#ad8ee6"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: statsOverlay.gpuTemp + "°C"
                    color: statsOverlay.gpuTemp > 85 ? "#f7768e" :
                           statsOverlay.gpuTemp > 70 ? "#ff9e64" : "#9ece6a"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                    Layout.rightMargin: 8
                }

                Text {
                    text: statsOverlay.gpuUsage + "%"
                    color: "#a9b1d6"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }
                Text {
                    text: statsOverlay.gpuPower + "W"
                    color: "#7aa2f7"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
            }

            // GPU VRAM
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "VRAM"
                    color: "#ad8ee6"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: statsOverlay.gpuVram.toFixed(1) + " GB"
                    color: "#a9b1d6"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#444b6a"
            }

            // Ping
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "PING"
                    color: statsOverlay.pingMs < 50 ? "#9ece6a" :
                           statsOverlay.pingMs < 100 ? "#e0af68" : "#f7768e"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: statsOverlay.pingMs + " ms"
                    color: "#a9b1d6"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }
            }

            // FPS
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "FPS"
                    color: statsOverlay.currentFps >= 60 ? "#9ece6a" :
                           statsOverlay.currentFps >= 30 ? "#e0af68" : "#f7768e"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: statsOverlay.currentFps > 0 ? statsOverlay.currentFps.toString() : "N/A"
                    color: "#a9b1d6"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
}
