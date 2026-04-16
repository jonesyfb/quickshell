import Quickshell
import QtQuick
import Niri 0.1

ShellRoot {
    // Shared system state – metrics, colors, polling processes
    SystemState { id: sys }

    // Niri IPC
    Niri {
        id: niri
        Component.onCompleted: connect()
        onConnected: console.log("Connected to niri")
        onErrorOccurred: function(error) { console.error("Error:", error) }
    }

    // One bar per monitor
    Variants {
        model: Quickshell.screens
        Bar {
            sysState: sys
            niriState: niri
        }
    }

    // Stats overlay – primary monitor only
    StatsOverlay {
        screen: Quickshell.screens[0]
        sysState: sys
    }

    // Obsidian notes widget – primary monitor only
    NoteWidget {
        screen: Quickshell.screens[0]
    }
}
