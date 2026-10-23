import QtQuick
import QtQuick.Controls

// Minimal Canvas-based multi-series line chart - no QtCharts dependency (the statically-linked Qt
// build this app ships with only includes qtbase/qtdeclarative/qtshadertools, and QtCharts is
// GPL/commercial only, which a statically linked binary cannot take on lightly).
//
// Points are placed by their actual timestamp, so a gap in the data - a restart, a quiet hour, a
// missing rollup bucket - shows up as a long flat stretch instead of being hidden by even spacing.
//
// Interaction: hover for a crosshair reading every series at that moment, click a legend entry -
// inline, or in the list behind the button when there are too many to fit - to hide that series,
// drag horizontally to zoom into a time range, ctrl+wheel to zoom in and out around the pointer,
// double-click to zoom back out.
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

    // Zoomed-in time window, or NaN for "all of it". Set by dragging or the wheel, cleared by
    // double-click.
    property real viewTMin: NaN
    property real viewTMax: NaN
    readonly property bool zoomed: !isNaN(root.viewTMin) && !isNaN(root.viewTMax)
    // The full extent of the data at the moment the window was picked, kept so that a later
    // refresh can tell whether it is still looking at the same period - see onSeriesChanged.
    property real zoomBaseSpan: 0

    readonly property real rightPad: 4
    readonly property real topPad: 18
    readonly property real bottomPad: 20
    // Gutter for the y-axis tick labels, sized to the widest one actually drawn.
    readonly property real leftPad: root.plot.series.length > 0 ? Math.max(24, tickMetrics.width + 10) : 4

    // Everything the painting and the interactions need, derived once per series/zoom/hide change:
    // {series: [{name, color, points: [{t, value, timestamp}]}], tMin, tMax, vMin, vMax, dataTMin,
    // dataTMax}, where tMin/tMax are the *visible* window, vMin/vMax cover only what falls inside
    // it, and dataTMin/dataTMax are the full extent of the data behind it - what zooming is bounded
    // by, and what tells a refresh of the same period apart from a change of period.
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
        const result = { series: [], tMin: 0, tMax: 0, vMin: 0, vMax: 0, dataTMin: 0, dataTMax: 0 }

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

        result.dataTMin = tMin
        result.dataTMax = tMax

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

    // The one way a window gets set, so that zoomBaseSpan cannot be left behind by one of the two
    // gestures that set one.
    function setZoom(tMin, tMax) {
        root.zoomBaseSpan = root.plot.dataTMax - root.plot.dataTMin
        root.viewTMin = tMin
        root.viewTMax = tMax
    }

    function resetZoom() {
        root.viewTMin = NaN
        root.viewTMax = NaN
        root.zoomBaseSpan = 0
    }

    // Narrow or widen the visible window by `factor` (below 1 zooms in), keeping whatever is under
    // `centerX` pinned to that pixel. Zooming about the pointer rather than about the middle is the
    // whole point of a wheel zoom: the spike being examined stays where it is and the chart opens
    // out around it, instead of sliding away as the window closes on its own centre.
    function zoomBy(factor, centerX) {
        const plot = root.plot
        if (plot.series.length === 0)
            return

        const fullSpan = plot.dataTMax - plot.dataTMin
        const span = plot.tMax - plot.tMin
        if (!(fullSpan > 0) || !(span > 0))
            return

        // 500x in is the floor. Past that the window falls between two samples on any realistic
        // series, and a chart with no points in it is not a more detailed view of anything.
        const newSpan = Math.max(fullSpan / 500, Math.min(fullSpan, span * factor))

        // Widened back out to the whole extent: drop the window rather than hold a full-width one,
        // so the chart follows new data again and the "zoomed" hint takes itself away.
        if (newSpan >= fullSpan) {
            root.resetZoom()
            return
        }

        const anchorT = root.timeAt(centerX)
        let tMin = anchorT - (anchorT - plot.tMin) / span * newSpan
        let tMax = tMin + newSpan
        // Zooming out near either end would otherwise walk the window off the data. Slide it back
        // instead of clipping it, so the wheel still delivers the span it was asked for.
        if (tMin < plot.dataTMin) {
            tMin = plot.dataTMin
            tMax = tMin + newSpan
        }
        if (tMax > plot.dataTMax) {
            tMax = plot.dataTMax
            tMin = tMax - newSpan
        }

        root.setZoom(tMin, tMax)
    }

    onPlotChanged: root.hover = null
    // A new period (or new data) invalidates a window picked against the old one.
    // A new *period* invalidates a window picked against the old one; a refresh of the same period
    // does not. This used to reset on any series change at all, which with the analytics page's
    // refresh timer meant a window picked by hand survived at most one refresh interval - barely
    // noticeable when zooming cost a deliberate drag, and unusable once a wheel notch does it.
    //
    // The span of the data separates the two cases cleanly: the ranges on offer step by four times
    // or more (1h, 6h, 24h, 7d), while re-asking for the same one moves the extent by a sample or
    // two. So anything that halves or doubles the span is a new period, and anything short of that
    // is the same period with fresher data - where the window still means what the user meant by
    // it, and buildPlot() clamps it to whatever actually arrived.
    //
    // buildPlot() rather than the `plot` property: this handler runs before that binding has been
    // re-evaluated, so reading it here describes the data that has just been replaced - which would
    // make every period change look like a refresh of the same one and keep a window that no longer
    // meant anything.
    onSeriesChanged: {
        if (!root.zoomed)
            return
        const fresh = root.buildPlot()
        const span = fresh.dataTMax - fresh.dataTMin
        if (!(span > 0) || !(root.zoomBaseSpan > 0) || span < root.zoomBaseSpan / 2 || span > root.zoomBaseSpan * 2)
            root.resetZoom()
        else
            root.zoomBaseSpan = span
    }

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
    //
    // The inline one is a single row that does not wrap, so past a handful of series it ran off
    // the left edge of the chart and took the earliest names with it - EQS splits its operations
    // nine ways, and the first of them read "eceiveMessages.priorityCount". It now gives way to
    // the button beside it as soon as it no longer fits, and the button opens the same list
    // somewhere it can be read.
    Row {
        id: legendBar
        visible: root.hasData && root.series.length > 1
        anchors.top: parent.top
        anchors.right: parent.right
        spacing: 10

        Row {
            id: legend
            visible: root.hasData && root.series.length > 1
                     && legend.implicitWidth + legendButton.width + legendBar.spacing <= root.width - root.leftPad
            anchors.verticalCenter: parent.verticalCenter
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

        // Always there once there is more than one line, whether or not the inline legend fits:
        // it is also the only way back when every series has been clicked out of sight.
        Rectangle {
            id: legendButton

            visible: root.hasData && root.series.length > 1
            anchors.verticalCenter: parent.verticalCenter
            width: buttonRow.implicitWidth + 14
            height: 18
            radius: 9
            color: legendPopup.visible || legendButtonArea.containsMouse
                   ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)

            Row {
                id: buttonRow
                anchors.centerIn: parent
                spacing: 5

                Text {
                    text: "☰"
                    color: "#9aa1ac"
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.series.length + " series"
                    color: "#9aa1ac"
                    font.pixelSize: 10
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: legendButtonArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: legendPopup.visible ? legendPopup.close() : legendPopup.open()
            }
        }
    }

    // The same list, somewhere with room for it: one line per series, however many there are.
    Popup {
        id: legendPopup

        // Hung under the button rather than centred on the chart: it belongs to this chart, and a
        // chart on this page is 160px tall, so a centred popup would cover the thing being read.
        //
        // Right edges aligned, because the button sits against the right edge of the chart: hung
        // from its left the list would run off the side of the window and take the ends of the
        // names with it, which is the thing this was built to stop.
        parent: legendButton
        x: legendButton.width - width
        y: legendButton.height + 4
        width: 240
        padding: 8
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            radius: 8
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            spacing: 6

            Item {
                width: parent.width
                height: 14

                Text {
                    anchors.left: parent.left
                    text: root.series.length + " series"
                    color: "#6b7280"
                    font.pixelSize: 10
                }

                // Only when there is something to undo, so the row is not offering to do nothing.
                Text {
                    anchors.right: parent.right
                    visible: Object.keys(root.hiddenSeries).length > 0
                    text: "show all"
                    color: showAllArea.containsMouse ? "#4f8cff" : "#9aa1ac"
                    font.pixelSize: 10

                    MouseArea {
                        id: showAllArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.hiddenSeries = ({})
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: "#2c313c" }

            // Scrolled rather than grown: EQS reports nine operations and a queue list can carry
            // more, and a popup taller than the window is no more readable than the row it
            // replaced.
            ScrollView {
                width: parent.width
                height: Math.min(260, popupEntries.implicitHeight)
                clip: true

                Column {
                    id: popupEntries
                    width: legendPopup.availableWidth

                    Repeater {
                        model: root.series

                        delegate: Rectangle {
                            id: popupEntry
                            required property var modelData

                            width: popupEntries.width
                            height: 22
                            color: popupEntryArea.containsMouse ? "#262b35" : "transparent"
                            radius: 4

                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6

                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: popupEntry.modelData.color
                                    opacity: root.isHidden(popupEntry.modelData.name) ? 0.35 : 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    width: parent.width - 14 - valueLabel.width - 12
                                    text: popupEntry.modelData.name
                                    color: "#e5e7eb"
                                    opacity: root.isHidden(popupEntry.modelData.name) ? 0.45 : 1
                                    font.pixelSize: 11
                                    font.strikeout: root.isHidden(popupEntry.modelData.name)
                                    // Middle rather than the end: these names differ in their last
                                    // segment - receiveMessages.priorityCount against
                                    // receiveMessages.claim - so eliding the tail would leave a
                                    // list of identical rows.
                                    elide: Text.ElideMiddle
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    id: valueLabel
                                    text: popupEntry.modelData.points.length > 0
                                          ? root.formatValue(popupEntry.modelData.points[popupEntry.modelData.points.length - 1].value)
                                          : "—"
                                    color: "#9aa1ac"
                                    opacity: root.isHidden(popupEntry.modelData.name) ? 0.45 : 1
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: popupEntryArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleSeries(popupEntry.modelData.name)
                            }
                        }
                    }
                }
            }
        }
    }

    Canvas {
        id: canvas
        anchors.top: legendBar.visible ? legendBar.bottom : parent.top
        anchors.topMargin: legendBar.visible ? 6 : 0
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

            // Without this the drag only works if it is drawn perfectly level. These charts sit in
            // the analytics page's ScrollView, and a Flickable takes the grab from a child as soon
            // as the pointer has moved its threshold in a direction it can flick - so a drag with
            // the few pixels of vertical drift any hand puts into it became a scroll, this area
            // got onCanceled instead of onReleased, and the range selection silently did nothing.
            // euclid-amo never needed it: nothing there puts a chart inside a Flickable.
            //
            // The cost is that dragging *over a chart* no longer scrolls the page. The wheel still
            // does - it is passed on below unless ctrl is held - and so does everything either side
            // of the chart, which is where a hand reaching for a scroll already is.
            preventStealing: true

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
                root.setZoom(root.timeAt(Math.min(from, mouse.x)), root.timeAt(Math.max(from, mouse.x)))
            }

            // Ctrl+wheel only - Cmd on macOS, which Qt folds into ControlModifier anyway. A bare
            // wheel is left unaccepted and travels on to the ScrollView the page scrolls in;
            // without that gate every chart would be a hole the page cannot be scrolled over, and
            // the analytics page is mostly chart. It is the same bargain maps and editors strike
            // for the same reason.
            onWheel: (wheel) => {
                if (!(wheel.modifiers & Qt.ControlModifier)) {
                    wheel.accepted = false
                    return
                }
                // angleDelta is in eighths of a degree, 120 to a mouse notch. Used as an exponent
                // rather than counted in notches so that a trackpad's stream of small deltas and a
                // mouse's few large ones cover the same zoom for the same amount of scrolling.
                root.zoomBy(Math.pow(1 / 1.25, wheel.angleDelta.y / 120), wheel.x)
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

        // Doubles as the only advertisement ctrl+wheel gets: a modifier gesture nobody is told
        // about is a gesture nobody uses. Shown while the pointer is over the chart rather than
        // always, so a page being read carries no instructions nobody is in a position to act on.
        Text {
            visible: !hoverArea.dragging && (root.zoomed || hoverArea.containsMouse)
            anchors.horizontalCenter: parent.horizontalCenter
            y: canvas.height - root.bottomPad + 4
            text: root.zoomed ? "zoomed · double-click to reset" : "ctrl+wheel or drag to zoom"
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
