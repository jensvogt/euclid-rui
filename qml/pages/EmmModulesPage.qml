import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// EMM: the module registry euclid-mgr works from. Every other module in this UI is one row of this
// table - what it is, whether it is meant to be running, and how many instances of it are.
//
// Modules only: the manager also runs transfer servers and application pools out of the same
// registry, but those are ETS's and EAP's, not modules, and are controlled from their own pages.
//
// Administrators only. A module list says how the installation itself is put together, which is an
// operator's business rather than a user's - though the restriction is this window's, not the
// server's: "list-modules" asks for a session and nothing more, so this hides the page rather than
// protecting the data behind it.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    // Everything "list-modules" returned, and the prefix the table is filtering it by. The filter
    // is applied here rather than by the server: the action takes no prefix, and the whole registry
    // is a dozen rows that already arrived.
    property var allModules: []
    property string prefix: ""
    readonly property var modules: {
        const wanted = root.prefix.trim().toLowerCase()
        if (wanted.length === 0) return root.allModules
        return root.allModules.filter(m => String(m.name).toLowerCase().startsWith(wanted))
    }
    readonly property int totalCount: root.modules.length
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    readonly property bool isAdmin: euclidClient.isAdmin

    signal back()
    signal openModuleDetails(string moduleName, var details)

    // Enabled and up, enabled and down, or switched off in the registry. A module nobody asked to
    // run is not a problem, so it reads grey rather than red.
    function stateColor(row) {
        if (!row || !row.active) return "#9aa1ac"
        return row.runningInstances > 0 ? "#4cd97b" : "#ff6b6b"
    }

    function stateText(row) {
        if (!row || !row.active) return "DISABLED"
        return row.runningInstances > 0 ? "RUNNING" : "STOPPED"
    }

    // None of these are sortable: the server has no sort for "list-modules", and the rows are put
    // in name order below - which is the order a registry is read in anyway.
    readonly property var columns: [
        { title: "Module", key: "name", fill: true, sortable: false },
        {
            title: "State",
            key: "active",
            sortable: false,
            formatter: function (v, row) { return root.stateText(row) },
            colorFor: function (v, row) { return root.stateColor(row) }
        },
        {
            title: "Instances",
            key: "runningInstances",
            sortable: false,
            // Running against the ceiling the autoscaler may grow to, written the way the EAP
            // applications table writes it. The floor is on the details page, where the pending
            // "1 → 3" of a scaling change belongs with it.
            formatter: function (v, row) {
                return row ? Number(v) + " / " + Number(row.maxInstances) : String(v)
            }
        },
        { title: "Auto-restart", key: "autoRestart", sortable: false, formatter: function (v) { return v ? "Yes" : "No" } },
        { title: "Created", key: "created", sortable: false, formatter: function (v) { return DateFormat.format(v) } },
        { title: "Modified", key: "modified", sortable: false, formatter: function (v) { return DateFormat.format(v) } }
    ]

    // What the last control action did, kept next to the table: every one of them is a request the
    // manager acts on a tick later, so there is nothing to see in the row itself yet.
    property string actionNote: ""

    // The bound to count from is the one asked for if a change is still pending, and the one in
    // force otherwise - otherwise two scale-ups in a row both compute from the same starting point.
    function pendingMin(row) {
        return row.desiredMinInstances >= 0 ? row.desiredMinInstances : row.minInstances
    }

    function pendingMax(row) {
        return row.desiredMaxInstances >= 0 ? row.desiredMaxInstances : row.maxInstances
    }

    // What the dialog opens on. Scaling moves the floor, not the ceiling: the floor is what the
    // manager guarantees to run, so raising it starts an instance while raising the ceiling only
    // permits one. Nothing is sent until the dialog is confirmed - these are only the numbers it
    // starts with, and both fields are editable.
    function scaleUpSuggestion(row) {
        const min = root.pendingMin(row) + 1
        // The server refuses a floor above the ceiling, so the ceiling comes along when pushed.
        return { min: min, max: Math.max(root.pendingMax(row), min) }
    }

    // Floors at one rather than zero, for the reason the menu item gives: a module scaled to zero
    // cannot be reached or restarted, so this view does not offer a way there.
    function scaleDownSuggestion(row) {
        // Suggests one, not zero - see the warning in the dialog for what a floor of zero means.
        return { min: Math.max(1, root.pendingMin(row) - 1), max: root.pendingMax(row) }
    }

    function refresh() {
        if (!root.loggedIn) {
            root.error = "Sign in to view modules."
            return
        }
        if (!root.isAdmin) {
            root.error = "Listing modules requires administrator access."
            return
        }
        root.loading = true
        root.error = ""
        // "list-modules" returns every module at once - there is no paging and no prefix filter.
        emmClient.fetchModules()
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Live updates are off by default: a table that reloads while it is being read
        // moves rows out from under the pointer. See AppSettings::liveListUpdates().
        running: appSettings.liveListUpdates && appSettings.autoRefreshSeconds > 0
                 && root.visible && root.loggedIn && root.isAdmin
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: emmClient
        function onModulesLoaded(list, total) {
            // The dashboard asks for this list too, and gets its own copy of the answer; this page
            // only takes the one it asked for.
            if (!root.visible) return
            root.loading = false
            root.error = ""
            // Only the installation's own modules, the ones declared in euclid.json. Transfer
            // servers and application pools are entries in the same registry - the manager runs
            // them the same way - but they are not modules, and their desired state belongs to ETS
            // and EAP, which is where they are started, stopped and scaled. Listing them here would
            // offer control that EMM refuses.
            //
            // Name order, since the registry comes back in whatever order it was written in.
            root.allModules = list.filter(m => m.core)
                                  .sort((a, b) => String(a.name).localeCompare(String(b.name)))
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onModulesFailed(message) {
            if (!root.visible) return
            root.loading = false
            root.error = message
        }
        function onModuleActionDone(name, action) {
            if (!root.visible) return
            root.actionNote = name + ": " + root.actionPhrase(action) + " - the manager acts on its next pass."
            // Re-read rather than patch: what changed is a desired value, and the row shows both
            // that and what is actually running.
            root.refresh()
        }
        function onModuleActionFailed(name, action, message) {
            if (!root.visible) return
            root.actionNote = ""
            root.error = name + ": " + message
        }
    }

    function actionPhrase(action) {
        if (action === "start-module") return "start requested"
        if (action === "stop-module") return "stop requested"
        if (action === "restart-module") return "restart requested"
        if (action === "set-instances") return "instance limits changed"
        if (action === "set-threads") return "worker threads changed"
        return action
    }

    Dialog {
        id: scaleDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property var module: null
        readonly property string moduleName: module ? module.name : ""
        readonly property int currentMin: module ? root.pendingMin(module) : 0
        readonly property int currentMax: module ? root.pendingMax(module) : 1
        readonly property int runningInstances: module ? Number(module.runningInstances) : 0

        readonly property int wantedMin: parseInt(minField.text, 10)
        readonly property int wantedMax: parseInt(maxField.text, 10)
        readonly property bool valid: !isNaN(wantedMin) && !isNaN(wantedMax)
                                      && wantedMin >= 0 && wantedMax >= 1 && wantedMin <= wantedMax

        // Refused by the server rather than silently corrected, so it is said here first.
        readonly property string problem: {
            if (isNaN(scaleDialog.wantedMin) || isNaN(scaleDialog.wantedMax)) return ""
            if (scaleDialog.wantedMax < 1) return "The ceiling has to be at least 1."
            if (scaleDialog.wantedMin > scaleDialog.wantedMax)
                return "The floor (" + scaleDialog.wantedMin + ") cannot be above the ceiling (" + scaleDialog.wantedMax + ")."
            return ""
        }

        function openFor(row, suggestion) {
            scaleDialog.module = row
            scaleDialog.open()
            minField.text = String(suggestion.min)
            maxField.text = String(suggestion.max)
            minField.forceActiveFocus()
            minField.selectAll()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: scaleDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Scale Module"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: scaleDialog.moduleName + "  ·  " + scaleDialog.runningInstances + " running, currently "
                          + scaleDialog.currentMin + "–" + scaleDialog.currentMax
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "The floor is what the manager keeps running; the ceiling is as far as the autoscaler may "
                      + "go under load. Raising the floor starts instances now, raising the ceiling only permits "
                      + "them. Neither happens here - the manager acts on its next pass."
            }

            Row {
                width: parent.width
                spacing: 12

                Column {
                    width: (scaleDialog.availableWidth - 12) / 2
                    spacing: 6
                    Text { text: "Min instances"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: minField
                        width: parent.width
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        validator: IntValidator { bottom: 0; top: 999 }
                        Keys.onReturnPressed: maxField.forceActiveFocus()
                    }
                }

                Column {
                    width: (scaleDialog.availableWidth - 12) / 2
                    spacing: 6
                    Text { text: "Max instances"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: maxField
                        width: parent.width
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        validator: IntValidator { bottom: 1; top: 999 }
                        Keys.onReturnPressed: if (applyScaleButton.enabled) applyScaleButton.clicked()
                    }
                }
            }

            // A floor of zero is accepted by EMM and honoured by the autoscaler, and it is a trap:
            // nothing brings the module back. Allowed here because typing it is a decision rather
            // than a slip, but not without saying what it costs.
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ffb545"
                font.pixelSize: 12
                visible: scaleDialog.wantedMin === 0
                text: "⚠  A floor of 0 lets the pool drain to nothing when idle, and nothing starts it again: "
                      + "the gateway answers 503 for a module with no instances rather than waking one, and the "
                      + "autoscaler needs a running instance to observe before it will add more. The module stays "
                      + "off the air until somebody scales it up again."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: scaleDialog.problem.length > 0
                text: scaleDialog.problem
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Cancel"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    onClicked: scaleDialog.close()
                }

                Button {
                    id: applyScaleButton
                    text: "Apply"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: scaleDialog.valid
                             && (scaleDialog.wantedMin !== scaleDialog.currentMin
                                 || scaleDialog.wantedMax !== scaleDialog.currentMax)
                    onClicked: {
                        emmClient.setModuleInstances(scaleDialog.moduleName, scaleDialog.wantedMin, scaleDialog.wantedMax)
                        scaleDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: threadsDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property var module: null
        readonly property string moduleName: module ? module.name : ""
        // What the module will be running with once the manager has cycled it, which is what the
        // field should open on rather than whatever it was started with.
        readonly property int currentThreads: module
            ? (module.desiredThreads >= 0 ? module.desiredThreads : 0) : 0

        function openFor(row) {
            threadsDialog.module = row
            threadsDialog.open()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            threadsField.text = threadsDialog.currentThreads > 0 ? String(threadsDialog.currentThreads) : ""
            threadsField.forceActiveFocus()
            threadsField.selectAll()
        }

        contentItem: Column {
            width: threadsDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Set Worker Threads"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: threadsDialog.moduleName
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Threads per instance (1–256)"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: threadsField
                    width: parent.width
                    placeholderText: "e.g. 8"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    validator: IntValidator { bottom: 1; top: 256 }
                    Keys.onReturnPressed: if (saveThreadsButton.enabled) saveThreadsButton.clicked()
                }
                Text {
                    text: "A thread count is fixed when a process starts, so the manager cycles the running "
                          + "instances through it one at a time rather than applying it in place."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Cancel"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    onClicked: threadsDialog.close()
                }

                Button {
                    id: saveThreadsButton
                    text: "Set"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: threadsField.acceptableInput
                    onClicked: {
                        emmClient.setModuleThreads(threadsDialog.moduleName, parseInt(threadsField.text, 10))
                        threadsDialog.close()
                    }
                }
            }
        }
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            width: parent.width
            spacing: 20

            Button {
                text: "‹ Back to Dashboard"
                flat: true
                onClicked: root.back()
            }

            SectionHeader {
                title: "Modules (" + root.totalCount + ")"
                subtitle: "The installation's own modules: what is defined, and what is up. "
                          + "Transfer servers and applications are run the same way but are not modules - "
                          + "they are controlled from the ETS and EAP pages."
            }

            // Shown instead of the table rather than beside it: an empty table under a permission
            // message reads like there are no modules.
            Rectangle {
                width: parent.width
                height: 120
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                visible: !root.isAdmin

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "The module registry is only shown to administrators."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }

            DataTable {
                width: parent.width
                visible: root.isAdmin
                columns: root.columns
                // One page: list-modules returns everything at once, so there is no size to pick.
                pageSizeSelectable: false
                rows: root.modules
                totalCount: root.totalCount
                // One page: "list-modules" returns every module at once.
                pageSize: root.totalCount > 0 ? root.totalCount : 1
                pageIndex: 0
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by module name..."
                emptyText: root.prefix.length > 0 ? "No module matches that name." : "No modules registered."
                onSearchChanged: (text) => root.prefix = text
                onRefreshRequested: root.refresh()

                // What EMM will accept for the row decides what is offered: start and stop only
                // for a core euclid module, restart only for one that is not stopped. Saying so as
                // a greyed-out item beats being refused after the click.
                rowsClickable: true
                onRowClicked: (row) => root.openModuleDetails(row.name, row)

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function(row) { root.openModuleDetails(row.name, row) }
                    },
                    {
                        text: "Start",
                        enabled: function(row) { return !!row && row.core && row.desiredStopped },
                        action: function(row) { emmClient.startModule(row.name) }
                    },
                    {
                        text: "Stop",
                        // EMM refuses to stop itself: there would be nothing left to start it again.
                        enabled: function(row) { return !!row && row.core && !row.desiredStopped && row.name !== "emm" },
                        action: function(row) { emmClient.stopModule(row.name) }
                    },
                    {
                        text: "Restart",
                        // Allowed for applications and transfer servers too - it changes no desired
                        // state, so nothing of EAP's or ETS's is contradicted by it.
                        enabled: function(row) { return !!row && !row.desiredStopped },
                        action: function(row) { emmClient.restartModule(row.name) }
                    },
                    {
                        text: "Scale Up…",
                        enabled: function(row) { return !!row && !row.desiredStopped },
                        action: function(row) { scaleDialog.openFor(row, root.scaleUpSuggestion(row)) }
                    },
                    {
                        text: "Scale Down…",
                        enabled: function(row) { return !!row && !row.desiredStopped && root.pendingMin(row) > 1 },
                        action: function(row) { scaleDialog.openFor(row, root.scaleDownSuggestion(row)) }
                    },
                    {
                        text: "Set threads…",
                        action: function(row) { threadsDialog.openFor(row) }
                    }
                ]
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#4cd97b"
                font.pixelSize: 12
                visible: root.isAdmin && root.actionNote.length > 0
                text: root.actionNote
            }
        }
    }
}
