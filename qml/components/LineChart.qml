import QtQuick

// Minimal Canvas-based multi-series line chart - no QtCharts dependency (the statically-linked Qt
// build this app ships with only includes qtbase/qtdeclarative/qtshadertools, not qtcharts).
// Points within a series are spaced evenly along X regardless of their actual timestamp gaps,
// which is fine here since every series comes from emo's fixed-interval flush (one point per
// averaging period).
Item {
    id: root

    // One entry per line: {name: string, color: color, points: [{"timestamp": ISO string, "value": number}]}
    property var series: []
    property string valueSuffix: ""
    property int decimals: 0

    readonly property bool hasData: series.some(s => s.points && s.points.length > 0)

    implicitHeight: 160

    function formatValue(v) {
        return (decimals > 0 ? v.toFixed(decimals) : Math.round(v)) + valueSuffix
    }

    function formatTime(iso) {
        if (!iso) return ""
        const d = new Date(iso)
        return isNaN(d.getTime()) ? "" : Qt.formatTime(d, "hh:mm")
    }

    Text {
        visible: !root.hasData
        anchors.centerIn: parent
        text: "No data yet"
        color: "#6b7280"
        font.pixelSize: 12
    }

    // Legend
    Row {
        id: legend
        visible: root.hasData && root.series.length > 1
        anchors.top: parent.top
        anchors.right: parent.right
        spacing: 14

        Repeater {
            model: root.series
            delegate: Row {
                spacing: 5
                Rectangle { width: 8; height: 8; radius: 4; color: modelData.color; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: modelData.name + (modelData.points.length > 0 ? " (" + root.formatValue(modelData.points[modelData.points.length - 1].value) + ")" : "")
                    color: "#9aa1ac"
                    font.pixelSize: 11
                }
            }
        }
    }

    Canvas {
        id: canvas
        anchors.top: legend.visible ? legend.bottom : parent.top
        anchors.topMargin: legend.visible ? 6 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        visible: root.hasData

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const nonEmpty = root.series.filter(s => s.points && s.points.length > 0)
            if (nonEmpty.length === 0)
                return

            const topPad = 18
            const bottomPad = 20
            const leftPad = 4
            const rightPad = 4
            const plotWidth = width - leftPad - rightPad
            const plotHeight = height - topPad - bottomPad

            let minV = nonEmpty[0].points[0].value
            let maxV = minV
            for (const s of nonEmpty) {
                for (const p of s.points) {
                    minV = Math.min(minV, p.value)
                    maxV = Math.max(maxV, p.value)
                }
            }
            if (minV === maxV) {
                minV -= 1
                maxV += 1
            }

            const xFor = (pts, i) => leftPad + (pts.length === 1 ? plotWidth / 2 : plotWidth * i / (pts.length - 1))
            const yFor = (v) => topPad + plotHeight - (plotHeight * (v - minV) / (maxV - minV))

            // Baseline grid
            ctx.strokeStyle = "#2c313c"
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(leftPad, topPad + plotHeight)
            ctx.lineTo(leftPad + plotWidth, topPad + plotHeight)
            ctx.stroke()

            for (const s of nonEmpty) {
                const pts = s.points
                const singleSeries = nonEmpty.length === 1

                if (singleSeries) {
                    // Filled area under the line - only when there's just one series, since
                    // several overlapping fills would just look muddy.
                    ctx.beginPath()
                    ctx.moveTo(xFor(pts, 0), topPad + plotHeight)
                    for (let i = 0; i < pts.length; i++) ctx.lineTo(xFor(pts, i), yFor(pts[i].value))
                    ctx.lineTo(xFor(pts, pts.length - 1), topPad + plotHeight)
                    ctx.closePath()
                    ctx.fillStyle = Qt.rgba(s.color.r, s.color.g, s.color.b, 0.12)
                    ctx.fill()
                }

                ctx.beginPath()
                for (let i = 0; i < pts.length; i++) {
                    const x = xFor(pts, i)
                    const y = yFor(pts[i].value)
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.strokeStyle = s.color
                ctx.lineWidth = 2
                ctx.stroke()

                // Latest point marker
                const lastX = xFor(pts, pts.length - 1)
                const lastY = yFor(pts[pts.length - 1].value)
                ctx.beginPath()
                ctx.arc(lastX, lastY, 3, 0, 2 * Math.PI)
                ctx.fillStyle = s.color
                ctx.fill()
            }

            // Shared max value label (top-left) - per-series latest values are in the legend
            // when there's more than one series; a single series also gets its own latest label.
            ctx.fillStyle = "#9aa1ac"
            ctx.font = "11px sans-serif"
            ctx.textAlign = "left"
            ctx.fillText(root.formatValue(maxV), leftPad, 12)
            if (nonEmpty.length === 1) {
                ctx.textAlign = "right"
                ctx.fillText(root.formatValue(nonEmpty[0].points[nonEmpty[0].points.length - 1].value), width - rightPad, 12)
            }

            // First/last timestamp labels, taken from the longest series
            const longest = nonEmpty.reduce((a, b) => b.points.length > a.points.length ? b : a)
            ctx.textAlign = "left"
            ctx.fillText(root.formatTime(longest.points[0].timestamp), leftPad, height - 6)
            ctx.textAlign = "right"
            ctx.fillText(root.formatTime(longest.points[longest.points.length - 1].timestamp), width - rightPad, height - 6)
        }

        Connections {
            target: root
            function onSeriesChanged() { canvas.requestPaint() }
        }
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
    }
}
