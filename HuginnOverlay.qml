import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// Huginn v2 chat overlay — right-anchored panel, mint green accent.
// Toggled by /tmp/huginn-visible flag file (same as v1).
// IPC via huginn_send.py → Unix socket.
PanelWindow {
    id: root

    required property var targetScreen

    // ── Palette ───────────────────────────────────────────────────────────────
    readonly property color colBg:      "#1a1b26"
    readonly property color colSurface: "#24283b"
    readonly property color colBorder:  "#3b4261"
    readonly property color colText:    "#c0caf5"
    readonly property color colMuted:   "#a9b1d6"
    readonly property color colDim:     "#565f89"
    readonly property color colMint:    "#7ed9a3"
    readonly property color colOrange:  "#ff9e64"
    readonly property color colRed:     "#f7768e"
    readonly property string font:      "JetBrainsMono Nerd Font"

    // ── Window ────────────────────────────────────────────────────────────────
    screen: targetScreen
    WlrLayershell.namespace:   "huginnOverlay"
    WlrLayershell.layer:       WlrLayer.Overlay
    WlrLayershell.keyboardFocus: overlayVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.right:  true
    anchors.top:    true
    anchors.bottom: true
    margins.top:    32
    implicitWidth:  overlayVisible ? 380 : 0
    color: "transparent"

    // ── State ─────────────────────────────────────────────────────────────────
    property bool   overlayVisible:  false
    property bool   isStreaming:     false
    property bool   isConnected:     false
    property string pendingConfirmId: ""

    visible: overlayVisible

    onOverlayVisibleChanged: {
        if (overlayVisible) inputField.forceActiveFocus()
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
        Qt.callLater(function() { chatView.positionViewAtEnd() })
    }

    // ── IPC ───────────────────────────────────────────────────────────────────
    readonly property string sendScript: "/home/nate/dotfiles/huginn/backend/huginn_send.py"

    function sendMessage() {
        var text = inputField.text.trim()
        if (!text || root.isStreaming) return
        chatModel.append({ role: "user", content: text, detail: "", result: "" })
        inputField.text = ""
        root.isStreaming = true
        chatView.positionViewAtEnd()
        huginnProc.command = ["python3", root.sendScript, "chat", "false", text]
        huginnProc.running = true
    }

    function clearChat() {
        huginnProc.command = ["python3", root.sendScript, "clear"]
        huginnProc.running = true
    }

    function recoverChat() {
        huginnProc.command = ["python3", root.sendScript, "recover"]
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
                Qt.callLater(function() { chatView.positionViewAtEnd() })
            } else if (msg.type === "confirm_required") {
                root.pendingConfirmId = msg.id || ""
                chatModel.append({ role: "confirm", content: msg.tool, detail: JSON.stringify(msg.args || {}), result: msg.id || "" })
                chatView.positionViewAtEnd()
            } else if (msg.type === "cleared") {
                chatModel.clear()
            } else if (msg.type === "recovered") {
                root.isStreaming = false
            } else if (msg.type === "tool_call") {
                chatModel.append({ role: "tool_call", content: msg.tool, detail: JSON.stringify(msg.args || {}), result: "" })
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
        } catch(e) {}
    }

    function sendConfirm(confirmId, approved) {
        for (var i = chatModel.count - 1; i >= 0; i--) {
            if (chatModel.get(i).role === "confirm" && chatModel.get(i).result === confirmId) {
                chatModel.setProperty(i, "role", approved ? "confirm_allowed" : "confirm_denied")
                break
            }
        }
        root.isStreaming = approved
        confirmProc.command = ["python3", root.sendScript, "confirm", confirmId, approved ? "true" : "false"]
        confirmProc.running = true
        root.pendingConfirmId = ""
    }

    Process {
        id: huginnProc
        stdout: SplitParser { onRead: function(line) { root.handleIpcLine(line) } }
        onExited: function(code) { root.isStreaming = false }
    }

    Process { id: confirmProc
        stdout: SplitParser { onRead: function(line) { root.handleIpcLine(line) } }
        onExited: function(code) { root.isStreaming = false }
    }

    Process {
        id: pingProc
        command: ["python3", root.sendScript, "ping"]
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var msg = JSON.parse(line)
                    if (msg.type === "pong") root.isConnected = true
                } catch(e) {}
            }
        }
        onExited: function(code) { if (code !== 0) root.isConnected = false }
    }

    Timer { interval: 3000; running: true; repeat: true; onTriggered: pingProc.running = true }

    Process {
        id: visibilityChecker
        command: ["sh", "-c", "[ -f /tmp/huginn-visible ] && echo 'true' || echo 'false'"]
        stdout: SplitParser { onRead: function(d) { root.overlayVisible = (d.trim() === "true") } }
    }
    Timer { interval: 100; running: true; repeat: true; onTriggered: visibilityChecker.running = true }

    Process { id: escapeClose; command: ["sh", "-c", "rm -f /tmp/huginn-visible"] }

    // ── UI ────────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: root.colBg
        border.color: root.colBorder
        border.width: 1

        // Mint left accent bar
        Rectangle {
            anchors.left:   parent.left
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            width: 3
            color: root.colMint
            opacity: root.isConnected ? 1.0 : 0.3
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 3
            spacing: 0

            // Header
            Rectangle {
                Layout.fillWidth: true
                height: 46
                color: "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 8

                    Text {
                        text: "ᚹ"
                        color: root.colMint
                        font.pixelSize: 17
                        font.family: root.font
                    }
                    Text {
                        text: "HUGINN"
                        color: root.colText
                        font.pixelSize: 12
                        font.family: root.font
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    Rectangle {
                        implicitWidth: liveDot.implicitWidth + liveLabel.implicitWidth + 16
                        implicitHeight: 18
                        radius: 3
                        color: root.isConnected
                            ? Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.1)
                            : Qt.rgba(root.colRed.r, root.colRed.g, root.colRed.b, 0.1)
                        border.color: root.isConnected
                            ? Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.3)
                            : Qt.rgba(root.colRed.r, root.colRed.g, root.colRed.b, 0.3)
                        border.width: 1

                        Row {
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                id: liveDot
                                text: "●"
                                color: root.isConnected ? root.colMint : root.colRed
                                font.pixelSize: 7
                                anchors.verticalCenter: parent.verticalCenter

                                SequentialAnimation on opacity {
                                    running: root.isStreaming
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 500; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 1.0; duration: 500; easing.type: Easing.InOutSine }
                                }
                            }
                            Text {
                                id: liveLabel
                                text: root.isStreaming ? "thinking" : root.isConnected ? "live" : "offline"
                                color: root.isConnected ? root.colMint : root.colRed
                                font.pixelSize: 10
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Recover
                    Text {
                        text: "↺"
                        color: recoverArea.containsMouse ? root.colMint : root.colDim
                        font.pixelSize: 15
                        font.family: root.font
                        Behavior on color { ColorAnimation { duration: 120 } }
                        MouseArea { id: recoverArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.recoverChat() }
                    }

                    // Clear
                    Text {
                        text: "✕"
                        color: clearArea.containsMouse ? root.colOrange : root.colDim
                        font.pixelSize: 13
                        font.family: root.font
                        Behavior on color { ColorAnimation { duration: 120 } }
                        MouseArea { id: clearArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clearChat() }
                    }

                    // Close panel
                    Text {
                        text: "›"
                        color: closeArea.containsMouse ? root.colText : root.colDim
                        font.pixelSize: 18
                        font.family: root.font
                        Behavior on color { ColorAnimation { duration: 120 } }
                        MouseArea { id: closeArea; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: escapeClose.running = true }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.colBorder }

            // Chat log
            ListView {
                id: chatView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: chatModel
                spacing: 2
                topMargin: 14
                bottomMargin: 14

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle { implicitWidth: 2; radius: 1; color: root.colBorder }
                }

                delegate: Item {
                    required property string role
                    required property string content
                    required property string detail
                    required property string result
                    required property int    index

                    width: chatView.width
                    height: roleHeight() + 8

                    function roleHeight() {
                        if (role === "tool_call") return toolChip.implicitHeight + 6
                        if (role === "confirm" || role === "confirm_allowed" || role === "confirm_denied")
                            return confirmBox.implicitHeight + 8
                        if (role === "user")      return userBubble.height + 4
                        if (role === "assistant") return huginnText.implicitHeight + 4
                        return 0
                    }

                    // ── Tool chip ─────────────────────────────────────────────
                    Rectangle {
                        id: toolChip
                        visible: role === "tool_call"
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        implicitHeight: chipRow.implicitHeight + 8
                        implicitWidth: chipRow.implicitWidth + 16
                        radius: 4
                        color: Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.07)
                        border.color: Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b,
                                              result.length > 0 ? 0.3 : 0.15)
                        border.width: 1

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: result.length > 0 ? "✓" : "→"
                                color: root.colMint
                                font.pixelSize: 11
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: content
                                color: root.colMint
                                font.pixelSize: 11
                                font.family: root.font
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                visible: result.length > 0
                                text: result.length > 60 ? result.substring(0, 60) + "…" : result
                                color: root.colDim
                                font.pixelSize: 10
                                font.family: root.font
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }

                    // ── Confirm prompt ────────────────────────────────────────
                    Rectangle {
                        id: confirmBox
                        visible: role === "confirm" || role === "confirm_allowed" || role === "confirm_denied"
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        implicitWidth: Math.min(confirmCol.implicitWidth + 24, chatView.width - 28)
                        implicitHeight: confirmCol.implicitHeight + 16
                        radius: 8
                        color: Qt.rgba(root.colOrange.r, root.colOrange.g, root.colOrange.b, 0.06)
                        border.color: Qt.rgba(root.colOrange.r, root.colOrange.g, root.colOrange.b, 0.3)
                        border.width: 1

                        Column {
                            id: confirmCol
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 12 }
                            spacing: 8

                            Text {
                                text: "⚠  " + content + " — approval required"
                                color: root.colOrange
                                font.pixelSize: 11
                                font.family: root.font
                                font.bold: true
                            }

                            Text {
                                visible: detail !== "" && detail !== "{}"
                                text: detail.length > 100 ? detail.substring(0, 100) + "…" : detail
                                color: root.colMuted
                                font.pixelSize: 10
                                font.family: root.font
                                width: parent.width
                                elide: Text.ElideRight
                            }

                            Row {
                                spacing: 8
                                visible: role === "confirm"

                                Rectangle {
                                    width: 64; height: 22; radius: 4
                                    color: allowArea2.containsMouse
                                        ? Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.2)
                                        : Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.1)
                                    border.color: Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.4)
                                    border.width: 1
                                    Text { anchors.centerIn: parent; text: "Approve"; color: root.colMint; font.pixelSize: 11; font.family: root.font; font.bold: true }
                                    MouseArea { id: allowArea2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.sendConfirm(result, true) }
                                }
                                Rectangle {
                                    width: 56; height: 22; radius: 4
                                    color: denyArea2.containsMouse
                                        ? Qt.rgba(root.colRed.r, root.colRed.g, root.colRed.b, 0.2)
                                        : "transparent"
                                    border.color: root.colBorder
                                    border.width: 1
                                    Text { anchors.centerIn: parent; text: "Deny"; color: root.colDim; font.pixelSize: 11; font.family: root.font }
                                    MouseArea { id: denyArea2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.sendConfirm(result, false) }
                                }
                            }

                            Text {
                                visible: role === "confirm_allowed" || role === "confirm_denied"
                                text: role === "confirm_allowed" ? "✓ approved — running" : "✕ denied"
                                color: role === "confirm_allowed" ? root.colMint : root.colDim
                                font.pixelSize: 11
                                font.family: root.font
                            }
                        }
                    }

                    // ── User bubble (right-aligned) ───────────────────────────
                    Rectangle {
                        id: userBubble
                        visible: role === "user"
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(userText.implicitWidth + 24, chatView.width - 60)
                        height: userText.contentHeight + 18
                        radius: 10
                        color: "#292e42"
                        border.color: root.colBorder
                        border.width: 1

                        TextEdit {
                            id: userText
                            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12; topMargin: 9 }
                            text: role === "user" ? content : ""
                            color: root.colText
                            font.pixelSize: 13
                            font.family: root.font
                            wrapMode: TextEdit.Wrap
                            readOnly: true
                            selectByMouse: true
                            selectionColor: Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.25)
                        }
                    }

                    // ── Huginn ambient text (left, no bubble) ─────────────────
                    TextEdit {
                        id: huginnText
                        visible: role === "assistant"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: role === "assistant" ? content : ""
                        textFormat: TextEdit.MarkdownText
                        readOnly: true
                        selectByMouse: true
                        color: root.colMuted
                        font.pixelSize: 13
                        font.family: root.font
                        wrapMode: TextEdit.Wrap
                        selectionColor: Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.25)
                    }
                }

                // Empty state
                Text {
                    anchors.centerIn: parent
                    visible: chatModel.count === 0
                    text: "ᚹ\nquiet"
                    color: Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.15)
                    font.pixelSize: 28
                    font.family: root.font
                    horizontalAlignment: Text.AlignHCenter
                    lineHeight: 1.4
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: root.colBorder }

            // Input
            Rectangle {
                Layout.fillWidth: true
                height: 52
                color: "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 12
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: root.colSurface
                        border.color: inputField.activeFocus
                            ? Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.4)
                            : root.colBorder
                        border.width: 1
                        radius: 8
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        TextInput {
                            id: inputField
                            anchors { fill: parent; leftMargin: 11; rightMargin: 11 }
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.colText
                            font.pixelSize: 13
                            font.family: root.font
                            selectionColor: Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.25)
                            clip: true

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: inputField.text.length === 0
                                text: root.isConnected ? "ask huginn…" : "daemon offline"
                                color: root.colDim
                                font: inputField.font
                            }

                            Keys.onReturnPressed: root.sendMessage()
                            Keys.onEscapePressed: escapeClose.running = true
                        }
                    }

                    Rectangle {
                        width: 36; height: 36
                        radius: 8
                        color: sendArea.containsMouse && !root.isStreaming
                            ? Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.15)
                            : "transparent"
                        border.color: root.isStreaming ? root.colBorder : Qt.rgba(root.colMint.r, root.colMint.g, root.colMint.b, 0.5)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: root.isStreaming ? "…" : "↵"
                            color: root.isStreaming ? root.colDim : root.colMint
                            font.pixelSize: 14
                            font.family: root.font
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
