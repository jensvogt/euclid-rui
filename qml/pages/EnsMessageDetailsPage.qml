import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string topicName: ""
    property string messageErn: ""
    property string messageId: ""
    property var details: ({})

    signal back()

    // Erns look like ern:ens:{region}:{accountId}:message:{messageId} - no namespace segment,
    // since messages are keyed by a randomly generated ID rather than a namespace-scoped name.
    function ernPart(index) {
        const parts = root.messageErn.split(":")
        return index < parts.length ? parts[index] : "—"
    }

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function byteLength(str) {
        if (!str)
            return 0
        let bytes = 0
        for (let i = 0; i < str.length; i++) {
            const code = str.charCodeAt(i)
            if (code <= 0x7f) bytes += 1
            else if (code <= 0x7ff) bytes += 2
            else if (code >= 0xd800 && code <= 0xdbff) { bytes += 4; i++ }
            else bytes += 3
        }
        return bytes
    }

    function statusColor(status) {
        if (status === "PUBLISHED") return "#4cd97b"
        return "#9aa1ac"
    }

    readonly property string status: detail("status", "")
    // The topic this message was published to. Carried on the message itself, so the page has it
    // without having to look the topic up.
    readonly property string topicErn: detail("topicErn", "")

    // What the publisher attached, already flattened to [{name, type, value}] by EnsClient and in
    // key order.
    //
    // There is no companion for euclid's own attributes, unlike the EQS message page: ENS stores
    // them on the message (Entity::ENS::Message::systemAttributes) but EnsMapper::toDto leaves them
    // behind and the DTO has no field to carry them, so nothing reaches this client. The System tab
    // is kept and says that outright - dropping it would make the gap look like a decision, and an
    // empty list would claim the message has none when what is true is that ENS does not send them.
    readonly property var attributes: detail("attributes", [])

    // Qt Quick's Text layout is O(n) in a way that becomes very noticeably slow (multi-second UI
    // freeze) on bodies in the hundreds-of-KB range, which message bodies can legitimately reach -
    // so only ever hand it a bounded preview.
    readonly property int bodyPreviewLimit: 16384
    readonly property string fullBody: detail("body", "")
    readonly property bool bodyTruncated: fullBody.length > bodyPreviewLimit
    readonly property string bodyPreview: bodyTruncated ? fullBody.substring(0, bodyPreviewLimit) : fullBody

    // An ENS message carries no content type, so the one handed to the viewer is read off the body
    // itself. It can only ever choose among text formats - the body arrived here as text - and all
    // it decides is whether the viewer offers to indent it.
    //
    // Never claimed for a truncated body: half a document does not parse, and the viewer would say
    // so in a way that reads like the message is malformed rather than merely cut short.
    readonly property string bodyContentType: {
        if (root.bodyTruncated) return "text/plain"
        const start = root.bodyPreview.trim().charAt(0)
        if (start === "{" || start === "[") return "application/json"
        if (start === "<") return "application/xml"
        return "text/plain"
    }

    // The same reading for the full-content dialog, taken from the whole body rather than the
    // preview: there is no truncation to work around there, so a document the tile above could
    // only show as plain text can be indented here - which is most of the reason to open it.
    readonly property string fullBodyContentType: {
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
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "Status"
                    value: root.status.length > 0 ? root.status : "—"
                    trend: root.status === "PUBLISHED" ? "delivered" : "processing"
                    trendUp: root.status === "PUBLISHED"
                    accent: root.statusColor(root.status)
                }
                StatCard { title: "Size"; value: SizeFormat.format(root.byteLength(root.fullBody)); trend: "on disk"; trendUp: true; accent: "#c56bff" }
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Topic"; value: root.topicName; copyable: true }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.ernPart(2) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.ernPart(3) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    // Its own row: an ERN is long enough to elide in a third of the tile, and it is
                    // what the CLI and every other client want pasted in.
                    DetailField { width: identityCol.width; label: "Message ERN"; value: root.messageErn; copyable: true }
                    DetailField { width: identityCol.width; label: "Topic ERN"; value: root.topicErn; copyable: true }
                }
            }

            // Body, attributes and system attributes as three tabs of one tile rather than three
            // tiles down the page - the same arrangement as the EQS message page, since it is the
            // same question being asked of a message. The panel keeps one height across all three
            // so that switching tabs does not move the tile up and down.
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
                            // find out it is empty. No count on the third: nothing is sent, so a
                            // "(0)" would be reporting a number this client never received.
                            TabButton { text: "Attributes (" + root.attributes.length + ")" }
                            TabButton { text: "System" }
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
                            // place. Nothing here writes it back: ENS has no action that replaces a
                            // published message's body, and a published message has already gone to
                            // its subscribers in any case - so an edit lives in this editor and
                            // nowhere else. The component's own "· edited" badge and Reset link say
                            // so while it is happening, and the line below says what it means.
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
                            // Always empty, and the text says why rather than letting it read as an
                            // answer about this message. See the note on root.attributes.
                            attributes: []
                            emptyText: "ENS does not send system attributes. It records euclid's own attributes on the "
                                       + "message, but list-messages leaves them out, so whether this message carries "
                                       + "any cannot be told from here."
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
                        text: "This edit is local to this editor. ENS has no action that replaces the body of a message "
                              + "already published, so nothing saves it - use Reset above to put the stored body back."
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
