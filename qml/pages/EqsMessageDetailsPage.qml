import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string queueName: ""
    property string messageErn: ""
    property string messageId: ""
    property var details: ({})

    signal back()

    // Erns look like ern:eqs:{region}:{accountId}:message:{messageId} - no namespace segment,
    // since messages are keyed by a randomly generated ID rather than a namespace-scoped name.
    function ernPart(index) {
        const parts = root.messageErn.split(":")
        return index < parts.length ? parts[index] : "—"
    }

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function statusColor(status) {
        if (status === "AVAILABLE") return "#4cd97b"
        if (status === "DELAYED") return "#ffb545"
        if (status === "INVISIBLE") return "#4f8cff"
        return "#9aa1ac"
    }

    function priorityColor(priority) {
        if (priority === "HIGH") return "#d94c4c"
        if (priority === "MEDIUM") return "#ffb545"
        if (priority === "LOW") return "#4f8cff"
        return "#9aa1ac"
    }

    readonly property string status: detail("status", "")
    readonly property string priority: detail("priority", "")
    readonly property string queueErn: detail("queueErn", "")

    // The two attribute maps, each already flattened to [{name, type, value}] by EqsClient and in
    // key order. Two properties rather than one, because EQS keeps them apart: "attributes" is
    // whatever the sender attached and "systemAttributes" is what euclid attached on top, and a
    // reader debugging their own message has to be able to tell which is which.
    readonly property var attributes: detail("attributes", [])
    readonly property var systemAttributes: detail("systemAttributes", [])

    // Qt Quick's Text layout is O(n) in a way that becomes very noticeably slow (multi-second UI
    // freeze) on bodies in the hundreds-of-KB range, which SQS message bodies can legitimately
    // reach (maxMessageLength defaults to 1 MB) - so only ever hand it a bounded preview.
    readonly property int bodyPreviewLimit: 16384
    readonly property string fullBody: detail("body", "")
    readonly property bool bodyTruncated: fullBody.length > bodyPreviewLimit
    readonly property string bodyPreview: bodyTruncated ? fullBody.substring(0, bodyPreviewLimit) : fullBody

    // An EQS message carries a content type - the server derives it from the body when the message
    // is sent - so that is what the viewer is told, and it only falls back to reading the body
    // itself when the message came from somewhere that recorded nothing.
    //
    // Never claimed for a truncated body: half a document does not parse, and the viewer would
    // report that in a way that reads like the message is malformed rather than merely cut short.
    readonly property string bodyContentType: {
        if (root.bodyTruncated) return "text/plain"
        const declared = String(root.detail("contentType", "")).trim()
        if (declared.length > 0) return declared
        const start = root.bodyPreview.trim().charAt(0)
        if (start === "{" || start === "[") return "application/json"
        if (start === "<") return "application/xml"
        return "text/plain"
    }

    // The same reading for the full-content dialog, which is the one place the whole body is on
    // screen. It has no truncation to work around, so a document that was only ever shown as plain
    // text in the tile above can be indented here - which is most of the reason to open it.
    readonly property string fullBodyContentType: {
        const declared = String(root.detail("contentType", "")).trim()
        if (declared.length > 0) return declared
        const start = root.fullBody.trim().charAt(0)
        if (start === "{" || start === "[") return "application/json"
        if (start === "<") return "application/xml"
        return "text/plain"
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
                    { label: "Messages", action: () => root.back() },
                    { label: root.messageId }
                ]
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.messageId
                    subtitle: root.messageErn
                }

                Button {
                    text: "- Delete"
                    flat: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#ff6b6b"
                    onClicked: {
                        eqsClient.deleteSqsMessage(root.queueErn, root.messageId)
                        root.back()
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "Status"
                    value: root.status.length > 0 ? root.status : "—"
                    trend: root.status === "AVAILABLE" ? "in queue" : "processing"
                    trendUp: root.status === "AVAILABLE"
                    accent: root.statusColor(root.status)
                }
                StatCard {
                    title: "Priority"
                    value: root.priority.length > 0 ? root.priority : "—"
                    trend: "delivery"
                    trendUp: true
                    accent: root.priorityColor(root.priority)
                }
                StatCard { title: "Size"; value: SizeFormat.format(root.detail("size", 0)); trend: "on disk"; trendUp: true; accent: "#c56bff" }
                StatCard { title: "Content Type"; value: root.detail("contentType", "—"); trend: "format"; trendUp: true; accent: "#4f8cff"; width:440 }
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Queue"; value: root.queueName; copyable: true }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.ernPart(2) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.ernPart(3) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    // Its own row: an ERN is long enough to elide in a third of the tile, and it is
                    // what the CLI and every other client want pasted in.
                    DetailField { width: identityCol.width; label: "Message ERN"; value: root.messageErn; copyable: true }
                    DetailField { width: identityCol.width; label: "Queue ERN"; value: root.queueErn; copyable: true }
                }
            }

            Rectangle {
                width: parent.width
                height: techCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: techCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Technical Details"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Grid {
                        width: parent.width
                        columns: 2
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField {
                            width: (techCol.width - 24) / 2
                            label: "Receipt Handle"
                            value: root.detail("receiptHandle", "").length > 0 ? root.detail("receiptHandle", "") : "None"
                        }
                        DetailField {
                            width: (techCol.width - 24) / 2
                            label: "Priority"
                            // Where in the queue this message sits: the receive loop weights
                            // priorities rather than taking them strictly in order, so a HIGH
                            // message is served sooner but a LOW one is not starved.
                            value: root.priority.length > 0 ? root.priority : "—"
                        }
                        DetailField {
                            width: (techCol.width - 24) / 2
                            label: "Received Count"
                            // What separates a first delivery from a redelivery of one that failed
                            // or timed out, and what the queue's maxReceiveCount is counted against
                            // before the message is moved to the dead letter queue.
                            value: String(root.detail("receivedCount", 0))
                        }
                        DetailField {
                            width: (techCol.width - 24) / 2
                            label: "Last Received"
                            value: root.detail("lastReceived", "").length > 0
                                   ? DateFormat.format(root.detail("lastReceived", "")) : "Never"
                        }
                    }
                }
            }

            // Body, attributes and system attributes as three tabs of one tile rather than three
            // tiles down the page: they are the three halves of "what was actually sent", and each
            // is read on its own. The panel keeps one height across all three so that switching
            // tabs does not move the tile - and with it everything under it - up and down.
            Rectangle {
                width: parent.width
                height: payloadCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: payloadCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: payloadTabs.implicitHeight

                        TabBar {
                            id: payloadTabs
                            // Sized to its tabs rather than to the tile: a three-tab bar stretched
                            // across a wide window puts "Body" a third of the way along it.
                            width: Math.min(parent.width, implicitWidth)
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"

                            TabButton { text: "Body" }
                            // Counted in the tab, so an empty one does not have to be opened to
                            // find out it is empty.
                            TabButton { text: "Attributes (" + root.attributes.length + ")" }
                            TabButton { text: "System (" + root.systemAttributes.length + ")" }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: payloadTabs.verticalCenter
                            spacing: 12

                            Text {
                                visible: payloadTabs.currentIndex === 0 && root.bodyTruncated
                                anchors.verticalCenter: parent.verticalCenter
                                text: "showing first " + SizeFormat.format(root.bodyPreviewLimit) + " of " + SizeFormat.format(root.fullBody.length)
                                color: "#ffb545"
                                font.pixelSize: 11
                            }

                            Button {
                                text: "Full Content"
                                flat: true
                                visible: payloadTabs.currentIndex === 0 && root.fullBody.length > 0
                                anchors.verticalCenter: parent.verticalCenter
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                onClicked: fullBodyDialog.open()
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 300

                        EditableText {
                            id: bodyView
                            anchors.fill: parent
                            visible: payloadTabs.currentIndex === 0
                            // Editable, so the body can be selected, searched and worked on in
                            // place. Nothing here writes it back: EQS has no action that replaces a
                            // sent message's body - see the action list in EqsServer.cpp - so an
                            // edit lives in this editor and nowhere else. The component's own
                            // "· edited" badge and Reset link say so while it is happening, and the
                            // line below says what it means.
                            //
                            // Except on a body too large to show whole: what is in the editor then
                            // is the first 16 KB of it, and editing a fragment of a document is not
                            // an edit of the document. Read the whole thing through "Full Content".
                            readOnly: root.bodyTruncated
                            contentType: root.bodyContentType
                            content: root.bodyPreview
                            // A message body is as often one long line as it is code, so it is
                            // wrapped rather than scrolled sideways - which is what the plain view
                            // did too.
                            wrapMode: TextArea.Wrap
                            emptyText: "(empty body)"
                        }

                        MessageAttributes {
                            anchors.fill: parent
                            visible: payloadTabs.currentIndex === 1
                            attributes: root.attributes
                            emptyText: "This message carries no attributes of its own."
                        }

                        MessageAttributes {
                            anchors.fill: parent
                            visible: payloadTabs.currentIndex === 2
                            attributes: root.systemAttributes
                            emptyText: "euclid attached no system attributes to this message."
                        }
                    }

                    // Only once there is an edit to explain. Said here rather than in the tab
                    // header because it is the answer to "where did my change go", which is a
                    // question nobody has until they have made one.
                    Text {
                        width: parent.width
                        visible: payloadTabs.currentIndex === 0 && bodyView.modified
                        wrapMode: Text.WordWrap
                        color: "#e0a458"
                        font.pixelSize: 11
                        text: "This edit is local to this editor. EQS has no action that replaces the body of a message "
                              + "already sent, so nothing saves it - use Reset above to put the stored body back."
                    }
                }
            }
        }
    }

    Dialog {
        id: fullBodyDialog
        modal: true
        anchors.centerIn: parent
        width: 800
        padding: 24
        standardButtons: Dialog.NoButton

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: fullBodyDialog.availableWidth
            spacing: 14

            Column {
                width: parent.width
                spacing: 2
                Text { text: "Full Body"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: SizeFormat.format(root.fullBody.length) + " total"
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }

            // The whole body, in the same viewer the Body tab uses - so a JSON message is indented
            // here too, and is selectable rather than merely readable. Read-only where the tab is
            // not: this is the view for reading a body too large for the tab to show whole, and an
            // editor over a megabyte of text is slow in a way a reader has no use for.
            EditableText {
                width: parent.width
                height: 420
                readOnly: true
                contentType: root.fullBodyContentType
                content: root.fullBody
                wrapMode: TextArea.Wrap
                emptyText: "(empty body)"
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
                    onClicked: fullBodyDialog.close()
                }
            }
        }
    }
}
