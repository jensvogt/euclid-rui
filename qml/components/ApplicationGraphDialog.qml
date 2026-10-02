import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// The whole namespace in one picture: every application the list is showing, and every queue, topic
// and bucket their declarations name, with the applications that share one attached to the same
// node.
//
// Each declaration is the file the application carries beside its artifact - `<applicationId>.
// euclid.json` in the application's own bucket - read here the same way anything else in a bucket is
// read, with ESM's get-object. There is no EAP action that hands declarations back and no action
// that hands back all of them at once, so this is one request per application: see `pump`, which
// keeps a few in the air at a time rather than opening one connection per application in the
// namespace and rather than waiting for each before asking for the next.
//
// Deliberately the declarations rather than the applications' `resources` lists. `resources` is a
// flat list of ERNs that exists to be mirrored onto the technical principal's grant - it says what
// may be reached and nothing about what is owned, which is half of what this picture is for.
Dialog {
    id: root

    // The rows the applications table is showing: applicationId, bucketErn, state, accountId and
    // namespace are what this uses.
    property var applications: []

    signal applicationActivated(string applicationId)

    // A declaration is a handful of resource names; anything near this is not one. The cutoff is the
    // server's, not this dialog's - get-object refuses an object at or above it rather than
    // streaming something this would then have to decide what to do with.
    readonly property int maxBytes: 256 * 1024

    // How many declarations are being read at once. A namespace can hold a few hundred
    // applications, and asking for all of them at once buys nothing: the requests queue anyway, and
    // the ones that do go out contend with whatever else the window is doing.
    readonly property int concurrency: 4

    property bool loading: false
    // Waiting to be asked for, and asked for but not yet answered - the second keyed by bucket and
    // key together, which is what the answer carries.
    property var queue: []
    property var inFlight: ({})
    property int inFlightCount: 0
    property int requestCount: 0
    property int completedCount: 0

    // Built as the answers come in and handed to the graph in one piece at the end, so the layout
    // settles once rather than restarting on every declaration that arrives.
    property var collected: []
    property var records: []
    // [{ id, message }] for the applications whose declaration could not be read at all - told
    // apart from the ones that simply have none, which is the ordinary state of anything deployed
    // before the sidecar existed.
    property var problems: []

    property bool sharedOnly: false
    property bool hideUndeclared: false

    readonly property var shownRecords: {
        if (!root.hideUndeclared) return root.records
        const kept = []
        for (const record of root.records) if (record.declared) kept.push(record)
        return kept
    }

    readonly property int declaredCount: {
        let count = 0
        for (const record of root.records) if (record.declared) ++count
        return count
    }

    modal: true
    anchors.centerIn: parent
    width: Math.min(1180, Overlay.overlay ? Overlay.overlay.width - 60 : 1180)
    padding: 24
    standardButtons: Dialog.NoButton

    background: Rectangle {
        radius: 16
        color: "#1b1e25"
        border.color: "#2c313c"
        border.width: 1
    }

    onOpened: root.load()
    // The requests outlive the dialog otherwise, and their answers would land in an empty map and be
    // ignored one at a time while the next open was already filling it.
    onClosed: root.forget()

    function forget() {
        root.loading = false
        root.queue = []
        root.inFlight = ({})
        root.inFlightCount = 0
    }

    function load() {
        root.forget()
        root.collected = []
        root.problems = []
        root.records = []

        const queue = []
        for (const application of root.applications) {
            const bucketErn = application.bucketErn === undefined ? "" : String(application.bucketErn)
            if (bucketErn.length === 0) {
                // An application whose artifact bucket is unknown - nothing to read from, and a
                // request that would fail for a reason nobody could act on is worse than saying so.
                root.fail(application, "no artifact bucket is recorded, so its declaration cannot be located")
                continue
            }
            queue.push(application)
        }

        root.queue = queue
        root.requestCount = queue.length
        root.completedCount = 0

        if (queue.length === 0) {
            root.finish()
            return
        }
        root.loading = true
        root.pump()
    }

    function requestKey(bucketErn, key) {
        return bucketErn + "|" + key
    }

    // Fills the in-flight set back up to `concurrency`, and is called again by every answer - so the
    // number of open requests is the thing held constant rather than the number of rounds.
    function pump() {
        while (root.inFlightCount < root.concurrency && root.queue.length > 0) {
            const application = root.queue.shift()
            const bucketErn = String(application.bucketErn)
            const key = String(application.applicationId) + ".euclid.json"
            root.inFlight[root.requestKey(bucketErn, key)] = application
            ++root.inFlightCount
            esmClient.fetchObjectContent(bucketErn, key, root.maxBytes)
        }
    }

    function record(application, declared, creates, uses, problem) {
        const collected = root.collected
        collected.push({
            id: String(application.applicationId),
            state: application.state === undefined ? "" : String(application.state),
            // What the plain names in the declaration are resolved against, and therefore part of
            // what makes two applications' "orders" the same queue rather than two of them.
            scope: [application.accountId === undefined ? "" : String(application.accountId),
                    application["namespace"] === undefined ? "" : String(application["namespace"])]
                   .filter(part => part.length > 0).join(" / "),
            declared: declared,
            problem: problem === undefined ? "" : problem,
            creates: creates,
            uses: uses
        })
    }

    // An application whose declaration is there and could not be read. It stays in the picture,
    // because leaving it out would be saying the namespace is smaller than it is - but with the
    // reason on it, so a node with nothing attached is not read as an application that declares
    // nothing.
    function fail(application, message) {
        root.record(application, false, [], [], message)
        root.problems = root.problems.concat([{ id: String(application.applicationId), message: message }])
    }

    function finish() {
        root.loading = false
        // Name order, so the seeding - and therefore the picture - does not depend on which
        // declarations happened to answer first.
        const collected = root.collected.slice()
        collected.sort((a, b) => a.id < b.id ? -1 : (a.id > b.id ? 1 : 0))
        root.records = collected
    }

    // One section of a declaration - "creates" or "uses" - flattened into the list the graph reads.
    //
    // Walks whatever kinds the file holds rather than only the three euclid knows: a stored
    // declaration was validated when it was applied, so an unfamiliar kind means a file written
    // against a newer euclid than this client, and dropping it silently would draw a picture that is
    // missing something without saying so. The graph greys out what it does not recognise.
    function sectionToList(document, section) {
        const source = document && document[section] ? document[section] : null
        if (!source) return []

        const list = []
        for (const kind of Object.keys(source)) {
            const entries = source[kind]
            if (!entries || entries.length === undefined) continue
            for (const entry of entries) {
                if (!entry || !entry.name) continue
                list.push({
                    kind: kind,
                    name: String(entry.name),
                    // Accepted as a string and as an array, because the file is written by hand and
                    // both spellings are already in use - one bucket wants ["subscribe", "read"]
                    // and one topic wants "produce". See Infrastructure::ReadResource.
                    access: entry.access === undefined ? []
                            : (typeof entry.access === "string" ? [entry.access] : entry.access),
                    owner: entry.owner === undefined ? "" : String(entry.owner)
                })
            }
        }
        return list
    }

    function settle(bucketErn, key) {
        const identifier = root.requestKey(bucketErn, key)
        const application = root.inFlight[identifier]
        // Not one of ours: this dialog shares esmClient with every object viewer in the window, and
        // an answer that arrives after the dialog was closed or reloaded has no place to go.
        if (application === undefined) return null
        delete root.inFlight[identifier]
        --root.inFlightCount
        ++root.completedCount
        return application
    }

    function advance() {
        if (root.queue.length > 0) root.pump()
        if (root.inFlightCount === 0 && root.queue.length === 0) root.finish()
    }

    Connections {
        target: esmClient

        function onObjectContentLoaded(bucketErn, key, content) {
            const application = root.settle(bucketErn, key)
            if (!application) return

            let document
            try {
                document = JSON.parse(content)
            } catch (error) {
                // The file is there and does not parse, which is a fault rather than an absence:
                // whatever EAP applied last is not what this says, and that is worth naming.
                root.fail(application, "its declaration is not valid JSON: " + error)
                root.advance()
                return
            }

            root.record(application, true,
                        root.sectionToList(document, "creates"),
                        root.sectionToList(document, "uses"), "")
            root.advance()
        }

        function onObjectContentFailed(bucketErn, key, message) {
            const application = root.settle(bucketErn, key)
            if (!application) return

            // ESM answers a missing object with "Object not found, bucket: ..., key: ...". Told
            // apart from a real failure because it is the ordinary state of an application that
            // ships no declaration, and drawing that as a fault would report the normal state of
            // most of an older installation as one.
            if (String(message).toLowerCase().indexOf("not found") >= 0)
                root.record(application, false, [], [], "")
            else
                root.fail(application, "its declaration could not be read: " + message)
            root.advance()
        }
    }

    contentItem: Column {
        width: root.availableWidth
        spacing: 14

        Item {
            width: parent.width
            height: titleColumn.implicitHeight

            Column {
                id: titleColumn
                width: parent.width - toolRow.width - 20
                spacing: 2

                Text { text: "Application graph"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    width: parent.width
                    text: root.loading
                          ? "Reading declarations… " + root.completedCount + " of " + root.requestCount
                          : root.records.length + " application(s) · " + root.declaredCount + " declare · "
                            + graph.resourceCount + " resource(s) · " + graph.sharedCount + " shared"
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
            }

            Row {
                id: toolRow
                spacing: 4
                anchors.right: parent.right
                anchors.verticalCenter: titleColumn.verticalCenter

                Button {
                    text: "Fit"
                    flat: true
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    // Also the way back from having panned or zoomed by hand: the picture starts
                    // framing itself again from here.
                    onClicked: { graph.autoFit = true; graph.fit() }
                }
                Button {
                    text: "Re-arrange"
                    flat: true
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    // Same graph, same seeding, so this is not a reshuffle in hope of a better one -
                    // it is how a layout that was dragged out of shape is put back.
                    onClicked: { graph.autoFit = true; graph.relayout() }
                }
                Button {
                    text: "Reload"
                    flat: true
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !root.loading
                    onClicked: root.load()
                }
            }
        }

        // What the lines mean, and the two questions the picture can be narrowed to answer. The
        // legend is not decoration here: solid against dashed is the whole ownership distinction,
        // and nothing else on screen says it.
        Flow {
            width: parent.width
            spacing: 18

            Row {
                spacing: 6
                Rectangle { width: 18; height: 2; color: "#9aa1ac"; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "owns — euclid created it, and it goes with the application"
                    color: "#9aa1ac"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                spacing: 6
                Row {
                    spacing: 3
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: 3
                        delegate: Rectangle { width: 4; height: 2; color: "#9aa1ac" }
                    }
                }
                Text {
                    text: "reaches — arrows point the way the data goes"
                    color: "#9aa1ac"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Repeater {
                model: [
                    { label: "queue", color: "#4f8cff" },
                    { label: "topic", color: "#c56bff" },
                    { label: "bucket", color: "#4cd97b" }
                ]
                delegate: Row {
                    required property var modelData
                    spacing: 5
                    Rectangle {
                        width: 9
                        height: 9
                        radius: 2
                        color: "transparent"
                        border.color: parent.modelData.color
                        border.width: 1.5
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: parent.modelData.label
                        color: "#9aa1ac"
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: 18

            CheckBox {
                id: sharedOnlyBox
                text: "Only shared resources"
                font.pixelSize: 12
                checked: root.sharedOnly
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
                onToggled: root.sharedOnly = checked
            }

            CheckBox {
                id: hideUndeclaredBox
                text: "Hide applications without a declaration"
                font.pixelSize: 12
                checked: root.hideUndeclared
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
                onToggled: root.hideUndeclared = checked
            }
        }

        Rectangle {
            width: parent.width
            height: Math.max(320, Math.min(620, (Overlay.overlay ? Overlay.overlay.height : 900) - 340))
            radius: 12
            color: "#14161b"
            border.color: "#2c313c"
            border.width: 1
            clip: true

            ApplicationGraph {
                id: graph
                anchors.fill: parent
                anchors.margins: 8
                visible: !root.loading && root.shownRecords.length > 0
                applications: root.shownRecords
                sharedOnly: root.sharedOnly
                onApplicationActivated: applicationId => {
                    root.close()
                    root.applicationActivated(applicationId)
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: 10
                visible: root.loading

                BusyIndicator {
                    running: root.loading
                    width: 36
                    height: 36
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Reading " + root.requestCount + " declaration(s)…"
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - 80
                spacing: 8
                visible: !root.loading && root.shownRecords.length === 0

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "◌"
                    color: "#6b7280"
                    font.pixelSize: 22
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    text: root.applications.length === 0
                          ? "There are no applications to draw."
                          : (root.declaredCount === 0
                             ? "None of these applications ships an infrastructure declaration, so there is nothing "
                               + "to draw. That is the state of everything deployed before the sidecar existed - it "
                               + "does not mean they have no connections, only that they do not declare them."
                             : "Everything is hidden by the filters above.")
                }
            }
        }

        // The declarations that could not be read at all. Kept out of the picture rather than drawn
        // as applications that own nothing, which is what they would otherwise look like.
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.problems.length > 0
            color: "#e0a458"
            font.pixelSize: 11
            text: {
                const named = root.problems.slice(0, 3).map(problem => problem.id + ": " + problem.message)
                return "⚠  " + root.problems.length + " declaration(s) could not be read, so those applications are "
                     + "drawn with nothing attached — " + named.join("; ")
                     + (root.problems.length > named.length ? "; …" : "")
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            color: "#6b7280"
            font.pixelSize: 11
            text: "Drawn from the declarations stored beside the artifacts, for the applications the list is "
                  + "currently showing — so this is what the applications ask for rather than what euclid has since "
                  + "made of it. Two applications share a node when they name the same resource and resolve it the "
                  + "same way. Drag a node to pin it, drag the background to pan, scroll to zoom, click an "
                  + "application to open it."
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
                onClicked: root.close()
            }
        }
    }
}
