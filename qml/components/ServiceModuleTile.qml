import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// One module's "<module>-service-count"/"<module>-service-time" pair, as two charts in a foldable
// tile - the shape every euclid module's Core::Monitoring::MonitoringTimer instrumentation
// produces, so EQS/ESM/ENS/EAM differ only by which metric name is fetched into it.
//
// Both series arrive already aggregated across the module's actions (see
// EmoClient::fetchAggregatedSeries), which is why each chart is a single line rather than the
// per-method bundle the gateway tile draws.
FoldableTile {
    id: root

    property var countPoints: []
    property var timePoints: []
    // Passed through to both charts - see LineChart.timeFormat.
    property string timeFormat: "hh:mm"
    property string footerText: ""

    signal refreshRequested()

    expanded: true

    headerContent: [
        Button {
            text: "⟳"
            font.pixelSize: 16
            flat: true
            implicitWidth: 32
            implicitHeight: 32
            Material.theme: Material.Dark
            onClicked: root.refreshRequested()
        }
    ]

    contentData: [
        Column {
            width: root.width - 32
            spacing: 20

            Column {
                width: parent.width
                spacing: 8
                Text { text: "Request Count"; color: "#c4c9d1"; font.pixelSize: 12; font.bold: true }
                LineChart {
                    width: parent.width
                    height: 160
                    timeFormat: root.timeFormat
                    series: [ { name: "Requests", color: "#4f8cff", points: root.countPoints } ]
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
                    timeFormat: root.timeFormat
                    series: [ { name: "Service time", color: "#c56bff", points: root.timePoints } ]
                }
            }

            Text {
                text: root.footerText
                color: "#6b7280"
                font.pixelSize: 11
            }
        }
    ]
}
