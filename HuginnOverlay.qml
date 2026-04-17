import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Window

// Huginn chat overlay. Toggled by /tmp/huginn-visible flag file.
// Communicates with the Python daemon via socat on the Unix socket.
PanelWindow {
    id: root

    required property var targetScreen

    // ── Palette (Midnight Raven) ──────────────────────────────────────────────
    readonly property color colBg:          "#1a1b26"
    readonly property color colSurface:     "#24283b"
    property color colAccent:      "#89ddff"
    property color colGold:        "#f7c95e"
    readonly property color colTextPrimary: "#c0caf5"
    readonly property color colTextMuted:   "#a9b1d6"
    readonly property color colBorder:      "#414868"
    readonly property string fontMono: "JetBrainsMono Nerd Font"
    readonly property string fontSans: "JetBrainsMono Nerd Font"

    // ── Window config ─────────────────────────────────────────────────────────
    screen: targetScreen
    WlrLayershell.namespace: "huginnOverlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.overlayVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Center via anchor+margin — PanelWindow has no x/y
    // Screen attached property reads dimensions from the window itself
    anchors.top:  true
    anchors.left: true
    margins.top:  Math.max(0, Math.floor((Screen.height - implicitHeight) / 2))
    margins.left: Math.max(0, Math.floor((Screen.width  - implicitWidth)  / 2))
    implicitWidth:  680
    implicitHeight: 540
    color: "transparent"

    // ── State ─────────────────────────────────────────────────────────────────
    property bool   overlayVisible:   false
    property bool   isStreaming:      false
    property bool   isConnected:      false
    property bool   isRecording:      false
    property bool   ttsEnabled:       false
    property bool   showThinking:     false
    property bool   showModelPicker:  false
    property string activeModel:      ""
    property string activeProfile:    ""
    property string pendingConfirmId:  ""
    property string pendingImagePath:  ""
    property var    profileList:       []

    visible: overlayVisible

    onOverlayVisibleChanged: {
        if (overlayVisible) {
            inputField.forceActiveFocus()
        }
    }

    // ── Message model ─────────────────────────────────────────────────────────
    ListModel { id: chatModel }

    function appendToken(token) {
        if (chatModel.count > 0 && chatModel.get(chatModel.count - 1).role === "assistant") {
            var prev = chatModel.get(chatModel.count - 1).content
            chatModel.setProperty(chatModel.count - 1, "content", prev + token)
        } else {
            chatModel.append({ role: "assistant", content: token, detail: "", result: "" })
        }
        chatView.positionViewAtEnd()
    }

    readonly property string sendScript: "/home/nate/dotfiles/huginn/backend/huginn_send.py"

    function sendMessage() {
        var text = inputField.text.trim()
        if (!text || root.isStreaming) return

        chatModel.append({ role: "user", content: text, detail: "", result: "" })
        inputField.text = ""
        root.isStreaming = true
        chatView.positionViewAtEnd()

        huginnProc.command = ["python3", root.sendScript, "chat", root.ttsEnabled ? "true" : "false", text]
        huginnProc.running = true
    }

    function clearChat() {
        huginnProc.command = ["python3", root.sendScript, "clear"]
        huginnProc.running = true
    }

    function handleIpcLine(line) {
        if (!line.trim()) return
        try {
            var msg = JSON.parse(line)
            if (msg.type === "token") {
                root.appendToken(msg.content)
            } else if (msg.type === "transcript") {
                chatModel.append({ role: "user", content: msg.content, detail: "", result: "" })
                chatView.positionViewAtEnd()
            } else if (msg.type === "done") {
                root.isStreaming = false
            } else if (msg.type === "model_switched") {
                root.activeModel = msg.label || msg.profile
            } else if (msg.type === "confirm_required") {
                root.pendingConfirmId = msg.id || ""
                var argsStr = JSON.stringify(msg.args || {})
                chatModel.append({ role: "confirm", content: msg.tool, detail: argsStr, result: msg.id || "" })
                chatView.positionViewAtEnd()
            } else if (msg.type === "thinking") {
                chatModel.append({ role: "thinking", content: msg.content, detail: "", result: "" })
                chatView.positionViewAtEnd()
            } else if (msg.type === "cleared") {
                chatModel.clear()
            } else if (msg.type === "tool_call") {
                var argsStr = JSON.stringify(msg.args || {})
                chatModel.append({ role: "tool_call", content: msg.tool, detail: argsStr, result: "" })
                chatView.positionViewAtEnd()
            } else if (msg.type === "tool_result") {
                for (var i = chatModel.count - 1; i >= 0; i--) {
                    if (chatModel.get(i).role === "tool_call" && chatModel.get(i).content === msg.tool) {
                        chatModel.setProperty(i, "result", msg.output)
                        break
                    }
                }
            } else if (msg.type === "error") {
                root.appendToken(msg.message)
                root.isStreaming = false
                root.isConnected = false
            }
        } catch(e) {
            console.error("Huginn parse error:", e, line)
        }
    }

    // ── IPC: one-shot process per message ────────────────────────────────────
    Process {
        id: huginnProc
        stdout: SplitParser { onRead: function(line) { root.handleIpcLine(line) } }
        onExited: function(code) { root.isStreaming = false }
    }

    // ── Voice: record + send ──────────────────────────────────────────────────
    Process {
        id: recordProc
        command: ["arecord", "-f", "S16_LE", "-r", "16000", "-c", "1", "-q", "/tmp/huginn-voice.wav"]
        onExited: function(code) {
            if (root.isRecording) {
                root.isRecording = false
                if (!root.isStreaming) {
                    root.isStreaming = true
                    voiceProc.command = [
                        "python3", root.sendScript, "voice_file",
                        "/tmp/huginn-voice.wav",
                        root.ttsEnabled ? "true" : "false"
                    ]
                    voiceProc.running = true
                }
            }
        }
    }

    Process {
        id: voiceProc
        stdout: SplitParser { onRead: function(line) { root.handleIpcLine(line) } }
        onExited: function(code) { root.isStreaming = false }
    }

    Process { id: confirmProc }

    // Grabs image/png from clipboard → /tmp/huginn-img-TIMESTAMP.png, echoes path or "none"
    Process {
        id: clipImageProc
        stdout: SplitParser {
            onRead: function(line) {
                var p = line.trim()
                if (p && p !== "none") root.attachImage(p)
            }
        }
    }

    Process { id: imageProc
        stdout: SplitParser { onRead: function(line) { root.handleIpcLine(line) } }
        onExited: function(code) { root.isStreaming = false }
    }

    Process {
        id: switchModelProc
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var msg = JSON.parse(line)
                    if (msg.type === "model_switched") {
                        root.activeModel   = msg.label || msg.profile
                        root.activeProfile = msg.profile
                        root.showModelPicker = false
                    }
                } catch(e) {}
            }
        }
    }

    function switchModel(profile) {
        switchModelProc.command = ["python3", root.sendScript, "switch_model", profile]
        switchModelProc.running = true
    }

    function sendConfirm(confirmId, approved) {
        for (var i = chatModel.count - 1; i >= 0; i--) {
            if (chatModel.get(i).role === "confirm" && chatModel.get(i).result === confirmId) {
                chatModel.setProperty(i, "role", approved ? "confirm_allowed" : "confirm_denied")
                break
            }
        }
        root.isStreaming = true
        confirmProc.command = ["python3", root.sendScript, "confirm", confirmId, approved ? "true" : "false"]
        confirmProc.running = true
        root.pendingConfirmId = ""
    }

    function attachImage(path) {
        root.pendingImagePath = path
        // Show preview in input area — caption is whatever's in inputField
        chatView.positionViewAtEnd()
    }

    function sendImage() {
        var path = root.pendingImagePath
        if (!path || root.isStreaming) return
        var caption = inputField.text.trim()
        chatModel.append({ role: "image_sent", content: caption || "Image", detail: path, result: "" })
        inputField.text = ""
        root.pendingImagePath = ""
        root.isStreaming = true
        chatView.positionViewAtEnd()
        imageProc.command = ["python3", root.sendScript, "image_file", path, caption, root.ttsEnabled ? "true" : "false"]
        imageProc.running = true
    }

    function grabClipboardImage() {
        var ts = Date.now()
        var dest = "/tmp/huginn-img-" + ts + ".png"
        clipImageProc.command = [
            "sh", "-c",
            "wl-paste --list-types 2>/dev/null | grep -qi 'image/' " +
            "&& wl-paste --type image/png > " + dest + " 2>/dev/null " +
            "&& echo " + dest + " || echo none"
        ]
        clipImageProc.running = true
    }

    // ── Ping to track connection status ───────────────────────────────────────
    Process {
        id: pingProc
        command: ["python3", root.sendScript, "ping"]

        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var msg = JSON.parse(line)
                    if (msg.type === "pong") {
                        root.isConnected = true
                        if (msg.label)    root.activeModel  = msg.label
                        if (msg.profile)  root.activeProfile = msg.profile
                        if (msg.profiles) root.profileList  = msg.profiles
                    }
                } catch(e) {}
            }
        }

        onExited: function(code) {
            if (code !== 0) root.isConnected = false
        }
    }

    Timer {
        interval: 3000; running: true; repeat: true
        onTriggered: pingProc.running = true
    }

    Process {
        id: escapeClose
        command: ["sh", "-c", "rm -f /tmp/huginn-visible"]
    }

    // ── Theme: poll active theme ──────────────────────────────────────────────
    Process {
        id: themeReader
        command: ["cat", "/home/nate/.config/huginn/current-theme.json"]
        stdout: SplitParser {
            onRead: function(line) {
                if (!line.trim()) return
                try {
                    var t = JSON.parse(line)
                    if (t.accent) root.colAccent = t.accent
                    if (t.gold)   root.colGold   = t.gold
                } catch(e) {}
            }
        }
    }
    Timer {
        interval: 500; running: true; repeat: true
        onTriggered: themeReader.running = true
    }

    // ── Visibility: flag-file toggle ──────────────────────────────────────────
    Process {
        id: visibilityChecker
        command: ["sh", "-c", "[ -f /tmp/huginn-visible ] && echo 'true' || echo 'false'"]
        stdout: SplitParser {
            onRead: function(data) { root.overlayVisible = (data.trim() === "true") }
        }
    }

    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: visibilityChecker.running = true
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: function(drop) {
            var urls = drop.urls
            for (var i = 0; i < urls.length; i++) {
                var path = urls[i].toString().replace("file://", "")
                if (/\.(png|jpg|jpeg|webp|gif|bmp)$/i.test(path)) {
                    root.attachImage(path)
                    break
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.rgba(0.102, 0.106, 0.149, 0.94)
        border.color: root.isConnected ? root.colAccent : root.colBorder
        border.width: 1

        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 0
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                height: 42
                color: Qt.rgba(0.141, 0.157, 0.220, 0.95)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    // Rune + name
                    RowLayout {
                        spacing: 8

                        Text {
                            text: "ᚱ"
                            color: root.colGold
                            font.pixelSize: 18
                            font.family: root.fontMono
                            style: Text.Normal
                        }

                        Text {
                            text: "HUGINN"
                            color: root.colTextPrimary
                            font.pixelSize: 13
                            font.family: root.fontMono
                            font.bold: true
                            font.letterSpacing: 2
                        }

                        Rectangle {
                            visible: root.activeModel !== ""
                            implicitWidth: modelPickerLabel.implicitWidth + 12
                            implicitHeight: 18
                            radius: 4
                            color: root.showModelPicker
                                ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.12)
                                : modelPickerBtn.containsMouse ? Qt.rgba(1,1,1,0.05) : "transparent"
                            border.color: root.showModelPicker ? root.colAccent : "transparent"
                            border.width: 1
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                id: modelPickerLabel
                                anchors.centerIn: parent
                                text: root.activeModel + "  ▾"
                                color: root.showModelPicker ? root.colAccent : root.colTextMuted
                                font.pixelSize: 10
                                font.family: root.fontMono
                            }
                            MouseArea {
                                id: modelPickerBtn
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showModelPicker = !root.showModelPicker
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Status dot
                    Row {
                        spacing: 6

                        Rectangle {
                            width: 7; height: 7
                            radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.isStreaming  ? root.colGold
                                 : root.isConnected  ? root.colAccent
                                 : "#f7768e"

                            SequentialAnimation on opacity {
                                running: root.isStreaming
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.3; duration: 600; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                            }
                        }

                        Text {
                            text: root.isStreaming  ? "thinking..."
                                : root.isConnected  ? "ready"
                                : "offline"
                            color: root.colTextMuted
                            font.pixelSize: 11
                            font.family: root.fontMono
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Clear button
                    MouseArea {
                        implicitWidth:  clearLabel.implicitWidth + 16
                        implicitHeight: 22
                        Layout.leftMargin: 8
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered:  clearLabel.color = root.colAccent
                        onExited:   clearLabel.color = root.colTextMuted
                        onClicked: root.clearChat()

                        Text {
                            id: clearLabel
                            anchors.centerIn: parent
                            text: "clear"
                            color: root.colTextMuted
                            font.pixelSize: 11
                            font.family: root.fontMono

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: root.colBorder
            }

            // Model picker panel
            Rectangle {
                Layout.fillWidth: true
                visible: root.showModelPicker
                implicitHeight: pickerFlow.implicitHeight + 16
                color: Qt.rgba(0.10, 0.11, 0.15, 0.97)
                border.color: root.colBorder
                border.width: 0

                Flow {
                    id: pickerFlow
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    spacing: 6

                    Repeater {
                        model: root.profileList
                        delegate: Rectangle {
                            required property var modelData
                            property bool isCurrent: modelData.id === root.activeProfile
                            property bool unavailable: !modelData.available

                            implicitWidth: pLabel.implicitWidth + 18
                            implicitHeight: 24
                            radius: 5
                            color: isCurrent
                                ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.15)
                                : unavailable ? Qt.rgba(1,1,1,0.02)
                                : pArea.containsMouse ? Qt.rgba(1,1,1,0.07) : Qt.rgba(1,1,1,0.04)
                            border.color: isCurrent ? root.colAccent
                                        : unavailable ? Qt.rgba(root.colBorder.r, root.colBorder.g, root.colBorder.b, 0.4)
                                        : root.colBorder
                            border.width: 1

                            Text {
                                id: pLabel
                                anchors.centerIn: parent
                                text: modelData.label + (unavailable ? " ✕" : "")
                                color: isCurrent   ? root.colAccent
                                     : unavailable ? Qt.rgba(root.colTextMuted.r, root.colTextMuted.g, root.colTextMuted.b, 0.35)
                                     : root.colTextMuted
                                font.pixelSize: 10
                                font.family: root.fontMono
                                font.bold: isCurrent
                            }

                            MouseArea {
                                id: pArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: unavailable ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                                enabled: !unavailable && !isCurrent
                                onClicked: root.switchModel(modelData.id)
                            }
                        }
                    }
                }

                // Bottom divider
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width; height: 1
                    color: root.colBorder
                }
            }

            // Chat log
            ListView {
                id: chatView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: chatModel
                spacing: 4
                topMargin: 12
                bottomMargin: 12
                leftMargin: 0
                rightMargin: 0

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 3
                        radius: 2
                        color: root.colBorder
                    }
                }

                delegate: Item {
                    required property string role
                    required property string content
                    required property string detail
                    required property string result
                    required property int    index

                    width: chatView.width
                    visible: role === "thinking" ? root.showThinking : true
                    height: role === "tool_call"                                                            ? toolPill.implicitHeight + 6
                          : (role === "confirm" || role === "confirm_allowed" || role === "confirm_denied") ? confirmBubble.height + 8
                          : role === "image_sent"                                                          ? imageBubble.height + 8
                          : role === "thinking"                                                             ? thinkingPill.implicitHeight + 6
                          : bubble.height + 8

                    // ── Tool call pill ────────────────────────────────────────
                    Rectangle {
                        id: toolPill
                        visible: role === "tool_call"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: toolCol.implicitHeight + 10
                        radius: 6
                        color: Qt.rgba(root.colGold.r, root.colGold.g, root.colGold.b, 0.07)
                        border.color: Qt.rgba(root.colGold.r, root.colGold.g, root.colGold.b, 0.3)
                        border.width: 1

                        Column {
                            id: toolCol
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            anchors.margins: 10
                            spacing: 4

                            // Tool name + args header
                            Row {
                                spacing: 6
                                width: parent.width
                                Text {
                                    text: "⚙"
                                    color: root.colGold
                                    font.pixelSize: 10
                                    font.family: root.fontMono
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: content
                                    color: root.colGold
                                    font.pixelSize: 11
                                    font.family: root.fontMono
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: detail
                                    color: root.colTextMuted
                                    font.pixelSize: 10
                                    font.family: root.fontMono
                                    anchors.verticalCenter: parent.verticalCenter
                                    elide: Text.ElideRight
                                    width: Math.min(implicitWidth, toolPill.width - 120)
                                }
                            }

                            // Output block
                            Rectangle {
                                visible: result.length > 0
                                width: parent.width
                                height: Math.min(outputText.implicitHeight + 12, 200)
                                radius: 4
                                color: Qt.rgba(0, 0, 0, 0.25)
                                border.color: Qt.rgba(root.colGold.r, root.colGold.g, root.colGold.b, 0.15)
                                border.width: 1
                                clip: true

                                Flickable {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    contentHeight: outputText.implicitHeight
                                    clip: true
                                    ScrollBar.vertical: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                        contentItem: Rectangle { implicitWidth: 2; radius: 1; color: root.colBorder }
                                    }

                                    Text {
                                        id: outputText
                                        width: parent.width
                                        text: result
                                        color: "#a9b1d6"
                                        font.pixelSize: 11
                                        font.family: root.fontMono
                                        wrapMode: Text.Wrap
                                        lineHeight: 1.3
                                    }
                                }
                            }
                        }
                    }

                    // ── Thinking block ────────────────────────────────────────
                    Rectangle {
                        id: thinkingPill
                        visible: role === "thinking"
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: chatView.width - 40
                        implicitHeight: thinkingText.implicitHeight + 16
                        radius: 6
                        color: Qt.rgba(root.colTextMuted.r, root.colTextMuted.g, root.colTextMuted.b, 0.04)
                        border.color: Qt.rgba(root.colBorder.r, root.colBorder.g, root.colBorder.b, 0.5)
                        border.width: 1

                        Row {
                            anchors { left: parent.left; top: parent.top; margins: 10 }
                            spacing: 6
                            Text {
                                text: "\uf0eb"
                                color: root.colTextMuted
                                font.pixelSize: 9; font.family: root.fontMono
                                opacity: 0.6
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "thinking"
                                color: root.colTextMuted
                                font.pixelSize: 9; font.family: root.fontMono
                                font.italic: true; font.bold: true
                                opacity: 0.6
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Text {
                            id: thinkingText
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10; topMargin: 28 }
                            text: content
                            color: root.colTextMuted
                            font.pixelSize: 11
                            font.family: root.fontSans
                            font.italic: true
                            opacity: 0.65
                            wrapMode: Text.Wrap
                            lineHeight: 1.35
                        }
                    }

                    // ── Confirm prompt ────────────────────────────────────────
                    Rectangle {
                        id: confirmBubble
                        visible: role === "confirm" || role === "confirm_allowed" || role === "confirm_denied"
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(confirmRow.implicitWidth + 24, chatView.width - 40)
                        height: confirmCol.implicitHeight + 14
                        radius: 8
                        color: Qt.rgba(0.969, 0.467, 0.557, 0.07)
                        border.color: "#f7768e"
                        border.width: 1

                        Column {
                            id: confirmCol
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                            spacing: 8

                            Row {
                                id: confirmRow
                                spacing: 6
                                Text {
                                    text: "\uf071"
                                    color: "#f7768e"
                                    font.pixelSize: 11; font.family: root.fontMono
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: "Allow Huginn to run  " + content + " ?"
                                    color: "#f7768e"
                                    font.pixelSize: 11; font.family: root.fontMono; font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                visible: detail !== ""
                                text: detail
                                color: root.colTextMuted
                                font.pixelSize: 10; font.family: root.fontMono
                                width: parent.width
                                elide: Text.ElideRight
                            }

                            Row {
                                spacing: 8
                                visible: role === "confirm"
                                Rectangle {
                                    width: allowLabel.implicitWidth + 16; height: 22; radius: 5
                                    color: allowArea.containsMouse ? Qt.rgba(0.388, 0.525, 0.286, 0.3) : Qt.rgba(0.388, 0.525, 0.286, 0.15)
                                    border.color: "#9ece6a"; border.width: 1
                                    Text { id: allowLabel; anchors.centerIn: parent; text: "Allow"; color: "#9ece6a"; font.pixelSize: 11; font.family: root.fontMono; font.bold: true }
                                    MouseArea { id: allowArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.sendConfirm(result, true) }
                                }
                                Rectangle {
                                    width: denyLabel.implicitWidth + 16; height: 22; radius: 5
                                    color: denyArea.containsMouse ? Qt.rgba(0.969, 0.467, 0.557, 0.3) : Qt.rgba(0.969, 0.467, 0.557, 0.15)
                                    border.color: "#f7768e"; border.width: 1
                                    Text { id: denyLabel; anchors.centerIn: parent; text: "Deny"; color: "#f7768e"; font.pixelSize: 11; font.family: root.fontMono; font.bold: true }
                                    MouseArea { id: denyArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.sendConfirm(result, false) }
                                }
                            }

                            Row {
                                spacing: 6
                                visible: role === "confirm_allowed" || role === "confirm_denied"
                                Text {
                                    text: role === "confirm_allowed" ? "✓ allowed — running..." : "✗ denied"
                                    color: role === "confirm_allowed" ? "#9ece6a" : "#f7768e"
                                    font.pixelSize: 11; font.family: root.fontMono; font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }

                    // ── Image sent bubble ─────────────────────────────────────
                    Rectangle {
                        id: imageBubble
                        visible: role === "image_sent"
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(imgBubbleRow.implicitWidth + 24, chatView.width - 80)
                        height: imgBubbleRow.implicitHeight + 16
                        radius: 8
                        color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.10)
                        border.color: root.colAccent
                        border.width: 1

                        Row {
                            id: imgBubbleRow
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                            spacing: 6
                            Text {
                                text: "\uf03e"
                                color: root.colAccent
                                font.pixelSize: 13; font.family: root.fontMono
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: content || "image"
                                color: root.colTextPrimary
                                font.pixelSize: 13; font.family: root.fontSans
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, imageBubble.width - 60)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // User messages: right-aligned
                    // Huginn messages: left-aligned with rune prefix
                    Rectangle {
                        id: bubble
                        visible: role !== "tool_call" && role !== "thinking"
                              && role !== "confirm" && role !== "confirm_allowed" && role !== "confirm_denied"
                              && role !== "image_sent"
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right:      role === "user"      ? parent.right : undefined
                        anchors.left:       role === "assistant" ? parent.left  : undefined
                        anchors.rightMargin: role === "user"      ? 16 : 0
                        anchors.leftMargin:  role === "assistant" ? 16 : 0

                        width:  role === "user"
                                    ? Math.min(userText.implicitWidth + 24, chatView.width - 80)
                                    : chatView.width - 32
                        height: role === "user"
                                    ? userText.implicitHeight + 16
                                    : assistantEdit.contentHeight + 16
                        radius: 8

                        color: role === "user"
                            ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.10)
                            : "transparent"
                        border.color: role === "user" ? root.colAccent : "transparent"
                        border.width: role === "user" ? 1 : 0

                        // Huginn rune prefix
                        Text {
                            visible: role === "assistant"
                            anchors.left: parent.left
                            anchors.top:  parent.top
                            anchors.topMargin: 10
                            text: "ᚱ "
                            color: root.colGold
                            font.pixelSize: 13
                            font.family: root.fontMono
                        }

                        // User messages: plain Text
                        Text {
                            id: userText
                            visible: role === "user"
                            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12; topMargin: 8 }
                            text: role === "user" ? content : ""
                            color: root.colTextPrimary
                            font.pixelSize: 13
                            font.family: root.fontSans
                            wrapMode: Text.Wrap
                            lineHeight: 1.4
                        }

                        // Assistant messages: markdown via TextEdit
                        TextEdit {
                            id: assistantEdit
                            visible: role === "assistant"
                            x: 26; y: 8
                            width: parent.width - 38
                            text: role === "assistant" ? content : ""
                            textFormat: TextEdit.MarkdownText
                            readOnly: true
                            color: root.colTextMuted
                            selectionColor: Qt.rgba(0.537, 0.863, 1.0, 0.3)
                            font.pixelSize: 13
                            font.family: root.fontSans
                            wrapMode: TextEdit.Wrap
                        }
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: chatModel.count === 0
                    text: "Thought takes flight.\nAsk me anything."
                    color: root.colBorder
                    font.pixelSize: 13
                    font.family: root.fontMono
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 1.6
                }
            }

            // Divider
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: root.colBorder
            }

            // Input row
            Rectangle {
                Layout.fillWidth: true
                height: 52
                color: Qt.rgba(0.141, 0.157, 0.220, 0.95)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.topMargin: 4
                    spacing: 6

                    // Paperclip: attach image from clipboard or send pending image
                    Rectangle {
                        implicitWidth:  32
                        implicitHeight: 32
                        radius: 8
                        color: root.pendingImagePath !== ""
                            ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.18)
                            : clipArea.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent"
                        border.color: root.pendingImagePath !== "" ? root.colAccent : root.colBorder
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf0c1"
                            color: root.pendingImagePath !== "" ? root.colAccent : root.colTextMuted
                            font.pixelSize: 13; font.family: root.fontMono
                        }

                        MouseArea {
                            id: clipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.pendingImagePath !== "") {
                                    root.sendImage()
                                } else {
                                    root.grabClipboardImage()
                                }
                            }
                        }
                    }

                    // Push-to-talk mic button
                    Rectangle {
                        implicitWidth:  32
                        implicitHeight: 32
                        radius: 8
                        color: root.isRecording
                            ? Qt.rgba(0.969, 0.467, 0.557, 0.20)
                            : micArea.containsMouse
                                ? Qt.rgba(1, 1, 1, 0.06)
                                : "transparent"
                        border.color: root.isRecording ? "#f7768e" : root.colBorder
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf130"
                            color: root.isRecording ? "#f7768e" : root.colTextMuted
                            font.pixelSize: 14
                            font.family: root.fontMono

                            SequentialAnimation on opacity {
                                running: root.isRecording
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: 500; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutSine }
                            }
                        }

                        MouseArea {
                            id: micArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: {
                                if (!root.isStreaming && !root.isRecording) {
                                    root.isRecording = true
                                    recordProc.running = true
                                }
                            }
                            onReleased: {
                                if (root.isRecording) {
                                    recordProc.running = false
                                }
                            }
                        }
                    }

                    TextInput {
                        id: inputField
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        color: root.colTextPrimary
                        font.pixelSize: 13
                        font.family: root.fontSans
                        selectionColor: Qt.rgba(0.537, 0.863, 1.0, 0.3)
                        clip: true

                        // Placeholder
                        Text {
                            anchors.fill: parent
                            anchors.verticalCenter: parent.verticalCenter
                            visible: inputField.text.length === 0
                            text: root.isConnected ? "speak..." : "daemon offline"
                            color: root.colBorder
                            font: inputField.font
                        }

                        Keys.onReturnPressed: root.pendingImagePath !== "" ? root.sendImage() : root.sendMessage()
                        Keys.onEscapePressed: escapeClose.running = true
                    }

                    // TTS toggle
                    Rectangle {
                        implicitWidth:  32
                        implicitHeight: 32
                        radius: 8
                        color: root.ttsEnabled
                            ? Qt.rgba(root.colGold.r, root.colGold.g, root.colGold.b, 0.12)
                            : ttsArea.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        border.color: root.ttsEnabled ? root.colGold : root.colBorder
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: root.ttsEnabled ? "\uf028" : "\uf026"
                            color: root.ttsEnabled ? root.colGold : root.colTextMuted
                            font.pixelSize: 13
                            font.family: root.fontMono
                        }

                        MouseArea {
                            id: ttsArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.ttsEnabled = !root.ttsEnabled
                        }
                    }

                    // Show-thinking toggle
                    Rectangle {
                        implicitWidth:  32
                        implicitHeight: 32
                        radius: 8
                        color: root.showThinking
                            ? Qt.rgba(root.colTextMuted.r, root.colTextMuted.g, root.colTextMuted.b, 0.10)
                            : thinkToggleArea.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        border.color: root.showThinking ? root.colTextMuted : root.colBorder
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf0eb"
                            color: root.showThinking ? root.colTextPrimary : root.colTextMuted
                            font.pixelSize: 13
                            font.family: root.fontMono
                            opacity: root.showThinking ? 1.0 : 0.5
                        }

                        MouseArea {
                            id: thinkToggleArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showThinking = !root.showThinking
                        }
                    }

                    // Send button
                    Rectangle {
                        implicitWidth:  32
                        implicitHeight: 32
                        radius: 8
                        color: sendArea.containsMouse && !root.isStreaming
                            ? Qt.rgba(0.537, 0.863, 1.0, 0.15)
                            : "transparent"
                        border.color: root.isStreaming ? root.colBorder : root.colAccent
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: root.isStreaming ? "…" : "↵"
                            color: root.isStreaming ? root.colBorder : root.colAccent
                            font.pixelSize: 14
                            font.family: root.fontMono
                        }

                        MouseArea {
                            id: sendArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.sendMessage()
                        }
                    }
                }
            }
        }
    }
}
