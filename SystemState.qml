import Quickshell.Io
import QtQuick

// Shared system metrics, colors, and polling processes.
// Instantiate once at the ShellRoot level and pass as a property where needed.
// Item root (not QtObject) so child Process/Timer objects have a default property to attach to.
Item {
    id: root
    visible: false

    // ── Palette ──────────────────────────────────────────────────────────────
    readonly property color colBg:     "#1a1b26"
    readonly property color colFg:     "#a9b1d6"
    readonly property color colMuted:  "#444b6a"
    readonly property color colCyan:   "#0db9d7"
    readonly property color colBlue:   "#7aa2f7"
    readonly property color colPurple: "#ad8ee6"
    readonly property color colYellow: "#e0af68"
    readonly property color colGreen:  "#9ece6a"
    readonly property color colRed:    "#f7768e"
    readonly property color colOrange: "#ff9e64"
    readonly property string fontFamily: "Jetbrains Nerd Mono"
    readonly property int    fontSize:   14

    // ── Metrics ───────────────────────────────────────────────────────────────
    property int  cpuUsage:    0
    property int  memUsage:    0
    property int  volumeLevel: 0
    property var  lastCpuIdle:  0
    property var  lastCpuTotal: 0

    property bool   vpnConnected: false
    property string vpnLocation:  ""

    property real downloadSpeed: 0
    property real uploadSpeed:   0
    property var  lastRxBytes:   0
    property var  lastTxBytes:   0
    property var  lastNetTime:   0

    property int  batteryPercent:  0
    property bool batteryCharging: false
    property string fullChargeBrightness: "100%"

    // ── Helpers ───────────────────────────────────────────────────────────────
    function toRoman(num) {
        var romans = [
            ["M",1000],["CM",900],["D",500],["CD",400],
            ["C",100],["XC",90],["L",50],["XL",40],
            ["X",10],["IX",9],["V",5],["IV",4],["I",1]
        ]
        var result = ""
        for (var i = 0; i < romans.length; i++) {
            while (num >= romans[i][1]) {
                result += romans[i][0]
                num -= romans[i][1]
            }
        }
        return result
    }

    property bool calendarVisible: false
    function toggleCalendar() { calendarVisible = !calendarVisible }

    function connectVpn()    { vpnConnect.running    = true }
    function disconnectVpn() { vpnDisconnect.running = true }

    // ── Processes ─────────────────────────────────────────────────────────────
    // Declared as direct children so their ids are visible within this file.

    Process {
        id: cpuProc
        command: ["sh", "-c", "head -1 /proc/stat"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                var p       = data.trim().split(/\s+/)
                var user    = parseInt(p[1]) || 0
                var nice    = parseInt(p[2]) || 0
                var system  = parseInt(p[3]) || 0
                var idle    = parseInt(p[4]) || 0
                var iowait  = parseInt(p[5]) || 0
                var irq     = parseInt(p[6]) || 0
                var softirq = parseInt(p[7]) || 0
                var total    = user + nice + system + idle + iowait + irq + softirq
                var idleTime = idle + iowait
                if (root.lastCpuTotal > 0) {
                    var dt = total - root.lastCpuTotal
                    var di = idleTime - root.lastCpuIdle
                    if (dt > 0) root.cpuUsage = Math.round(100 * (dt - di) / dt)
                }
                root.lastCpuTotal = total
                root.lastCpuIdle  = idleTime
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
                var p = data.trim().split(/\s+/)
                root.memUsage = Math.round(100 * (parseInt(p[2]) || 0) / (parseInt(p[1]) || 1))
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
                var m = data.match(/Volume:\s*([\d.]+)/)
                if (m) root.volumeLevel = Math.round(parseFloat(m[1]) * 100)
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
                var p   = data.trim().split(/\s+/)
                var rx  = parseInt(p[0]) || 0
                var tx  = parseInt(p[1]) || 0
                var now = Date.now()
                if (root.lastNetTime > 0) {
                    var dt = (now - root.lastNetTime) / 1000
                    if (dt > 0) {
                        root.downloadSpeed = ((rx - root.lastRxBytes) / dt) / 1024
                        root.uploadSpeed   = ((tx - root.lastTxBytes) / dt) / 1024
                    }
                }
                root.lastRxBytes = rx
                root.lastTxBytes = tx
                root.lastNetTime = now
            }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: vpnStatus
        command: ["mullvad", "status"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                if (data.includes("Connected")) {
                    root.vpnConnected = true
                } else if (data.includes("Disconnected")) {
                    root.vpnConnected = false
                    root.vpnLocation  = ""
                } else if (data.includes("Visible location:")) {
                    var m = data.match(/Visible location:\s*(.+?)(?:\. IPv4|$)/)
                    if (m) root.vpnLocation = m[1].trim()
                }
            }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: vpnConnect
        command: ["mullvad", "connect"]
        onExited: vpnStatus.running = true
    }

    Process {
        id: vpnDisconnect
        command: ["mullvad", "disconnect"]
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

    Process {
        id: batteryProc
        command: ["sh", "-c", "echo $(cat /sys/class/power_supply/BAT1/capacity) $(cat /sys/class/power_supply/BAT1/status)"]
        stdout: SplitParser {
            onRead: function(data) {
                if (!data) return
                var parts = data.trim().split(/\s+/)
                if (parts.length >= 2) {
                    root.batteryPercent  = parseInt(parts[0]) || 0
                    root.batteryCharging = parts[1].toLowerCase() === 'charging'
                }
            }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: brightnessControl
        command: ["brightnessctl", "--class=backlight", "set", "50%"]
        function updateBrightness() {
            var target = "50%"
            if (root.batteryPercent <= 10 && !root.batteryCharging)       target = "20%"
            else if (root.batteryPercent <= 25 && !root.batteryCharging)  target = "30%"
            else if (root.batteryCharging)                                 target = "100%"
            else if (root.batteryPercent >= 95 && !root.batteryCharging)  target = root.fullChargeBrightness
            if (command[3] !== target) {
                command = ["brightnessctl", "-d", "amdgpu_bl1", "set", target]
                running = true
            }
        }
    }

    Process {
        id: refreshRateManager
        command: ["niri", "msg", "output", "eDP-1", "mode", "1920x1080@144.003"]
        function updateRefreshRate() {
            var mode = (root.batteryPercent <= 50 && !root.batteryCharging)
                ? "1920x1080@60.019"
                : "1920x1080@144.003"
            command = ["niri", "msg", "output", "eDP-1", "mode", mode]
            running = true
        }
    }

    // Poll all metrics every 2 s
    Timer {
        interval: 2000; running: true; repeat: true
        onTriggered: {
            cpuProc.running   = true
            memProc.running   = true
            volProc.running   = true
            netProc.running   = true
            vpnStatus.running = true
            batteryProc.running = true
            brightnessControl.updateBrightness()
            refreshRateManager.updateRefreshRate()
        }
    }

    // Rotate VPN server every 6 hours
    Timer {
        interval: 21600000; running: true; repeat: true
        onTriggered: vpnAutoRotate.running = true
    }
}
