import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "logic.js" as Logic

// Dank Switcher daemon.
//
// Flow:
//   Super+Tab (Hyprland bind -> hl.dsp.global("dankswitcher:next"))
//     -> first press maps the (empty) overlay to grab the keyboard, fetches
//        `hyprctl -j clients`, sorts MRU, then shows the strip
//     -> further presses move the selection
//   Release Super
//     -> Keys.onReleased on the overlay's exclusive keyboard grab, OR
//     -> Hyprland release bind -> hl.dsp.global("dankswitcher:select")
//     -> quick tap or after cycling: overlay closes, then the selected window
//        is focused (Hyprland follows to its workspace)
//     -> Super+Tab held past holdMs with no further Tab: overlay stays open in
//        sticky mode (Tab/arrows, then Enter, a click, or Super again)
//   Escape / click on empty space -> close without changing focus

PluginComponent {
    id: root

    readonly property string shortcutAppId: "dankswitcher"

    property bool open: false
    // True from the first Tab until the client list has been handled. Not the
    // same as clientsProc.running, which drops before stdout is delivered.
    property bool loading: false
    property var windows: []
    property int selected: 0
    property string pendingAddr: ""

    property bool sticky: false
    property bool pendingSelect: false
    property bool pendingCancel: false
    property int pendingSteps: 0
    property int tabCount: 0
    property real pressedAt: 0
    property real releaseGuardUntil: 0

    // Settings (edited in DMS Settings -> Plugins -> Dank Switcher)
    readonly property bool showTitle: (root.pluginData && root.pluginData.showTitle !== undefined) ? root.pluginData.showTitle : true
    readonly property int iconSize: Logic.clampInt(root.pluginData ? root.pluginData.iconSize : undefined, 16, 128, 56)
    readonly property bool includeSpecial: (root.pluginData && root.pluginData.includeSpecial === true)
    readonly property int containerRadius: Logic.clampInt(root.pluginData ? root.pluginData.containerRadius : undefined, 0, 64, 20)
    // Super released sooner than this after the first Tab is a quick tap;
    // held longer with no further Tab, the strip goes sticky.
    readonly property int holdMs: Logic.clampInt(root.pluginData ? root.pluginData.holdMs : undefined, 150, 2000, 500)

    function next() {
        if (windows.length)
            selected = (selected + 1) % windows.length;
    }

    function prev() {
        if (windows.length)
            selected = (selected + windows.length - 1) % windows.length;
    }

    function openSwitcher() {
        if (loading)
            return;
        loading = true;
        loadWatchdog.restart();
        clientsProc.running = true;
    }

    // If hyprctl never reports back, don't leave the switcher stuck loading.
    Timer {
        id: loadWatchdog
        interval: 2000
        onTriggered: {
            if (root.loading)
                root.finishLoading();
        }
    }

    // Super+Tab / Super+Shift+Tab (or IPC next/prev).
    function step(dir) {
        if (open) {
            tabCount++;
            if (dir > 0)
                next();
            else
                prev();
            return;
        }
        if (loading) {
            // Tabs that land while the client list is still loading.
            tabCount++;
            pendingSteps += dir;
            return;
        }
        resetSession();
        tabCount = 1;
        pressedAt = Date.now();
        openSwitcher();
    }

    function resetSession() {
        sticky = false;
        pendingSelect = false;
        pendingCancel = false;
        pendingSteps = 0;
        tabCount = 0;
        releaseGuardUntil = 0;
    }

    function close(doFocus) {
        if (!open)
            return;
        const entry = (doFocus && windows.length) ? windows[selected] : null;
        open = false;
        resetSession();
        if (!entry)
            return;
        pendingAddr = entry.address;
        focusTimer.start();
    }

    function select() {
        if (!open)
            return;
        close(true);
    }

    // Super was released. The same release can arrive twice (keyboard grab
    // and Hyprland release bind), so going sticky also opens a short guard.
    function superReleased() {
        // Plain Super taps with no switcher session.
        if (!open && !loading)
            return;
        if (sticky) {
            if (Date.now() < releaseGuardUntil)
                return;
            select();
            return;
        }
        if (tabCount <= 1 && Date.now() - pressedAt >= holdMs) {
            sticky = true;
            releaseGuardUntil = Date.now() + 250;
            return;
        }
        if (!open) {
            // Quick tap before the strip is up: switch once the list loads.
            pendingSelect = true;
            return;
        }
        select();
    }

    function cancel() {
        if (loading && !open) {
            pendingCancel = true;
            return;
        }
        close(false);
    }

    function finishLoading() {
        loading = false;
        resetSession();
    }

    function iconPathFor(cls, title) {
        return Logic.iconPathFor(DesktopEntries, Quickshell, cls, title);
    }

    // Give the layer surface a moment to unmap so keyboard focus returns to
    // the compositor before we ask it to focus a window.
    Timer {
        id: focusTimer
        interval: 110
        onTriggered: {
            if (Logic.isSafeAddress(root.pendingAddr))
                Hyprland.dispatch('hl.dsp.focus({ window = "address:' + root.pendingAddr + '" })');
            root.pendingAddr = "";
        }
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                let clients = [];
                try {
                    clients = JSON.parse(text);
                } catch (e) {
                    console.warn("dankswitcher: could not parse hyprctl clients:", e);
                }
                root.fillWindows(clients);
            }
        }
    }

    // The overlay is already up (grabbing the keyboard) while loading, so
    // `open` must go true before `loading` goes false or it would remap.
    function fillWindows(clients) {
        // Late result after the watchdog gave up.
        if (!root.loading)
            return;
        const ordered = Array.isArray(clients) ? Logic.orderClients(clients, root.includeSpecial) : [];
        const records = [];
        for (const c of ordered) {
            if (!Logic.isSafeAddress(c.address))
                continue;
            records.push({
                address: c.address,
                cls: c.class || c.initialClass || "",
                title: c.title || "",
                workspaceName: c.workspace ? String(c.workspace.name) : ""
            });
        }

        if (!records.length || root.pendingCancel) {
            root.finishLoading();
            return;
        }

        const n = records.length;
        root.windows = records;
        // Start on the previously used window, GNOME style, plus any Tabs
        // pressed while loading.
        root.selected = ((root.pendingSteps % n) + n) % n;
        root.pendingSteps = 0;

        if (root.pendingSelect) {
            root.pendingAddr = records[root.selected].address;
            root.finishLoading();
            focusTimer.start();
            return;
        }
        root.open = true;
        root.loading = false;
    }

    // ---- Hyprland global shortcuts (hl.dsp.global("dankswitcher:<name>")) ----

    GlobalShortcut {
        appid: root.shortcutAppId
        name: "next"
        onPressed: root.step(1)
    }

    GlobalShortcut {
        appid: root.shortcutAppId
        name: "prev"
        onPressed: root.step(-1)
    }

    // Fired by the Super release binds. Hyprland can report a release bind as
    // either a pressed or a released event, so listen for both; duplicates are
    // harmless in superReleased().
    GlobalShortcut {
        appid: root.shortcutAppId
        name: "select"
        onPressed: root.superReleased()
        onReleased: root.superReleased()
    }

    GlobalShortcut {
        appid: root.shortcutAppId
        name: "cancel"
        onPressed: root.cancel()
    }

    // ---- dms ipc call dankswitcher <fn> ----

    IpcHandler {
        target: "dankswitcher"

        function next(): string {
            root.step(1);
            return "ok";
        }

        function prev(): string {
            root.step(-1);
            return "ok";
        }

        function select(): string {
            root.select();
            return "ok";
        }

        function cancel(): string {
            root.cancel();
            return "ok";
        }

        function toggle(): string {
            if (root.open) {
                root.cancel();
            } else if (!root.loading) {
                // Nothing is held, so open straight into sticky mode.
                root.resetSession();
                root.sticky = true;
                root.openSwitcher();
            }
            return "ok";
        }
    }

    // ---- Overlay ----

    // Mapped as soon as loading starts so the keyboard grab is in place early
    // and can see Super come up; the strip itself only shows once open.
    LazyLoader {
        active: root.open || root.loading

        PanelWindow {
            id: panel

            // Hover only drives the selection once the pointer actually moves,
            // so a cursor that happens to sit where the strip appears doesn't
            // steal it.
            property bool pointerMoved: false
            property point pointerStart: Qt.point(-1, -1)

            function notePointer(p) {
                if (pointerMoved)
                    return;
                if (pointerStart.x < 0) {
                    pointerStart = p;
                    return;
                }
                if (Math.abs(p.x - pointerStart.x) + Math.abs(p.y - pointerStart.y) > 4)
                    pointerMoved = true;
            }

            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            WlrLayershell.namespace: root.shortcutAppId
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // Clicking empty space dismisses without switching focus.
            MouseArea {
                anchors.fill: parent
                onClicked: root.cancel()

                // Non-blocking, so it tracks the pointer over the strip too.
                HoverHandler {
                    onPointChanged: {
                        if (hovered)
                            panel.notePointer(point.position);
                    }
                }
            }

            Item {
                anchors.centerIn: parent
                width: stripBg.width
                height: stripBg.height + (titleLabel.visible ? titleLabel.height + Theme.spacingM : 0)
                focus: true
                Keys.priority: Keys.BeforeItem

                Rectangle {
                    id: stripBg
                    visible: root.open
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: strip.width + Theme.spacingM * 2
                    height: strip.height + Theme.spacingM * 2
                    radius: root.containerRadius
                    color: Theme.floatingSurface !== undefined ? Theme.floatingSurface : Theme.surface
                    border.width: 1
                    border.color: Theme.popupFieldBorderColor !== undefined ? Theme.popupFieldBorderColor : Qt.alpha(Theme.outline, 0.3)

                    Row {
                        id: strip
                        anchors.centerIn: parent
                        spacing: Theme.spacingM

                        Repeater {
                            model: root.windows

                            delegate: Rectangle {
                                id: tile
                                required property int index
                                required property var modelData
                                readonly property bool isSelected: root.selected === index
                                readonly property bool mouseOver: panel.pointerMoved && hover.hovered

                                onMouseOverChanged: {
                                    if (mouseOver)
                                        root.selected = index;
                                }

                                width: root.iconSize + Theme.spacingM * 2
                                height: root.iconSize + Theme.spacingM * 2
                                radius: Math.max(6, root.containerRadius - Theme.spacingM)
                                color: isSelected ? Qt.alpha(Theme.primary, 0.22) : (mouseOver ? Qt.alpha(Theme.surfaceText, 0.08) : "transparent")
                                border.width: isSelected ? 2 : 0
                                border.color: Theme.primary

                                scale: (isSelected || mouseOver) ? 1.06 : 1.0
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 90
                                        easing.type: Easing.OutQuad
                                    }
                                }

                                Image {
                                    anchors.centerIn: parent
                                    width: root.iconSize
                                    height: root.iconSize
                                    sourceSize.width: root.iconSize
                                    sourceSize.height: root.iconSize
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    source: root.iconPathFor(tile.modelData.cls, tile.modelData.title)
                                }

                                HoverHandler {
                                    id: hover
                                }

                                TapHandler {
                                    onTapped: {
                                        root.selected = tile.index;
                                        root.select();
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    id: titleLabel
                    visible: root.open && root.showTitle && root.windows.length > 0
                    anchors.top: stripBg.bottom
                    anchors.topMargin: Theme.spacingM
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(stripBg.width, 640)
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Font.Medium
                    text: {
                        if (!root.windows.length)
                            return "";
                        const w = root.windows[root.selected];
                        const ws = w.workspaceName ? "  ·  " + w.workspaceName : "";
                        return (w.title || w.cls) + ws;
                    }
                }

                // The exclusive grab delivers key events here while Super is held.
                Keys.onPressed: event => {
                    switch (event.key) {
                    case Qt.Key_Escape:
                        root.cancel();
                        event.accepted = true;
                        break;
                    case Qt.Key_Tab:
                    case Qt.Key_Right:
                    case Qt.Key_Down:
                        root.next();
                        event.accepted = true;
                        break;
                    case Qt.Key_Backtab:
                    case Qt.Key_Left:
                    case Qt.Key_Up:
                        root.prev();
                        event.accepted = true;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                        root.select();
                        event.accepted = true;
                        break;
                    }
                }

                Keys.onReleased: event => {
                    const superReleasing = event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R;
                    if (superReleasing) {
                        root.superReleased();
                        event.accepted = true;
                    }
                }

                Component.onCompleted: forceActiveFocus()
            }
        }
    }

    Component.onCompleted: console.info("dankswitcher: daemon loaded")
}
