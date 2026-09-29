import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// What one application is wired to, drawn from its own infrastructure declaration.
//
// The declaration is the file the application carries beside its artifact - `<applicationId>.
// euclid.json` in the application's own bucket - which EAP reads on create, update and redeploy to
// make the installation match. It is read here the same way anything else in a bucket is read, with
// ESM's get-object: there is no EAP action that hands a declaration back, and none is needed.
//
// Deliberately the declaration rather than the application's `resources` list. `resources` is a flat
// list of ERNs that exists to be mirrored onto the technical principal's grant - it is what ESM and
// EQS enforce - so it says what may be reached and nothing about what is owned, which is the
// distinction a picture of connections is for.
Dialog {
    id: root

    property string applicationId: ""
    // The application's own bucket, where the declaration sits beside the artifact.
    property string bucketErn: ""

    // A declaration is a handful of resource names; anything near this is not one. The cutoff is
    // the server's, not this dialog's - get-object refuses an object at or above it rather than
    // streaming something this would then have to decide what to do with.
    readonly property int maxBytes: 256 * 1024

    readonly property string objectKey: root.applicationId + ".euclid.json"

    property bool loading: false
    // Set when the object is simply not there, which is not an error: every application deployed
    // before the sidecar existed has no declaration, and saying "failed" about those would report
    // the normal state of most of an older installation as a fault.
    property bool missing: false
    property string errorText: ""

    property var creates: []
    property var uses: []

    readonly property bool hasGraph: !root.loading && !root.missing && root.errorText.length === 0
                                     && (root.creates.length > 0 || root.uses.length > 0)

    modal: true
    anchors.centerIn: parent
    width: Math.min(900, Overlay.overlay ? Overlay.overlay.width - 80 : 900)
    padding: 24
    standardButtons: Dialog.NoButton

    background: Rectangle {
        radius: 16
        color: "#1b1e25"
        border.color: "#2c313c"
        border.width: 1
    }

    onOpened: root.load()

    function load() {
        root.creates = []
        root.uses = []
        root.missing = false
        root.errorText = ""

        if (root.bucketErn.length === 0) {
            // An application whose artifact bucket is unknown to this page - nothing to read from,
            // and saying so beats a request that would fail for a reason nobody could act on.
            root.errorText = "This application has no artifact bucket recorded, so its declaration cannot be located."
            return
        }

        root.loading = true
        esmClient.fetchObjectContent(root.bucketErn, root.objectKey, root.maxBytes)
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

    Connections {
        target: esmClient

        function onObjectContentLoaded(bucketErn, key, content) {
            // Both, because this dialog shares esmClient with the object viewer: a bucket page
            // reading some other object must not land here.
            if (!root.loading || bucketErn !== root.bucketErn || key !== root.objectKey) return
            root.loading = false

            let document
            try {
                document = JSON.parse(content)
            } catch (error) {
                root.errorText = "The declaration is not valid JSON: " + error
                return
            }

            root.creates = root.sectionToList(document, "creates")
            root.uses = root.sectionToList(document, "uses")
        }

        function onObjectContentFailed(bucketErn, key, message) {
            if (!root.loading || bucketErn !== root.bucketErn || key !== root.objectKey) return
            root.loading = false
            // ESM answers a missing object with "Object not found, bucket: ..., key: ...". Told
            // apart from a real failure because it is the ordinary state of an application that
            // ships no declaration, and that is worth saying in its own words.
            if (String(message).toLowerCase().indexOf("not found") >= 0) root.missing = true
            else root.errorText = message
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
                width: parent.width - 90
                spacing: 2

                Text { text: "Connections"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    width: parent.width
                    text: "What \"" + root.applicationId + "\" declares in " + root.objectKey + "."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                }
            }

            Button {
                text: "Reload"
                flat: true
                anchors.right: parent.right
                anchors.verticalCenter: titleColumn.verticalCenter
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
                enabled: !root.loading
                onClicked: root.load()
            }
        }

        // The legend, which is also the count: two numbers and what the two halves of the picture
        // mean, so the drawing does not have to be decoded before it can be read.
        Row {
            width: parent.width
            spacing: 18
            visible: root.hasGraph

            Row {
                spacing: 6
                Rectangle { width: 16; height: 2; color: "#9aa1ac"; anchors.verticalCenter: parent.verticalCenter }
                Text {
                    text: "Owns " + root.creates.length + " (left) — euclid created these, and they go with it"
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
                    text: "Reaches " + root.uses.length + " (right) — somebody else owns these"
                    color: "#9aa1ac"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 440
            radius: 12
            color: "#14161b"
            border.color: "#2c313c"
            border.width: 1
            clip: true

            BusyIndicator {
                anchors.centerIn: parent
                running: root.loading
                visible: root.loading
                width: 36
                height: 36
            }

            ConnectionGraph {
                anchors.fill: parent
                anchors.margins: 12
                visible: root.hasGraph
                applicationId: root.applicationId
                creates: root.creates
                uses: root.uses
            }

            // Nothing to draw, for one of three reasons, each said in its own words rather than
            // collapsed into one empty state - "no declaration" and "a declaration that names
            // nothing" are different facts about an application.
            Column {
                anchors.centerIn: parent
                width: parent.width - 80
                spacing: 8
                visible: !root.loading && !root.hasGraph

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.errorText.length > 0 ? "⚠" : "◌"
                    color: root.errorText.length > 0 ? "#e0a458" : "#6b7280"
                    font.pixelSize: 22
                }

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    color: root.errorText.length > 0 ? "#e0a458" : "#9aa1ac"
                    font.pixelSize: 12
                    text: {
                        if (root.errorText.length > 0) return root.errorText
                        if (root.missing)
                            return "This application ships no infrastructure declaration, so there is nothing to draw. "
                                 + "Everything deployed before the sidecar existed is in this state - it does not mean "
                                 + "the application has no connections, only that it does not declare them."
                        return "The declaration names no resources: this application neither creates nor uses anything."
                    }
                }
            }
        }

        // What the picture is and is not, kept under it rather than in a tooltip: it is drawn from
        // what the application asked for, and an operator comparing it against the installation
        // should know that is what they are comparing.
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.hasGraph
            color: "#6b7280"
            font.pixelSize: 11
            text: "Read from the declaration stored beside the artifact, so this is what the application asks for "
                  + "rather than what euclid has since made of it. Names are resolved against this application's own "
                  + "account and namespace. A declared owner is recorded by whoever wrote the file - euclid checks that "
                  + "the resource exists, not who claims it."
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
