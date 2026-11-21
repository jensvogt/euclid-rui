import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// The machines behind the dashboard's System Load gauges, one row each. The dashboard folds every
// host into one average; this is the same four metrics left apart - the newest sample of each,
// per "host" label - so the one busy worker that an average of five hides is the one on top.
Item {
    id: root
    property bool loggedIn: false

    // What each metric said last, per host: {host: {value, maxValue, timestamp}}.
    property var cpu: ({})
    property var memory: ({})
    property var loadPerCore: ({})
    property var queuePerCore: ({})
    property int pending: 0
    // EAP's worker nodes by lowercased name, so a host that is one can open its node page. The
    // manager's machine reports load as well and is no node - its row stays where it is.
    property var nodes: ({})

    signal openNodeDetails(string nodeName, var details)
    property string error: ""
    property string lastUpdatedText: "—"

    property string filterText: ""
    property string filterMatchType: "contains"
    property string sortKey: "cpu"
    property bool sortAscending: false

    readonly property var metrics: ["system-cpu-usage", "system-memory-usage-percent",
                                    "system-load-per-core", "system-processor-queue-per-core"]

    // A host that has not reported for this long is shown greyed out: it may be stopped, or its
    // collector may be - either way the figures beside it are history, not load.
    //
    // Three averaging periods. EMO writes a row only when its period closes (average-period, five
    // minutes as shipped) and stamps it with the period's start, so a healthy host's newest sample
    // is always between one and two periods old - and a little more while the write is on its way.
    // Two periods would flag every host for a moment each cycle; three means one was missed.
    readonly property int staleSeconds: 900

    function sampleOf(map, host) {
        const s = map[host]
        return s === undefined ? null : s
    }

    // One row per host that reported any of the four. Load is load-per-core where the platform has
    // a load average, and processor queue per core where it does not (Windows) - the same choice
    // the dashboard gauge makes, made here per machine.
    readonly property var rows: {
        const hosts = {}
        for (const map of [root.cpu, root.memory, root.loadPerCore, root.queuePerCore])
            for (const host in map) hosts[host] = true

        const now = Date.now()
        const list = []
        for (const host in hosts) {
            const c = root.sampleOf(root.cpu, host)
            const m = root.sampleOf(root.memory, host)
            const l = root.sampleOf(root.loadPerCore, host)
            const q = root.sampleOf(root.queuePerCore, host)
            const load = l !== null ? l : q
            let newest = ""
            for (const s of [c, m, l, q])
                if (s !== null && String(s.timestamp) > newest) newest = String(s.timestamp)
            const ageSeconds = newest.length > 0 ? (now - Date.parse(newest)) / 1000 : Infinity
            list.push({
                host: host,
                cpu: c !== null ? c.value : -1,
                cpuPeak: c !== null ? c.maxValue : -1,
                memory: m !== null ? m.value : -1,
                load: load !== null ? load.value : -1,
                loadIsQueue: l === null && q !== null,
                lastSeen: newest,
                stale: ageSeconds > root.staleSeconds,
                node: root.nodes[host.toLowerCase()] || null
            })
        }

        const matched = list.filter(r => TextMatch.matches(r.host, root.filterText, root.filterMatchType, true))
        const key = root.sortKey
        const dir = root.sortAscending ? 1 : -1
        matched.sort((a, b) => {
            const av = a[key], bv = b[key]
            if (av === bv) return a.host.localeCompare(b.host)
            return (av < bv ? -1 : 1) * dir
        })
        return matched
    }

    // Amber with no headroom left, red when work is waiting - the dashboard gauge's thresholds.
    function percentColor(v) {
        if (v < 0) return "#6b7280"
        if (v >= 90) return "#ff6b6b"
        if (v >= 75) return "#ffb545"
        return "#c4c9d1"
    }
    function loadColor(v, row) {
        if (v < 0) return "#6b7280"
        const saturation = row && row.loadIsQueue ? 2 : 1
        if (v >= saturation) return "#ff6b6b"
        if (v >= saturation * 0.8) return "#ffb545"
        return "#c4c9d1"
    }

    readonly property var columns: [
        {
            title: "Host",
            key: "host",
            fill: true,
            tooltip: "The machine, as its collector names itself.",
            colorFor: function (v, row) { return row && row.stale ? "#6b7280" : "white" }
        },
        {
            title: "Role",
            key: "node",
            sortable: false,
            tooltip: "\"Worker node\" when the host is registered with EAP - click the row for its node page. "
                     + "Anything else reporting load is shown too, the manager's machine among them.",
            formatter: function (v) { return v ? "Worker node" : "—" },
            colorFor: function (v) { return v ? "#4f8cff" : "#6b7280" }
        },
        {
            title: "CPU",
            key: "cpu",
            tooltip: "CPU in use across all cores, newest sample.",
            formatter: function (v) { return v >= 0 ? v.toFixed(1) + " %" : "—" },
            colorFor: function (v) { return root.percentColor(v) }
        },
        {
            title: "CPU peak",
            key: "cpuPeak",
            tooltip: "The highest reading within that sample's bucket - a burst the average smooths away.",
            formatter: function (v) { return v >= 0 ? v.toFixed(1) + " %" : "—" },
            colorFor: function (v) { return root.percentColor(v) }
        },
        {
            title: "Memory",
            key: "memory",
            tooltip: "The machine's memory in use.",
            formatter: function (v) { return v >= 0 ? v.toFixed(1) + " %" : "—" },
            colorFor: function (v) { return root.percentColor(v) }
        },
        {
            title: "Load / core",
            key: "load",
            tooltip: "Load average per core, where the platform has one: 1.0 is every core busy, more is "
                     + "work waiting. On Windows the processor queue per core instead, saturated at 2.",
            formatter: function (v, row) {
                if (v < 0) return "—"
                return v.toLocaleString(Qt.locale(), "f", 2) + (row && row.loadIsQueue ? " (queue)" : "")
            },
            colorFor: function (v, row) { return root.loadColor(v, row) }
        },
        {
            title: "Last seen",
            key: "lastSeen",
            tooltip: "The start of the newest five-minute period any of the four samples covers - so a "
                     + "host reporting normally reads 5 to 10 minutes ago. Amber after "
                     + (root.staleSeconds / 60) + " minutes, when at least one period has been missed.",
            formatter: function (v) { return v ? DateFormat.format(v) : "—" },
            colorFor: function (v, row) { return row && row.stale ? "#ffb545" : "#9aa1ac" }
        }
    ]

    function refresh() {
        if (!root.loggedIn) {
            root.error = "Sign in to see the workers' load."
            return
        }
        root.error = ""
        root.pending = root.metrics.length
        for (const name of root.metrics) emoClient.fetchLatestByLabel(name)
        eapClient.fetchNodes()
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: eapClient
        function onNodesLoaded(list, total) {
            const map = {}
            for (const n of list) map[String(n.name).toLowerCase()] = n
            root.nodes = map
        }
    }

    Connections {
        target: emoClient
        function onLatestByLabelLoaded(name, latest) {
            const i = root.metrics.indexOf(name)
            if (i < 0) return
            if (name === "system-cpu-usage") root.cpu = latest
            else if (name === "system-memory-usage-percent") root.memory = latest
            else if (name === "system-load-per-core") root.loadPerCore = latest
            else root.queuePerCore = latest
            root.pending = Math.max(0, root.pending - 1)
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onLatestByLabelFailed(name, message) {
            if (root.metrics.indexOf(name) < 0) return
            root.pending = Math.max(0, root.pending - 1)
            // One of the two load metrics is missing on every platform, so its failure is expected;
            // only CPU and memory failing says something is wrong.
            if (name === "system-cpu-usage" || name === "system-memory-usage-percent")
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
                title: "Worker Load (" + root.rows.length + ")"
                subtitle: "CPU, memory and load of every machine that reports them - the dashboard's System "
                          + "Load, host by host."
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.rows
                totalCount: root.rows.length
                pageSize: root.rows.length > 0 ? root.rows.length : 1
                pageIndex: 0
                pageSizeSelectable: false
                loading: root.pending > 0
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by host..."
                matchType: root.filterMatchType
                emptyText: root.filterText.length > 0 ? "No host matches." : "No host has reported yet."
                sortKey: root.sortKey
                sortAscending: root.sortAscending
                // Only a worker node has a page to open; the click on any other row does nothing.
                rowsClickable: true
                onRowClicked: (row) => { if (row.node) root.openNodeDetails(row.node.name, row.node) }

                onSearchChanged: (text, matchType) => {
                    root.filterText = text
                    root.filterMatchType = matchType
                }
                onSortRequested: (key, ascending) => {
                    root.sortKey = key
                    root.sortAscending = ascending
                }
                onRefreshRequested: root.refresh()
            }
        }
    }
}
