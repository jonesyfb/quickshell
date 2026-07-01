import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

PanelWindow {
    id: root

    required property var targetScreen

    screen: targetScreen
    WlrLayershell.layer:     WlrLayer.Overlay
    WlrLayershell.namespace: "huginnNotification"
    exclusionMode:           ExclusionMode.Ignore

    anchors.bottom: true
    anchors.right:  true

    implicitWidth:  root.notifVisible ? 450 : 0
    implicitHeight: root.notifVisible ? 250 : 0
    color:          "transparent"

    // ── State ─────────────────────────────────────────────────────────────────
    property bool   notifVisible: false
    property bool   notifIdle:    false
    property string notifType:    "info"
    property string notifTitle:   "huginn"
    property string notifBody:    ""
    property string bodyDisplay:  ""
    property string notifTime:    ""

    // ── IPC polling ───────────────────────────────────────────────────────────
    Process {
        id: notifyCheck
        command: ["sh", "-c",
            "[ -f /tmp/huginn-notify.json ] && cat /tmp/huginn-notify.json && rm -f /tmp/huginn-notify.json"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                var t = line.trim()
                if (!t) return
                try {
                    var d = JSON.parse(t)
                    root.notifType  = d.type  || "info"
                    root.notifTitle = d.title || "huginn"
                    root.notifBody  = (d.body  || "").replace(/\\n/g, "\n")
                    root.fireNotif()
                } catch(e) {}
            }
        }
    }

    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: { if (!root.notifVisible) notifyCheck.running = true }
    }

    // ── Typewriter ────────────────────────────────────────────────────────────
    Timer {
        id: twTimer
        interval: 20; repeat: true
        property int twIdx: 0
        onTriggered: {
            if (twIdx < root.notifBody.length) {
                root.bodyDisplay += root.notifBody[twIdx]
                twIdx++
            } else {
                stop()
                idleDelay.start()
            }
        }
    }

    Timer {
        id: idleDelay; interval: 300
        onTriggered: { root.notifIdle = true; autoTimer.start() }
    }

    Timer {
        id: autoTimer; interval: 5000
        onTriggered: root.dismissNotif()
    }

    // Hard kill if exitAnim.onFinished never fires
    Timer {
        id: hardKill; interval: 30000
        onTriggered: {
            root.notifVisible = false
            root.notifIdle    = false
            slideOffset.x = 0
            slideOffset.y = 0
            notifBox.opacity = 0
        }
    }

    // ── Crow caw ──────────────────────────────────────────────────────────────
    Process {
        id: crowPlay
        command: ["sh", "-c", "huginn-crow &"]
    }

    // ── API ───────────────────────────────────────────────────────────────────
    function fireNotif() {
        bodyDisplay  = ""
        notifIdle    = false
        notifVisible = false   // reset so animations re-trigger
        autoTimer.stop()
        hardKill.stop()
        twTimer.stop()
        idleDelay.stop()
        twTimer.twIdx = 0

        // next frame: show + animate
        notifTime = Qt.formatTime(new Date(), "HH:mm")
        Qt.callLater(function() {
            notifVisible = true
            crowPlay.running = true
            enterAnim.start()
            landAnim.start()
            twTimer.start()
            hardKill.start()
        })
    }

    function dismissNotif() {
        autoTimer.stop()
        hardKill.stop()
        twTimer.stop()
        idleDelay.stop()
        bobAnim.stop()
        exitAnim.start()
    }

    // ── Animations ────────────────────────────────────────────────────────────
    ParallelAnimation {
        id: enterAnim
        NumberAnimation {
            target: notifBox; property: "opacity"
            from: 0; to: 1; duration: 400
            easing.type: Easing.OutQuart
        }
        NumberAnimation {
            target: slideOffset; property: "y"
            from: 50; to: 0; duration: 450
            easing.type: Easing.OutQuart
        }
    }

    ParallelAnimation {
        id: exitAnim
        NumberAnimation {
            target: notifBox; property: "opacity"
            to: 0; duration: 220
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: slideOffset; property: "x"
            to: 100; duration: 220
            easing.type: Easing.InQuad
        }
        onFinished: {
            root.notifVisible = false
            root.notifIdle    = false
            slideOffset.x = 0
            slideOffset.y = 0
        }
    }

    // Raven land bounce
    SequentialAnimation {
        id: landAnim
        NumberAnimation {
            target: ravenImg; property: "yOffset"
            from: -12; to: 4; duration: 275
            easing.type: Easing.OutQuart
        }
        NumberAnimation {
            target: ravenImg; property: "yOffset"
            to: 0; duration: 225
            easing.type: Easing.InOutQuad
        }
    }

    // Raven idle bob
    SequentialAnimation {
        id: bobAnim
        loops: Animation.Infinite
        running: root.notifIdle
        NumberAnimation {
            target: ravenImg; property: "yOffset"
            to: -4; duration: 1750
            easing.type: Easing.InOutSine
        }
        NumberAnimation {
            target: ravenImg; property: "yOffset"
            to: 0; duration: 1750
            easing.type: Easing.InOutSine
        }
    }

    // ── Visual ────────────────────────────────────────────────────────────────
    Item {
        id: notifBox
        anchors.bottom: parent.bottom
        anchors.right:  parent.right
        anchors.bottomMargin: 16
        anchors.rightMargin:  16

        width:   bubbleCol.width + ravenImg.width - 6
        height:  Math.max(bubbleCol.height + 18, ravenImg.height)
        opacity: 0
        visible: root.notifVisible

        transform: Translate { id: slideOffset; x: 0; y: 0 }

        // Bubble column
        Item {
            id: bubbleCol
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            anchors.right: ravenImg.left
            anchors.rightMargin: 6

            width:  bubble.width
            height: bubble.height

            Rectangle {
                id: bubble
                width:  220
                height: bubbleContent.implicitHeight + 18
                radius: 12
                color:  "#12121c"
                border.width: 1
                border.color: "#2e2e50"

                // Flatten bottom-right corner
                layer.enabled: true

                Column {
                    id: bubbleContent
                    anchors.left:    parent.left
                    anchors.right:   parent.right
                    anchors.top:     parent.top
                    anchors.margins: 13
                    anchors.topMargin: 10
                    spacing: 6

                    // Header row
                    Item {
                        width: parent.width
                        height: Math.max(badge.height, titleText.implicitHeight, closeBtn.implicitHeight)

                        Rectangle {
                            id: badge
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width:  badgeText.implicitWidth + 10
                            height: 16
                            radius: 3
                            color: root.notifType === "warn" ? "#2e1e00"
                                 : root.notifType === "ok"   ? "#0a2018"
                                 :                             "#1c1c42"

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: root.notifType === "warn" ? "WARN"
                                    : root.notifType === "ok"   ? "OK"
                                    :                             "INFO"
                                font.family: "JetBrains Nerd Mono"
                                font.pixelSize: 9
                                font.weight: Font.Medium
                                font.letterSpacing: 0.6
                                color: root.notifType === "warn" ? "#e8b040"
                                     : root.notifType === "ok"   ? "#40d880"
                                     :                             "#9090e8"
                            }
                        }

                        Text {
                            id: titleText
                            anchors.left: badge.right
                            anchors.leftMargin: 5
                            anchors.right: closeBtn.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.notifTitle
                            font.family: "JetBrains Nerd Mono"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            color: "#a0a0d8"
                            elide: Text.ElideRight
                        }

                        Text {
                            id: closeBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "×"
                            font.pixelSize: 15
                            color: "#4a4870"
                            leftPadding: 8

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -4
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.dismissNotif()
                            }

                            HoverHandler {
                                onHoveredChanged: parent.color = hovered ? "#a0a0d8" : "#4a4870"
                            }
                        }
                    }

                    // Body
                    Text {
                        id: bodyText
                        width: parent.width
                        text: root.bodyDisplay
                        font.family: "JetBrains Nerd Mono"
                        font.pixelSize: 12
                        lineHeight: 1.55
                        lineHeightMode: Text.ProportionalHeight
                        color: "#c0bed8"
                        wrapMode: Text.Wrap
                    }

                    // Timestamp
                    Text {
                        id: timeText
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: root.notifTime
                        font.family: "JetBrains Nerd Mono"
                        font.pixelSize: 10
                        color: "#4a4870"
                    }
                }
            }
        }

        // Raven image
        Image {
            id: ravenImg
            anchors.right:  parent.right
            anchors.bottom: parent.bottom

            width:            140
            height:           140
            fillMode:         Image.PreserveAspectFit
            source:           Qt.resolvedUrl("assets/Huginn_v1.png")
            smooth:           false
            antialiasing:     false

            property real yOffset: 0
            transform: Translate { y: ravenImg.yOffset }
        }
    }
}
