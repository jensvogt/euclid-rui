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
        { id: "eam", title: "EAM Traffic", description: "All EAM actions" }
    ]

    // {module id: points}, one entry per tile above.
    property var moduleCountPoints: ({})
    property var moduleTimePoints: ({})

    // All tiles are fetched in the same pass, so one timestamp covers them.
    property string metricsUpdatedText: "—"

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

    // User-configurable via the chart settings dialog (gear icon). enabledMethods is a
    // {methodName: bool} map - all four methods are always fetched (cheap, and switching one
    // back on shouldn't need a refetch), visibility is purely a client-side display filter.
    property int historyRangeIndex: 0
    property var enabledMethods: ({ GET: true, POST: true, PUT: true, DELETE: true })

    readonly property var historyRange: root.historyRanges[root.historyRangeIndex]

    // Start of the selected calendar period. "limit" alone would give the last N buckets, which
    // at 09:00 would reach back into yesterday and make the "Today" label a lie, so points before
    // this instant are dropped once they arrive.
    //
    // Month/year boundaries are taken in UTC because DAY buckets are aligned to UTC midnight: a
    // local-midnight boundary would drop the 1st's bucket in every zone west of Greenwich.
    // Today/this week use local midnight, which is what those words mean to the user, and their
    // buckets are at most an hour wide so the boundary is off by at most one point.
    function historyRangeStart() {
        const now = new Date()
        switch (root.historyRangeIndex) {
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

    function pointsInRange(points) {
        const start = root.historyRangeStart().getTime()
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

    function refreshMetrics() {
        if (!root.loggedIn)
            return
        const range = root.historyRange
        for (const m of root.httpMethods) {
            emoClient.fetchSeries("gateway-service-count", "method", m.name, range.limit, range.resolution)
            emoClient.fetchSeries("gateway-service-time", "method", m.name, range.limit, range.resolution)
        }
        for (const m of root.serviceModules) {
            emoClient.fetchAggregatedSeries(m.id + "-service-count", range.limit * root.maxServiceActions, range.resolution)
            emoClient.fetchAggregatedSeries(m.id + "-service-time", range.limit * root.maxServiceActions, range.resolution)
        }
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
            const inRange = root.pointsInRange(points)
            if (name === "gateway-service-count") {
                const byMethod = Object.assign({}, root.requestCountByMethod)
                byMethod[labelValue] = inRange
                root.requestCountByMethod = byMethod
            } else if (name === "gateway-service-time") {
                const byMethod = Object.assign({}, root.requestTimeByMethod)
                byMethod[labelValue] = inRange
                root.requestTimeByMethod = byMethod
            } else if (!root.setModulePoints(name, inRange)) return
            root.metricsUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
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

            SectionHeader {
                title: "Analytics"
                subtitle: "Traffic sources and conversion breakdown."
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
                        onClicked: chartSettingsDialog.open()
                    },
                    Button {
                        text: "⟳"
                        font.pixelSize: 16
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        Material.theme: Material.Dark
                        onClicked: root.refreshMetrics()
                    }
                ]

                contentData: [
                    Column {
                        width: gatewayTile.width - 32
                        spacing: 20

                        Column {
                            width: parent.width
                            spacing: 8
                            Text { text: "Request Count"; color: "#c4c9d1"; font.pixelSize: 12; font.bold: true }
                            LineChart {
                                width: parent.width
                                height: 160
                                timeFormat: root.historyRange.timeFormat
                                series: root.seriesFor(root.requestCountByMethod)
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 8
                            Text { text: "Request Time"; color: "#c4c9d1"; font.pixelSize: 12; font.bold: true }
                            LineChart {
                                width: parent.width
                                height: 160
                                valueSuffix: " ms"
                                decimals: 1
                                timeFormat: root.historyRange.timeFormat
                                series: root.seriesFor(root.requestTimeByMethod)
                            }
                        }

                        Text {
                            text: root.historyRange.label + " · updated " + root.metricsUpdatedText
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                    }
                ]
            }

            // One tile per instrumented module. No gear on these: the period set in the Gateway
            // tile's chart settings applies to every chart on the page, and they have no
            // per-series toggles of their own.
            Repeater {
                model: root.serviceModules
                delegate: ServiceModuleTile {
                    required property var modelData

                    width: contentColumn.width
                    title: modelData.title
                    timeFormat: root.historyRange.timeFormat
                    countPoints: root.moduleCountPoints[modelData.id] || []
                    timePoints: root.moduleTimePoints[modelData.id] || []
                    footerText: modelData.description + " · " + root.historyRange.label
                                + " · updated " + root.metricsUpdatedText
                    onRefreshRequested: root.refreshMetrics()
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

    Dialog {
        id: chartSettingsDialog
        modal: true
        anchors.centerIn: parent
        width: 360
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        // ComboBox's currentIndex binding gets clobbered by its own internal model-populate
        // logic, same as every other dialog's combo/spinbox in this app - set it imperatively
        // on open instead (see createKeyDialog's onOpened in EkmKeysPage.qml for the same idiom).
        onOpened: historyCombo.currentIndex = root.historyRangeIndex

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
                Text { text: "Chart Settings"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "The period applies to every chart on this page; the method toggles to the Gateway Traffic charts."
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
                    onActivated: {
                        root.historyRangeIndex = currentIndex
                        // The points already on screen are of the previous period's resolution and
                        // would be plotted against the new period's axis labels until its responses
                        // land - drop them rather than show a chart that mixes bucket widths.
                        root.requestCountByMethod = ({})
                        root.requestTimeByMethod = ({})
                        root.moduleCountPoints = ({})
                        root.moduleTimePoints = ({})
                        root.refreshMetrics()
                    }
                }
                Text {
                    text: {
                        const r = root.historyRange
                        return r.resolution === "RAW" ? "One point per emo flush period (5 min)"
                             : r.resolution === "HOUR" ? "One point per hour" : "One point per day"
                    }
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: historyColumn.width
                }
            }

            Column {
                id: methodsColumn
                width: parent.width
                spacing: 10
                Text { text: "HTTP Methods"; color: "#9aa1ac"; font.pixelSize: 12 }

                Repeater {
                    model: root.httpMethods
                    delegate: Row {
                        width: methodsColumn.width
                        height: 28
                        spacing: 10

                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: modelData.color
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: modelData.name
                            color: "#e5e7eb"
                            font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 66
                        }
                        ToggleSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.enabledMethods[modelData.name]
                            onToggled: (checked) => {
                                const updated = Object.assign({}, root.enabledMethods)
                                updated[modelData.name] = checked
                                root.enabledMethods = updated
                            }
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
