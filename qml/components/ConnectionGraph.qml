import QtQuick
import QtQuick.Controls

// One application and the resources its declaration names, as a hub and its spokes.
//
// Split down the middle rather than scattered round a circle, because the split is the thing worth
// seeing: what the application owns goes on the left, what it only reaches goes on the right. The
// two are different in kind - euclid creates the first and merely grants access to the second - and
// an operator looking at a service wants to know which of its neighbours would disappear with it.
//
// The split is also what keeps the picture legible as it grows: two fans of evenly spaced rows
// cannot collide with each other, and within a fan the spacing is what is held constant. See
// `layout`.
//
// Drawn the way LineChart is, and for the same reason: the statically linked Qt build ships only
// qtbase/qtdeclarative/qtshadertools, so there is no graphing module to reach for. Only the edges
// go into the Canvas; the nodes are real Items positioned over it, which is what gives them text
// that elides, hover without hit-testing arithmetic, and a tooltip each.
Item {
    id: root

    property string applicationId: ""
    // Both [{kind, name, access, owner}] - "creates" entries carry no access, since owning a
    // resource is the access.
    property var creates: []
    property var uses: []

    implicitWidth: 720
    implicitHeight: 420

    readonly property int nodeWidth: 150
    readonly property int nodeHeight: 42

    function colorForKind(kind) {
        if (kind === "queues") return "#4f8cff"
        if (kind === "topics") return "#c56bff"
        if (kind === "buckets") return "#4cd97b"
        // A kind euclid does not know - which a stored declaration should not contain, since the
        // server refuses one - drawn in grey rather than dropped, so a file that somehow holds it
        // is visible rather than silently short a node.
        return "#9aa1ac"
    }

    // The singular, for a node's own label: a node is one queue, not "queues".
    function kindLabel(kind) {
        if (kind === "queues") return "queue"
        if (kind === "topics") return "topic"
        if (kind === "buckets") return "bucket"
        return kind
    }

    // Where every node sits, computed once per size or data change and read by both the Canvas and
    // the Repeater - so the line and the box it points at can never disagree about where the box is.
    //
    // Each side is a fan: rows spaced evenly down the panel, drawn in towards the hub at the top and
    // bottom so the shape reads as radial rather than as two lists.
    //
    // Rows rather than an even spread of angles around an ellipse, which is what this was first.
    // Angles look right for four or five nodes and fall apart past that: near the top of an ellipse
    // the vertical distance between neighbours collapses, so the boxes overlap while the angles
    // between them are still comfortably apart. Spacing the rows is the thing that actually has to
    // hold, so it is the thing that is computed.
    readonly property var layout: {
        const cx = root.width / 2
        const cy = root.height / 2

        // How far out a node in the middle of a fan sits, and how far the ends are drawn back in.
        // The bow is capped so that even a fully drawn-in node keeps clear of the hub.
        const baseX = Math.max(140, root.width / 2 - root.nodeWidth / 2 - 12)
        const bow = Math.min(70, Math.max(0, baseX - root.nodeWidth / 2 - 110))
        const usable = Math.max(root.nodeHeight, root.height - root.nodeHeight - 8)

        const placed = []
        const place = function (items, side, owned) {
            const count = items.length
            if (count === 0) return

            // Never more than a node and a gap apart, so a short fan does not sprawl; never more
            // than the panel divided by the count, so a long one still fits.
            const spacing = count > 1 ? Math.min(root.nodeHeight + 10, usable / (count - 1)) : 0
            const top = cy - spacing * (count - 1) / 2

            for (let i = 0; i < count; ++i) {
                // -1 at the top of the fan, 0 in the middle, 1 at the bottom.
                const offset = count === 1 ? 0 : (i / (count - 1)) * 2 - 1
                const item = items[i]
                placed.push({
                    x: cx + side * (baseX - (1 - Math.cos(offset * Math.PI / 2)) * bow),
                    y: top + i * spacing,
                    kind: String(item.kind),
                    name: String(item.name),
                    owner: String(item.owner === undefined ? "" : item.owner),
                    access: item.access === undefined ? [] : item.access,
                    owned: owned
                })
            }
        }

        // Left for what it owns, right for what it reaches.
        place(root.creates, -1, true)
        place(root.uses, 1, false)
        return placed
    }

    // Which node the pointer is over, or -1. Drives both the node's own highlight and the weight of
    // its edge, so following a line back to its box does not mean tracing it by eye.
    property int hoveredIndex: -1

    onLayoutChanged: edges.requestPaint()
    onHoveredIndexChanged: edges.requestPaint()

    Canvas {
        id: edges
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const cx = root.width / 2
            const cy = root.height / 2

            for (let i = 0; i < root.layout.length; ++i) {
                const node = root.layout[i]
                const hovered = i === root.hoveredIndex
                const dimmed = root.hoveredIndex >= 0 && !hovered

                ctx.beginPath()
                ctx.globalAlpha = dimmed ? 0.25 : 1.0
                ctx.strokeStyle = root.colorForKind(node.kind)
                ctx.lineWidth = hovered ? 2.5 : 1.4

                // Owned is solid, reached is dashed - the same distinction the two halves make,
                // said a second way so it survives a node being read on its own.
                if (ctx.setLineDash)
                    ctx.setLineDash(node.owned ? [] : [5, 4])

                // Stopped at the edge of each box rather than run between their centres, so a line
                // does not emerge from under the label it points at.
                //
                // Where the ray leaves a box, not where it leaves a circle around it: a fixed
                // radius is only ever right for one direction, and taking half the width left the
                // edges to the nodes directly above and below the hub ending a node's height short
                // of them. This is the intersection with the rectangle itself, which is correct in
                // every direction and costs two divisions.
                const dx = node.x - cx
                const dy = node.y - cy
                const length = Math.max(1, Math.sqrt(dx * dx + dy * dy))
                const ux = dx / length
                const uy = dy / length

                const reach = function (halfWidth, halfHeight) {
                    const toSide = Math.abs(ux) > 0.0001 ? halfWidth / Math.abs(ux) : Infinity
                    const toCap = Math.abs(uy) > 0.0001 ? halfHeight / Math.abs(uy) : Infinity
                    return Math.min(toSide, toCap)
                }

                // A few pixels clear of the node's border, so the line meets it rather than
                // touching it. The hub is drawn over the canvas, so its end needs no such gap.
                const from = reach(hub.width / 2, hub.height / 2)
                const to = reach(root.nodeWidth / 2 + 5, root.nodeHeight / 2 + 5)

                ctx.moveTo(cx + ux * from, cy + uy * from)
                ctx.lineTo(node.x - ux * to, node.y - uy * to)
                ctx.stroke()
            }

            if (ctx.setLineDash) ctx.setLineDash([])
            ctx.globalAlpha = 1.0
        }
    }

    // The hub. Drawn after the edges so the lines run under it.
    Rectangle {
        id: hub
        anchors.centerIn: parent
        width: Math.min(200, root.width - 40)
        height: 54
        radius: 10
        color: "#2c3648"
        border.color: "#4f8cff"
        border.width: 1

        Column {
            anchors.centerIn: parent
            width: parent.width - 20
            spacing: 2

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.applicationId
                color: "white"
                font.pixelSize: 13
                font.bold: true
                elide: Text.ElideMiddle
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: "application"
                color: "#9aa1ac"
                font.pixelSize: 10
            }
        }
    }

    Repeater {
        model: root.layout

        delegate: Rectangle {
            id: node
            required property var modelData
            required property int index

            x: node.modelData.x - width / 2
            y: node.modelData.y - height / 2
            width: root.nodeWidth
            height: root.nodeHeight
            radius: 8
            color: "#1b1e25"
            border.color: root.colorForKind(node.modelData.kind)
            border.width: root.hoveredIndex === node.index ? 2 : 1
            opacity: root.hoveredIndex >= 0 && root.hoveredIndex !== node.index ? 0.45 : 1.0

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    text: node.modelData.name
                    color: "#e5e7eb"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                }

                Text {
                    width: parent.width
                    // The access levels are what a "uses" edge actually means - "read" and "write"
                    // on the same bucket are two different relationships - so they belong on the
                    // node rather than only in the tooltip.
                    text: node.modelData.owned
                          ? root.kindLabel(node.modelData.kind)
                          : root.kindLabel(node.modelData.kind)
                            + (node.modelData.access.length > 0 ? " · " + node.modelData.access.join(", ") : "")
                    color: "#6b7280"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            HoverHandler {
                onHoveredChanged: root.hoveredIndex = hovered ? node.index : -1
            }

            ToolTip.visible: root.hoveredIndex === node.index
            ToolTip.text: {
                const lines = [node.modelData.name + "  (" + root.kindLabel(node.modelData.kind) + ")"]
                if (node.modelData.owned) {
                    lines.push("Created and owned by " + root.applicationId + ".")
                } else {
                    lines.push("Reached with: "
                               + (node.modelData.access.length > 0 ? node.modelData.access.join(", ") : "no access named"))
                    // Recorded by the declaration's author rather than checked by euclid, which
                    // verifies the resource exists and not who wrote it down - so it is shown as a
                    // claim about ownership, not as a fact euclid stands behind.
                    if (node.modelData.owner.length > 0)
                        lines.push("Declared owner: " + node.modelData.owner)
                }
                return lines.join("\n")
            }
        }
    }
}
