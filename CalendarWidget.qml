import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// Calendar popup — click the clock in the bar to toggle.
// Fetches from Radicale via fetch-calendar.sh.
// Credentials live in ~/.config/quickshell/calendar.conf (not in git).
PanelWindow {
    id: calWidget
    property var sysState

    WlrLayershell.namespace: "calendarWidget"
    WlrLayershell.layer: WlrLayer.Overlay
    exclusionMode: ExclusionMode.Ignore
    visible: sysState ? sysState.calendarVisible : false

    anchors.top: true
    anchors.right: true
    margins.top: 30
    margins.right: 0

    implicitWidth: 310
    implicitHeight: 530
    color: "transparent"

    // ── State ─────────────────────────────────────────────────────────────────
    property var calendarEvents: []
    property string icsBuffer:   ""
    property int viewYear:  new Date().getFullYear()
    property int viewMonth: new Date().getMonth()   // 0-based

    // ── Fetch ─────────────────────────────────────────────────────────────────
    onVisibleChanged: if (visible) fetchProc.running = true

    Timer { interval: 300000; running: true; repeat: true; onTriggered: fetchProc.running = true }

    Process {
        id: fetchProc
        command: ["bash", "-c", "exec ~/dotfiles/quickshell/fetch-calendar.sh"]
        stdout: SplitParser {
            onRead: function(data) { calWidget.icsBuffer += data + "\n" }
        }
        onExited: {
            calWidget.calendarEvents = calWidget.parseIcs(calWidget.icsBuffer)
            calWidget.icsBuffer = ""
        }
        Component.onCompleted: running = true
    }

    // ── ICS parsing ───────────────────────────────────────────────────────────
    function parseIcsDate(line) {
        // Strip property name, keep value after last ':'
        var val = line.split(":").pop().trim()
        var allDay = line.includes("VALUE=DATE") || val.length === 8
        var y  = parseInt(val.substring(0, 4))
        var mo = parseInt(val.substring(4, 6)) - 1
        var d  = parseInt(val.substring(6, 8))
        if (allDay) return { date: new Date(y, mo, d, 0, 0), allDay: true }
        var h   = parseInt(val.substring(9, 11))  || 0
        var min = parseInt(val.substring(11, 13)) || 0
        // UTC → local
        if (val.endsWith("Z")) return { date: new Date(Date.UTC(y, mo, d, h, min)), allDay: false }
        return { date: new Date(y, mo, d, h, min), allDay: false }
    }

    function parseIcs(data) {
        // Unfold continuation lines (start with space/tab)
        var raw = data.split("\n")
        var lines = []
        for (var i = 0; i < raw.length; i++) {
            var l = raw[i]
            if ((l.startsWith(" ") || l.startsWith("\t")) && lines.length > 0)
                lines[lines.length - 1] += l.trim()
            else
                lines.push(l.trim())
        }

        var today = new Date(); today.setHours(0, 0, 0, 0)

        var events = []
        var ev = null
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i]
            if      (line === "BEGIN:VEVENT") ev = { summary: "", start: null, end: null, allDay: false }
            else if (line === "END:VEVENT" && ev) {
                if (ev.start && ev.start >= today) events.push(ev)
                ev = null
            }
            else if (ev) {
                if      (line.startsWith("SUMMARY:"))  ev.summary = line.substring(8)
                else if (line.match(/^DTSTART/)) { var r = parseIcsDate(line); ev.start = r.date; ev.allDay = r.allDay }
                else if (line.match(/^DTEND/))   ev.end = parseIcsDate(line).date
            }
        }

        events.sort(function(a, b) { return a.start - b.start })
        return events
    }

    // ── Calendar helpers ──────────────────────────────────────────────────────
    function daysInMonth(y, m)  { return new Date(y, m + 1, 0).getDate() }
    function firstDayOfMonth(y, m) { return new Date(y, m, 1).getDay() }  // 0 = Sun

    function hasEvent(day) {
        for (var i = 0; i < calendarEvents.length; i++) {
            var ev = calendarEvents[i]
            if (ev.start &&
                ev.start.getFullYear() === viewYear &&
                ev.start.getMonth()    === viewMonth &&
                ev.start.getDate()     === day) return true
        }
        return false
    }

    function prevMonth() {
        if (viewMonth === 0) { viewMonth = 11; viewYear-- } else viewMonth--
    }
    function nextMonth() {
        if (viewMonth === 11) { viewMonth = 0; viewYear++ } else viewMonth++
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Rectangle {
        id: bg
        anchors.fill: parent
        color: sysState.colBg
        radius: 8
        border.color: sysState.colMuted
        border.width: 1

        property real cellW: (width - 24) / 7

        ColumnLayout {
            anchors { fill: parent; margins: 12 }
            spacing: 6

            // Month navigation
            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "‹"
                    color: sysState.colFg; font.pixelSize: 18; font.family: sysState.fontFamily
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: prevMonth() }
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.formatDate(new Date(viewYear, viewMonth, 1), "MMMM yyyy").toUpperCase()
                    color: sysState.colFg; font.pixelSize: 12; font.family: sysState.fontFamily; font.bold: true
                }
                // Today button
                Text {
                    text: "●"
                    color: sysState.colCyan; font.pixelSize: 10; font.family: sysState.fontFamily
                    visible: viewYear !== new Date().getFullYear() || viewMonth !== new Date().getMonth()
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { viewYear = new Date().getFullYear(); viewMonth = new Date().getMonth() }
                    }
                }
                Text {
                    text: "›"
                    color: sysState.colFg; font.pixelSize: 18; font.family: sysState.fontFamily
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: nextMonth() }
                }
            }

            // Day headers
            Row {
                Layout.fillWidth: true
                Repeater {
                    model: ["SU","MO","TU","WE","TH","FR","SA"]
                    Text {
                        width: bg.cellW
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: sysState.colMuted; font.pixelSize: 10; font.family: sysState.fontFamily
                    }
                }
            }

            // Calendar grid
            Grid {
                Layout.fillWidth: true
                columns: 7

                Repeater {
                    model: firstDayOfMonth(viewYear, viewMonth) + daysInMonth(viewYear, viewMonth)

                    Item {
                        width: bg.cellW
                        height: bg.cellW

                        property int  day:       index - firstDayOfMonth(viewYear, viewMonth) + 1
                        property bool valid:     index >= firstDayOfMonth(viewYear, viewMonth)
                        property bool isToday: {
                            var n = new Date()
                            return valid && day === n.getDate() &&
                                   viewMonth === n.getMonth() && viewYear === n.getFullYear()
                        }
                        property bool dotted: valid && hasEvent(day)

                        // Today highlight circle
                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - 6; height: width; radius: width / 2
                            color: isToday ? sysState.colCyan : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            text: valid ? day.toString() : ""
                            color: isToday ? sysState.colBg : (dotted ? sysState.colBlue : sysState.colFg)
                            font.pixelSize: 11; font.family: sysState.fontFamily; font.bold: isToday || dotted
                        }

                        // Event dot
                        Rectangle {
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 4; height: 4; radius: 2
                            color: sysState.colBlue
                            visible: dotted && !isToday
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: sysState.colMuted }

            // Upcoming events header
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "UPCOMING"
                    color: sysState.colMuted; font.pixelSize: 10; font.family: sysState.fontFamily; font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: calendarEvents.length > 0 ? calendarEvents.length + " events" : "no events"
                    color: sysState.colMuted; font.pixelSize: 10; font.family: sysState.fontFamily
                }
            }

            // Events list
            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: calendarEvents
                spacing: 6

                delegate: RowLayout {
                    width: ListView.view.width
                    spacing: 8

                    Rectangle { width: 3; height: 36; radius: 2; color: sysState.colBlue }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: modelData.summary || "(no title)"
                            color: sysState.colFg
                            font.pixelSize: 12; font.family: sysState.fontFamily; font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: {
                                if (!modelData.start) return ""
                                if (modelData.allDay)
                                    return Qt.formatDate(modelData.start, "ddd, MMM d")
                                return Qt.formatDateTime(modelData.start, "ddd, MMM d · h:mm AP")
                            }
                            color: sysState.colMuted
                            font.pixelSize: 10; font.family: sysState.fontFamily
                        }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: calendarEvents.length === 0
                    text: "No upcoming events"
                    color: sysState.colMuted; font.pixelSize: 11; font.family: sysState.fontFamily
                }
            }
        }
    }
}
