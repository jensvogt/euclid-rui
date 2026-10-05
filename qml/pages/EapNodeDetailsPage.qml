import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// One worker node. Everything here is the worker's own account of itself, replaced on every
// registration - euclid collects none of it, because the worker is the only thing that can read
// the machine it runs on.
//
// The one exception is `drained`, which is the only field an operator writes, and the only action
// this page offers.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string nodeName: ""
    // The row this page was opened from, which is what it paints with until "get-node" answers.
    property var details: ({})

    // The same node as of the last refresh, or null before one has answered. Kept apart from
    // `details` rather than assigned over it: `details` is bound to a window property in Main.qml,
    // and writing to it from here would break that binding for good.
    property var loaded: null

    readonly property var node: root.loaded !== null ? root.loaded : root.details

    property string error: ""
    property string actionNote: ""
    property bool draining: false
    property bool deleting: false

    signal back()

    function detail(key, fallback) {
        return root.node && root.node[key] !== undefined ? root.node[key] : fallback
    }

    readonly property bool live: root.detail("live", false) === true
    readonly property bool drained: root.detail("drained", false) === true
    // Node::acceptsWork server-side. The two flags are independent, so this is the only honest way
    // to ask whether anything can be placed here.
    readonly property bool acceptsWork: root.live && !root.drained

    function nodeState() {
        if (!root.node || root.node.name === undefined) return "—"
        // Quiet first: a drained node that has also stopped renewing is a problem rather than a
        // decision, and reading it as DRAINED would make it look intended.
        if (!root.live) return "QUIET"
        if (root.drained) return "DRAINED"
        return "READY"
    }

    function nodeStateColor() {
        const state = root.nodeState()
        if (state === "READY") return "#4cd97b"
        if (state === "DRAINED") return "#ffb545"
        if (state === "QUIET") return "#ff6b6b"
        return "#9aa1ac"
    }

    // "linux-x86_64". Either half may be missing - a worker older than the fields reports neither -
    // and then only the other is shown, since "linux-" reads as truncated rather than absent.
    function platformText() {
        const os = String(root.detail("os", "")).trim()
        const arch = String(root.detail("arch", "")).trim()
        if (os.length === 0 && arch.length === 0) return "—"
        if (os.length === 0) return arch
        if (arch.length === 0) return os
        return os + "-" + arch
    }

    readonly property var labelKeys: {
        const labels = root.detail("labels", null)
        return labels ? Object.keys(labels).sort() : []
    }

    function refresh() {
        if (!root.loggedIn || root.nodeName.length === 0)
            return
        root.error = ""
        eapClient.fetchNode(root.nodeName)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()
    // Opening a node goes through hidden-to-visible, so this is about the name changing underneath
    // a page already on screen.
    onNodeNameChanged: if (visible) refresh()

    Connections {
        target: eapClient

        function onNodeLoaded(node, details) {
            if (node !== root.nodeName) return
            root.loaded = details
            root.error = ""
        }
        function onNodeLoadFailed(node, message) {
            if (node !== root.nodeName) return
            // The server's own wording, which for a name that is not registered says so plainly.
            // Not cleared from the screen: the last reading is still what this page was opened
            // with, and the message above it says it is no longer current.
            root.error = message
        }
        function onNodeDeleted(node) {
            if (node !== root.nodeName) return
            root.deleting = false
            root.back()
        }
        function onNodeDeleteFailed(message) {
            root.deleting = false
            root.error = message
        }
        function onNodeDrainChanged(node, drained) {
            if (node !== root.nodeName) return
            root.draining = false
            // Said in full, because "drained" is narrower than it reads: what stops is placement.
            root.actionNote = drained
                ? "Drained: nothing new is placed here. What this node already runs keeps running and its "
                  + "leases keep renewing - instances leave only as they are replaced."
                : "Back in service: instances can be placed here again."
            root.refresh()
        }
        function onNodeDrainFailed(message) {
            root.draining = false
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
                    { label: "Worker Nodes", action: () => root.back() },
                    { label: root.nodeName }
                ]
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.nodeName
                    subtitle: "Registered by " + root.detail("principal", "—")
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 12

                    Button {
                        text: root.drained ? "Put Back In Service" : "Drain"
                        highlighted: true
                        Material.theme: Material.Dark
                        // Draining is the cautious direction and undraining the restorative one, so
                        // only the first is coloured as a change worth thinking about.
                        Material.accent: root.drained ? "#4cd97b" : "#ffb545"
                        enabled: !root.draining && !root.deleting && root.nodeName.length > 0
                        onClicked: {
                            root.actionNote = ""
                            root.draining = true
                            eapClient.setNodeDrained(root.nodeName, !root.drained)
                        }
                    }

                    Button {
                        text: "Delete Registration"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        enabled: !root.deleting && root.nodeName.length > 0
                        onClicked: deleteDialog.open()
                    }
                }
            }

            Text {
                width: parent.width
                visible: root.error.length > 0
                text: root.error
                color: "#ff6b6b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "State"
                    value: root.nodeState()
                    trend: root.acceptsWork ? "takes new instances" : "nothing is placed here"
                    trendUp: root.acceptsWork
                    accent: root.nodeStateColor()
                }
                StatCard {
                    title: "CPUs"
                    value: String(root.detail("cpuCount", 0))
                    // What placement actually uses it for, rather than "cores" - the figure only
                    // matters as the divisor.
                    trend: "load is divided by this"
                    trendUp: true
                    accent: "#4f8cff"
                }
                StatCard {
                    title: "OS / Arch"
                    value: root.platformText()
                    trend: "what the worker was built for"
                    trendUp: root.platformText() !== "—"
                    accent: "#c56bff"
                    width: 440
                }
                StatCard {
                    title: "Last Seen"
                    value: DateFormat.format(root.detail("lastSeen", ""))
                    // The whole diagnosis when the state reads QUIET: a node that has gone is a
                    // node whose last renewal is old.
                    trend: root.live ? "renewing" : "has not renewed inside the lease"
                    trendUp: root.live
                    accent: root.live ? "#4cd97b" : "#ff6b6b"
                    width: 440
                }
            }

            Rectangle {
                width: parent.width
                height: identityCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: identityCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Identity"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (identityCol.width - 48) / 3; label: "Node"; value: root.nodeName; copyable: true }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Operating system"; value: root.detail("os", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Architecture"; value: root.detail("arch", "—") }
                        DetailField {
                            width: (identityCol.width - 48) / 3
                            label: "euclid version"
                            value: root.detail("version", "—")
                        }
                        DetailField { width: (identityCol.width - 48) / 3; label: "CPUs"; value: String(root.detail("cpuCount", 0)) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Last seen"; value: DateFormat.format(root.detail("lastSeen", "")) }
                    }

                    // Its own row, and worth its own line: the name belongs to whoever registered
                    // it first, so this is also what says a second worker cannot take the name over
                    // and inherit the instances running under it.
                    DetailField { width: identityCol.width; label: "Registered by"; value: root.detail("principal", "—"); copyable: true }

                    Text {
                        width: parent.width
                        text: "Everything above is the worker's own account of itself, replaced on every registration. "
                              + "A worker that restarts re-registers under the same name and picks up the instances it "
                              + "already had, which is what makes a restart cheap rather than a re-placement."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: labelsCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: labelsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Labels"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        text: "What an application's placement constraints are matched against: a node says what it is "
                              + "and an application says what it needs. Free-form on purpose - euclid has no opinion "
                              + "about what \"gpu\" means."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.labelKeys.length === 0
                        // Not a fault: a node with no labels is matched by any placement that names
                        // none, which is most of them.
                        text: "No labels. Only applications that name no placement constraints are put here."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Flow {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.labelKeys

                            delegate: Rectangle {
                                id: labelChip
                                required property string modelData

                                radius: 8
                                color: "#2c3648"
                                height: 26
                                width: labelChipText.implicitWidth + 20

                                Text {
                                    id: labelChipText
                                    anchors.centerIn: parent
                                    text: labelChip.modelData + "=" + root.detail("labels", {})[labelChip.modelData]
                                    color: "#c4c9d1"
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
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
                text: "What is running here is not shown: the manager records which node owns each slot, but "
                      + "\"list-modules\" does not report it, so no client can tell. QUIET means the worker has not "
                      + "renewed inside the lease period - which does not by itself mean its processes have stopped, "
                      + "so euclid does not re-place them on that alone."
            }
        }
    }

    // Worth a confirmation less for the damage it does than for the damage it does not: an operator
    // reaching for "delete" on a node they want gone is reaching for the wrong thing, and the
    // dialog is the only place that can say so before it is clicked.
    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 440
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: deleteDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 8

                Text { text: "Delete Registration"; color: "white"; font.pixelSize: 18; font.bold: true }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    text: "Removes the record of \"" + root.nodeName + "\", freeing the name for another principal to "
                          + "register under. The name is bound to whoever claimed it first, and that binding is what "
                          + "stops one worker inheriting another's instances and credentials - so giving it away is a "
                          + "deliberate act."
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#ffb545"
                    font.pixelSize: 12
                    // Only while the worker is still there, because that is when this does not do
                    // what it looks like it does.
                    visible: root.live
                    text: "⚠  This node is still renewing. Deleting the registration does not stop it: the leases are "
                          + "left alone and the worker registers again on its next renewal. To retire a node, drain "
                          + "it and then stop the worker."
                }
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Cancel"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    onClicked: deleteDialog.close()
                }

                Button {
                    text: "Delete"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#ff6b6b"
                    enabled: !root.deleting
                    onClicked: {
                        root.deleting = true
                        deleteDialog.close()
                        eapClient.deleteNode(root.nodeName)
                    }
                }
            }
        }
    }
}
