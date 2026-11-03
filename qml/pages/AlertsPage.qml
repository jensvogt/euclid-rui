import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// Where every series an EMO alert rule judges stands right now - one row per rule and series, the
// way "euclid-cli emo list-alerts" prints it - plus one row per disabled rule.
//
// The disabled rules are there because a state is not something to switch: what the context menu
// turns on and off is the rule, and a rule switched off has no series in "list-alerts" at all
// (the server retires them). Without a row of its own it would vanish from the page the moment it
// was deactivated, and there would be nothing left to right-click to bring it back.
//
// Administrators only, as the server has it: a rule reads the installation's metrics, not an
// account's.
Item {
    id: root
    property bool loggedIn: false

    // "list-alerts" and "list-alert-rules" as they came.
    property var series: []
    property var rules: []

    property int pending: 0
    readonly property bool loading: pending > 0
    property string error: ""
    property string lastUpdatedText: "—"

    signal openRuleDetails(string ruleId)

    // What the last activate or deactivate did, kept beside the table: a deactivated rule's rows
    // turn into one DISABLED row, and nothing on it says that was the change just asked for.
    property string actionNote: ""

    // The table's rows: every series, each marked as belonging to an enabled rule (a disabled one
    // has none), and a stand-in row for each disabled rule.
    readonly property var alerts: {
        const rows = root.series.map(s => Object.assign({ enabled: true }, s))
        const judged = {}
        for (const s of root.series) judged[s.ruleId] = true
        for (const rule of root.rules) {
            const disabled = rule.enabled === false
            // An enabled rule with series is already on screen through them. One without is new
            // (nothing judged until the next period's flush) or matches nothing that reports -
            // either way it gets a PENDING row, or a rule just added would not show at all.
            if (!disabled && judged[rule.ruleId]) continue
            rows.push({
                ruleId: rule.ruleId,
                name: rule.name,
                labels: rule.labels,
                state: disabled ? "DISABLED" : "PENDING",
                comparison: rule.comparison,
                warning: rule.warning,
                critical: rule.critical,
                description: rule.description,
                enabled: !disabled
            })
        }
        return rows
    }

    readonly property int disabledCount: root.rules.filter(r => r.enabled === false).length

    function isFiring(state) {
        return state === "CRITICAL" || state === "WARNING" || state === "NO_DATA"
    }

    // One state, or "everything that is firing". Applied here rather than sent to the server: the
    // listing is small, and only the unfiltered one says how many series there are in all - which
    // is what turns an empty "firing" view into "all N are OK" instead of a blank table.
    property string stateFilter: ""
    property bool firingOnly: false

    // The search field. Matched here, like the filters above, against what a row shows rather than
    // by prefix on one key as the server-paged tables do: someone looking for a host's alerts types
    // the host, which is in the series column, not at the start of the rule id.
    property string searchText: ""

    function matchesSearch(row) {
        const needle = root.searchText.trim().toLowerCase()
        if (needle.length === 0) return true
        const hay = [row.ruleId, row.name, root.labelText(row.labels), row.description, root.stateText(row.state)]
        return hay.some(h => String(h || "").toLowerCase().indexOf(needle) >= 0)
    }

    readonly property var visibleAlerts: root.alerts.filter(function (a) {
        if (root.firingOnly && !root.isFiring(a.state)) return false
        if (root.stateFilter.length > 0 && a.state !== root.stateFilter) return false
        return root.matchesSearch(a)
    })

    // Paged here too: the table is handed one page, as every other table is.
    property int pageIndex: 0
    property int pageSize: 10
    readonly property var pagedAlerts: root.sortedAlerts.slice(root.pageIndex * root.pageSize,
                                                               (root.pageIndex + 1) * root.pageSize)

    // A refresh, a filter or a deactivation can leave fewer pages than the one being shown; step
    // back to the last one rather than show an empty page with rows behind it.
    onVisibleAlertsChanged: {
        const last = Math.max(0, Math.ceil(root.visibleAlerts.length / root.pageSize) - 1)
        if (root.pageIndex > last) root.pageIndex = last
    }
    onStateFilterChanged: pageIndex = 0
    onFiringOnlyChanged: pageIndex = 0

    // Sorted here, since the listing comes back in one piece. Default: worst first, which is the
    // question anyone opening this page is asking.
    property string sortKey: "state"
    property bool sortAscending: true

    readonly property var stateRank: ({ "CRITICAL": 0, "WARNING": 1, "NO_DATA": 2, "OK": 3, "PENDING": 4, "DISABLED": 5 })

    function stateColor(state) {
        if (state === "CRITICAL") return "#ff6b6b"
        if (state === "WARNING") return "#ffb545"
        if (state === "NO_DATA") return "#9aa1ac"
        if (state === "OK") return "#4cd97b"
        if (state === "DISABLED") return "#6b7280"
        if (state === "PENDING") return "#4f8cff"
        return "#9aa1ac"
    }

    function stateText(state) {
        return state === "NO_DATA" ? "NO DATA" : (state || "—")
    }

    function labelText(labels) {
        const keys = Object.keys(labels || {})
        if (keys.length === 0) return "—"
        return keys.sort().map(k => k + "=" + labels[k]).join(", ")
    }

    function numberText(v) {
        if (v === undefined || v === null || v === "") return "—"
        const n = Number(v)
        if (isNaN(n)) return String(v)
        return Math.abs(n) >= 100 ? n.toFixed(0) : n.toFixed(2)
    }

    // "above 80 / 90": the direction and both lines, so a value can be read against them without
    // looking the rule up.
    function thresholdText(row) {
        if (!row) return "—"
        const w = row.warning === undefined || row.warning === null ? "—" : root.numberText(row.warning)
        const c = row.critical === undefined || row.critical === null ? "—" : root.numberText(row.critical)
        return (row.comparison || "").toLowerCase() + " " + w + " / " + c
    }

    function sortValue(row, key) {
        if (key === "state") return root.stateRank[row.state] !== undefined ? root.stateRank[row.state] : 9
        if (key === "value") return row.value === undefined ? -Infinity : Number(row.value)
        if (key === "labels") return root.labelText(row.labels)
        const v = row[key]
        return v === undefined || v === null ? "" : String(v)
    }

    readonly property var sortedAlerts: {
        const key = root.sortKey
        const dir = root.sortAscending ? 1 : -1
        return root.visibleAlerts.slice().sort(function (a, b) {
            const va = root.sortValue(a, key)
            const vb = root.sortValue(b, key)
            if (va < vb) return -dir
            if (va > vb) return dir
            // Ties fall back to rule and series, so the order is stable between refreshes.
            const ra = a.ruleId + "|" + root.labelText(a.labels)
            const rb = b.ruleId + "|" + root.labelText(b.labels)
            return ra < rb ? -1 : (ra > rb ? 1 : 0)
        })
    }

    readonly property var columns: [
        {
            title: "State",
            key: "state",
            tooltip: "What the rule currently judges. NO_DATA means the series stopped reporting, "
                     + "which is not the same as being within threshold; DISABLED means the rule "
                     + "is judging nothing at all.",
            formatter: function (v) { return root.stateText(v) },
            colorFor: function (v) { return root.stateColor(v) }
        },
        {
            title: "Rule",
            key: "ruleId",
            tooltip: "The alert rule this row comes from. One rule produces a row per series it "
                     + "matches."
        },
        {
            title: "Metric",
            key: "name",
            tooltip: "The metric the rule watches."
        },
        {
            // For a disabled rule, its selector rather than a series: it judges none right now.
            title: "Series",
            key: "labels",
            fill: true,
            tooltip: "Which series of the metric this row judges, by its labels. For a disabled "
                     + "rule it is the selector instead, since the rule is judging none right now.",
            formatter: function (v) { return root.labelText(v) },
            colorFor: function (v) { return root.labelText(v) === "—" ? "#6b7280" : "#c4c9d1" }
        },
        {
            title: "Value",
            key: "value",
            // Meaningless for a series that stopped reporting - it is the last figure, not a
            // current one - and absent for a disabled rule.
            tooltip: "The figure the rule last judged. Shown as a dash where it would mislead: a "
                     + "series that stopped reporting has only its last value, not a current one.",
            formatter: function (v, row) {
                return row && (row.state === "NO_DATA" || row.state === "DISABLED" || row.state === "PENDING") ? "—" : root.numberText(v)
            }
        },
        {
            title: "Threshold",
            key: "warning",
            sortable: false,
            tooltip: "The levels the value is compared against. Not sortable: it is composed from "
                     + "the rule's warning and critical levels rather than being one field.",
            formatter: function (v, row) { return root.thresholdText(row) }
        },
        {
            title: "Since",
            key: "since",
            tooltip: "When this row entered the state it is in now - how long the alert has been "
                     + "firing, rather than when the rule was written.",
            formatter: function (v) { return v ? DateFormat.format(v) : "—" }
        },
        {
            title: "Last seen",
            key: "lastSeen",
            tooltip: "When the series last reported a sample. An old timestamp here is what NO_DATA "
                     + "is made of.",
            formatter: function (v) { return v ? DateFormat.format(v) : "—" }
        }
    ]

    readonly property int activeCount: root.series.filter(a => root.isFiring(a.state)).length

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view alerts."
            return
        }
        if (!euclidClient.isAdmin) {
            error = "Alerts are visible to administrators only."
            series = []
            rules = []
            return
        }
        // Set, not added to: a refresh started while one is in flight supersedes it, and the
        // counter only has to reach zero once both of the latest answers are in.
        pending = 2
        error = ""
        emoClient.fetchAlerts()
        emoClient.fetchAlertRules()
    }

    function settle() {
        root.pending = Math.max(0, root.pending - 1)
        if (root.pending === 0) root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
    }

    // What the table shows when it is empty and the reason is the filter, not the server.
    function filteredEmptyText() {
        if (root.searchText.trim().length > 0)
            return "No alerts match '" + root.searchText.trim() + "'."
        const total = root.series.length
        const all = total === 1 ? "the one series is" : "all " + total + " series are"
        if (root.firingOnly && root.activeCount === 0)
            return total === 0 ? "Nothing is firing." : "Nothing is firing — " + all + " OK."
        if (root.stateFilter === "PENDING")
            return "Every enabled rule has judged at least one series."
        if (root.stateFilter === "DISABLED")
            return "No rule is disabled."
        if (root.stateFilter.length > 0)
            return "No series is " + root.stateText(root.stateFilter) + "."
        return "No alerts match the filter."
    }

    onVisibleChanged: {
        if (visible) refresh()
        else actionNote = ""
    }
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.liveListUpdates && appSettings.autoRefreshSeconds > 0
                 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    // Whether the session is an administrator's can be learned after loggedIn flips.
    Connections {
        target: euclidClient
        function onIsAdminChanged() { if (root.visible && root.loggedIn) root.refresh() }
    }

    Connections {
        target: emoClient
        function onAlertsLoaded(list) {
            root.series = list
            root.settle()
        }
        function onAlertsFailed(message) {
            root.error = message
            root.settle()
        }
        function onAlertRulesLoaded(list) {
            root.rules = list
            root.settle()
        }
        function onAlertRulesFailed(message) {
            root.error = message
            root.settle()
        }
        function onAlertRuleEnabledChanged(ruleId, enabled) {
            // The details page switches rules too; what it did is said there.
            if (!root.visible) return
            // Said in full, because the switch is wider than the row it was used on: it is the
            // rule, and with it every series the rule judges.
            root.actionNote = enabled
                ? "Rule '" + ruleId + "' activated. Its series are judged again from the next period, "
                  + "and appear here once they have been."
                : "Rule '" + ruleId + "' deactivated. None of its series are judged any more, and any that "
                  + "were firing have been cleared."
            root.refresh()
        }
        function onAlertRuleEnabledFailed(ruleId, message) {
            root.error = "Could not change rule '" + ruleId + "': " + message
        }
    }

    // What "list-metrics" returned, for the Add dialog's metric picker. Fetched when the dialog
    // opens rather than with the list: it is only needed to write a rule.
    property var metrics: []

    Dialog {
        id: createRuleDialog
        modal: true
        anchors.centerIn: parent
        width: Math.min(760, root.width - 48)
        height: Math.min(implicitHeight, root.height - 48)
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool creating: false
        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            createForm.load({})
            createRuleDialog.errorText = ""
            createRuleDialog.creating = false
            emoClient.fetchMetrics()
        }

        // However it closed - created, cancelled, Escape - the table is re-read, so a rule added
        // here (or by anybody else in the meantime) is on screen as soon as the dialog is gone.
        onClosed: root.refresh()

        contentItem: ScrollView {
            id: createScroll
            contentWidth: availableWidth
            clip: true

            Column {
                width: createScroll.availableWidth
                spacing: 20

                Column {
                    width: parent.width
                    spacing: 4
                    Text { text: "Add Alert"; color: "white"; font.pixelSize: 18; font.bold: true }
                    Text {
                        text: "A threshold rule on one metric. Each series it matches gets a state of its own, "
                              + "judged at every period's flush; a change of state is published as emo.alert.raised "
                              + "or emo.alert.cleared."
                        color: "#9aa1ac"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }

                AlertRuleForm {
                    id: createForm
                    width: parent.width
                    createMode: true
                    metrics: root.metrics
                    existingRuleIds: root.rules.map(r => r.ruleId)
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 12
                    color: createRuleDialog.errorText.length > 0 ? "#ff6b6b" : "#ffb545"
                    visible: text.length > 0
                    text: createRuleDialog.errorText.length > 0 ? createRuleDialog.errorText : createForm.validationError
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
                        onClicked: createRuleDialog.close()
                    }

                    BusyIndicator {
                        running: createRuleDialog.creating
                        visible: createRuleDialog.creating
                        width: 22
                        height: 22
                        anchors.right: createButton.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Button {
                        id: createButton
                        text: "Create"
                        highlighted: true
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        enabled: !createRuleDialog.creating && createForm.valid
                        onClicked: {
                            createRuleDialog.errorText = ""
                            createRuleDialog.creating = true
                            emoClient.createAlertRule(createForm.values())
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: emoClient
        function onMetricsLoaded(list) {
            root.metrics = list
        }
        function onAlertRuleCreated(ruleId, rule) {
            if (!createRuleDialog.opened) return
            createRuleDialog.creating = false
            createRuleDialog.close()
            root.actionNote = "Rule '" + ruleId + "' created. "
                + (rule.enabled === false
                   ? "It is disabled, so it shows as one DISABLED row until it is activated."
                   : "Its series appear here once it has judged a row of them, at the next period's flush.")
            // No refresh here: closing the dialog does it (onClosed).
        }
        function onAlertRuleCreateFailed(ruleId, message) {
            if (!createRuleDialog.opened) return
            createRuleDialog.creating = false
            createRuleDialog.errorText = message
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

            Breadcrumb {
                width: parent.width
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    width: parent.width - addButton.width - 16
                    title: "Alerts (" + root.series.length + ")"
                    subtitle: (root.series.length === 0
                               ? "No series is being judged by an alert rule."
                               : root.activeCount === 0
                                 ? "Every series is OK."
                                 : root.activeCount + " of " + root.series.length + " series need attention.")
                              + (root.disabledCount === 0 ? ""
                                 : " " + root.disabledCount + (root.disabledCount === 1 ? " rule is" : " rules are")
                                   + " disabled.")
                }

                Button {
                    id: addButton
                    text: "+ Add Alert"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createRuleDialog.open()
                }
            }

            Row {
                spacing: 24

                Row {
                    spacing: 10
                    Text {
                        text: "State"
                        color: "#9aa1ac"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    ComboBox {
                        id: stateCombo
                        width: 160
                        implicitHeight: 36
                        // "All" is no filter; the rest are the state values themselves.
                        model: ["All", "CRITICAL", "WARNING", "NO_DATA", "OK", "PENDING", "DISABLED"]
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onActivated: root.stateFilter = currentIndex === 0 ? "" : currentText
                    }
                }

                Row {
                    spacing: 10
                    ToggleSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: root.firingOnly
                        onToggled: (checked) => root.firingOnly = checked
                    }
                    Text {
                        // "Firing", not "active": a rule that is switched on is also active, and
                        // this hides the series that are OK, not the rules that are disabled.
                        text: "Firing only (not OK)"
                        color: "#9aa1ac"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.pagedAlerts
                totalCount: root.visibleAlerts.length
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by rule, metric, label or state..."
                onSearchChanged: (text) => {
                    root.searchText = text
                    root.pageIndex = 0
                }
                onPageChanged: (index) => root.pageIndex = index
                onPageSizeRequested: (size) => {
                    root.pageSize = size
                    root.pageIndex = 0
                }
                emptyText: root.alerts.length > 0
                           ? root.filteredEmptyText()
                           : "No alerts. A series appears once a rule has judged a row of it."
                sortKey: root.sortKey
                sortAscending: root.sortAscending
                onSortRequested: (key, ascending) => {
                    root.sortKey = key
                    root.sortAscending = ascending
                    root.pageIndex = 0
                }
                onRefreshRequested: root.refresh()
                rowsClickable: true
                onRowClicked: (row) => root.openRuleDetails(row.ruleId)

                contextMenuActions: [
                    {
                        text: "Edit rule…",
                        action: function (row) { root.openRuleDetails(row.ruleId) }
                    },
                    {
                        // Two entries rather than one that changes meaning with the row: each is
                        // greyed out when the rule is already in that state, which also says which
                        // state it is in before anything is clicked.
                        text: "Deactivate rule",
                        enabled: function (row) { return !!row && row.enabled === true },
                        action: function (row) {
                            root.actionNote = ""
                            root.error = ""
                            emoClient.setAlertRuleEnabled(row.ruleId, false)
                        }
                    },
                    {
                        text: "Activate rule",
                        enabled: function (row) { return !!row && row.enabled === false },
                        action: function (row) {
                            root.actionNote = ""
                            root.error = ""
                            emoClient.setAlertRuleEnabled(row.ruleId, true)
                        }
                    }
                ]
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#4cd97b"
                font.pixelSize: 12
                visible: root.actionNote.length > 0
                text: root.actionNote
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "Activating and deactivating applies to the rule, and so to every series it judges, not "
                      + "only the row it was done from. Last seen is the start of the period the last row covers; "
                      + "a series whose last seen is falling behind has stopped reporting. NO DATA is raised only "
                      + "by rules that set a no-data period. PENDING is a rule that has not judged a series yet - "
                      + "new until the next period's flush, or matching nothing that reports."
            }
        }
    }
}
