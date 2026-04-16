import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Toggleable overlay showing CPU/GPU/mem/ping/fps charts.
// Visibility is controlled by the existence of /tmp/quickshell-stats-visible.
PanelWindow {
    id: overlay

    property var sysState  // SystemState instance

    WlrLayershell.namespace: "statsOverlay"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    visible: visibilityState.visible

    anchors { top: true; left: true }
    margins { top: 0; left: 0 }
    implicitWidth: 250
    implicitHeight: 260
    color: "transparent"

    // ── History buffers ───────────────────────────────────────────────────────
    property var cpuHistory: []
    property var memHistory: []
    property int maxHistoryPoints: 30

    // ── Hardware readings ─────────────────────────────────────────────────────
    property int pingMs:    0
    property int currentFps: 0
    property int gpuUsage:  0
    property int gpuTemp:   0
    property int gpuVram:   0
    property int gpuPower:  0
    property int cpuTemp:   0

    // ── Visibility state ──────────────────────────────────────────────────────
    QtObject {
        id: visibilityState
        property bool visible: false
        onVisibleChanged: console.log("statsOverlay visible:", visible)
    }

    Process {
        id: visibilityChecker
        command: ["sh", "-c", "[ -f /tmp/quickshell-stats-visible ] && echo 'true' || echo 'false'"]
        stdout: SplitParser {
            onRead: function(data) { visibilityState.visible = (data.trim() === "true") }
        }
    }

    Timer { interval: 100; running: true; repeat: true; onTriggered: visibilityChecker.running = true }

    // ── Hardware processes ────────────────────────────────────────────────────
    Process {
        id: pingProc
        command: ["sh", "-c", "ping -c 1 -W 1 1.1.1.1 | grep 'time=' | awk -F'time=' '{print $2}' | awk '{print $1}'"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                var ms = parseFloat(data.trim())
                if (!isNaN(ms)) overlay.pingMs = Math.round(ms)
            }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: fpsProc
        command: ["bash", "/home/nate/.local/bin/get-gamescope-fps.sh"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                var fps = parseInt(data.trim())
                if (!isNaN(fps)) overlay.currentFps = fps
            }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: gpuUsageProc
        command: ["sh", "-c", "cat /sys/class/drm/card1/device/gpu_busy_percent 2>/dev/null || echo 0"]
        stdout: SplitParser {
            onRead: function(data) { if (data) overlay.gpuUsage = parseInt(data.trim()) || 0 }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: gpuTempProc
        command: ["sh", "-c", "sensors -j 2>/dev/null | jq -r '.\"amdgpu-pci-0300\".junction.temp2_input // 0'"]
        stdout: SplitParser {
            onRead: function(data) { if (data) overlay.gpuTemp = Math.round(parseFloat(data.trim())) || 0 }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: gpuVramProc
        command: ["sh", "-c", "cat /sys/class/drm/card1/device/mem_info_vram_used 2>/dev/null || echo 0"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                overlay.gpuVram = Math.round((parseInt(data.trim()) || 0) / 1024 / 1024 / 1024 * 10) / 10
            }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: gpuPowerProc
        command: ["sh", "-c", "sensors -j 2>/dev/null | jq -r '.\"amdgpu-pci-0300\".PPT.power1_average // 0'"]
        stdout: SplitParser {
            onRead: function(data) { if (data) overlay.gpuPower = Math.round(parseFloat(data.trim())) || 0 }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: cpuTempProc
        command: ["sh", "-c", "sensors -j 2>/dev/null | jq -r '.\"k10temp-pci-00c3\".Tctl.temp1_input // 0' || echo 0"]
        stdout: SplitParser {
            onRead: function(data) { if (data) overlay.cpuTemp = Math.round(parseFloat(data.trim())) || 0 }
        }
        Component.onCompleted: running = true
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            pingProc.running     = true
            fpsProc.running      = true
            gpuUsageProc.running = true
            gpuTempProc.running  = true
            gpuVramProc.running  = true
            cpuTempProc.running  = true

            overlay.cpuHistory.push(sysState.cpuUsage)
            overlay.memHistory.push(sysState.memUsage)
            if (overlay.cpuHistory.length > overlay.maxHistoryPoints) overlay.cpuHistory.shift()
            if (overlay.memHistory.length > overlay.maxHistoryPoints) overlay.memHistory.shift()

            cpuChart.requestPaint()
            memChart.requestPaint()
        }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0.102, 0.106, 0.149, 0.5)
        radius: 8
        border.color: "#444b6a"; border.width: 1

        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 10

            // CPU
            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "CPU"; color: "#e0af68"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: overlay.cpuTemp + "°C"
                        color: overlay.cpuTemp > 80 ? "#f7768e" : overlay.cpuTemp > 65 ? "#ff9e64" : "#9ece6a"
                        font.family: "Jetbrains Nerd Mono"; font.pixelSize: 10; Layout.rightMargin: 8
                    }
                    Text { text: sysState.cpuUsage + "%"; color: "#a9b1d6"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11 }
                }
                Canvas {
                    id: cpuChart
                    Layout.fillWidth: true; Layout.preferredHeight: 30
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        if (overlay.cpuHistory.length < 2) return
                        ctx.strokeStyle = "#444b6a"; ctx.lineWidth = 0.5
                        for (var i = 0; i <= 4; i++) {
                            var y = (height / 4) * i
                            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                        }
                        ctx.strokeStyle = "#e0af68"; ctx.lineWidth = 2; ctx.beginPath()
                        var pts = overlay.cpuHistory
                        var stepX = width / (overlay.maxHistoryPoints - 1)
                        for (var i = 0; i < pts.length; i++) {
                            var x = i * stepX; var y = height - (pts[i] / 100 * height)
                            i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
                        }
                        ctx.stroke()
                        ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath()
                        ctx.fillStyle = Qt.rgba(0.878, 0.686, 0.408, 0.2); ctx.fill()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#444b6a" }

            // Memory
            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "MEMORY"; color: "#0db9d7"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11; font.bold: true }
                    Item { Layout.fillWidth: true }
                    Text { text: sysState.memUsage + "%"; color: "#a9b1d6"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11 }
                }
                Canvas {
                    id: memChart
                    Layout.fillWidth: true; Layout.preferredHeight: 30
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        if (overlay.memHistory.length < 2) return
                        ctx.strokeStyle = "#444b6a"; ctx.lineWidth = 0.5
                        for (var i = 0; i <= 4; i++) {
                            var y = (height / 4) * i
                            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                        }
                        ctx.strokeStyle = "#0db9d7"; ctx.lineWidth = 2; ctx.beginPath()
                        var pts = overlay.memHistory
                        var stepX = width / (overlay.maxHistoryPoints - 1)
                        for (var i = 0; i < pts.length; i++) {
                            var x = i * stepX; var y = height - (pts[i] / 100 * height)
                            i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
                        }
                        ctx.stroke()
                        ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath()
                        ctx.fillStyle = Qt.rgba(0.051, 0.725, 0.843, 0.2); ctx.fill()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#444b6a" }

            // GPU
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Text { text: "GPU"; color: "#ad8ee6"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11; font.bold: true }
                Item { Layout.fillWidth: true }
                Text {
                    text: overlay.gpuTemp + "°C"
                    color: overlay.gpuTemp > 85 ? "#f7768e" : overlay.gpuTemp > 70 ? "#ff9e64" : "#9ece6a"
                    font.family: "Jetbrains Nerd Mono"; font.pixelSize: 10; Layout.rightMargin: 8
                }
                Text { text: overlay.gpuUsage + "%"; color: "#a9b1d6"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11 }
                Text { text: overlay.gpuPower + "W"; color: "#7aa2f7"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 10 }
            }

            // VRAM
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Text { text: "VRAM"; color: "#ad8ee6"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11 }
                Item { Layout.fillWidth: true }
                Text { text: overlay.gpuVram.toFixed(1) + " GB"; color: "#a9b1d6"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11 }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: "#444b6a" }

            // Ping
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Text {
                    text: "PING"
                    color: overlay.pingMs < 50 ? "#9ece6a" : overlay.pingMs < 100 ? "#e0af68" : "#f7768e"
                    font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11; font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text { text: overlay.pingMs + " ms"; color: "#a9b1d6"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11 }
            }

            // FPS
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Text {
                    text: "FPS"
                    color: overlay.currentFps >= 60 ? "#9ece6a" : overlay.currentFps >= 30 ? "#e0af68" : "#f7768e"
                    font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11; font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: overlay.currentFps > 0 ? overlay.currentFps.toString() : "N/A"
                    color: "#a9b1d6"; font.family: "Jetbrains Nerd Mono"; font.pixelSize: 11
                }
            }

            Item { Layout.fillHeight: true }
        }
    }
}
