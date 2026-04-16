import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick

// Obsidian Goals.md rendered as a read-only markdown widget.
// Reloads every 5 seconds. Pinned to primary monitor.
PanelWindow {
    WlrLayershell.namespace: "noteWidget"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    anchors.top: true
    anchors.right: true
    margins.top: 40
    margins.right: 20

    implicitWidth: 380
    implicitHeight: 500
    color: "transparent"

    property string noteText: ""

    Process {
        id: noteReader
        command: ["cat", "/home/nate/Documents/Obsidian Vault/Goals.md"]
        stdout: SplitParser {
            onRead: function(data) { noteText += data + "\n" }
        }
        stderr: SplitParser {
            onRead: function(data) { console.error("noteReader error:", data) }
        }
        onExited: console.log("Note loaded, length:", noteText.length)
        Component.onCompleted: running = true
    }

    Timer {
        interval: 5000; running: true; repeat: true
        onTriggered: { noteText = ""; noteReader.running = true }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Qt.rgba(0.102, 0.106, 0.149, 0.85)
        border.color: "#444b6a"; border.width: 1

        TextEdit {
            anchors.fill: parent; anchors.margins: 14
            text: noteText
            textFormat: TextEdit.MarkdownText
            readOnly: true
            wrapMode: Text.Wrap
            color: "#a9b1d6"
            font.pixelSize: 16; font.family: "Jetbrains Nerd Mono"
            selectByMouse: false
        }
    }
}
