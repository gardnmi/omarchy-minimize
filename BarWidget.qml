import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "io.github.gardnmi.window-shelf"

  readonly property string shelfWorkspace: "special:omarchy-minimized"
  readonly property string peekWorkspace: "special:omarchy-window-peek"
  readonly property int maxTitleLength: Math.max(4, Number(setting("maxTitleLength", 18)))
  readonly property int maxChipWidth: Math.max(Style.space(80), Number(setting("maxChipWidth", Style.space(180))))
  readonly property int previewDelay: Math.max(0, Number(setting("previewDelay", 350)))
  readonly property int peekWidth: Math.max(Style.space(320), Number(setting("peekWidth", 960)))
  readonly property int peekHeight: Math.max(Style.space(240), Number(setting("peekHeight", 640)))
  readonly property var minimizedWindows: Hyprland.toplevels.values.filter(function(toplevel) {
    return root.isManaged(toplevel)
  })
  readonly property var activeWindow: Hyprland.activeToplevel
  readonly property bool canMinimize: activeWindow !== null && !isManaged(activeWindow)
  property var pendingPreviewToplevel: null
  property Item pendingPreviewAnchor: null
  property var previewToplevel: null
  property Item previewAnchor: null
  property var peekToplevel: null
  property var pendingPeekToplevel: null
  property string peekOriginWorkspace: ""
  property bool peekVisible: false
  property bool peekWasFloating: false
  property int peekOriginalFullscreen: 0
  property var peekOriginalSize: null
  property var peekOriginalPosition: null
  property bool peekHideAlready: false

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  function isMinimized(toplevel) {
    return toplevel !== null && toplevel.workspace !== null
      && toplevel.workspace.name === shelfWorkspace
  }

  function isPeeked(toplevel) {
    return toplevel !== null && toplevel.workspace !== null
      && toplevel.workspace.name === peekWorkspace
  }

  function isManaged(toplevel) {
    return isMinimized(toplevel) || isPeeked(toplevel)
  }

  function normalizedAddress(toplevel) {
    if (!toplevel || !toplevel.address) return ""
    var address = String(toplevel.address)
    return address.indexOf("0x") === 0 ? address : "0x" + address
  }

  function moveRequest(toplevel, workspace, follow) {
    var address = normalizedAddress(toplevel)
    if (!address || !workspace) return ""
    return "hl.dsp.window.move({ workspace = " + JSON.stringify(workspace)
      + ", window = " + JSON.stringify("address:" + address)
      + ", follow = " + (follow ? "true" : "false") + " })"
  }

  function moveWindow(toplevel, workspace, follow) {
    var request = moveRequest(toplevel, workspace, follow)
    if (!request) return
    Quickshell.execDetached(["hyprctl", "dispatch", request])
  }

  function windowFloatRequest(toplevel, action) {
    var address = normalizedAddress(toplevel)
    if (!address) return ""
    return "hl.dsp.window.float({ action = " + JSON.stringify(action)
      + ", window = " + JSON.stringify("address:" + address) + " })"
  }

  function windowResizeRequest(toplevel, width, height) {
    var address = normalizedAddress(toplevel)
    if (!address) return ""
    return "hl.dsp.window.resize({ x = " + Math.round(width) + ", y = " + Math.round(height)
      + ", window = " + JSON.stringify("address:" + address) + " })"
  }

  function windowPositionRequest(toplevel, x, y) {
    var address = normalizedAddress(toplevel)
    if (!address) return ""
    return "hl.dsp.window.move({ x = " + Math.round(x) + ", y = " + Math.round(y)
      + ", relative = false, window = " + JSON.stringify("address:" + address) + " })"
  }

  function windowCenterRequest(toplevel) {
    var address = normalizedAddress(toplevel)
    if (!address) return ""
    return "hl.dsp.window.center({ window = " + JSON.stringify("address:" + address) + " })"
  }

  function windowFullscreenRequest(toplevel, fullscreenMode) {
    var address = normalizedAddress(toplevel)
    if (!address || fullscreenMode <= 0) return ""
    var mode = fullscreenMode === 1 ? "maximized" : "fullscreen"
    return "hl.dsp.window.fullscreen({ mode = " + JSON.stringify(mode)
      + ", window = " + JSON.stringify("address:" + address) + " })"
  }

  function minimizeActive() {
    if (!canMinimize) return
    moveWindow(activeWindow, shelfWorkspace, false)
  }

  function restore(toplevel) {
    var workspace = Hyprland.focusedWorkspace
    var destination = workspace && String(workspace.name).indexOf("special:") !== 0
      ? workspace.name : peekOriginWorkspace
    if (!destination) return
    if (peekToplevel === toplevel || isPeeked(toplevel)) {
      if (peekProcess.running) return
      peekVisible = false
      runPeekCommand(["hyprctl", "dispatch", moveRequest(toplevel, destination, true)], "restore-move")
    } else {
      moveWindow(toplevel, destination, true)
    }
  }

  function runPeekCommand(command, action) {
    if (peekProcess.running || !command || command.length === 0) return false
    peekProcess.action = action
    peekProcess.command = command
    peekProcess.running = true
    return true
  }

  function togglePeek(toplevel) {
    if (!toplevel || peekProcess.running) return
    cancelPreview(toplevel)
    if (peekToplevel === toplevel || isPeeked(toplevel)) {
      closePeek(toplevel)
      return
    }
    if (peekToplevel) {
      pendingPeekToplevel = toplevel
      closePeek(peekToplevel)
      return
    }

    var workspace = Hyprland.focusedWorkspace
    if (!workspace || String(workspace.name).indexOf("special:") === 0) return
    peekToplevel = toplevel
    peekOriginWorkspace = workspace.name
    peekVisible = false
    var ipc = toplevel.lastIpcObject || null
    peekWasFloating = !!(ipc && ipc.floating)
    peekOriginalFullscreen = Number(ipc && ipc.fullscreen ? ipc.fullscreen : 0)
    peekOriginalSize = ipc && Array.isArray(ipc.size) ? ipc.size.slice(0, 2) : null
    peekOriginalPosition = ipc && Array.isArray(ipc.at) ? ipc.at.slice(0, 2) : null
    runPeekCommand(["hyprctl", "dispatch", moveRequest(toplevel, peekWorkspace, false)], "show-move")
  }

  function closePeek(toplevel, alreadyHidden) {
    var target = toplevel || peekToplevel
    if (!target || peekProcess.running) return
    peekVisible = false
    peekHideAlready = alreadyHidden === true
    runPeekCommand(["hyprctl", "dispatch", moveRequest(target, shelfWorkspace, false)], "hide-move")
  }

  function clearPeekState() {
    peekToplevel = null
    peekOriginWorkspace = ""
    peekVisible = false
    peekWasFloating = false
    peekOriginalFullscreen = 0
    peekOriginalSize = null
    peekOriginalPosition = null
    peekHideAlready = false
  }

  function runPeekToggle(action) {
    runPeekCommand(["hyprctl", "dispatch",
      "hl.dsp.workspace.toggle_special(\"omarchy-window-peek\")"], action)
  }

  function finalizePeek() {
    clearPeekState()
    if (pendingPeekToplevel) {
      var next = pendingPeekToplevel
      pendingPeekToplevel = null
      Qt.callLater(function() { root.togglePeek(next) })
    }
  }

  function completePeekExit(kind) {
    if (peekOriginalFullscreen > 0) {
      runPeekCommand(["hyprctl", "dispatch",
        windowFullscreenRequest(peekToplevel, peekOriginalFullscreen)], kind + "-fullscreen")
    } else if (kind === "hide" && peekHideAlready) {
      finalizePeek()
    } else {
      runPeekToggle(kind + "-toggle")
    }
  }

  function finishPeekExit(kind) {
    if (!peekToplevel) {
      clearPeekState()
      return
    }
    if (!peekWasFloating) {
      runPeekCommand(["hyprctl", "dispatch", windowFloatRequest(peekToplevel, "off")], kind + "-float")
    } else if (peekOriginalSize && peekOriginalSize.length === 2) {
      runPeekCommand(["hyprctl", "dispatch", windowResizeRequest(peekToplevel,
        peekOriginalSize[0], peekOriginalSize[1])], kind + "-resize")
    } else {
      completePeekExit(kind)
    }
  }

  function finishPeekResize(kind) {
    if (peekOriginalPosition && peekOriginalPosition.length === 2) {
      runPeekCommand(["hyprctl", "dispatch", windowPositionRequest(peekToplevel,
        peekOriginalPosition[0], peekOriginalPosition[1])], kind + "-position")
    } else {
      completePeekExit(kind)
    }
  }

  function finishPeekCommand(action, exitCode) {
    if (exitCode !== 0) {
      var failedTarget = peekToplevel
      clearPeekState()
      if (failedTarget && action.indexOf("show-") === 0) moveWindow(failedTarget, shelfWorkspace, false)
      return
    }

    if (action === "show-move") {
      Qt.callLater(function() {
        if (root.peekOriginalFullscreen > 0) {
          root.runPeekCommand(["hyprctl", "dispatch",
            root.windowFullscreenRequest(root.peekToplevel, root.peekOriginalFullscreen)], "show-fullscreen")
        } else {
          root.runPeekCommand(["hyprctl", "dispatch",
            root.windowFloatRequest(root.peekToplevel, "on")], "show-float")
        }
      })
    } else if (action === "show-fullscreen") {
      Qt.callLater(function() {
        root.runPeekCommand(["hyprctl", "dispatch",
          root.windowFloatRequest(root.peekToplevel, "on")], "show-float")
      })
    } else if (action === "show-float") {
      Qt.callLater(function() {
        root.runPeekCommand(["hyprctl", "dispatch",
          root.windowResizeRequest(root.peekToplevel, root.peekWidth, root.peekHeight)], "show-resize")
      })
    } else if (action === "show-resize") {
      Qt.callLater(function() {
        root.runPeekCommand(["hyprctl", "dispatch",
          root.windowCenterRequest(root.peekToplevel)], "show-center")
      })
    } else if (action === "show-center") {
      Qt.callLater(function() { root.runPeekToggle("show-toggle") })
    } else if (action === "show-toggle") {
      peekVisible = true
    } else if (action === "hide-move" || action === "restore-move") {
      var exitKind = action === "hide-move" ? "hide" : "restore"
      Qt.callLater(function() { root.finishPeekExit(exitKind) })
    } else if (action === "hide-resize" || action === "restore-resize") {
      var resizeKind = action === "hide-resize" ? "hide" : "restore"
      Qt.callLater(function() { root.finishPeekResize(resizeKind) })
    } else if (action === "hide-position" || action === "restore-position"
        || action === "hide-float" || action === "restore-float") {
      var stateKind = action.indexOf("hide-") === 0 ? "hide" : "restore"
      Qt.callLater(function() { root.completePeekExit(stateKind) })
    } else if (action === "hide-fullscreen" || action === "restore-fullscreen") {
      var fullscreenKind = action.indexOf("hide-") === 0 ? "hide" : "restore"
      Qt.callLater(function() {
        if (fullscreenKind === "hide" && root.peekHideAlready) root.finalizePeek()
        else root.runPeekToggle(fullscreenKind + "-toggle")
      })
    } else if (action === "hide-toggle" || action === "restore-toggle") {
      finalizePeek()
    } else if (action === "external-toggle") {
      finalizePeek()
    }
  }

  function handleFocusedWorkspaceChanged() {
    if (!peekToplevel || !peekVisible || peekProcess.running) return
    var workspace = Hyprland.focusedWorkspace
    if (workspace && workspace.name !== peekWorkspace) closePeek(peekToplevel, true)
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
    if (previewToplevel && !isManaged(previewToplevel)) cancelPreview(previewToplevel)
    if (peekToplevel && !peekProcess.running && peekVisible
        && (!isManaged(peekToplevel) || !isPeeked(peekToplevel))) {
      peekVisible = false
      runPeekToggle("external-toggle")
    } else if (peekToplevel && !isManaged(peekToplevel) && !peekProcess.running) {
      clearPeekState()
    }
  }

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() { root.handleFocusedWorkspaceChanged() }
  }

  Process {
    id: peekProcess
    property string action: ""
    onExited: function(exitCode) {
      var completedAction = action
      action = ""
      root.finishPeekCommand(completedAction, exitCode)
    }
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
        tooltipText: String(modelData.title || "Window")
          + (root.isPeeked(modelData) ? " - click to restore, right-click to close Peek"
            : " - click to restore, right-click to Peek")
        onTooltipHoveredChanged: {
          if (tooltipHovered && root.isMinimized(modelData)) root.requestPreview(chip, modelData)
          else root.cancelPreview(modelData)
        }
        onPressed: function(button) {
          if (button === Qt.LeftButton) {
            root.cancelPreview(modelData)
            root.restore(modelData)
          } else if (button === Qt.RightButton) {
            root.togglePeek(modelData)
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
            color: root.isPeeked(chip.modelData) ? Color.accent
              : (root.bar ? root.bar.barForeground : Color.foreground)
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
