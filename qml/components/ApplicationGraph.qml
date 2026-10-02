import QtQuick
import QtQuick.Controls

// Every application at once, and the resources their declarations name, as one graph.
//
// ConnectionGraph draws one application as a hub with its resources fanned out either side, which
// is the right picture for a service read on its own. It is the wrong picture for a namespace: what
// an operator wants from the whole set is not each application's own list again, but where two of
// them meet - the queue one writes and another reads is the coupling that a per-application view
// shows twice and names once on each side, without ever saying they are the same queue.
//
// So a resource is a node here rather than a leaf. Every application that names it attaches to the
// same node, and an application-to-application relationship is what a path of length two through
// one of them means. Nothing in the picture is drawn from an application's own list of neighbours,
// because that list is exactly what cannot show this.
//
// Laid out by simulation rather than by arithmetic, for the reason the per-application view does not
// need one: a hub and its spokes have a shape that can be computed, and an arbitrary graph does not.
// See `step` - Fruchterman-Reingold, seeded deterministically so the same namespace is drawn the
// same way twice, and settled over a few hundred frames rather than solved before the first one.
//
// Drawn the way LineChart and ConnectionGraph are: the statically linked Qt build ships only
// qtbase/qtdeclarative/qtshadertools, so there is no graphing module to reach for. Only the edges go
// into the Canvas; the nodes are real Items over it, which is what gives them elided text, hover
// without hit-testing arithmetic, a tooltip each and a drag handle.
Item {
    id: root

    // [{ id, state, declared, scope, creates: [{kind,name,access,owner}], uses: [...] }] - `scope`
    // is what the names in the two lists are resolved against, and is part of a resource's identity
    // here: two applications naming "orders" mean the same queue only if they resolve it the same
    // way. See ApplicationGraphDialog, which builds it.
    property var applications: []

    // Drop every resource only one application touches. What is left is the coupling: the thing
    // that would have to be renegotiated before either side of it could be changed alone.
    property bool sharedOnly: false

    // A click on an application, which the page above turns into its details.
    signal applicationActivated(string applicationId)

    implicitWidth: 820
    implicitHeight: 520

    // Model sizes. Both are scaled by `zoom` when drawn, so a node keeps its share of the picture as
    // it is zoomed rather than growing into it.
    readonly property int appWidth: 148
    readonly property int appHeight: 46
    readonly property int resourceWidth: 132
    readonly property int resourceHeight: 38

    // Far enough out for a namespace of a few hundred nodes to be shown whole, which is what the
    // first look at one is for: a graph cropped to the panel would be read as the whole graph. What
    // is lost that far out is the labels, and they are dropped rather than rendered as smudges - see
    // the delegate, which stops drawing them before they stop being letters.
    readonly property real minZoom: 0.1
    readonly property real maxZoom: 2.5

    // The graph itself. `nodes` holds applications and resources in one array because the layout
    // treats them alike - only the drawing tells them apart.
    property var nodes: []
    property var edges: []
    // adjacency[i] = every node one edge away, which is what hovering dims everything else against.
    property var adjacency: []

    // The nodes the simulation arranges, and the ones it cannot.
    //
    // A node with no edges has nothing pulling it anywhere, so repulsion alone decides where it
    // goes - and repulsion alone means "as far from everything as the run is long". One application
    // that declares nothing would then set the scale of the whole picture and squeeze the part with
    // structure in it down to a corner. They are parked in a row under the graph instead, which is
    // where a person drawing this by hand would put them. See `park`.
    property var bound: []
    property var loose: []

    // Model coordinates, one per node, replaced whole on every tick: a Repeater delegate bound to an
    // element of this cannot see it mutated in place, and the whole point of a settling layout is
    // that the boxes move while it settles.
    property var positions: []

    property real zoom: 1
    property real panX: 0
    property real panY: 0
    // Kept in view while the layout settles, until somebody moves the picture themselves - at which
    // point continuing to reframe it would be fighting them for the viewport. The Fit button turns
    // it back on.
    property bool autoFit: true

    property int hoveredIndex: -1

    // How hard the layout is still pushing. Counts down to nothing, which is what stops the timer.
    property real temperature: 0
    // Whether the settled layout has been turned to face the panel yet - once per arrangement, not
    // once per time it comes to rest: a graph that is nudged after it has settled should not swing
    // round because a node was dragged. See `orient`.
    property bool oriented: false

    // Roughly the length an edge settles at, and the unit every force in `step` is expressed in. A
    // little wider than a node, so two connected boxes sit beside each other rather than on top.
    readonly property real spread: 190

    readonly property int applicationCount: {
        let count = 0
        for (const node of root.nodes) if (node.type === "app") ++count
        return count
    }
    readonly property int resourceCount: root.nodes.length - root.applicationCount
    readonly property int sharedCount: {
        let count = 0
        for (const node of root.nodes) if (node.type === "resource" && node.apps.length > 1) ++count
        return count
    }

    // Where each node is on screen, which is the one place the canvas and the delegates agree about.
    readonly property var placed: {
        const out = []
        for (let i = 0; i < root.positions.length; ++i) {
            out.push({
                x: root.positions[i].x * root.zoom + root.panX,
                y: root.positions[i].y * root.zoom + root.panY
            })
        }
        return out
    }

    function colorForKind(kind) {
        if (kind === "queues") return "#4f8cff"
        if (kind === "topics") return "#c56bff"
        if (kind === "buckets") return "#4cd97b"
        // A kind euclid does not know - which a stored declaration should not contain, since the
        // server refuses one - drawn in grey rather than dropped, so a file that somehow holds it is
        // visible rather than silently short a node.
        return "#9aa1ac"
    }

    // The singular, for a node's own label: a node is one queue, not "queues".
    function kindLabel(kind) {
        if (kind === "queues") return "queue"
        if (kind === "topics") return "topic"
        if (kind === "buckets") return "bucket"
        return kind
    }

    function stateColor(state) {
        if (state === "RUNNING") return "#4cd97b"
        if (state === "STOPPED") return "#ffb545"
        return "#9aa1ac"
    }

    // Which way the data goes on a "uses" edge, worked out from the access levels the declaration
    // names. Which levels exist is the server's table rather than this one's, so this matches on
    // what they are spelled out of instead of listing them: an access nobody here recognises leaves
    // the edge without an arrow, which says less but says nothing false.
    function flowFor(access) {
        let toResource = false
        let toApplication = false
        for (const level of access) {
            const name = String(level).toLowerCase()
            if (name.indexOf("write") >= 0 || name.indexOf("produce") >= 0 || name.indexOf("publish") >= 0
                    || name.indexOf("send") >= 0 || name.indexOf("put") >= 0)
                toResource = true
            if (name.indexOf("read") >= 0 || name.indexOf("subscribe") >= 0 || name.indexOf("consume") >= 0
                    || name.indexOf("receive") >= 0 || name.indexOf("get") >= 0 || name.indexOf("list") >= 0)
                toApplication = true
        }
        if (toResource && toApplication) return "both"
        if (toResource) return "out"
        if (toApplication) return "in"
        return ""
    }

    // Accepted as a string and as an array, because the file is written by hand and both spellings
    // are already in use - one bucket wants ["subscribe", "read"] and one topic wants "produce".
    // See Infrastructure::ReadResource.
    function accessList(value) {
        if (value === undefined || value === null) return []
        return typeof value === "string" ? [value] : value
    }

    function nodeWidth(index) {
        return root.nodes[index].type === "app" ? root.appWidth : root.resourceWidth
    }

    function nodeHeight(index) {
        return root.nodes[index].type === "app" ? root.appHeight : root.resourceHeight
    }

    function isNeighbour(index) {
        if (root.hoveredIndex < 0 || root.hoveredIndex === index) return true
        return root.adjacency[root.hoveredIndex].indexOf(index) >= 0
    }

    onApplicationsChanged: root.rebuild()
    onSharedOnlyChanged: root.rebuild()
    onPlacedChanged: edgeCanvas.requestPaint()
    onHoveredIndexChanged: edgeCanvas.requestPaint()
    // Only while nothing has been moved by hand: a window resize should reframe a picture nobody has
    // touched, and must not undo one somebody has.
    onWidthChanged: if (root.autoFit) root.fit()
    onHeightChanged: if (root.autoFit) root.fit()

    Component.onCompleted: root.rebuild()

    // Applications first, then one node per resource any of them names, then an edge per naming.
    //
    // A resource is identified by scope, kind and name together. Kind because a queue and a topic
    // may share a name and are not the same thing; scope because a plain name in a declaration means
    // nothing until it is resolved, and two applications resolving it differently are talking about
    // two resources however alike the files read.
    function rebuild() {
        const nodes = []
        const edges = []
        const resourceIndex = ({})

        for (const application of root.applications) {
            nodes.push({
                type: "app",
                id: String(application.id),
                label: String(application.id),
                state: String(application.state === undefined ? "" : application.state),
                scope: String(application.scope === undefined ? "" : application.scope),
                // An application deployed before the sidecar existed ships no declaration, which is
                // not the same fact as a declaration naming nothing - so it is carried rather than
                // inferred from an empty pair of lists.
                declared: application.declared !== false,
                // And a declaration that is there and could not be read is a third state again:
                // that application's edges are missing rather than absent, and a node that said
                // "no declaration" about it would be the picture lying about why it is empty.
                problem: application.problem === undefined ? "" : String(application.problem),
                owns: 0,
                uses: 0,
                apps: []
            })
        }

        const attach = function (appIndex, entry, owned) {
            const application = nodes[appIndex]
            const kind = String(entry.kind)
            const name = String(entry.name)
            const key = application.scope + "|" + kind + "|" + name

            let index = resourceIndex[key]
            if (index === undefined) {
                index = nodes.length
                resourceIndex[key] = index
                nodes.push({
                    type: "resource",
                    kind: kind,
                    label: name,
                    scope: application.scope,
                    owners: [],
                    users: [],
                    // Distinct applications touching it, which is what "shared" is counted on:
                    // an application that both creates a queue and lists it under uses is still
                    // one application.
                    apps: []
                })
            }

            const node = nodes[index]
            const access = root.accessList(entry.access)
            if (owned) {
                node.owners.push(application.id)
                ++application.owns
            } else {
                node.users.push({
                    app: application.id,
                    access: access,
                    owner: entry.owner === undefined ? "" : String(entry.owner)
                })
                ++application.uses
            }
            if (node.apps.indexOf(application.id) < 0) node.apps.push(application.id)

            edges.push({
                a: appIndex,
                b: index,
                owned: owned,
                kind: kind,
                flow: owned ? "" : root.flowFor(access)
            })
        }

        for (let a = 0; a < root.applications.length; ++a) {
            const application = root.applications[a]
            for (const entry of (application.creates === undefined ? [] : application.creates)) {
                if (entry && entry.name) attach(a, entry, true)
            }
            for (const entry of (application.uses === undefined ? [] : application.uses)) {
                if (entry && entry.name) attach(a, entry, false)
            }
        }

        root.install(root.sharedOnly ? root.keepShared(nodes, edges) : { nodes: nodes, edges: edges })
    }

    // The same graph with the resources only one application touches taken out, and the edges to
    // them with it. The applications all stay: one that turns out to share nothing is a fact about
    // the namespace worth seeing, and dropping it would make the picture answer a question - "which
    // applications are coupled" - with a list that quietly excludes the interesting half.
    function keepShared(nodes, edges) {
        const remap = new Array(nodes.length).fill(-1)
        const kept = []
        for (let i = 0; i < nodes.length; ++i) {
            if (nodes[i].type === "resource" && nodes[i].apps.length < 2) continue
            remap[i] = kept.length
            kept.push(nodes[i])
        }

        const keptEdges = []
        for (const edge of edges) {
            if (remap[edge.a] < 0 || remap[edge.b] < 0) continue
            keptEdges.push({ a: remap[edge.a], b: remap[edge.b], owned: edge.owned, kind: edge.kind, flow: edge.flow })
        }
        return { nodes: kept, edges: keptEdges }
    }

    function install(graph) {
        root.hoveredIndex = -1
        root.nodes = graph.nodes
        root.edges = graph.edges

        const adjacency = []
        for (let i = 0; i < graph.nodes.length; ++i) adjacency.push([])
        for (const edge of graph.edges) {
            if (adjacency[edge.a].indexOf(edge.b) < 0) adjacency[edge.a].push(edge.b)
            if (adjacency[edge.b].indexOf(edge.a) < 0) adjacency[edge.b].push(edge.a)
        }
        root.adjacency = adjacency

        const bound = []
        const loose = []
        for (let i = 0; i < graph.nodes.length; ++i) {
            if (adjacency[i].length > 0) bound.push(i)
            else loose.push(i)
        }
        root.bound = bound
        root.loose = loose

        root.autoFit = true
        root.relayout()
    }

    // A fixed hash rather than Math.random: the same namespace drawn twice should be the same
    // picture, or nobody can say "the one on the left" about it.
    function noise(index, salt) {
        const value = Math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
        return value - Math.floor(value)
    }

    // Seeded on a sunflower spiral - evenly spread, no two nodes on top of each other, and no ring
    // structure for the simulation to have to break out of. A circle is worse than it looks: every
    // node starts the same distance from the centre, so the first few hundred repulsions all point
    // outwards and the layout has to undo that before it can start arranging anything.
    function relayout() {
        const count = root.nodes.length
        const positions = []
        for (let i = 0; i < count; ++i) positions.push({ x: 0, y: 0, pinned: false })

        const bound = root.bound
        const radius = root.spread * Math.sqrt(Math.max(1, bound.length)) / 1.7
        // The golden angle, which is what stops the spiral's arms from lining up.
        const golden = Math.PI * (3 - Math.sqrt(5))

        for (let i = 0; i < bound.length; ++i) {
            const angle = i * golden
            const distance = radius * Math.sqrt((i + 0.5) / Math.max(1, bound.length))
            positions[bound[i]] = {
                x: Math.cos(angle) * distance + (root.noise(i, 1) - 0.5) * 12,
                y: Math.sin(angle) * distance + (root.noise(i, 2) - 0.5) * 12,
                pinned: false
            }
        }

        root.park(positions)
        root.positions = positions
        root.oriented = false
        root.temperature = bound.length > 0 ? root.spread : 0
        root.fit()
        if (bound.length > 0) simulation.start()
    }

    // The nodes with no edges, laid out in rows under whatever the simulation has arranged - as
    // wide as the picture is, so they read as a list beneath it rather than as part of it. Redone
    // after every pass, because what they sit under is still moving.
    function park(positions) {
        if (root.loose.length === 0) return

        let minX = 0, maxX = 0, maxY = 0
        if (root.bound.length > 0) {
            minX = Infinity; maxX = -Infinity; maxY = -Infinity
            for (const index of root.bound) {
                minX = Math.min(minX, positions[index].x)
                maxX = Math.max(maxX, positions[index].x)
                maxY = Math.max(maxY, positions[index].y)
            }
        }

        const columnWidth = root.appWidth + 26
        const rowHeight = root.appHeight + 18
        const columns = Math.max(1, Math.min(root.loose.length,
                                             Math.floor(Math.max(maxX - minX, columnWidth * 3) / columnWidth)))
        const left = (minX + maxX) / 2 - (columns - 1) * columnWidth / 2
        // Clear of the graph by more than the layout's own spacing, so the row cannot be mistaken
        // for the bottom of it.
        const top = root.bound.length > 0 ? maxY + root.spread * 0.75 : 0

        for (let i = 0; i < root.loose.length; ++i) {
            // Except one that was dragged somewhere: a parked node put where somebody wants it
            // stays there, the same way a pinned one in the graph does.
            if (positions[root.loose[i]].pinned) continue
            positions[root.loose[i]] = {
                x: left + (i % columns) * columnWidth,
                y: top + Math.floor(i / columns) * rowHeight,
                pinned: false
            }
        }
    }

    // One pass of Fruchterman-Reingold: every node pushes every other away, every edge pulls its two
    // together, and a weak pull towards the origin keeps a component that shares nothing with the
    // rest from drifting off the picture. The temperature caps how far anything may move in one
    // pass and cools to nothing, which is what makes it settle instead of oscillating.
    function step() {
        const bound = root.bound
        if (bound.length === 0 || root.temperature <= 0.6) {
            simulation.stop()
            // Once, as the layout comes to rest: see `orient`.
            if (bound.length > 0 && !root.oriented) {
                root.oriented = true
                root.orient()
            }
            return
        }

        const k = root.spread
        const count = root.nodes.length
        // More passes per frame while the graph is small enough for them to be free. A namespace
        // with a few hundred nodes settles a little slower and stays responsive, which is the
        // better trade: it is on screen the whole time.
        const rounds = bound.length > 120 ? 1 : 3

        const aspect = root.width > 0 && root.height > 0
                     ? Math.max(0.6, Math.min(2.4, root.width / root.height)) : 1.6
        const gravityX = 0.08 / aspect
        const gravityY = 0.08 * aspect

        const next = []
        for (const position of root.positions) next.push({ x: position.x, y: position.y, pinned: position.pinned })

        for (let round = 0; round < rounds && root.temperature > 0.6; ++round) {
            const dx = new Array(count).fill(0)
            const dy = new Array(count).fill(0)

            for (let a = 0; a < bound.length; ++a) {
                for (let b = a + 1; b < bound.length; ++b) {
                    const i = bound[a]
                    const j = bound[b]
                    let deltaX = next[i].x - next[j].x
                    let deltaY = next[i].y - next[j].y
                    let distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY)
                    if (distance < 0.01) {
                        // Two nodes in the same place have no direction to be pushed apart along,
                        // so one is invented - deterministically, like the seeding.
                        deltaX = root.noise(i * count + j, 3) - 0.5
                        deltaY = root.noise(i * count + j, 4) - 0.5
                        distance = 0.01
                    }
                    const force = (k * k) / distance
                    dx[i] += (deltaX / distance) * force
                    dy[i] += (deltaY / distance) * force
                    dx[j] -= (deltaX / distance) * force
                    dy[j] -= (deltaY / distance) * force
                }
            }

            for (const edge of root.edges) {
                const deltaX = next[edge.a].x - next[edge.b].x
                const deltaY = next[edge.a].y - next[edge.b].y
                const distance = Math.max(0.01, Math.sqrt(deltaX * deltaX + deltaY * deltaY))
                const force = (distance * distance) / k
                dx[edge.a] -= (deltaX / distance) * force
                dy[edge.a] -= (deltaY / distance) * force
                dx[edge.b] += (deltaX / distance) * force
                dy[edge.b] += (deltaY / distance) * force
            }

            for (const i of bound) {
                // Dragged nodes are the operator's statement about where that node goes, so the
                // layout arranges itself around them rather than over them.
                if (next[i].pinned) continue

                // A weak pull towards the origin, which is what keeps two halves that share nothing
                // from drifting apart for as long as the run lasts. Weak enough that it only
                // decides anything at a distance: within the graph it is a rounding error against
                // the forces the edges apply.
                //
                // Harder along whichever axis the panel is shorter on, so what settles is roughly
                // the shape of the space it is being drawn in. Nothing about a graph makes it
                // round, and a round one in a wide panel is fitted on its height - which costs
                // every node the same scale, and the labels their legibility, to leave the sides
                // empty.
                dx[i] -= next[i].x * gravityX
                dy[i] -= next[i].y * gravityY

                const length = Math.sqrt(dx[i] * dx[i] + dy[i] * dy[i])
                if (length < 0.0001) continue
                const limit = Math.min(length, root.temperature)
                next[i].x += (dx[i] / length) * limit
                next[i].y += (dy[i] / length) * limit
            }

            root.separate(next)
            root.temperature *= 0.975
        }

        root.park(next)
        root.positions = next
        if (root.autoFit) root.fit()
    }

    // Turns the settled layout so that whichever way it is longest runs along whichever way the
    // panel is widest.
    //
    // Nothing in the simulation has an opinion about which way is up, so the same graph is as likely
    // to settle down the diagonal as across - and a picture that runs corner to corner is fitted on
    // its diagonal, which is the one measurement no amount of space to the sides can improve. The
    // rotation changes nothing about what is drawn; it just stops the framing from being decided by
    // an accident of where the first pass happened to push things.
    //
    // The long way is the principal axis - the direction the node positions vary most in, which for
    // a chain of services is the chain.
    function orient() {
        const bound = root.bound
        if (bound.length < 3 || root.width <= 0 || root.height <= 0) return

        let centreX = 0, centreY = 0
        for (const index of bound) {
            centreX += root.positions[index].x
            centreY += root.positions[index].y
        }
        centreX /= bound.length
        centreY /= bound.length

        let xx = 0, xy = 0, yy = 0
        for (const index of bound) {
            const dx = root.positions[index].x - centreX
            const dy = root.positions[index].y - centreY
            xx += dx * dx
            xy += dx * dy
            yy += dy * dy
        }

        const angle = 0.5 * Math.atan2(2 * xy, xx - yy)
        const rotation = (root.width >= root.height ? 0 : Math.PI / 2) - angle
        // Already close enough; turning a picture by two degrees buys nothing and costs the reader
        // the layout they were looking at.
        if (Math.abs(Math.sin(rotation)) < 0.05) return

        const cos = Math.cos(rotation)
        const sin = Math.sin(rotation)
        const positions = []
        for (const position of root.positions) positions.push({ x: position.x, y: position.y, pinned: position.pinned })
        for (const index of bound) {
            const dx = positions[index].x - centreX
            const dy = positions[index].y - centreY
            positions[index].x = centreX + dx * cos - dy * sin
            positions[index].y = centreY + dx * sin + dy * cos
        }

        // Boxes do not turn with the layout - they stay upright, which is what makes their labels
        // readable - so two that cleared each other diagonally can cover each other once the
        // picture is square on. A couple of passes settle that.
        root.separate(positions)
        root.separate(positions)

        root.park(positions)
        root.positions = positions
        if (root.autoFit) root.fit()
    }

    // Pushes apart any two boxes that are on top of each other, along whichever axis they overlap
    // less on.
    //
    // The simulation knows nodes as points, and two points a comfortable distance apart can still be
    // two boxes covering each other's labels - a queue's name is 130 pixels wide and its centre is
    // dimensionless. Repelling harder is not the fix: it would space the whole graph for its widest
    // node and lose the distances that mean something. This runs after the forces, so the layout
    // decides where things go and this only decides that they can be read.
    function separate(positions) {
        const bound = root.bound
        for (let a = 0; a < bound.length; ++a) {
            for (let b = a + 1; b < bound.length; ++b) {
                const i = bound[a]
                const j = bound[b]
                const reachX = (root.nodeWidth(i) + root.nodeWidth(j)) / 2 + 16
                const reachY = (root.nodeHeight(i) + root.nodeHeight(j)) / 2 + 12

                const deltaX = positions[j].x - positions[i].x
                const deltaY = positions[j].y - positions[i].y
                const overlapX = reachX - Math.abs(deltaX)
                const overlapY = reachY - Math.abs(deltaY)
                if (overlapX <= 0 || overlapY <= 0) continue

                // Both give way, unless one of them was put where it is by hand.
                const movable = (positions[i].pinned ? 0 : 1) + (positions[j].pinned ? 0 : 1)
                if (movable === 0) continue
                const shareI = positions[i].pinned ? 0 : 1 / movable
                const shareJ = positions[j].pinned ? 0 : 1 / movable

                if (overlapX < overlapY) {
                    const push = (deltaX >= 0 ? 1 : -1) * overlapX
                    positions[i].x -= push * shareI
                    positions[j].x += push * shareJ
                } else {
                    const push = (deltaY >= 0 ? 1 : -1) * overlapY
                    positions[i].y -= push * shareI
                    positions[j].y += push * shareJ
                }
            }
        }
    }

    // Frames everything, node boxes included. They are drawn at `zoom` times their model size, so
    // the width a node takes on screen is part of what has to fit - which is why this solves for the
    // zoom rather than measuring at the current one and correcting afterwards.
    function fit() {
        const count = root.positions.length
        if (count === 0 || root.width <= 0 || root.height <= 0) return

        let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity
        for (const position of root.positions) {
            minX = Math.min(minX, position.x)
            maxX = Math.max(maxX, position.x)
            minY = Math.min(minY, position.y)
            maxY = Math.max(maxY, position.y)
        }

        const margin = 18
        const zoomX = (root.width - margin * 2) / (maxX - minX + root.appWidth)
        const zoomY = (root.height - margin * 2) / (maxY - minY + root.appHeight)
        // Never enlarged past life size: a namespace with three nodes in it should read as a small
        // graph, not as three enormous boxes.
        const zoom = Math.max(root.minZoom, Math.min(1.0, Math.min(zoomX, zoomY)))

        root.zoom = zoom
        root.panX = root.width / 2 - ((minX + maxX) / 2) * zoom
        root.panY = root.height / 2 - ((minY + maxY) / 2) * zoom
    }

    // Around a point on screen, so what is under the pointer stays under it - which is the only way
    // zooming towards something works without also having to pan after every step.
    function zoomAround(screenX, screenY, factor) {
        const zoom = Math.max(root.minZoom, Math.min(root.maxZoom, root.zoom * factor))
        if (zoom === root.zoom) return
        root.panX = screenX - ((screenX - root.panX) / root.zoom) * zoom
        root.panY = screenY - ((screenY - root.panY) / root.zoom) * zoom
        root.zoom = zoom
    }

    function moveNode(index, modelDeltaX, modelDeltaY) {
        const next = []
        for (let i = 0; i < root.positions.length; ++i) {
            const position = root.positions[i]
            if (i === index) {
                next.push({ x: position.x + modelDeltaX, y: position.y + modelDeltaY, pinned: true })
            } else {
                next.push({ x: position.x, y: position.y, pinned: position.pinned })
            }
        }
        root.positions = next
        // Enough to let the rest rearrange around where it was put, not enough to throw the picture
        // out: this is a nudge, not a restart.
        root.temperature = Math.max(root.temperature, root.spread * 0.12)
        simulation.start()
    }

    Timer {
        id: simulation
        interval: 16
        repeat: true
        running: false
        onTriggered: root.step()
    }

    // Under the canvas and the nodes, so a press that misses everything pans and a press on a node
    // drags it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        property real pressX: 0
        property real pressY: 0

        onPressed: mouse => {
            pressX = mouse.x
            pressY = mouse.y
            root.autoFit = false
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            root.panX += mouse.x - pressX
            root.panY += mouse.y - pressY
            pressX = mouse.x
            pressY = mouse.y
        }
        onWheel: wheel => {
            root.autoFit = false
            root.zoomAround(wheel.x, wheel.y, wheel.angleDelta.y > 0 ? 1.12 : 1 / 1.12)
        }
    }

    Canvas {
        id: edgeCanvas
        anchors.fill: parent
        antialiasing: true

        // The scene is drawn in screen coordinates rather than by transforming the canvas, so a line
        // is one pixel wide at every zoom: a Canvas scaled by its parent is a texture being
        // stretched, and this picture is mostly thin lines.
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            if (root.placed.length !== root.nodes.length) return

            const arrow = function (x, y, ux, uy, color) {
                const size = 7
                ctx.beginPath()
                ctx.moveTo(x, y)
                ctx.lineTo(x - ux * size + uy * size * 0.5, y - uy * size - ux * size * 0.5)
                ctx.lineTo(x - ux * size - uy * size * 0.5, y - uy * size + ux * size * 0.5)
                ctx.closePath()
                ctx.fillStyle = color
                ctx.fill()
            }

            for (const edge of root.edges) {
                const from = root.placed[edge.a]
                const to = root.placed[edge.b]
                const touched = root.hoveredIndex === edge.a || root.hoveredIndex === edge.b
                const dimmed = root.hoveredIndex >= 0 && !touched
                const color = root.colorForKind(edge.kind)

                ctx.globalAlpha = dimmed ? 0.12 : (touched ? 1.0 : 0.65)
                ctx.strokeStyle = color
                ctx.lineWidth = touched ? 2.4 : 1.2

                // Owned is solid, reached is dashed - euclid creates the first and merely grants
                // access to the second, and which of an application's neighbours would disappear
                // with it is the distinction worth being able to read off the line alone.
                if (ctx.setLineDash) ctx.setLineDash(edge.owned ? [] : [5, 4])

                ctx.beginPath()
                ctx.moveTo(from.x, from.y)
                ctx.lineTo(to.x, to.y)
                ctx.stroke()

                if (edge.flow.length === 0) continue

                // Which way the data goes, on the line that carries it. The arrowhead sits along
                // the line rather than at its end because both ends are under a box.
                const deltaX = to.x - from.x
                const deltaY = to.y - from.y
                const length = Math.max(0.01, Math.sqrt(deltaX * deltaX + deltaY * deltaY))
                const ux = deltaX / length
                const uy = deltaY / length

                if (ctx.setLineDash) ctx.setLineDash([])
                if (edge.flow === "out" || edge.flow === "both") {
                    const at = edge.flow === "both" ? 0.62 : 0.55
                    arrow(from.x + deltaX * at, from.y + deltaY * at, ux, uy, color)
                }
                if (edge.flow === "in" || edge.flow === "both") {
                    const at = edge.flow === "both" ? 0.38 : 0.45
                    arrow(from.x + deltaX * at, from.y + deltaY * at, -ux, -uy, color)
                }
            }

            if (ctx.setLineDash) ctx.setLineDash([])
            ctx.globalAlpha = 1.0
        }
    }

    Repeater {
        model: root.nodes

        delegate: Rectangle {
            id: node
            required property var modelData
            required property int index

            readonly property bool isApplication: node.modelData.type === "app"
            readonly property var at: root.placed.length > node.index ? root.placed[node.index] : ({ x: 0, y: 0 })
            readonly property bool near: root.isNeighbour(node.index)
            readonly property color accent: {
                if (!node.isApplication) return root.colorForKind(node.modelData.kind)
                if (node.modelData.problem.length > 0) return "#e0a458"
                return node.modelData.declared ? root.stateColor(node.modelData.state) : "#4b5563"
            }

            x: node.at.x - width / 2
            y: node.at.y - height / 2
            width: (node.isApplication ? root.appWidth : root.resourceWidth) * root.zoom
            height: (node.isApplication ? root.appHeight : root.resourceHeight) * root.zoom
            radius: (node.isApplication ? 10 : 8) * root.zoom
            // Applications are filled and resources are not, so which of the two a box is survives
            // being read at a zoom where its second line is too small to make out.
            color: node.isApplication ? "#2c3648" : "#1b1e25"
            border.color: node.accent
            border.width: (root.hoveredIndex === node.index ? 2 : 1) * Math.max(1, root.zoom)
            opacity: node.near ? 1.0 : 0.25

            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8 * root.zoom
                anchors.rightMargin: 8 * root.zoom
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1

                Text {
                    width: parent.width
                    horizontalAlignment: node.isApplication ? Text.AlignHCenter : Text.AlignLeft
                    text: node.modelData.label
                    color: node.isApplication ? "white" : "#e5e7eb"
                    font.pixelSize: (node.isApplication ? 12.5 : 11.5) * root.zoom
                    font.bold: node.isApplication
                    elide: Text.ElideMiddle
                    // Below this the glyphs are noise in a box the size of a word, and the shape of
                    // the graph is what is being looked at anyway. The tooltip still names anything
                    // the pointer is over.
                    visible: root.zoom >= 0.3
                }

                Text {
                    width: parent.width
                    visible: root.zoom >= 0.42
                    horizontalAlignment: node.isApplication ? Text.AlignHCenter : Text.AlignLeft
                    text: {
                        if (!node.isApplication)
                            return root.kindLabel(node.modelData.kind)
                                 + (node.modelData.apps.length > 1 ? "  ·  " + node.modelData.apps.length + " apps" : "")
                        if (node.modelData.problem.length > 0) return "declaration unreadable"
                        if (!node.modelData.declared) return "no declaration"
                        return "owns " + node.modelData.owns + " · uses " + node.modelData.uses
                    }
                    color: node.isApplication ? "#9aa1ac" : "#6b7280"
                    font.pixelSize: Math.max(6, 9.5 * root.zoom)
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: node.isApplication ? Qt.PointingHandCursor : Qt.ArrowCursor

                property real pressX: 0
                property real pressY: 0
                property bool moved: false

                onEntered: root.hoveredIndex = node.index
                onExited: if (root.hoveredIndex === node.index) root.hoveredIndex = -1

                onPressed: mouse => {
                    pressX = mouse.x
                    pressY = mouse.y
                    moved = false
                }
                onPositionChanged: mouse => {
                    if (!pressed) return
                    const deltaX = mouse.x - pressX
                    const deltaY = mouse.y - pressY
                    // A few pixels of slack, so a click that shivers is still a click.
                    if (!moved && Math.abs(deltaX) < 3 && Math.abs(deltaY) < 3) return
                    moved = true
                    root.autoFit = false
                    // The node moves with the pointer, so the press point stays where it was within
                    // the box and the delta is what is left over each time.
                    root.moveNode(node.index, deltaX / root.zoom, deltaY / root.zoom)
                }
                onClicked: {
                    if (moved || !node.isApplication) return
                    root.applicationActivated(node.modelData.id)
                }
            }

            ToolTip.visible: root.hoveredIndex === node.index
            ToolTip.text: {
                const lines = []
                if (node.isApplication) {
                    lines.push(node.modelData.label + "  (application)")
                    if (node.modelData.state.length > 0) lines.push(node.modelData.state)
                    if (node.modelData.problem.length > 0) {
                        lines.push("Nothing is attached because " + node.modelData.problem + ".")
                        lines.push("Click to open it.")
                    } else if (!node.modelData.declared) {
                        lines.push("Ships no infrastructure declaration, so nothing is drawn for it. That does "
                                   + "not mean it has no connections, only that it does not declare them.")
                    } else {
                        lines.push("Owns " + node.modelData.owns + ", reaches " + node.modelData.uses + ".")
                        lines.push("Click to open it.")
                    }
                    return lines.join("\n")
                }

                lines.push(node.modelData.label + "  (" + root.kindLabel(node.modelData.kind) + ")")
                if (node.modelData.owners.length > 0) lines.push("Created by: " + node.modelData.owners.join(", "))
                // Worth saying rather than left blank: a resource every application only reaches is
                // one nothing here creates, which either belongs to a service outside this list or
                // to nobody, and both are things to go and check.
                else lines.push("Created by: nothing in this list declares it")

                for (const user of node.modelData.users) {
                    lines.push("Reached by " + user.app
                               + (user.access.length > 0 ? ": " + user.access.join(", ") : ": no access named")
                               // Recorded by the declaration's author rather than checked by euclid,
                               // which verifies the resource exists and not who wrote it down.
                               + (user.owner.length > 0 ? "  (declared owner: " + user.owner + ")" : ""))
                }
                if (node.modelData.scope.length > 0) lines.push("Resolved in " + node.modelData.scope + ".")
                return lines.join("\n")
            }
        }
    }
}
