import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// What a rule has actually done, for the one series the alerts table was right-clicked on. The
// table itself only says where that series stands now; this is the record of it getting there -
// one row per state change, with the figure and the line that decided it.
//
// EMO keeps the history per rule rather than per series, and "list-alert-history" filters by rule
// and by time only. A rule judging several series therefore answers with all of them mixed
// together, and picking out the one that was clicked is this dialog's job, not the server's - see
// matchesSeries() and the "Show all series" switch, which is there because a rule that has never
// fired for this series but has for a sibling is worth being able to see rather than reading as an
// empty history.
Dialog {
    id: root

    property string ruleId: ""
    property string metricName: ""
    // The clicked row's label map, e.g. {host: "node-a", interval: "1m"}. The history is narrowed
    // to the transitions carrying exactly these.
    property var seriesLabels: ({})

    property bool loading: false
    property string errorText: ""
    property var transitions: []
    property bool showAllSeries: false

    function labelText(labels) {
        const keys = Object.keys(labels || {})
        if (keys.length === 0) return "—"
        return keys.sort().map(k => k + "=" + labels[k]).join(", ")
    }

    // Exact match on the whole label set rather than a subset: two series of one rule can differ by
    // a single label, and a subset test would fold them together.
    function matchesSeries(labels) {
        const want = root.seriesLabels || {}
        const got = labels || {}
        const wantKeys = Object.keys(want)
        if (wantKeys.length !== Object.keys(got).length) return false
        return wantKeys.every(k => String(got[k]) === String(want[k]))
    }

    readonly property var seriesTransitions: root.transitions.filter(t => root.matchesSeries(t.labels))
    readonly property var shownTransitions: root.showAllSeries ? root.transitions : root.seriesTransitions

    // Paging, filtering and sorting are all client-side: the server answers with one block and has
    // no paged read of a history, so the table is handed a page out of what is already in hand.
    property string filter: ""
    property int pageIndex: 0
    property int pageSize: 10
    // Newest first, which is the order the server returns them in and the one this is read in.
    property string sortColumn: "timestamp"
    property bool sortAscending: false

    readonly property var filteredTransitions: {
        const needle = root.filter.toLowerCase()
        const matched = needle.length === 0 ? root.shownTransitions.slice() : root.shownTransitions.filter(t =>
            String(t.state).toLowerCase().indexOf(needle) >= 0
            || String(t.previous).toLowerCase().indexOf(needle) >= 0
            || String(t.reason).toLowerCase().indexOf(needle) >= 0
            || root.labelText(t.labels).toLowerCase().indexOf(needle) >= 0)

        const key = root.sortColumn
        const direction = root.sortAscending ? 1 : -1
        return matched.sort((a, b) => {
            const left = a[key]
            const right = b[key]
            // value and threshold are numbers and have to compare as such - as text, 9 sorts after
            // 100. A timestamp is ISO 8601, which orders correctly either way.
            if (typeof left === "number" && typeof right === "number") return (left - right) * direction
            return String(left).localeCompare(String(right)) * direction
        })
    }

    readonly property int pageCount: Math.max(1, Math.ceil(root.filteredTransitions.length / root.pageSize))
    readonly property int clampedPage: Math.min(root.pageIndex, root.pageCount - 1)
    readonly property var page: root.filteredTransitions.slice(
        root.clampedPage * root.pageSize,
        root.clampedPage * root.pageSize + root.pageSize)

    onFilteredTransitionsChanged: {
        if (root.pageIndex > root.pageCount - 1)
            root.pageIndex = root.pageCount - 1
    }

    function levelColor(level) {
        if (level === "CRITICAL") return "#ff4f5e"
        if (level === "WARNING") return "#ffb545"
        if (level === "OK") return "#4cd97b"
        if (level === "NO_DATA") return "#9aa1ac"
        return "#c4c9d1"
    }

    function numberText(v) {
        if (v === undefined || v === null || v === "") return "—"
        const n = Number(v)
        if (isNaN(n)) return String(v)
        return Math.abs(n) >= 100 ? n.toFixed(0) : n.toFixed(2)
    }

    readonly property var columns: [
        {
            title: "When",
            key: "timestamp",
            tooltip: "When the series changed state. Newest first, as the server returns them.",
            formatter: function (v) { return DateFormat.format(v) }
        },
        {
            title: "Change",
            key: "state",
            tooltip: "What the series moved from and to. The arrival state is what colours the row.",
            formatter: function (v, row) {
                return (row && row.previous ? String(row.previous) : "—") + "  →  " + String(v)
            },
            colorFor: function (v) { return root.levelColor(String(v)) }
        },
        {
            title: "Value",
            key: "value",
            tooltip: "The figure that caused the change.",
            formatter: function (v) { return root.numberText(v) }
        },
        {
            title: "Threshold",
            key: "threshold",
            tooltip: "The line the value was judged against. Empty where the change was not a "
                     + "threshold crossing - a series going quiet has no line to cross.",
            formatter: function (v) { return root.numberText(v) }
        },
        {
            title: "Statistic",
            key: "statistic",
            tooltip: "How the samples in the window were reduced before being compared - the rule's "
                     + "own setting, repeated here because a rule can be edited after the fact."
        },
        {
            title: "Series",
            key: "labels",
            // Only worth a column when more than one series is on screen; it is the same value on
            // every row otherwise.
            hidden: !root.showAllSeries,
            sortable: false,
            tooltip: "Which series of the rule this change belongs to.",
            formatter: function (v) { return root.labelText(v) }
        },
        {
            title: "Reason",
            key: "reason",
            fill: true,
            sortable: false,
            tooltip: "What the server recorded about the change, in its own words."
        }
    ]

    function reload() {
        if (root.ruleId.length === 0) return
        root.loading = true
        root.errorText = ""
        emoClient.fetchAlertHistory(root.ruleId)
    }

    modal: true
    anchors.centerIn: parent
    width: Math.min(1100, parent ? parent.width - 80 : 1100)
    padding: 28
    topPadding: 24
    bottomPadding: 24
    standardButtons: Dialog.NoButton

    background: Rectangle {
        radius: 16
        color: "#1b1e25"
        border.color: "#2c313c"
        border.width: 1
    }

    onOpened: {
        root.transitions = []
        root.filter = ""
        root.pageIndex = 0
        root.showAllSeries = false
        root.reload()
    }

    Connections {
        target: emoClient
        function onAlertHistoryLoaded(ruleId, list) {
            if (ruleId !== root.ruleId) return
            root.loading = false
            root.transitions = list
            root.errorText = ""
        }
        function onAlertHistoryFailed(ruleId, message) {
            if (ruleId !== root.ruleId) return
            root.loading = false
            root.errorText = message
        }
    }

    contentItem: Column {
        width: root.availableWidth
        spacing: 16

        Column {
            width: parent.width
            spacing: 4
            Text { text: "Alert History"; color: "white"; font.pixelSize: 18; font.bold: true }
            Text {
                width: parent.width
                text: root.metricName + "  ·  " + root.labelText(root.seriesLabels)
                color: "#9aa1ac"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: "Rule " + root.ruleId + ". Kept for as long as the installation's alert history "
                      + "retention allows (90 days as shipped), so an old alert can run out of "
                      + "history while its rule is still here."
                color: "#6b7280"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }

        Row {
            width: parent.width
            spacing: 10

            ToggleSwitch {
                id: allSeriesSwitch
                anchors.verticalCenter: parent.verticalCenter
                checked: root.showAllSeries
                onToggled: (checked) => {
                    root.showAllSeries = checked
                    root.pageIndex = 0
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Show every series this rule judges"
                color: "#c4c9d1"
                font.pixelSize: 12
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Said out loud rather than left to be inferred from a switch: a history that is
                // empty for this series but not for the rule is the case this exists for.
                text: root.showAllSeries
                      ? root.transitions.length + " change(s) across the whole rule"
                      : root.seriesTransitions.length + " of " + root.transitions.length
                        + " change(s) are this series"
                color: "#6b7280"
                font.pixelSize: 11
            }
        }

        DataTable {
            width: parent.width
            columns: root.columns
            rows: root.page
            totalCount: root.filteredTransitions.length
            pageSize: root.pageSize
            pageIndex: root.clampedPage
            loading: root.loading
            error: root.errorText
            searchPlaceholder: "Filter by state, reason or series..."
            emptyText: root.filter.length > 0
                       ? "No change matches that."
                       : (root.showAllSeries
                          ? "This rule has recorded no state changes."
                          : "This series has recorded no state changes. Turn on \"every series\" above to see the rule's own.")
            rowsClickable: false
            sortKey: root.sortColumn
            sortAscending: root.sortAscending

            onSearchChanged: (text) => {
                root.filter = text
                root.pageIndex = 0
            }
            onRefreshRequested: root.reload()
            onPageChanged: (index) => { root.pageIndex = index }
            onPageSizeRequested: (size) => {
                root.pageSize = size
                root.pageIndex = 0
            }
            onSortRequested: (key, ascending) => {
                root.sortColumn = key
                root.sortAscending = ascending
            }
        }

        Button {
            text: "Close"
            anchors.right: parent.right
            highlighted: true
            Material.theme: Material.Dark
            Material.accent: "#4f8cff"
            onClicked: root.close()
        }
    }
}
