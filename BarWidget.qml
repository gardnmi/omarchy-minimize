import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "io.github.gardnmi.window-shelf"

  readonly property string shelfWorkspace: "special:omarchy-minimized"
  readonly property int maxTitleLength: Math.max(4, Number(setting("maxTitleLength", 18)))
  readonly property int maxChipWidth: Math.max(Style.space(80), Number(setting("maxChipWidth", Style.space(180))))
  readonly property int previewDelay: Math.max(0, Number(setting("previewDelay", 350)))
  readonly property var minimizedWindows: Hyprland.toplevels.values.filter(function(toplevel) {
    return root.isMinimized(toplevel)
  })
  readonly property var activeWindow: Hyprland.activeToplevel
  readonly property bool canMinimize: activeWindow !== null && !isMinimized(activeWindow)
  property var pendingPreviewToplevel: null
  property Item pendingPreviewAnchor: null
  property var previewToplevel: null
  property Item previewAnchor: null

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  function isMinimized(toplevel) {
    return toplevel !== null && toplevel.workspace !== null
      && toplevel.workspace.name === shelfWorkspace
  }

  function moveWindow(toplevel, workspace, follow) {
    if (!toplevel || !toplevel.address || !workspace) return
    var address = String(toplevel.address)
    if (address.indexOf("0x") !== 0) address = "0x" + address
    var request = "hl.dsp.window.move({ workspace = " + JSON.stringify(workspace)
      + ", window = " + JSON.stringify("address:" + address)
      + ", follow = " + (follow ? "true" : "false") + " })"
    Quickshell.execDetached(["hyprctl", "dispatch", request])
  }

  function minimizeActive() {
    if (!canMinimize) return
    moveWindow(activeWindow, shelfWorkspace, false)
  }

  function restore(toplevel) {
    var workspace = Hyprland.focusedWorkspace
    if (!workspace || workspace.name === shelfWorkspace) return
    moveWindow(toplevel, workspace.name, true)
  }

  function windowTitle(toplevel) {
    var title = String(toplevel && toplevel.title ? toplevel.title : "Window").trim()
    if (title.length <= maxTitleLength) return title
    return title.substring(0, maxTitleLength - 3) + "..."
  }

  function verticalLabel(toplevel) {
    var ipc = toplevel ? toplevel.lastIpcObject : null
    var app = String(ipc && ipc.class ? ipc.class : windowTitle(toplevel)).trim()
    return app.length > 0 ? app.charAt(0).toUpperCase() : "W"
  }

  function desktopEntry(toplevel) {
    if (!toplevel) return null
    var ipc = toplevel.lastIpcObject || null
    var wayland = toplevel.wayland || null
    var candidates = [
      wayland && wayland.appId ? wayland.appId : "",
      ipc && ipc.class ? ipc.class : "",
      ipc && ipc.initialClass ? ipc.initialClass : ""
    ]
    for (var i = 0; i < candidates.length; i++) {
      var candidate = String(candidates[i] || "").trim()
      if (!candidate) continue
      var entry = DesktopEntries.heuristicLookup(candidate)
      if (entry) return entry
    }
    return null
  }

  function windowIcon(toplevel) {
    var entry = desktopEntry(toplevel)
    var icon = String(entry && entry.icon ? entry.icon : "")
    if (icon.indexOf("file://") === 0 || icon.indexOf("image://") === 0) return icon
    if (icon.charAt(0) === "/") return Util.fileUrl(icon)
    return Quickshell.iconPath(icon || "application-x-executable", true)
  }

  function requestPreview(anchor, toplevel) {
    pendingPreviewAnchor = anchor
    pendingPreviewToplevel = toplevel
    previewTimer.restart()
  }

  function cancelPreview(toplevel) {
    if (pendingPreviewToplevel === toplevel) {
      previewTimer.stop()
      pendingPreviewAnchor = null
      pendingPreviewToplevel = null
    }
    if (previewToplevel === toplevel) {
      previewToplevel = null
      previewAnchor = null
    }
  }

  onMinimizedWindowsChanged: {
    if (previewToplevel && !isMinimized(previewToplevel)) cancelPreview(previewToplevel)
  }

  Timer {
    id: previewTimer
    interval: root.previewDelay
    onTriggered: {
      root.previewAnchor = root.pendingPreviewAnchor
      root.previewToplevel = root.pendingPreviewToplevel
      root.pendingPreviewAnchor = null
      root.pendingPreviewToplevel = null
    }
  }

  GridLayout {
    id: layout

    columns: root.vertical ? 1 : root.minimizedWindows.length + 1
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(1) : 0

    WidgetButton {
      id: minimizeButton

      bar: root.bar
      text: ""
      keepSpace: true
      hasVisualContent: true
      labelVisible: false
      fixedWidth: root.barSize
      fixedHeight: root.barSize
      dimmed: !root.canMinimize
      interactive: root.canMinimize
      tooltipText: root.canMinimize ? "Minimize active window (Super+M)" : "No active window to minimize"
      onPressed: function(button) {
        if (button === Qt.LeftButton) root.minimizeActive()
      }

      Item {
        width: Style.space(16)
        height: Style.space(15)
        anchors.centerIn: parent

        Rectangle {
          id: minimizePane
          width: Style.space(12)
          height: Style.space(8)
          x: Math.round((parent.width - width) / 2)
          y: minimizeButton.tooltipHovered ? Style.space(6) : Style.space(2)
          color: "transparent"
          border.width: Math.max(1, Style.spaceReal(1))
          border.color: minimizeButton.tooltipHovered ? Color.accent
            : (root.bar ? root.bar.barForeground : Color.foreground)
          radius: Style.space(1)

          Behavior on y {
            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
          }

          Behavior on border.color {
            ColorAnimation { duration: 120 }
          }
        }

        Rectangle {
          width: Style.space(16)
          height: Math.max(1, Style.space(2))
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          color: minimizeButton.tooltipHovered ? Color.accent
            : (root.bar ? root.bar.barForeground : Color.foreground)
          radius: height / 2

          Behavior on color {
            ColorAnimation { duration: 120 }
          }
        }
      }
    }

    Repeater {
      model: root.minimizedWindows

      WidgetButton {
        id: chip

        required property var modelData
        readonly property int iconExtent: Style.space(15)
        readonly property string iconSource: root.windowIcon(modelData)

        TextMetrics {
          id: titleMetrics
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          text: root.windowTitle(parent.modelData)
        }

        bar: root.bar
        text: ""
        keepSpace: true
        hasVisualContent: true
        labelVisible: false
        fixedWidth: root.vertical ? root.barSize
          : Math.min(root.maxChipWidth, titleMetrics.advanceWidth + iconExtent + Style.space(24))
        fixedHeight: root.barSize
        clip: true
        tooltipText: String(modelData.title || "Window") + " - click to restore"
        onTooltipHoveredChanged: {
          if (tooltipHovered) root.requestPreview(chip, modelData)
          else root.cancelPreview(modelData)
        }
        onPressed: function(button) {
          if (button === Qt.LeftButton) {
            root.cancelPreview(modelData)
            root.restore(modelData)
          }
        }

        Row {
          anchors.centerIn: parent
          spacing: root.vertical ? 0 : Style.space(6)

          Item {
            width: chip.iconExtent
            height: chip.iconExtent

            Image {
              id: appIcon
              anchors.fill: parent
              source: chip.iconSource
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              fillMode: Image.PreserveAspectFit
              asynchronous: true
            }

            Text {
              anchors.centerIn: parent
              visible: appIcon.status === Image.Error || appIcon.source.toString() === ""
              text: root.verticalLabel(chip.modelData)
              color: root.bar ? root.bar.barForeground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
            }
          }

          Text {
            visible: !root.vertical
            width: Math.max(0, chip.width - chip.iconExtent - Style.space(18))
            text: root.windowTitle(chip.modelData)
            color: root.bar ? root.bar.barForeground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
          }
        }
      }
    }
  }

  PopupCard {
    id: previewCard

    anchorItem: root.previewAnchor || root
    bar: root.bar
    owner: root
    triggerMode: "hover"
    open: root.previewToplevel !== null && root.previewAnchor !== null
    contentWidth: Style.space(320)
    contentHeight: Style.space(220)
    padding: Style.space(8)

    Item {
      anchors.fill: parent

      Item {
        id: previewFrame
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: previewTitle.top
        anchors.bottomMargin: Style.space(7)
        clip: true

        Image {
          width: Style.space(48)
          height: width
          anchors.centerIn: parent
          source: root.previewToplevel ? root.windowIcon(root.previewToplevel) : ""
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          opacity: previewView.hasContent ? 0 : 0.5
        }

        ScreencopyView {
          id: previewView
          anchors.fill: parent
          captureSource: root.previewToplevel ? root.previewToplevel.wayland : null
          live: previewCard.open
          paintCursor: false
        }
      }

      Text {
        id: previewTitle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        text: root.previewToplevel ? String(root.previewToplevel.title || "Window") : ""
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
      }
    }
  }
}
