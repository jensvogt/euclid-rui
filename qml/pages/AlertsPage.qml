import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// Where every series an EMO alert rule judges stands right now - one row per rule and series, the
// way "euclid-cli emo list-alerts" prints it. Read-only: rules are written elsewhere, and a state
// is the evaluator's to change, not anybody's to edit.
//
// Administrators only, as the server has it: a rule reads the installation's metrics, not an
// account's.
Item {
    id: root
    property bool loggedIn: false

    property var alerts: []
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    // One state, or "everything that is not OK". Applied here rather than sent to the server: the
    // listing is small, and only the unfiltered one says how many series there are in all - which
    // is what turns an empty "firing" view into "all N are OK" instead of a blank table.
    property string stateFilter: ""
    property bool firingOnly: false

    readonly property var visibleAlerts: root.alerts.filter(function (a) {
        if (root.firingOnly && a.state === "OK") return false
        if (root.stateFilter.length > 0 && a.state !== root.stateFilter) return false
        return true
    })

    // Sorted here, since the listing comes back in one piece. Default: worst first, which is the
    // question anyone opening this page is asking.
    property string sortKey: "state"
    property bool sortAscending: true

    readonly property var stateRank: ({ "CRITICAL": 0, "WARNING": 1, "NO_DATA": 2, "OK": 3 })

    function stateColor(state) {
        if (state === "CRITICAL") return "#ff6b6b"
        if (state === "WARNING") return "#ffb545"
        if (state === "NO_DATA") return "#9aa1ac"
        if (state === "OK") return "#4cd97b"
        return "#9aa1ac"
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
        if (key === "value") return Number(row.value)
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
            formatter: function (v) { return v === "NO_DATA" ? "NO DATA" : (v || "—") },
            colorFor: function (v) { return root.stateColor(v) }
        },
        { title: "Rule", key: "ruleId" },
        { title: "Metric", key: "name" },
        {
            title: "Series",
            key: "labels",
            fill: true,
            formatter: function (v) { return root.labelText(v) },
            colorFor: function (v) { return root.labelText(v) === "—" ? "#6b7280" : "#c4c9d1" }
        },
        {
            title: "Value",
            key: "value",
            // Meaningless for a series that stopped reporting: it is the last figure, not a current one.
            formatter: function (v, row) { return row && row.state === "NO_DATA" ? "—" : root.numberText(v) }
        },
        {
            title: "Threshold",
            key: "warning",
            sortable: false,
            formatter: function (v, row) { return root.thresholdText(row) }
        },
        { title: "Since", key: "since", formatter: function (v) { return v ? DateFormat.format(v) : "—" } },
        { title: "Last seen", key: "lastSeen", formatter: function (v) { return v ? DateFormat.format(v) : "—" } }
    ]

    readonly property int activeCount: root.alerts.filter(a => a.state !== "OK").length

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view alerts."
            return
        }
        if (!euclidClient.isAdmin) {
            error = "Alerts are visible to administrators only."
            alerts = []
            return
        }
        loading = true
        error = ""
        emoClient.fetchAlerts()
    }

    // What the table shows when it is empty and the reason is the filter, not the server.
    function filteredEmptyText() {
        const total = root.alerts.length
        const all = total === 1 ? "the one series is" : "all " + total + " series are"
        if (root.firingOnly && root.activeCount === 0)
            return "Nothing is firing — " + all + " OK."
        if (root.stateFilter.length > 0)
            return "No series is " + (root.stateFilter === "NO_DATA" ? "NO DATA" : root.stateFilter)
                   + (root.firingOnly ? " and firing" : "") + "."
        return "No alerts match the filter."
    }

    onVisibleChanged: if (visible) refresh()
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
            root.loading = false
            root.error = ""
            root.alerts = list
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onAlertsFailed(message) {
            root.loading = false
            root.error = message
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

            SectionHeader {
                width: parent.width
                title: "Alerts (" + root.alerts.length + ")"
                subtitle: root.alerts.length === 0
                          ? "No series is being judged by an alert rule."
                          : root.activeCount === 0
                            ? "Every series is OK."
                            : root.activeCount + " of " + root.alerts.length + " series need attention."
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
                        // Display text vs. what the server is sent; "All" is no filter.
                        model: ["All", "CRITICAL", "WARNING", "NO_DATA", "OK"]
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
                rows: root.sortedAlerts
                totalCount: root.visibleAlerts.length
                // One page: "list-alerts" returns everything at once.
                pageSizeSelectable: false
                pageSize: root.visibleAlerts.length > 0 ? root.visibleAlerts.length : 1
                pageIndex: 0
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchable: false
                emptyText: root.alerts.length > 0
                           ? root.filteredEmptyText()
                           : "No alerts. A series appears once a rule has judged a row of it."
                sortKey: root.sortKey
                sortAscending: root.sortAscending
                onSortRequested: (key, ascending) => {
                    root.sortKey = key
                    root.sortAscending = ascending
                }
                onRefreshRequested: root.refresh()
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "Last seen is the start of the period the last row covers; a series whose last seen is "
                      + "falling behind has stopped reporting. NO DATA is raised only by rules that set a "
                      + "no-data period."
            }
        }
    }
}
