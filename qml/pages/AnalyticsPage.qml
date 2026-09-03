import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false

    // "gateway-service-count"/"gateway-service-time" are recorded once per request in the
    // gateway's router, labelled by HTTP method (GET/POST/PUT/DELETE) - the closest thing emo
    // exposes to overall traffic across every module. One point per method per emo flush period
    // (5 minutes by default server-side).
    readonly property var httpMethods: [
        { name: "GET", color: "#4f8cff" },
        { name: "POST", color: "#4cd97b" },
        { name: "PUT", color: "#ffb545" },
        { name: "DELETE", color: "#ff6b6b" }
    ]
    property var requestCountByMethod: ({})
    property var requestTimeByMethod: ({})

    // Every other module records "<id>-service-count"/"<id>-service-time" the same way, but
    // labelled with the action ("send-message", "receive-messages", ...) rather than a handful of
    // HTTP methods - around twenty per module, too many to give a line each, and the client can't
    // tell which ones a deployment actually exercises. So each module's actions are aggregated
    // into one line per chart: total requests, and the mean time one took. See
    // EmoClient::fetchAggregatedSeries().
    readonly property var serviceModules: [
        { id: "eqs", title: "EQS Traffic", description: "All EQS actions" },
        { id: "esm", title: "ESM Traffic", description: "All ESM actions" },
        { id: "ens", title: "ENS Traffic", description: "All ENS actions" },
        { id: "eam", title: "EAM Traffic", description: "All EAM actions" },
        { id: "ets", title: "ETS Traffic", description: "All ETS actions" }
    ]

    // {module id: points}, one entry per tile above.
    property var moduleCountPoints: ({})
    property var moduleTimePoints: ({})

    // One layer below the actions: what EQS's repository actually does against MongoDB, per
    // operation. Fetched as one series per operation rather than aggregated, because "which
    // operation dominates" is exactly the question the aggregate answers away.
    //
    // The receive path is broken into its parts on purpose. A long poll is mostly sleeping, and
    // its cost is not one query but several per 100ms attempt: priorityCount runs once per
    // priority per attempt whether or not a message is there to take.
    readonly property var repositoryOperations: [
        { name: "receiveMessages.priorityCount", color: "#ff6b6b" },
        { name: "receiveMessages.claim", color: "#4f8cff" },
        { name: "receiveMessages.queueLookup", color: "#c56bff" },
        { name: "receiveMessages.counters", color: "#4cd97b" },
        { name: "receiveMessages.redrive", color: "#ffb545" },
        { name: "sendMessage", color: "#2dd4bf" },
        { name: "deleteMessage", color: "#f472b6" },
        { name: "listMessages", color: "#a3a3a3" },
        { name: "countMessagesForQueue", color: "#eab308" },
        { name: "resetExpiredMessages", color: "#60a5fa" }
    ]
    property var repositoryCountByOperation: ({})
    property var repositoryTimeByOperation: ({})

    // {tileId: "hh:mm:ss"}. Per tile rather than one page-wide stamp: each tile now refreshes on
    // its own period, so they no longer come back together.
    property var updatedByTile: ({})

    // Row cap multiplier for the aggregated per-module queries: one bucket costs one row per
    // action, so the cap has to be buckets * actions. The busiest module instruments 23 actions,
    // so 32 leaves room for a few more before histories start getting trimmed at the far end.
    readonly property int maxServiceActions: 32

    // Selectable chart periods. Each one is pinned to the emo storage tier whose bucket width
    // suits its span (see EmoClient::fetchSeries): asking for a year of RAW points would be
    // ~105,000 rows per series and they aren't kept that long anyway, while a day of DAY points
    // is a single point. `limit` is the number of buckets that span can hold (RAW assumes emo's
    // default 5-minute average-period), so the server's newest-first cut never drops a bucket
    // that's still inside the period.
    readonly property var historyRanges: [
        { label: "Today",      resolution: "RAW",  limit: 288, timeFormat: "hh:mm" },
        { label: "This week",  resolution: "HOUR", limit: 168, timeFormat: "ddd hh:mm" },
        { label: "This month", resolution: "DAY",  limit: 31,  timeFormat: "dd MMM" },
        { label: "This year",  resolution: "DAY",  limit: 366, timeFormat: "dd MMM" }
    ]

    // Every tile has its own gear, so every tile has its own period: {tileId: rangeIndex}, keyed
    // by "gateway" or a module id. Absent means the first range (Today).
    property var rangeIndexByTile: ({})
    // Gateway only. All four methods are always fetched (cheap, and switching one back on
    // shouldn't need a refetch), visibility is purely a client-side display filter.
    property var enabledMethods: ({ GET: true, POST: true, PUT: true, DELETE: true })
    // {tileId: {count: bool, time: bool}} - which of a module tile's two charts to draw. Absent
    // means both, so a tile the user has never configured needs no entry.
    property var chartsByTile: ({})

    function rangeIndexFor(tileId) {
        const index = root.rangeIndexByTile[tileId]
        return index === undefined ? 0 : index
    }

    function rangeFor(tileId) {
        return root.historyRanges[root.rangeIndexFor(tileId)]
    }

    // Every tile on the page, set at once. Assigned rather than bound: a tile's own header click
    // writes `expanded` directly, and a binding would be broken by the first one of those anyway.
    function setAllExpanded(expanded) {
        gatewayTile.expanded = expanded
        repositoryTile.expanded = expanded
        for (let i = 0; i < moduleTiles.count; ++i) {
            const tile = moduleTiles.itemAt(i)
            if (tile) tile.expanded = expanded
        }
    }

    function chartVisible(tileId, which) {
        const charts = root.chartsByTile[tileId]
        return !charts || charts[which] !== false
    }

    function setChartVisible(tileId, which, visible) {
        const updated = Object.assign({}, root.chartsByTile)
        const charts = Object.assign({ count: true, time: true }, updated[tileId])
        charts[which] = visible
        updated[tileId] = charts
        root.chartsByTile = updated
    }

    // Changing a period invalidates only that tile: its points came back at the old resolution and
    // would be plotted against the new period's axis until its own responses land.
    function setRangeIndex(tileId, index) {
        const updated = Object.assign({}, root.rangeIndexByTile)
        updated[tileId] = index
        root.rangeIndexByTile = updated
        root.clearTile(tileId)
        root.refreshTile(tileId)
    }

    function clearTile(tileId) {
        if (tileId === "gateway") {
            root.requestCountByMethod = ({})
            root.requestTimeByMethod = ({})
            return
        }
        if (tileId === "eqs-repository") {
            root.repositoryCountByOperation = ({})
            root.repositoryTimeByOperation = ({})
            return
        }
        const counts = Object.assign({}, root.moduleCountPoints)
        const times = Object.assign({}, root.moduleTimePoints)
        delete counts[tileId]
        delete times[tileId]
        root.moduleCountPoints = counts
        root.moduleTimePoints = times
    }

    // Which tile a metric belongs to, so a response can be filtered against that tile's period
    // rather than some page-wide one. Empty for a name this page doesn't draw.
    function tileForMetric(name) {
        if (name === "gateway-service-count" || name === "gateway-service-time")
            return "gateway"
        if (name === "eqs-repository-count" || name === "eqs-repository-time")
            return "eqs-repository"
        for (const m of root.serviceModules) {
            if (name === m.id + "-service-count" || name === m.id + "-service-time")
                return m.id
        }
        return ""
    }

    // Start of the selected calendar period. "limit" alone would give the last N buckets, which
    // at 09:00 would reach back into yesterday and make the "Today" label a lie, so points before
    // this instant are dropped once they arrive.
    //
    // Month/year boundaries are taken in UTC because DAY buckets are aligned to UTC midnight: a
    // local-midnight boundary would drop the 1st's bucket in every zone west of Greenwich.
    // Today/this week use local midnight, which is what those words mean to the user, and their
    // buckets are at most an hour wide so the boundary is off by at most one point.
    function historyRangeStart(rangeIndex) {
        const now = new Date()
        switch (rangeIndex) {
        // This week - back to the most recent Monday (getDay() counts Sunday as 0)
        case 1: {
            const start = new Date(now.getFullYear(), now.getMonth(), now.getDate())
            start.setDate(start.getDate() - (start.getDay() + 6) % 7)
            return start
        }
        case 2:
            return new Date(Date.UTC(now.getFullYear(), now.getMonth(), 1))
        case 3:
            return new Date(Date.UTC(now.getFullYear(), 0, 1))
        default:
            return new Date(now.getFullYear(), now.getMonth(), now.getDate())
        }
    }

    function pointsInRange(points, tileId) {
        const start = root.historyRangeStart(root.rangeIndexFor(tileId)).getTime()
        return points.filter(p => {
            const t = new Date(p.timestamp).getTime()
            return !isNaN(t) && t >= start
        })
    }

    // Builds LineChart's `series` list from a {method: points} map, always in the same
    // GET/POST/PUT/DELETE order regardless of which responses have come back yet.
    function seriesFor(byMethod) {
        const result = []
        for (const m of root.httpMethods) {
            if (!root.enabledMethods[m.name]) continue
            result.push({ name: m.name, color: m.color, points: byMethod[m.name] || [] })
        }
        return result
    }

    // The repository chart's series, in the fixed order above so a colour always means the same
    // operation whichever of them have reported yet.
    function repositorySeriesFor(byOperation) {
        const result = []
        for (const op of root.repositoryOperations)
            result.push({ name: op.name, color: op.color, points: byOperation[op.name] || [] })
        return result
    }

    // One tile's worth of requests, at that tile's own period.
    function refreshTile(tileId) {
        if (!root.loggedIn)
            return
        const range = root.rangeFor(tileId)
        if (tileId === "gateway") {
            for (const m of root.httpMethods) {
                emoClient.fetchSeries("gateway-service-count", "method", m.name, range.limit, range.resolution)
                emoClient.fetchSeries("gateway-service-time", "method", m.name, range.limit, range.resolution)
            }
            return
        }
        if (tileId === "eqs-repository") {
            for (const op of root.repositoryOperations) {
                emoClient.fetchSeries("eqs-repository-count", "operation", op.name, range.limit, range.resolution)
                emoClient.fetchSeries("eqs-repository-time", "operation", op.name, range.limit, range.resolution)
            }
            return
        }
        emoClient.fetchAggregatedSeries(tileId + "-service-count", range.limit * root.maxServiceActions, range.resolution)
        emoClient.fetchAggregatedSeries(tileId + "-service-time", range.limit * root.maxServiceActions, range.resolution)
    }

    // What F5 calls (see Main.qml's refreshCurrentPage()): for this page, every tile at once.
    function refresh() {
        root.refreshMetrics()
    }

    function refreshMetrics() {
        root.refreshTile("gateway")
        root.refreshTile("eqs-repository")
        for (const m of root.serviceModules)
            root.refreshTile(m.id)
    }

    // Files `points` under the module a "<id>-service-count"/"-service-time" metric belongs to,
    // and reports whether the name was one of those at all. Reassigning a copy of the whole map
    // (rather than mutating it) is what makes the tiles' bindings re-evaluate.
    function setModulePoints(name, points) {
        for (const m of root.serviceModules) {
            const isCount = name === m.id + "-service-count"
            if (!isCount && name !== m.id + "-service-time")
                continue
            const updated = Object.assign({}, isCount ? root.moduleCountPoints : root.moduleTimePoints)
            updated[m.id] = points
            if (isCount) root.moduleCountPoints = updated
            else root.moduleTimePoints = updated
            return true
        }
        return false
    }

    onVisibleChanged: if (visible) refreshMetrics()
    onLoggedInChanged: if (loggedIn && visible) refreshMetrics()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refreshMetrics()
    }

    Connections {
        target: emoClient
        function onSeriesLoaded(name, labelValue, points) {
            const tileId = root.tileForMetric(name)
            if (tileId.length === 0) return
            const inRange = root.pointsInRange(points, tileId)
            if (name === "gateway-service-count") {
                const byMethod = Object.assign({}, root.requestCountByMethod)
                byMethod[labelValue] = inRange
                root.requestCountByMethod = byMethod
            } else if (name === "gateway-service-time") {
                const byMethod = Object.assign({}, root.requestTimeByMethod)
                byMethod[labelValue] = inRange
                root.requestTimeByMethod = byMethod
            } else if (name === "eqs-repository-count") {
                const byOperation = Object.assign({}, root.repositoryCountByOperation)
                byOperation[labelValue] = inRange
                root.repositoryCountByOperation = byOperation
            } else if (name === "eqs-repository-time") {
                const byOperation = Object.assign({}, root.repositoryTimeByOperation)
                byOperation[labelValue] = inRange
                root.repositoryTimeByOperation = byOperation
            } else {
                root.setModulePoints(name, inRange)
            }
            const updated = Object.assign({}, root.updatedByTile)
            updated[tileId] = Qt.formatDateTime(new Date(), "hh:mm:ss")
            root.updatedByTile = updated
        }
        function onSeriesFailed(name, labelValue, message) {
            if (name === "gateway-service-count") {
                const byMethod = Object.assign({}, root.requestCountByMethod)
                byMethod[labelValue] = []
                root.requestCountByMethod = byMethod
            } else if (name === "gateway-service-time") {
                const byMethod = Object.assign({}, root.requestTimeByMethod)
                byMethod[labelValue] = []
                root.requestTimeByMethod = byMethod
            } else if (name === "eqs-repository-count" || name === "eqs-repository-time") {
                const byOperation = Object.assign({}, name === "eqs-repository-count"
                                                     ? root.repositoryCountByOperation : root.repositoryTimeByOperation)
                byOperation[labelValue] = []
                if (name === "eqs-repository-count") root.repositoryCountByOperation = byOperation
                else root.repositoryTimeByOperation = byOperation
            } else {
                root.setModulePoints(name, [])
            }
        }
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            id: contentColumn
            width: parent.width
            spacing: 28

            Item {
                width: parent.width
                height: analyticsHeader.implicitHeight

                SectionHeader {
                    id: analyticsHeader
                    title: "Analytics"
                    subtitle: "Traffic sources and conversion breakdown."
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: analyticsHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: "Expand all"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: root.setAllExpanded(true)
                    }
                    Button {
                        text: "Collapse all"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: root.setAllExpanded(false)
                    }
                }
            }

            FoldableTile {
                id: gatewayTile
                width: parent.width
                title: "Gateway Traffic"
                expanded: true

                headerContent: [
                    Button {
                        text: "⚙"
                        font.pixelSize: 16
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        Material.theme: Material.Dark
                        onClicked: chartSettingsDialog.openFor("gateway", "Gateway Traffic")
                    },
                    Button {
                        text: "⟳"
                        font.pixelSize: 16
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        Material.theme: Material.Dark
                        onClicked: root.refreshTile("gateway")
                    }
                ]

                contentData: [
                    Column {
                        width: gatewayTile.width - 32
                        spacing: 20

                        Column {
                            width: parent.width
                            spacing: 8
                            visible: root.chartVisible("gateway", "count")
                            Text { text: "Request Count"; color: "#c4c9d1"; font.pixelSize: 12; font.bold: true }
                            LineChart {
                                width: parent.width
                                height: 160
                                timeFormat: root.rangeFor("gateway").timeFormat
                                series: root.seriesFor(root.requestCountByMethod)
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 8
                            visible: root.chartVisible("gateway", "time")
                            Text { text: "Request Time"; color: "#c4c9d1"; font.pixelSize: 12; font.bold: true }
                            LineChart {
                                width: parent.width
                                height: 160
                                valueSuffix: " ms"
                                decimals: 1
                                timeFormat: root.rangeFor("gateway").timeFormat
                                series: root.seriesFor(root.requestTimeByMethod)
                            }
                        }

                        Text {
                            text: root.rangeFor("gateway").label + " · updated "
                                  + (root.updatedByTile["gateway"] || "—")
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                    }
                ]
            }

            // One line per repository operation rather than one per module: this tile exists to
            // answer which database operation the load is, and an aggregate would hide that.
            FoldableTile {
                id: repositoryTile
                width: parent.width
                title: "EQS Database Operations"
                expanded: true

                headerContent: [
                    Button {
                        text: "⚙"
                        font.pixelSize: 16
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        Material.theme: Material.Dark
                        onClicked: chartSettingsDialog.openFor("eqs-repository", "EQS Database Operations")
                    },
                    Button {
                        text: "⟳"
                        font.pixelSize: 16
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        Material.theme: Material.Dark
                        onClicked: root.refreshTile("eqs-repository")
                    }
                ]

                contentData: [
                    Column {
                        width: repositoryTile.width - 32
                        spacing: 20

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "What EQS asks of MongoDB, counted per operation. The receive path is split into its "
                                  + "parts: a long poll runs priorityCount once per priority every 100ms of waiting, "
                                  + "whether or not there is a message to take, while claim only runs when there is one."
                            color: "#6b7280"
                            font.pixelSize: 11
                        }

                        Column {
                            width: parent.width
                            spacing: 8
                            visible: root.chartVisible("eqs-repository", "count")
                            Text { text: "Operations"; color: "#c4c9d1"; font.pixelSize: 12; font.bold: true }
                            LineChart {
                                width: parent.width
                                height: 160
                                timeFormat: root.rangeFor("eqs-repository").timeFormat
                                series: root.repositorySeriesFor(root.repositoryCountByOperation)
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 8
                            visible: root.chartVisible("eqs-repository", "time")
                            Text { text: "Time per operation"; color: "#c4c9d1"; font.pixelSize: 12; font.bold: true }
                            LineChart {
                                width: parent.width
                                height: 160
                                valueSuffix: " ms"
                                decimals: 2
                                timeFormat: root.rangeFor("eqs-repository").timeFormat
                                series: root.repositorySeriesFor(root.repositoryTimeByOperation)
                            }
                        }

                        Text {
                            text: root.rangeFor("eqs-repository").label + " · updated "
                                  + (root.updatedByTile["eqs-repository"] || "—")
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                    }
                ]
            }

            // One tile per instrumented module, each with its own gear: period, and which of its
            // two charts to draw, are per tile - comparing a module's month against the gateway's
            // today is a normal thing to want.
            Repeater {
                id: moduleTiles
                model: root.serviceModules
                delegate: ServiceModuleTile {
                    required property var modelData

                    width: contentColumn.width
                    title: modelData.title
                    timeFormat: root.rangeFor(modelData.id).timeFormat
                    countPoints: root.moduleCountPoints[modelData.id] || []
                    timePoints: root.moduleTimePoints[modelData.id] || []
                    showCount: root.chartVisible(modelData.id, "count")
                    showTime: root.chartVisible(modelData.id, "time")
                    footerText: modelData.description + " · " + root.rangeFor(modelData.id).label
                                + " · updated " + (root.updatedByTile[modelData.id] || "—")
                    onRefreshRequested: root.refreshTile(modelData.id)
                    onSettingsRequested: chartSettingsDialog.openFor(modelData.id, modelData.title)
                }
            }

            Rectangle {
                width: parent.width
                height: 260
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 30

                    Column {
                        spacing: 16
                        width: 220
                        anchors.verticalCenter: parent.verticalCenter

                        Text { text: "Traffic Sources"; color: "white"; font.pixelSize: 15; font.bold: true }

                        Repeater {
                            model: [
                                { label: "Organic Search", pct: 42, color: "#4f8cff" },
                                { label: "Direct", pct: 27, color: "#4cd97b" },
                                { label: "Referral", pct: 18, color: "#ffb545" },
                                { label: "Social", pct: 13, color: "#c56bff" }
                            ]
                            delegate: Column {
                                spacing: 4
                                width: 220

                                Row {
                                    width: parent.width
                                    Text {
                                        text: modelData.label
                                        color: "#c4c9d1"
                                        font.pixelSize: 12
                                        width: parent.width - 34
                                    }
                                    Text {
                                        text: modelData.pct + "%"
                                        color: "white"
                                        font.pixelSize: 12
                                        width: 34
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 6
                                    radius: 3
                                    color: "#2c313c"

                                    Rectangle {
                                        height: parent.height
                                        radius: 3
                                        color: modelData.color
                                        width: 0
                                        Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                                        Component.onCompleted: width = parent.width * modelData.pct / 100
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: 1
                        height: parent.height
                        Rectangle { anchors.fill: parent; color: "#2c313c" }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 18

                        Text { text: "Conversion Funnel"; color: "white"; font.pixelSize: 15; font.bold: true }

                        Repeater {
                            model: [
                                { label: "Visitors", value: 1.0 },
                                { label: "Signups", value: 0.62 },
                                { label: "Trials", value: 0.34 },
                                { label: "Paid", value: 0.15 }
                            ]
                            delegate: Row {
                                spacing: 12
                                Text {
                                    text: modelData.label
                                    color: "#9aa1ac"
                                    font.pixelSize: 12
                                    width: 70
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Rectangle {
                                    height: 22
                                    radius: 6
                                    color: "#4f8cff"
                                    opacity: 0.35 + 0.65 * modelData.value
                                    width: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                                    Component.onCompleted: width = 260 * modelData.value

                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Math.round(modelData.value * 100) + "%"
                                        color: "white"
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
                height: 200
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    Text { text: "Top Pages"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Repeater {
                        model: [
                            { page: "/dashboard", views: "8,204" },
                            { page: "/pricing", views: "5,912" },
                            { page: "/docs/getting-started", views: "4,330" }
                        ]
                        delegate: Row {
                            width: parent.width
                            height: 28
                            Text { text: modelData.page; color: "#c4c9d1"; font.pixelSize: 13; width: parent.width - 100 }
                            Text { text: modelData.views; color: "#9aa1ac"; font.pixelSize: 13; width: 100; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }
            }
        }
    }

    // One dialog serving every tile: they configure the same things, and `tileId` is what decides
    // whose period is being edited and whether the gateway's per-method toggles apply.
    Dialog {
        id: chartSettingsDialog
        modal: true
        anchors.centerIn: parent
        width: 360
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string tileId: "gateway"
        property string tileTitle: "Gateway Traffic"
        readonly property bool gateway: chartSettingsDialog.tileId === "gateway"

        // ComboBox's currentIndex binding gets clobbered by its own internal model-populate
        // logic, same as every other dialog's combo/spinbox in this app - set it imperatively
        // on open instead (see createKeyDialog's onOpened in EkmKeysPage.qml for the same idiom).
        function openFor(tileId, tileTitle) {
            chartSettingsDialog.tileId = tileId
            chartSettingsDialog.tileTitle = tileTitle
            chartSettingsDialog.open()
            historyCombo.currentIndex = root.rangeIndexFor(tileId)
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: chartSettingsDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: chartSettingsDialog.tileTitle + " Settings"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    text: "Applies to this tile only - each tile keeps its own period, so one can show today "
                          + "while another shows the year."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                id: historyColumn
                width: parent.width
                spacing: 6
                Text { text: "Period"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: historyCombo
                    width: historyColumn.width
                    model: root.historyRanges.map(r => r.label)
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onActivated: root.setRangeIndex(chartSettingsDialog.tileId, currentIndex)
                }
                Text {
                    text: {
                        const r = root.rangeFor(chartSettingsDialog.tileId)
                        return r.resolution === "RAW" ? "One point per emo flush period (5 min)"
                             : r.resolution === "HOUR" ? "One point per hour" : "One point per day"
                    }
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: historyColumn.width
                }
            }

            // Gateway: one line per HTTP method, since its metrics are labelled by method.
            Column {
                id: methodsColumn
                width: parent.width
                spacing: 10
                visible: chartSettingsDialog.gateway

                Text { text: "HTTP Methods"; color: "#9aa1ac"; font.pixelSize: 12 }

                Repeater {
                    model: root.httpMethods
                    delegate: Row {
                        id: methodRow
                        required property var modelData

                        width: methodsColumn.width
                        height: 28
                        spacing: 10

                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: methodRow.modelData.color
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: methodRow.modelData.name
                            color: "#e5e7eb"
                            font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter
                            width: methodRow.width - 66
                        }
                        ToggleSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.enabledMethods[methodRow.modelData.name]
                            onToggled: (checked) => {
                                const updated = Object.assign({}, root.enabledMethods)
                                updated[methodRow.modelData.name] = checked
                                root.enabledMethods = updated
                            }
                        }
                    }
                }
            }

            // Module tiles: a single aggregated line per chart, so what there is to switch is the
            // charts themselves.
            Column {
                id: chartsColumn
                width: parent.width
                spacing: 10
                visible: !chartSettingsDialog.gateway

                Text { text: "Charts"; color: "#9aa1ac"; font.pixelSize: 12 }

                Repeater {
                    model: [
                        { key: "count", label: "Request Count" },
                        { key: "time", label: "Request Time" }
                    ]
                    delegate: Row {
                        id: chartRow
                        required property var modelData

                        width: chartsColumn.width
                        height: 28
                        spacing: 10

                        Text {
                            text: chartRow.modelData.label
                            color: "#e5e7eb"
                            font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter
                            width: chartRow.width - 56
                        }
                        ToggleSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.chartVisible(chartSettingsDialog.tileId, chartRow.modelData.key)
                            onToggled: (checked) => root.setChartVisible(chartSettingsDialog.tileId,
                                                                        chartRow.modelData.key, checked)
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Close"
                    flat: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    onClicked: chartSettingsDialog.close()
                }
            }
        }
    }
}
