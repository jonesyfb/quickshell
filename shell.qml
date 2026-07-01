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

    // Calendar popup – primary monitor, toggled by clicking the clock
    CalendarWidget {
        screen: Quickshell.screens[0]
        sysState: sys
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

    // Huginn AI overlay – primary monitor only
    HuginnOverlay {
        targetScreen: Quickshell.screens[0]
    }

    // Desktop notifications – primary monitor only
    NotificationsOverlay {
        targetScreen: Quickshell.screens[0]
        sysState: sys
    }

    // Huginn raven notification popup – bottom-right, triggered via huginn-notify
    HuginnNotification {
        targetScreen: Quickshell.screens[0]
    }
}
