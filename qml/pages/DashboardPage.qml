import QtQuick
import QtQuick.Controls
import "../components"

Item {
    id: root
    property bool loggedIn: false

    // The dashboard shows overall system load, not a single module's - "average" over the
    // last hour across all modules (no labelName/labelValue filter) is the closest thing emo
    // exposes to a system-wide figure.
    property real cpuPercent: -1
    property real memoryPercent: -1

    // "gateway-service-count" is recorded once per request in the gateway's router, labelled by
    // HTTP method - the closest thing emo exposes to overall traffic across every module. The
    // aggregated fetch folds those labels into one point per bucket (a RATE sums over its labels),
    // which is the total request count this chart wants.
    //
    // DAY resolution, because the bars are days. One bucket costs one row per label, so the cap is
    // buckets * labels: far more than the seven days drawn, since the oldest bucket of a response
    // that hit the cap is dropped server-side as incomplete.
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
        emoClient.fetchAverage("euclid-cpu-usage")
        emoClient.fetchAverage("euclid-memory-usage-percent")
        emoClient.fetchAggregatedSeries(root.trafficMetric, root.trafficRowLimit, "DAY")
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
        target: emoClient
        function onAverageLoaded(name, value) {
            if (name === "euclid-cpu-usage") root.cpuPercent = value
            else if (name === "euclid-memory-usage-percent") root.memoryPercent = value
        }
        function onAverageFailed(name, message) {
            if (name === "euclid-cpu-usage") root.cpuPercent = -1
            else if (name === "euclid-memory-usage-percent") root.memoryPercent = -1
        }
        // The analytics page asks for this metric too, but per method - an aggregated response is
        // the one with no label, which is what this page asked for and what it draws.
        function onSeriesLoaded(name, labelValue, points) {
            if (name !== root.trafficMetric || labelValue.length > 0) return
            root.trafficPoints = points
            root.trafficError = ""
        }
        function onSeriesFailed(name, labelValue, message) {
            if (name !== root.trafficMetric || labelValue.length > 0) return
            root.trafficPoints = []
            root.trafficError = message
        }
    }

    ScrollView {
        id: scrollView
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            width: scrollView.availableWidth
            spacing: 28

            SectionHeader {
                title: "Dashboard"
                subtitle: "Welcome back, here's what's happening today."
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "Active Users"
                    value: "12,483"
                    trend: "+4.3% this week"
                    trendUp: true
                    accent: "#4f8cff"
                }
                StatCard {
                    title: "Revenue"
                    value: "$48,920"
                    trend: "+8.1% this week"
                    trendUp: true
                    accent: "#4cd97b"
                }
                StatCard {
                    title: "Error Rate"
                    value: "0.42%"
                    trend: "-1.2% this week"
                    trendUp: false
                    accent: "#ffb545"
                }
                StatCard {
                    title: "Avg. Session"
                    value: "6m 12s"
                    trend: "+0.8% this week"
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
}
