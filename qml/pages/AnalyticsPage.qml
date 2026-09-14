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

    // When a refresh somebody asked for last completed - F5, or opening the page. Deliberately not
    // moved by the periodic timer: this line answers "when did I last pull this", which is the
    // question a key you just pressed raises, and a figure that quietly advanced on its own would
    // answer a different one. The cadence beside it says the data is fresher than this in between.
    property string lastUpdatedText: "—"
    // Set while a refresh somebody asked for is outstanding, so the line can say so rather than
    // appear to ignore the key, and cleared by whichever read answers first.
    property bool refreshing: false
    // Whether the outstanding refresh was asked for. The reads themselves are identical either way;
    // only what they stamp differs.
    property bool refreshRequested: false

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
    //
    // The first one is a rolling window rather than a calendar one, and it is the default: at
    // 09:00 "Today" is nine hours of chart and yesterday's evening - usually the more interesting
    // half - has just fallen off the left edge. 288 RAW buckets are exactly 24 hours, so it costs
    // the same query as "Today" and reads the same way.
    readonly property var historyRanges: [
        { id: "last24h", label: "Last 24 hours", resolution: "RAW",  limit: 288, timeFormat: "hh:mm", rollingHours: 24 },
        { id: "today",   label: "Today",         resolution: "RAW",  limit: 288, timeFormat: "hh:mm" },
        { id: "week",    label: "This week",     resolution: "HOUR", limit: 168, timeFormat: "ddd hh:mm" },
        { id: "month",   label: "This month",    resolution: "DAY",  limit: 31,  timeFormat: "dd MMM" },
        { id: "year",    label: "This year",     resolution: "DAY",  limit: 366, timeFormat: "dd MMM" }
    ]

    // Every tile has its own gear, so every tile has its own period: {tileId: rangeIndex}, keyed
    // by "gateway" or a module id. Absent means the first range (Last 24 hours).
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

    // Start of the selected period. "limit" alone would give the last N buckets, which at 09:00
    // would reach back into yesterday and make the "Today" label a lie, so points before this
    // instant are dropped once they arrive.
    //
    // Month/year boundaries are taken in UTC because DAY buckets are aligned to UTC midnight: a
    // local-midnight boundary would drop the 1st's bucket in every zone west of Greenwich.
    // Today/this week use local midnight, which is what those words mean to the user, and their
    // buckets are at most an hour wide so the boundary is off by at most one point.
    //
    // Keyed by the range's id rather than its position, so the list above can be reordered or
    // added to without silently repointing every case.
    function historyRangeStart(rangeIndex) {
        const now = new Date()
        const range = root.historyRanges[rangeIndex]

        // A rolling window is measured back from this moment; the calendar ones start at a boundary.
        if (range && range.rollingHours !== undefined)
            return new Date(now.getTime() - range.rollingHours * 3600000)

        switch (range ? range.id : "today") {
        // This week - back to the most recent Monday (getDay() counts Sunday as 0)
        case "week": {
            const start = new Date(now.getFullYear(), now.getMonth(), now.getDate())
            start.setDate(start.getDate() - (start.getDay() + 6) % 7)
            return start
        }
        case "month":
            return new Date(Date.UTC(now.getFullYear(), now.getMonth(), 1))
        case "year":
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
    // ── EAP pools ────────────────────────────────────────────────────────────
    //
    // Not a metric series like everything else on this page, and it cannot be: utilisation and
    // backlog are a control signal the autoscaler reads off the module record, deliberately kept
    // out of the monitoring store - see Entity::EMM::Module::utilisation for why. So this tile is
    // the live state of the pools rather than a chart of it.

    // Application pools, by the name the manager runs them under. An EMM module row is named after
    // Entity::EAP::RuntimeName(), not the applicationId, so the two lists are joined on that.
    property var applications: []
    property var modules: []

    // The newest "application-utilisation"/"application-backlog" sample per instance, from EMO.
    //
    // Two roads carry the same numbers and an application may be on either. The newer one is
    // "eap report-load", which writes them onto the instance record where the manager reads them on
    // every reconcile; the older is pushing them to EMO as metrics, which the manager still reads
    // back as a fallback - but only to decide scaling. It never copies them onto the record (see
    // Controller.cpp's second load pass), so an application on the older road reports nothing as far
    // as list-modules is concerned while quite visibly driving its pool. Reading both is the only
    // way this tile can say what is actually happening.
    property var emoUtilisation: ({})
    property var emoBacklog: ({})

    // How old an EMO sample may be before it stops counting as current. Wider than the manager's
    // own load-freshness-seconds (45 as shipped) on purpose, because these samples do not arrive
    // when they are taken: EMO accumulates in memory and writes a row only when its averaging
    // bucket closes - euclid.modules.emo.average-period, five minutes as shipped - so the newest
    // row for a busy instance is routinely minutes old - measured at eleven on an installation
    // whose pools had just gone quiet. Three buckets, so a late flush does not blank the tile,
    // while an instance that has genuinely stopped reporting still ages out. The manager applies no
    // age limit at all on this road, which is the other end of the same trade.
    readonly property int emoSampleWindowSeconds: 900

    function freshSample(map, instanceId) {
        const sample = map[instanceId]
        if (!sample) return undefined
        const at = new Date(sample.timestamp)
        if (isNaN(at.getTime())) return undefined
        if ((Date.now() - at.getTime()) / 1000 > root.emoSampleWindowSeconds) return undefined
        // The peak, not the average, for the reason EmoClient records both and the manager reads
        // this one.
        return Number(sample.maxValue)
    }

    // One pool, summed the way Database::Entity::EMM::SummarisePool does it: the mean for
    // utilisation and the total for backlog, counting only the instances that report at all.
    function summarise(module) {
        const instances = module.instances || []
        let running = 0
        let reporting = 0
        let utilisationSum = 0
        let backlog = 0

        for (const instance of instances) {
            if (String(instance.state) !== "RUNNING") continue
            ++running

            // The record first: it is the road the autoscaler prefers and the fresher of the two.
            let utilisation = Number(instance.utilisation)
            let waiting = Number(instance.backlog)

            if (utilisation < 0) {
                const sample = root.freshSample(root.emoUtilisation, String(instance.instanceId))
                if (sample !== undefined) utilisation = sample
            }
            if (waiting < 0) {
                const sample = root.freshSample(root.emoBacklog, String(instance.instanceId))
                if (sample !== undefined) waiting = sample
            }

            if (utilisation < 0 && waiting < 0) continue
            ++reporting
            if (utilisation >= 0) utilisationSum += utilisation
            if (waiting >= 0) backlog += waiting
        }

        return {
            running: running,
            reporting: reporting,
            utilisation: reporting > 0 ? utilisationSum / reporting : -1,
            backlog: reporting > 0 ? backlog : -1
        }
    }

    readonly property var applicationPools: {
        const pools = []
        for (const application of root.applications) {
            const runtimeName = String(application.runtimeName).length > 0
                                ? String(application.runtimeName) : String(application.applicationId)
            const module = root.modules.find(m => String(m.name) === runtimeName)
            if (!module) continue
            const load = root.summarise(module)
            pools.push({
                applicationId: String(application.applicationId),
                runtimeName: runtimeName,
                running: load.running,
                maxInstances: Number(module.maxInstances),
                reporting: load.reporting,
                utilisation: load.utilisation,
                backlog: load.backlog
            })
        }
        return pools.sort((a, b) => String(a.applicationId).localeCompare(String(b.applicationId)))
    }

    readonly property int poolInstances: root.applicationPools.reduce((sum, p) => sum + p.running, 0)
    readonly property int poolCeiling: root.applicationPools.reduce((sum, p) => sum + p.maxInstances, 0)
    // Across the pools that report, for the reason a single pool is averaged: half the instances at
    // 100% is 50%, and a pool that reports nothing is not a pool at zero.
    readonly property var reportingPools: root.applicationPools.filter(p => p.reporting > 0)
    readonly property double poolUtilisation: root.reportingPools.length > 0
        ? root.reportingPools.reduce((sum, p) => sum + p.utilisation, 0) / root.reportingPools.length
        : -1
    readonly property int poolBacklog: root.reportingPools.reduce((sum, p) => sum + p.backlog, 0)

    // A percentage already, not a fraction: the manager's own threshold is
    // kBusyUtilisationPercent = 5.0, and what instances report reads 51.7, 61.5. Multiplying by a
    // hundred here would have shown 5173%.
    function utilisationText(value) {
        return value < 0 ? "—" : Math.round(value) + "%"
    }

    // The colours the autoscaler's thresholds imply rather than arbitrary bands: a pool sitting
    // near its ceiling is the one worth noticing.
    function utilisationColor(value) {
        if (value < 0) return "#6b7280"
        if (value >= 80) return "#ff6b6b"
        if (value >= 50) return "#ffb545"
        return "#4cd97b"
    }

    // Called by F5 as well as by the page's own timer - see Main.qml's refreshCurrentPage(), which
    // passes true for the first. Acted on here only to say that the key did something: the read is
    // the same read either way.
    function refresh(requested) {
        if (requested === true) {
            root.refreshing = true
            root.refreshRequested = true
        }
        root.refreshMetrics()
    }

    function markUpdated() {
        if (!root.refreshRequested)
            return
        // The first answer to arrive is the one that stamps it: the tiles come back one at a time,
        // and the last of them can be seconds later - long enough that a line updating on it would
        // look like the key was slow.
        root.refreshRequested = false
        root.refreshing = false
        root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
    }

    function refreshMetrics() {
        // The pools, which are read rather than charted - see applicationPools above.
        eapClient.fetchApplications("")
        emmClient.fetchModules()
        // The older of the two load roads - see emoUtilisation. One request per metric, not one per
        // instance.
        emoClient.fetchLatestByLabel("application-utilisation")
        emoClient.fetchLatestByLabel("application-backlog")
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

    onVisibleChanged: if (visible) root.refresh(true)
    onLoggedInChanged: if (loggedIn && visible) root.refresh(true)

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refreshMetrics()
    }

    Connections {
        target: eapClient
        function onApplicationsLoaded(list, total) {
            root.applications = list
            root.markUpdated()
        }
    }

    Connections {
        target: emmClient
        function onModulesLoaded(list, total) {
            root.modules = list
            root.markUpdated()
        }
    }

    Connections {
        target: emoClient
        function onLatestByLabelLoaded(metricName, latest) {
            if (metricName === "application-utilisation") root.emoUtilisation = latest
            else if (metricName === "application-backlog") root.emoBacklog = latest
            root.markUpdated()
        }
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
            root.markUpdated()
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

            // ── EAP pools ────────────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: poolsColumn.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: poolsColumn
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: poolsHeader.implicitHeight

                        Text {
                            id: poolsHeader
                            text: "Application Pools"
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: poolsHeader.verticalCenter
                            spacing: 20

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.poolInstances + " / " + root.poolCeiling + " instances"
                                color: "#c4c9d1"
                                font.pixelSize: 12
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.utilisationText(root.poolUtilisation) + " used"
                                color: root.utilisationColor(root.poolUtilisation)
                                font.pixelSize: 12
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.poolBacklog + " waiting"
                                color: root.poolBacklog > 0 ? "#ffb545" : "#6b7280"
                                font.pixelSize: 12
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 11
                        // Said plainly because this tile is the odd one out on a page of charts,
                        // and because the numbers come from somewhere unusual.
                        text: "What each application's pool is doing right now, not a history of it: utilisation and "
                              + "backlog are what an instance reports about itself for the autoscaler to act on, and "
                              + "they are deliberately kept out of the metrics store. Utilisation is the mean across "
                              + "the instances that report; backlog is their total, because half a pool at 100% is a "
                              + "pool at 50%, while half a pool holding 500 each is 1000 waiting."
                    }

                    Text {
                        visible: root.applicationPools.length === 0
                        text: "No application pools are running."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.applicationPools

                        delegate: Item {
                            id: poolRow
                            required property var modelData

                            width: poolsColumn.width
                            height: 44

                            // Name, and underneath it the name the pool actually runs as when the
                            // two differ - which is what the module list and the host show.
                            Column {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.3
                                spacing: 2

                                Text {
                                    text: poolRow.modelData.applicationId
                                    color: "#e5e7eb"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                                Text {
                                    visible: poolRow.modelData.runtimeName !== poolRow.modelData.applicationId
                                    text: poolRow.modelData.runtimeName
                                    color: "#6b7280"
                                    font.pixelSize: 10
                                    font.family: "monospace"
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }

                            // Instances against the ceiling the pool may grow to: the pair that says
                            // whether there is headroom left.
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: parent.width * 0.32
                                anchors.verticalCenter: parent.verticalCenter
                                text: poolRow.modelData.running + " / " + poolRow.modelData.maxInstances
                                color: poolRow.modelData.running >= poolRow.modelData.maxInstances
                                       ? "#ffb545" : "#c4c9d1"
                                font.pixelSize: 12
                            }

                            // Utilisation as a bar, because a proportion is what it is.
                            Rectangle {
                                id: utilisationTrack
                                anchors.left: parent.left
                                anchors.leftMargin: parent.width * 0.44
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * 0.3
                                height: 8
                                radius: 4
                                color: "#2c313c"

                                Rectangle {
                                    width: poolRow.modelData.utilisation > 0
                                           ? Math.min(1, poolRow.modelData.utilisation / 100) * utilisationTrack.width
                                           : 0
                                    height: parent.height
                                    radius: parent.radius
                                    color: root.utilisationColor(poolRow.modelData.utilisation)
                                }
                            }

                            Text {
                                anchors.left: utilisationTrack.right
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.utilisationText(poolRow.modelData.utilisation)
                                color: root.utilisationColor(poolRow.modelData.utilisation)
                                font.pixelSize: 12
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                // "—" rather than 0 for a pool nothing reports from: an instance
                                // that has never said anything is not an instance saying it is idle,
                                // and the autoscaler treats the two differently too.
                                text: poolRow.modelData.reporting === 0
                                      ? "not reporting"
                                      : poolRow.modelData.backlog + " waiting"
                                      + (poolRow.modelData.reporting < poolRow.modelData.running
                                         ? " · " + poolRow.modelData.reporting + " of "
                                           + poolRow.modelData.running + " reporting" : "")
                                color: poolRow.modelData.reporting === 0 ? "#6b7280"
                                       : (poolRow.modelData.backlog > 0 ? "#ffb545" : "#6b7280")
                                font.pixelSize: 11
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: "#232830"
                            }
                        }
                    }
                }
            }

            // The page's own "last update", directly under the last tile: the tiles each carry
            // their own, and none of them answers "is this page live at all". Left rather than
            // right because it reads as a footnote to the content above it, not as a control.
            Item {
                width: parent.width
                height: 28

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    BusyIndicator {
                        running: root.refreshing
                        visible: root.refreshing
                        width: 14
                        height: 14
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.refreshing ? "Refreshing…" : "Last update " + root.lastUpdatedText
                        color: "#6b7280"
                        font.pixelSize: 11
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        // What the stamp beside it does and does not mean. The tiles keep updating
                        // on the timer in between, so saying only "last update" would read as
                        // though nothing had happened since.
                        text: appSettings.autoRefreshSeconds > 0
                              ? "· F5 · refreshing on its own every " + appSettings.autoRefreshSeconds + "s"
                              : "· F5 to refresh"
                        color: "#4a5160"
                        font.pixelSize: 11
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
