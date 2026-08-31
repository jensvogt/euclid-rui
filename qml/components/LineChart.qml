import QtQuick

// Minimal Canvas-based multi-series line chart - no QtCharts dependency (the statically-linked Qt
// build this app ships with only includes qtbase/qtdeclarative/qtshadertools, and QtCharts is
// GPL/commercial only, which a statically linked binary cannot take on lightly).
//
// Points are placed by their actual timestamp, so a gap in the data - a restart, a quiet hour, a
// missing rollup bucket - shows up as a long flat stretch instead of being hidden by even spacing.
//
// Interaction: hover for a crosshair reading every series at that moment, click a legend entry to
// hide that series, drag horizontally to zoom into a time range, double-click to zoom back out.
Item {
    id: root

    // One entry per line: {name: string, color: color, points: [{"timestamp": ISO string, "value": number}]}
    property var series: []
    property string valueSuffix: ""
    property int decimals: 0
    // Qt.formatDateTime() format for the axis ends and the crosshair readout. The default suits
    // points minutes apart; a chart spanning days or months should widen it (e.g. "dd MMM"),
    // otherwise both ends read "00:00".
    property string timeFormat: "hh:mm"
    // Roughly how many horizontal gridlines to aim for; the actual count lands on round values.
    property int tickCount: 3

    readonly property bool hasData: series.some(s => s.points && s.points.length > 0)

    implicitHeight: 160

    // {seriesName: true} for series the user has clicked out of the legend. Keyed by name so it
    // survives the series list being rebuilt on every refresh.
    property var hiddenSeries: ({})

    // Zoomed-in time window, or NaN for "all of it". Set by dragging, cleared by double-click.
    property real viewTMin: NaN
    property real viewTMax: NaN
    readonly property bool zoomed: !isNaN(root.viewTMin) && !isNaN(root.viewTMax)

    readonly property real rightPad: 4
    readonly property real topPad: 18
    readonly property real bottomPad: 20
    // Gutter for the y-axis tick labels, sized to the widest one actually drawn.
    readonly property real leftPad: root.plot.series.length > 0 ? Math.max(24, tickMetrics.width + 10) : 4

    // Everything the painting and the interactions need, derived once per series/zoom/hide change:
    // {series: [{name, color, points: [{t, value, timestamp}]}], tMin, tMax, vMin, vMax}, where
    // tMin/tMax are the *visible* window and vMin/vMax cover only what falls inside it.
    readonly property var plot: root.buildPlot()
    readonly property var ticks: root.buildTicks()

    function isHidden(name) {
        return root.hiddenSeries[name] === true
    }

    function formatValue(v) {
        return (decimals > 0 ? v.toFixed(decimals) : Math.round(v)) + valueSuffix
    }

    // Tick labels need their own precision: with a step below 1 the chart's own `decimals` (0 for
    // counts) would print several gridlines as the same number.
    function formatTick(v) {
        const step = root.ticks.length > 1 ? Math.abs(root.ticks[1] - root.ticks[0]) : 1
        const digits = step >= 1 ? root.decimals : Math.min(3, Math.ceil(-Math.log(step) / Math.LN10))
        return (digits > 0 ? v.toFixed(digits) : Math.round(v)) + root.valueSuffix
    }

    function formatTime(iso) {
        if (!iso) return ""
        const d = new Date(iso)
        return isNaN(d.getTime()) ? "" : Qt.formatDateTime(d, root.timeFormat)
    }

    function buildPlot() {
        const result = { series: [], tMin: 0, tMax: 0, vMin: 0, vMax: 0 }

        const nonEmpty = (root.series || []).filter(s => s.points && s.points.length > 0 && !root.isHidden(s.name))
        if (nonEmpty.length === 0)
            return result

        // A single unparseable timestamp drops the whole chart back to even index spacing, rather
        // than mixing two x scales - t is then just the point's position in its series.
        let timeAxis = true
        for (const s of nonEmpty) {
            for (const p of s.points) {
                if (isNaN(new Date(p.timestamp).getTime())) {
                    timeAxis = false
                    break
                }
            }
            if (!timeAxis) break
        }

        let tMin = Infinity, tMax = -Infinity
        for (const s of nonEmpty) {
            const points = []
            for (let i = 0; i < s.points.length; i++) {
                const p = s.points[i]
                const t = timeAxis ? new Date(p.timestamp).getTime() : i
                points.push({ t: t, value: p.value, timestamp: p.timestamp })
                tMin = Math.min(tMin, t)
                tMax = Math.max(tMax, t)
            }
            result.series.push({ name: s.name, color: s.color, points: points })
        }

        // Zooming narrows the window; every series keeps all of its points so its line still
        // enters and leaves the window at the edges, and painting clips to the plot area.
        result.tMin = root.zoomed ? Math.max(tMin, root.viewTMin) : tMin
        result.tMax = root.zoomed ? Math.min(tMax, root.viewTMax) : tMax
        if (result.tMax <= result.tMin) {
            result.tMin = tMin
            result.tMax = tMax
        }

        // The value range covers what is on screen, so zooming in on a quiet stretch actually
        // resolves it instead of leaving it flat against a peak elsewhere.
        let vMin = Infinity, vMax = -Infinity
        for (const s of result.series) {
            for (const p of s.points) {
                if (p.t < result.tMin || p.t > result.tMax) continue
                vMin = Math.min(vMin, p.value)
                vMax = Math.max(vMax, p.value)
            }
        }
        if (vMin === Infinity) {
            // Window between two samples: fall back to the whole series rather than divide by zero.
            for (const s of result.series) {
                for (const p of s.points) {
                    vMin = Math.min(vMin, p.value)
                    vMax = Math.max(vMax, p.value)
                }
            }
        }
        // A flat line still needs a band to sit in, and one lone point needs a range to divide by.
        if (vMin === vMax) {
            vMin -= 1
            vMax += 1
        }
        result.vMin = vMin
        result.vMax = vMax
        return result
    }

    // Round gridline values (1, 2 or 5 times a power of ten) inside the current value range.
    function buildTicks() {
        const plot = root.plot
        if (plot.series.length === 0)
            return []

        const span = plot.vMax - plot.vMin
        if (!(span > 0))
            return [plot.vMin]

        const rawStep = span / Math.max(1, root.tickCount)
        const magnitude = Math.pow(10, Math.floor(Math.log(rawStep) / Math.LN10))
        const normalized = rawStep / magnitude
        // Thresholds sit between the candidates rather than at them, so a raw step of 5.3 picks 5
        // (three gridlines) instead of rounding up to 10 and leaving a single line on the chart.
        const step = (normalized < 1.5 ? 1 : normalized < 3 ? 2 : normalized < 7 ? 5 : 10) * magnitude

        const values = []
        // The epsilon keeps a tick that lands exactly on vMax from being lost to rounding.
        for (let v = Math.ceil(plot.vMin / step) * step; v <= plot.vMax + step * 1e-6; v += step)
            values.push(v)
        return values
    }

    function xFor(t) {
        const span = root.plot.tMax - root.plot.tMin
        const width = canvas.width - root.leftPad - root.rightPad
        // Everything at one instant (or a single point) sits in the middle rather than at x=0.
        if (span <= 0) return root.leftPad + width / 2
        return root.leftPad + width * (t - root.plot.tMin) / span
    }

    function timeAt(x) {
        const span = root.plot.tMax - root.plot.tMin
        const width = canvas.width - root.leftPad - root.rightPad
        if (span <= 0 || width <= 0) return root.plot.tMin
        return root.plot.tMin + span * Math.max(0, Math.min(1, (x - root.leftPad) / width))
    }

    function yFor(v) {
        const height = canvas.height - root.topPad - root.bottomPad
        return root.topPad + height - height * (v - root.plot.vMin) / (root.plot.vMax - root.plot.vMin)
    }

    // Nearest sample of `points` to time t, by absolute distance. Points are chronological, but a
    // linear scan is cheap at these sizes and stays correct if they ever aren't.
    function nearestPoint(points, t) {
        let best = null
        let bestDistance = Infinity
        for (const p of points) {
            const distance = Math.abs(p.t - t)
            if (distance < bestDistance) {
                bestDistance = distance
                best = p
            }
        }
        return best
    }

    // {t, timestamp, rows: [{name, color, value, y}]} for the sample nearest the cursor, or null
    // when there is nothing to read. The anchor is a real sample rather than the raw cursor time,
    // so the crosshair always sits on data instead of between two points.
    property var hover: null

    function updateHover(mouseX) {
        if (root.plot.series.length === 0) {
            root.hover = null
            return
        }

        const cursorT = root.timeAt(mouseX)

        let anchor = null
        let anchorDistance = Infinity
        for (const s of root.plot.series) {
            const nearest = root.nearestPoint(s.points, cursorT)
            const distance = Math.abs(nearest.t - cursorT)
            if (distance < anchorDistance) {
                anchorDistance = distance
                anchor = nearest
            }
        }
        if (!anchor) {
            root.hover = null
            return
        }

        const rows = []
        for (const s of root.plot.series) {
            const nearest = root.nearestPoint(s.points, anchor.t)
            rows.push({ name: s.name, color: s.color, value: nearest.value, y: root.yFor(nearest.value) })
        }
        root.hover = { t: anchor.t, timestamp: anchor.timestamp, rows: rows }
    }

    function toggleSeries(name) {
        const updated = Object.assign({}, root.hiddenSeries)
        if (updated[name]) delete updated[name]
        else updated[name] = true
        root.hiddenSeries = updated
    }

    function resetZoom() {
        root.viewTMin = NaN
        root.viewTMax = NaN
    }

    onPlotChanged: root.hover = null
    // A new period (or new data) invalidates a window picked against the old one.
    onSeriesChanged: root.resetZoom()

    // Sizes the y-axis gutter. Measuring the widest label beats a fixed width, which would either
    // clip six-figure counts or waste space on two-digit ones.
    TextMetrics {
        id: tickMetrics
        font.pixelSize: 11
        text: {
            let widest = ""
            for (const value of root.ticks) {
                const label = root.formatTick(value)
                if (label.length > widest.length) widest = label
            }
            return widest
        }
    }

    Text {
        visible: !root.hasData
        anchors.centerIn: parent
        text: "No data yet"
        color: "#6b7280"
        font.pixelSize: 12
    }

    Text {
        visible: root.hasData && root.plot.series.length === 0
        anchors.centerIn: parent
        text: "All series hidden"
        color: "#6b7280"
        font.pixelSize: 12
    }

    // Legend - click an entry to hide or show that series.
    Row {
        id: legend
        visible: root.hasData && root.series.length > 1
        anchors.top: parent.top
        anchors.right: parent.right
        spacing: 14

        Repeater {
            model: root.series
            // An Item, not the Row itself: a Row refuses to position children that use fill or
            // horizontal anchors, and the click target has to fill the entry - putting the
            // MouseArea straight into the Row silently breaks the whole legend.
            delegate: Item {
                id: legendEntry
                required property var modelData

                width: entryRow.implicitWidth
                height: entryRow.implicitHeight
                opacity: root.isHidden(legendEntry.modelData.name) ? 0.4 : 1

                Row {
                    id: entryRow
                    spacing: 5

                    Rectangle {
                        width: 8
                        height: 8
                        radius: 4
                        color: legendEntry.modelData.color
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: legendEntry.modelData.name + (legendEntry.modelData.points.length > 0
                              ? " (" + root.formatValue(legendEntry.modelData.points[legendEntry.modelData.points.length - 1].value) + ")"
                              : "")
                        color: "#9aa1ac"
                        font.pixelSize: 11
                        font.strikeout: root.isHidden(legendEntry.modelData.name)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -3
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleSeries(legendEntry.modelData.name)
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
        visible: root.plot.series.length > 0

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const plot = root.plot
            if (plot.series.length === 0)
                return

            const plotWidth = width - root.leftPad - root.rightPad
            const plotHeight = height - root.topPad - root.bottomPad

            // Gridlines and their labels, in the left gutter
            ctx.font = "11px sans-serif"
            ctx.lineWidth = 1
            for (const value of root.ticks) {
                const y = root.yFor(value)
                if (y < root.topPad - 0.5 || y > root.topPad + plotHeight + 0.5)
                    continue
                ctx.strokeStyle = "#262b35"
                ctx.beginPath()
                // The half-pixel keeps a 1px line from being drawn across two rows of pixels.
                ctx.moveTo(root.leftPad, Math.round(y) + 0.5)
                ctx.lineTo(root.leftPad + plotWidth, Math.round(y) + 0.5)
                ctx.stroke()

                ctx.fillStyle = "#6b7280"
                ctx.textAlign = "right"
                ctx.fillText(root.formatTick(value), root.leftPad - 6, y + 4)
            }

            // Baseline, drawn over the gridlines
            ctx.strokeStyle = "#2c313c"
            ctx.beginPath()
            ctx.moveTo(root.leftPad, root.topPad + plotHeight)
            ctx.lineTo(root.leftPad + plotWidth, root.topPad + plotHeight)
            ctx.stroke()

            // Series are clipped to the plot area: when zoomed, points outside the window would
            // otherwise be painted over the gutter and the labels.
            ctx.save()
            ctx.beginPath()
            ctx.rect(root.leftPad, root.topPad, plotWidth, plotHeight)
            ctx.clip()

            for (const s of plot.series) {
                const pts = s.points
                const singleSeries = plot.series.length === 1

                if (singleSeries) {
                    // Filled area under the line - only when there's just one series, since
                    // several overlapping fills would just look muddy.
                    ctx.beginPath()
                    ctx.moveTo(root.xFor(pts[0].t), root.topPad + plotHeight)
                    for (const p of pts) ctx.lineTo(root.xFor(p.t), root.yFor(p.value))
                    ctx.lineTo(root.xFor(pts[pts.length - 1].t), root.topPad + plotHeight)
                    ctx.closePath()
                    // Qt.alpha() rather than Qt.rgba(s.color.r, ...): series come from plain JS
                    // objects, so s.color is usually still the "#rrggbb" string it was written as,
                    // and a string has no .r/.g/.b - that read yields undefined and paints nothing.
                    ctx.fillStyle = Qt.alpha(s.color, 0.12)
                    ctx.fill()
                }

                ctx.beginPath()
                for (let i = 0; i < pts.length; i++) {
                    const x = root.xFor(pts[i].t)
                    const y = root.yFor(pts[i].value)
                    if (i === 0) ctx.moveTo(x, y)
                    else ctx.lineTo(x, y)
                }
                ctx.strokeStyle = s.color
                ctx.lineWidth = 2
                ctx.stroke()

                // Latest point marker
                ctx.beginPath()
                ctx.arc(root.xFor(pts[pts.length - 1].t), root.yFor(pts[pts.length - 1].value), 3, 0, 2 * Math.PI)
                ctx.fillStyle = s.color
                ctx.fill()
            }
            ctx.restore()

            // Latest value, top right - the per-series ones are in the legend when there is more
            // than one series.
            if (plot.series.length === 1) {
                const only = plot.series[0].points
                ctx.fillStyle = "#9aa1ac"
                ctx.textAlign = "right"
                ctx.fillText(root.formatValue(only[only.length - 1].value), width - root.rightPad, 12)
            }

            // Axis ends, taken from the visible window rather than any one series
            ctx.fillStyle = "#9aa1ac"
            ctx.textAlign = "left"
            const first = root.nearestPoint(plot.series[0].points, plot.tMin)
            ctx.fillText(root.formatTime(first.timestamp), root.leftPad, height - 6)
            ctx.textAlign = "right"
            const longest = plot.series.reduce((a, b) => b.points.length > a.points.length ? b : a)
            const last = root.nearestPoint(longest.points, plot.tMax)
            ctx.fillText(root.formatTime(last.timestamp), width - root.rightPad, height - 6)
        }

        Connections {
            target: root
            function onPlotChanged() { canvas.requestPaint() }
            function onTicksChanged() { canvas.requestPaint() }
        }
        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        // ── Crosshair, zoom selection ────────────────────────────────────────
        // Drawn as items rather than into the Canvas: repainting every series on each mouse move
        // would redo the whole chart for a one-pixel line.

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton
            cursorShape: Qt.CrossCursor

            // Drag start, in pixels; NaN while not dragging.
            property real dragFrom: NaN
            property real dragTo: NaN
            readonly property bool dragging: !isNaN(dragFrom) && !isNaN(dragTo)
            // Below this the drag was really a click, and zooming into a few pixels of chart would
            // just strand the user in an empty window.
            readonly property int minimumDragPixels: 8

            onPositionChanged: (mouse) => {
                if (isNaN(dragFrom)) {
                    root.updateHover(mouse.x)
                } else {
                    dragTo = mouse.x
                    root.hover = null
                }
            }
            onPressed: (mouse) => {
                dragFrom = mouse.x
                dragTo = mouse.x
                root.hover = null
            }
            onReleased: (mouse) => {
                const from = dragFrom
                dragFrom = NaN
                dragTo = NaN
                if (isNaN(from) || Math.abs(mouse.x - from) < minimumDragPixels) {
                    root.updateHover(mouse.x)
                    return
                }
                const a = root.timeAt(Math.min(from, mouse.x))
                const b = root.timeAt(Math.max(from, mouse.x))
                root.viewTMin = a
                root.viewTMax = b
            }
            onCanceled: {
                dragFrom = NaN
                dragTo = NaN
            }
            onDoubleClicked: root.resetZoom()
            onExited: root.hover = null
        }

        // Zoom selection band
        Rectangle {
            visible: hoverArea.dragging
            color: "#4f8cff"
            opacity: 0.18
            x: Math.min(hoverArea.dragFrom, hoverArea.dragTo)
            width: Math.abs(hoverArea.dragTo - hoverArea.dragFrom)
            y: root.topPad
            height: canvas.height - root.topPad - root.bottomPad
        }

        Text {
            visible: root.zoomed && !hoverArea.dragging
            anchors.horizontalCenter: parent.horizontalCenter
            y: canvas.height - root.bottomPad + 4
            text: "zoomed · double-click to reset"
            color: "#6b7280"
            font.pixelSize: 10
        }

        Rectangle {
            id: crosshair
            visible: hoverArea.containsMouse && !hoverArea.dragging && root.hover !== null
            width: 1
            color: "#4b5565"
            x: root.hover ? root.xFor(root.hover.t) : 0
            y: root.topPad
            height: canvas.height - root.topPad - root.bottomPad
        }

        Repeater {
            model: crosshair.visible && root.hover ? root.hover.rows : []
            delegate: Rectangle {
                id: marker
                required property var modelData

                width: 7
                height: 7
                radius: 3.5
                color: marker.modelData.color
                border.color: "#14161b"
                border.width: 1
                x: crosshair.x - marker.width / 2
                y: marker.modelData.y - marker.height / 2
            }
        }

        Rectangle {
            id: readout
            visible: crosshair.visible
            radius: 6
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
            width: readoutColumn.implicitWidth + 16
            height: readoutColumn.implicitHeight + 12
            // Flips to the left of the crosshair when it would otherwise run off the right edge.
            x: Math.max(0, crosshair.x + 10 + width <= canvas.width ? crosshair.x + 10 : crosshair.x - 10 - width)
            y: root.topPad

            Column {
                id: readoutColumn
                anchors.centerIn: parent
                spacing: 3

                Text {
                    text: root.hover ? root.formatTime(root.hover.timestamp) : ""
                    color: "#9aa1ac"
                    font.pixelSize: 10
                }

                Repeater {
                    model: root.hover ? root.hover.rows : []
                    delegate: Row {
                        id: readoutRow
                        required property var modelData

                        spacing: 6

                        Rectangle {
                            width: 7
                            height: 7
                            radius: 3.5
                            color: readoutRow.modelData.color
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: readoutRow.modelData.name
                            color: "#9aa1ac"
                            font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.formatValue(readoutRow.modelData.value)
                            color: "#e5e7eb"
                            font.pixelSize: 11
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }
}
