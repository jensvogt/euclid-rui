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

    ScrollView {
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            width: parent.width
            spacing: 20

            Button {
                text: "‹ Back to Messages"
                flat: true
                onClicked: root.back()
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Topic"; value: root.topicName }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.ernPart(2) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.ernPart(3) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }
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

                        DetailField { width: (techCol.width - 24) / 2; label: "MD5 (Body)"; value: root.detail("md5Body", "—"); copyable: true }
                        DetailField { width: (techCol.width - 24) / 2; label: "MD5 (Attributes)"; value: root.detail("md5Attributes", "—"); copyable: true }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: bodyCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: bodyCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: bodyHeaderRow.implicitHeight

                        Row {
                            id: bodyHeaderRow
                            spacing: 10
                            Text { text: "Body"; color: "white"; font.pixelSize: 15; font.bold: true }
                            Text {
                                visible: root.bodyTruncated
                                anchors.verticalCenter: parent.verticalCenter
                                text: "showing first " + SizeFormat.format(root.bodyPreviewLimit) + " of " + SizeFormat.format(root.fullBody.length)
                                color: "#ffb545"
                                font.pixelSize: 11
                            }
                        }

                        Button {
                            text: "Full Content"
                            flat: true
                            visible: root.fullBody.length > 0
                            anchors.right: parent.right
                            anchors.verticalCenter: bodyHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: fullBodyDialog.open()
                        }
                    }

                    // Read-only: a published message is what it is, and ENS has no action that
                    // would write a changed body back.
                    EditableText {
                        id: bodyView
                        width: parent.width
                        // Grows with the body up to the same cap the plain text view had, so a
                        // two-line message does not sit in a panel sized for a hundred.
                        height: Math.max(120, Math.min(300, bodyView.implicitContentHeight))
                        readOnly: true
                        contentType: root.bodyContentType
                        content: root.bodyPreview
                        // A message body is as often one long line as it is code, so it is wrapped
                        // rather than scrolled sideways - which is what the plain view did too.
                        wrapMode: TextArea.Wrap
                        emptyText: "(empty body)"
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

            Rectangle {
                width: parent.width
                height: 420
                radius: 8
                color: "#14161b"
                border.color: "#2c313c"
                border.width: 1

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true

                    Text {
                        width: parent.width
                        text: root.fullBody.length > 0 ? root.fullBody : "(empty body)"
                        color: "#c4c9d1"
                        font.family: "monospace"
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }
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
