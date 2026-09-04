import QtQuick
import QtQuick.Controls
import "../components"

Item {
    id: root
    property bool loggedIn: false

    // The machine's load, both figures read the same way: emo samples "system-cpu-usage" and
    // "system-memory-usage-percent" from /proc, labelled by host. Not the per-module
    // "euclid-cpu-usage"/"euclid-memory-usage-percent", which answer what one process holds - the
    // memory gauge used to read one of those and showed a module's own 0.02% as the machine's.
    property real cpuPercent: -1
    property real memoryPercent: -1

    // The module registry: what euclid-mgr is meant to be running, and what actually is.
    property var modules: []
    property string modulesError: ""
    // Distinguishes "not asked yet" from "asked, and the registry is empty" - the second is a
    // real answer and should not read as though it were still loading.
    property bool modulesFetched: false

    // Modules, not everything euclid-mgr runs: transfer servers and application pools live in the
    // same registry but are ETS's and EAP's own, and counting them here would make this figure
    // grow with how much is deployed rather than with how the installation is put together.
    readonly property var coreModules: root.modules.filter(m => m.core)
    // "Active" here means enabled in the registry - a module switched off is not something anyone
    // is waiting for, so it counts towards neither figure.
    readonly property int enabledModules: root.coreModules.filter(m => m.active).length
    // Enabled and with at least one instance up. The two numbers disagree exactly when something
    // euclid-mgr should be running is not running, which is the whole point of showing them.
    readonly property int runningModules: root.coreModules.filter(m => m.active && m.runningInstances > 0).length
    readonly property bool modulesKnown: root.modulesFetched && root.modulesError.length === 0

    // "gateway-service-count" is recorded once per request in the gateway's router, labelled by
    // HTTP method - the closest thing emo exposes to overall traffic across every module. The
    // aggregated fetch folds those labels into one point per bucket (a RATE sums over its labels),
    // which is the total request count this chart wants.
    //
    // DAY resolution, because the bars are days. One bucket costs one row per label, so the cap is
    // buckets * labels: far more than the seven days drawn, since the oldest bucket of a response
    // that hit the cap is dropped server-side as incomplete.
    // What euclid's MongoDB occupies, every collection of it together. One label - the database
    // name - so there is nothing to fold, and it arrives in bytes for SizeFormat to render.
    property real databaseSize: -1
    // How many collections that database holds, and how many documents across them. Both single
    // labelled gauges like the size above, and all three move at emo's bucket cadence.
    property real databaseCollections: -1
    property real databaseObjects: -1
    // The three sizes MongoDB reports separately, and they measure different things: data size is
    // the documents uncompressed, storage size what their collections actually occupy after
    // compression, index size what the indexes add on top. Storage below data is compression
    // working, not an error.
    property real databaseDataSize: -1
    property real databaseIndexSize: -1
    property real databaseStorageSize: -1

    readonly property string trafficMetric: "gateway-service-count"
    readonly property int trafficRowLimit: 96
    property var trafficPoints: []
    property string trafficError: ""

    // The last seven days as bars, oldest first. Built from calendar days rather than from whatever
    // buckets came back: a day with no traffic has no bucket at all, and without the day slots its
    // neighbours would slide over to fill the gap and be labelled as days they are not.
    readonly property var weekBars: {
        const names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        // emo's DAY buckets are UTC-aligned, so days are keyed and labelled in UTC - keying in
        // local time would file a bucket under the neighbouring bar for anyone not on UTC.
        const byDay = ({})
        for (const point of root.trafficPoints) {
            const stamp = new Date(point.timestamp)
            if (isNaN(stamp.getTime())) continue
            const key = stamp.toISOString().substring(0, 10)
            byDay[key] = (byDay[key] || 0) + Number(point.value)
        }

        const bars = []
        const now = new Date()
        for (let back = 6; back >= 0; --back) {
            const day = new Date(now.getTime() - back * 86400000)
            bars.push({
                label: names[day.getUTCDay()],
                value: byDay[day.toISOString().substring(0, 10)] || 0,
                today: back === 0
            })
        }
        return bars
    }

    // Bars are drawn as a fraction of the busiest day, so a quiet week still fills the chart.
    readonly property real trafficMax: {
        let max = 0
        for (const bar of root.weekBars) max = Math.max(max, bar.value)
        return max
    }
    readonly property real trafficTotal: {
        let total = 0
        for (const bar of root.weekBars) total += bar.value
        return total
    }

    function refresh() {
        if (!root.loggedIn)
            return
        emoClient.fetchAverage("system-cpu-usage")
        emoClient.fetchAverage("system-memory-usage-percent")
        emoClient.fetchAverage("database-total-size")
        emoClient.fetchAverage("database-collections")
        emoClient.fetchAverage("database-objects")
        emoClient.fetchAverage("database-data-size")
        emoClient.fetchAverage("database-index-size")
        emoClient.fetchAverage("database-storage-size")
        emoClient.fetchAggregatedSeries(root.trafficMetric, root.trafficRowLimit, "DAY")
        emmClient.fetchModules()
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    // When something last arrived, which is not the same as when it was last asked for: a refresh
    // whose every request failed leaves this showing the older time it is still displaying data
    // from, which is the useful thing to know.
    property string lastUpdatedText: "—"

    function markUpdated() {
        root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
    }

    Connections {
        target: emoClient
        function onAverageLoaded(name, value) {
            if (name === "system-cpu-usage") root.cpuPercent = value
            else if (name === "system-memory-usage-percent") root.memoryPercent = value
            else if (name === "database-total-size") root.databaseSize = value
            else if (name === "database-collections") root.databaseCollections = value
            else if (name === "database-objects") root.databaseObjects = value
            else if (name === "database-data-size") root.databaseDataSize = value
            else if (name === "database-index-size") root.databaseIndexSize = value
            else if (name === "database-storage-size") root.databaseStorageSize = value
            else return
            root.markUpdated()
        }
        function onAverageFailed(name, message) {
            if (name === "system-cpu-usage") root.cpuPercent = -1
            else if (name === "system-memory-usage-percent") root.memoryPercent = -1
            else if (name === "database-total-size") root.databaseSize = -1
            else if (name === "database-collections") root.databaseCollections = -1
            else if (name === "database-objects") root.databaseObjects = -1
            else if (name === "database-data-size") root.databaseDataSize = -1
            else if (name === "database-index-size") root.databaseIndexSize = -1
            else if (name === "database-storage-size") root.databaseStorageSize = -1
        }
        // The analytics page asks for this metric too, but per method - an aggregated response is
        // the one with no label, which is what this page asked for and what it draws.
        function onSeriesLoaded(name, labelValue, points) {
            if (name !== root.trafficMetric || labelValue.length > 0) return
            root.trafficPoints = points
            root.trafficError = ""
            root.markUpdated()
        }
        function onSeriesFailed(name, labelValue, message) {
            if (name !== root.trafficMetric || labelValue.length > 0) return
            root.trafficPoints = []
            root.trafficError = message
        }
    }

    Connections {
        target: emmClient
        function onModulesLoaded(list, total) {
            root.modules = list
            root.modulesError = ""
            root.modulesFetched = true
            root.markUpdated()
        }
        function onModulesFailed(message) {
            root.modules = []
            root.modulesError = message
            root.modulesFetched = true
        }
    }

    ScrollView {
        id: scrollView
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        // Stops above the stamp rather than filling the page: an overlay in the corner would sit on
        // top of whatever the content ends with once it is scrolled to the bottom.
        anchors.bottom: lastUpdatedLabel.top
        anchors.margins: 28
        anchors.bottomMargin: 8
        contentWidth: availableWidth
        clip: true

        Column {
            width: scrollView.availableWidth
            spacing: 28

            SectionHeader {
                title: "Dashboard"
                subtitle: "Welcome back, here's what's happening today."
            }

            // A Grid rather than a Flow so the cards fill the row exactly: Flow lays children out
            // at their own width and leaves whatever is left over as a ragged gap on the right,
            // while this divides the row between however many fit and stretches each to its share.
            Grid {
                id: statGrid
                width: parent.width
                spacing: 18

                // Kept explicit: a Grid cannot ask how many children it has in a binding that
                // re-evaluates, so adding or removing a card above means changing this too.
                readonly property int cardCount: 7
                // Below this a card is too narrow for its value, so the row wraps instead.
                readonly property int minCardWidth: 200

                columns: Math.max(1, Math.min(statGrid.cardCount,
                                              Math.floor((statGrid.width + statGrid.spacing) / (statGrid.minCardWidth + statGrid.spacing))))
                readonly property real cellWidth: (statGrid.width - statGrid.spacing * (statGrid.columns - 1)) / statGrid.columns

                StatCard {
                    width: statGrid.cellWidth
                    title: "Active Modules"
                    value: root.modulesKnown ? String(root.runningModules) : "—"
                    // The denominator is what makes the number mean anything: 6 is good news out
                    // of 6 and bad news out of 9.
                    trend: !root.modulesKnown
                           ? (root.modulesError.length > 0 ? "unavailable" : "loading…")
                           : (root.enabledModules === 0
                              ? "no modules enabled"
                              : (root.runningModules === root.enabledModules
                                 ? "all " + root.enabledModules + " running"
                                 : (root.enabledModules - root.runningModules) + " of " + root.enabledModules + " not running"))
                    trendUp: root.modulesKnown && root.runningModules === root.enabledModules
                    accent: "#4f8cff"
                }
                StatCard {
                    width: statGrid.cellWidth
                    title: "Database Size"
                    value: root.databaseSize >= 0 ? SizeFormat.format(root.databaseSize) : "—"
                    trend: "on disk"
                    trendUp: true
                    accent: "#4cd97b"
                }
                StatCard {
                    width: statGrid.cellWidth
                    title: "Data Size"
                    value: root.databaseDataSize >= 0 ? SizeFormat.format(root.databaseDataSize) : "—"
                    trend: "uncompressed"
                    trendUp: true
                    accent: "#4cd97b"
                }
                StatCard {
                    width: statGrid.cellWidth
                    title: "Index Size"
                    value: root.databaseIndexSize >= 0 ? SizeFormat.format(root.databaseIndexSize) : "—"
                    trend: "indexes"
                    trendUp: true
                    accent: "#4cd97b"
                }
                StatCard {
                    width: statGrid.cellWidth
                    title: "Storage Size"
                    value: root.databaseStorageSize >= 0 ? SizeFormat.format(root.databaseStorageSize) : "—"
                    trend: "allocated"
                    trendUp: true
                    accent: "#4cd97b"
                }
                StatCard {
                    width: statGrid.cellWidth
                    title: "Collections"
                    value: root.databaseCollections >= 0 ? String(root.databaseCollections) : "—"
                    trend: "in the database"
                    trendUp: true
                    accent: "#ffb545"
                }
                StatCard {
                    width: statGrid.cellWidth
                    title: "Documents"
                    // Grouped rather than raw: 1486668 says less at a glance than 1,486,668.
                    value: root.databaseObjects >= 0 ? root.databaseObjects.toLocaleString(Qt.locale(), "f", 0) : "—"
                    trend: "across all collections"
                    trendUp: true
                    accent: "#c56bff"
                }
            }

            Row {
                width: parent.width
                spacing: 18

                Rectangle {
                    width: parent.width * 0.42
                    height: 280
                    radius: 14
                    color: "#20242e"
                    border.color: "#2c313c"
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 18

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "System Load"
                            color: "#9aa1ac"
                            font.pixelSize: 13
                        }

                        Row {
                            spacing: 24
                            Gauge {
                                value: Math.min(1, Math.max(0, root.cpuPercent) / 100)
                                valueText: root.cpuPercent >= 0 ? Math.round(root.cpuPercent) + "%" : "—"
                                label: "CPU"
                                progressColor: "#4f8cff"
                            }
                            Gauge {
                                value: Math.min(1, Math.max(0, root.memoryPercent) / 100)
                                valueText: root.memoryPercent >= 0 ? Math.round(root.memoryPercent) + "%" : "—"
                                label: "Memory"
                                progressColor: "#4cd97b"
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width * 0.58 - 18
                    height: 280
                    radius: 14
                    color: "#20242e"
                    border.color: "#2c313c"
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 14

                        Column {
                            width: parent.width
                            spacing: 2

                            Text {
                                text: "Weekly Traffic"
                                color: "white"
                                font.pixelSize: 15
                                font.bold: true
                            }
                            Text {
                                text: root.trafficError.length > 0
                                      ? root.trafficError
                                      : (root.trafficTotal > 0
                                         ? Math.round(root.trafficTotal) + " gateway requests · last 7 days"
                                         : "No gateway requests recorded in the last 7 days.")
                                color: root.trafficError.length > 0 ? "#ff6b6b" : "#6b7280"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        Row {
                            id: barRow
                            width: parent.width
                            height: 170
                            spacing: 18

                            readonly property int barHeight: 140

                            Repeater {
                                model: root.weekBars
                                delegate: Column {
                                    id: barColumn
                                    required property var modelData

                                    spacing: 8
                                    width: (barRow.width - barRow.spacing * 6) / 7

                                    Item {
                                        width: parent.width
                                        height: barRow.barHeight

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            radius: 6
                                            // Today is the bar being filled in as the day goes on,
                                            // so it is the one worth picking out.
                                            color: barColumn.modelData.today ? "#4f8cff" : "#2c3648"
                                            // A binding rather than a one-shot assignment: the
                                            // chart is refetched on a timer, and a day with no
                                            // traffic still needs a visible foot to sit on.
                                            height: root.trafficMax > 0
                                                    ? Math.max(2, barRow.barHeight * barColumn.modelData.value / root.trafficMax)
                                                    : 2
                                            Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                        }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: barColumn.modelData.label
                                        color: barColumn.modelData.today ? "#c4c9d1" : "#9aa1ac"
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 280
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 14

                    Text {
                        text: "Recent Activity"
                        color: "white"
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Column {
                        width: parent.width
                        spacing: 10

                        ActivityRow {
                            width: parent.width
                            initials: "AK"
                            avatarColor: "#4f8cff"
                            title: "Anna Kern deployed build #482"
                            subtitle: "production · euclid-rui"
                            time: "2m ago"
                        }
                        ActivityRow {
                            width: parent.width
                            initials: "TS"
                            avatarColor: "#4cd97b"
                            title: "Tom Sato resolved issue #918"
                            subtitle: "bug · high priority"
                            time: "18m ago"
                        }
                        ActivityRow {
                            width: parent.width
                            initials: "MB"
                            avatarColor: "#ffb545"
                            title: "Maria Bell commented on PR #205"
                            subtitle: "code review"
                            time: "1h ago"
                        }
                        ActivityRow {
                            width: parent.width
                            initials: "JV"
                            avatarColor: "#c56bff"
                            title: "Jens Vogt updated settings"
                            subtitle: "configuration"
                            time: "3h ago"
                        }
                    }
                }
            }
        }
    }

    // Fixed in the corner rather than at the end of the content: it says how current the page is,
    // which is worth reading without scrolling to the bottom to find it.
    Text {
        id: lastUpdatedLabel
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 28
        anchors.bottomMargin: 12
        text: "Last update " + root.lastUpdatedText
        color: "#6b7280"
        font.pixelSize: 11
    }
}
