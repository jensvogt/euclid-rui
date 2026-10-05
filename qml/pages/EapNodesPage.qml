import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// The hosts euclid places applications on. Not a list anybody maintains: a `euclid-wrk` registers
// itself, renews, and eventually goes quiet, so this is a census of what has turned up rather than
// a declaration of what should exist. There is no "add node" here for that reason, and no delete -
// a node leaves by being switched off, and its record is what the master has to go on in between.
//
// Not where euclid's own modules run, either. EQS, ESM, EAM and the rest stay on the manager's
// host; a worker node holds cached artifacts and log files and nothing durable.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    property var nodes: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    // What the last drain or undrain did, kept beside the table: the row it was done to says
    // "drained" either way, and nothing on it says the change was the one just asked for.
    property string actionNote: ""

    signal back()
    signal openNodeDetails(string nodeName, var details)

    // Whether a node is placeable, which is Node::acceptsWork server-side: live and not drained.
    // The two flags are independent - a node can be drained and also have gone quiet - so this is
    // the only honest way to ask the question.
    function acceptsWork(row) {
        return !!row && row.live === true && row.drained !== true
    }

    // One word for the two flags together, because an operator reads a state and not a pair of
    // booleans. Quiet is listed ahead of drained deliberately: a drained node that has also stopped
    // renewing is a problem, not a decision, and should not read as though somebody meant it.
    function nodeState(row) {
        if (!row) return "—"
        if (row.live !== true) return "QUIET"
        if (row.drained === true) return "DRAINED"
        return "READY"
    }

    function nodeStateColor(row) {
        const state = root.nodeState(row)
        if (state === "READY") return "#4cd97b"
        if (state === "DRAINED") return "#ffb545"
        if (state === "QUIET") return "#ff6b6b"
        return "#9aa1ac"
    }

    // The host as one word: "linux-x86_64", "windows-x86_64". The two halves are reported together
    // by the worker and neither is enough alone - a Raspberry Pi and a PC are both "linux", and a
    // native artifact runs on one operating system and one architecture.
    //
    // Either half may be missing, and then only the other is shown: a worker older than these
    // fields reports neither, and writing "linux-" for one that reported only an OS would read as a
    // truncated value rather than an absent one.
    function platformText(row) {
        if (!row) return "—"
        const os = String(row.os === undefined ? "" : row.os).trim()
        const arch = String(row.arch === undefined ? "" : row.arch).trim()
        if (os.length === 0 && arch.length === 0) return "—"
        if (os.length === 0) return arch
        if (arch.length === 0) return os
        return os + "-" + arch
    }

    // The labels a worker registered itself with, as "key=value" pairs. What placement is written
    // against, so they are worth seeing on the node rather than only in a placement rule.
    function labelText(labels) {
        if (!labels) return "—"
        const keys = Object.keys(labels)
        if (keys.length === 0) return "—"
        return keys.sort().map(k => k + "=" + labels[k]).join(", ")
    }

    readonly property var columns: [
        { title: "Node", key: "name", fill: true },
        {
            // Not a column somebody can act on, but the one that answers "why can nothing be placed
            // here" when the state says QUIET - a node that has gone is a node whose last renewal
            // is old, and the age is the whole diagnosis.
            title: "State",
            key: "live",
            formatter: function (v, row) { return root.nodeState(row) },
            colorFor: function (v, row) { return root.nodeStateColor(row) }
        },
        { title: "Last seen", key: "lastSeen", formatter: function (v) { return DateFormat.format(v) } },
        { title: "CPUs", key: "cpuCount" },
        {
            // Beside the version, because the three together are what says which build is running
            // where - and an artifact built for one platform does not run on another, which is the
            // thing a placement rule is usually working around.
            title: "OS / Arch",
            key: "os",
            formatter: function (v, row) { return root.platformText(row) },
            // Dimmed when neither half was reported, the way the Labels column is: nothing is
            // wrong with the node, its worker is simply older than the fields.
            colorFor: function (v, row) { return root.platformText(row) === "—" ? "#6b7280" : "#c4c9d1" }
        },
        { title: "Version", key: "version" },
        {
            title: "Labels",
            key: "labels",
            formatter: function (v) { return root.labelText(v) },
            colorFor: function (v) { return root.labelText(v) === "—" ? "#6b7280" : "#c4c9d1" }
        },
        // The EAM principal the worker registered as. The node name belongs to whoever claimed it
        // first, and this is who that was - so it is also what says a second worker cannot take the
        // name over and inherit the instances running under it.
        { title: "Registered by", key: "principal" }
    ]

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view worker nodes."
            return
        }
        loading = true
        error = ""
        // "list-nodes" takes no prefix and has no paging: an installation has as many nodes as it
        // has hosts, and there is nothing to filter server-side.
        eapClient.fetchNodes()
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Live updates are off by default: a table that reloads while it is being read moves rows
        // out from under the pointer. See AppSettings::liveListUpdates().
        running: appSettings.liveListUpdates && appSettings.autoRefreshSeconds > 0
                 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: eapClient
        function onNodesLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.nodes = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onNodesFailed(message) {
            root.loading = false
            root.error = message
        }
        function onNodeDrainChanged(node, drained) {
            // Said in full, because "drained" is narrower than it reads: what stops is placement,
            // and everything the node is already running stays where it is.
            root.actionNote = drained
                ? "Node '" + node + "' drained: nothing new is placed on it. What it already runs keeps "
                  + "running and its leases keep renewing - instances leave only as they are replaced."
                : "Node '" + node + "' is back in service: it can be placed on again."
            root.refresh()
        }
        function onNodeDrainFailed(message) {
            root.error = message
        }
        function onNodeDeleted(node) {
            root.actionNote = "Registration for '" + node + "' deleted. The name is free for another principal to "
                            + "register under."
            root.refresh()
        }
        function onNodeDeleteFailed(message) {
            root.error = message
        }
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            width: parent.width
            spacing: 20

            Breadcrumb {
                width: parent.width
                segments: [
                    { label: "EAP", action: () => root.back() },
                    { label: "Worker Nodes" }
                ]
            }

            SectionHeader {
                width: parent.width
                title: "Worker Nodes (" + root.totalCount + ")"
                // The count that matters stated outright, since the title's is the registered one
                // and those are not the same number the moment a node goes quiet.
                subtitle: root.totalCount === 0
                          ? "No workers have registered. Applications run on the manager's host."
                          : root.nodes.filter(n => root.acceptsWork(n)).length
                            + " of " + root.totalCount + " can take work."
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.nodes
                totalCount: root.totalCount
                // One page: "list-nodes" returns every node at once, so there is no size to pick
                // and nothing to page through.
                pageSizeSelectable: false
                pageSize: root.totalCount > 0 ? root.totalCount : 1
                pageIndex: 0
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                // No search box: the server takes no prefix for this listing, and a filter that
                // only hid rows already on screen would look like the others and not behave like
                // them.
                searchable: false
                emptyText: "No worker nodes are registered."
                rowsClickable: true
                onRowClicked: (row) => root.openNodeDetails(row.name, row)
                onRefreshRequested: root.refresh()

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function(row) {
                            root.openNodeDetails(row.name, row)
                        }
                    },
                    {
                        // Two entries rather than one that changes meaning with the row under the
                        // cursor: each is greyed out when the node is already in that state, which
                        // also says which state it is in before anything is clicked.
                        text: "Drain",
                        enabled: function(row) { return !!row && row.drained !== true },
                        action: function(row) {
                            root.actionNote = ""
                            eapClient.setNodeDrained(row.name, true)
                        }
                    },
                    {
                        text: "Put back in service",
                        enabled: function(row) { return !!row && row.drained === true },
                        action: function(row) {
                            root.actionNote = ""
                            eapClient.setNodeDrained(row.name, false)
                        }
                    },
                    {
                        // Only for a node nothing is coming from. Deleting a live registration is
                        // not a way to retire a node - the worker registers again on its next
                        // renewal - so the one case where it does what it looks like it does is a
                        // node that has already gone. The details page explains the rest.
                        text: "Delete registration",
                        enabled: function(row) { return !!row && row.live !== true },
                        action: function(row) {
                            root.actionNote = ""
                            eapClient.deleteNode(row.name)
                        }
                    }
                ]
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#4cd97b"
                font.pixelSize: 12
                visible: root.actionNote.length > 0
                text: root.actionNote
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "READY takes new instances. DRAINED keeps what it has and accepts nothing new. QUIET means "
                      + "the worker has not renewed inside the lease period - which does not by itself mean its "
                      + "processes have stopped, so euclid does not re-place them on that alone."
            }
        }
    }
}
