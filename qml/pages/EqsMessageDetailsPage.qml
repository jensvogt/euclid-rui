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
        if (priority === "MIDDLE") return "#ffb545"
        if (priority === "LOW") return "#4f8cff"
        return "#9aa1ac"
    }

    readonly property string status: detail("status", "")
    readonly property string priority: detail("priority", "")
    readonly property string queueErn: detail("queueErn", "")

    // Qt Quick's Text layout is O(n) in a way that becomes very noticeably slow (multi-second UI
    // freeze) on bodies in the hundreds-of-KB range, which SQS message bodies can legitimately
    // reach (maxMessageLength defaults to 1 MB) - so only ever hand it a bounded preview.
    readonly property int bodyPreviewLimit: 16384
    readonly property string fullBody: detail("body", "")
    readonly property bool bodyTruncated: fullBody.length > bodyPreviewLimit
    readonly property string bodyPreview: bodyTruncated ? fullBody.substring(0, bodyPreviewLimit) : fullBody

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
                StatCard { title: "Content Type"; value: root.detail("contentType", "—"); trend: "format"; trendUp: true; accent: "#4f8cff" }
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Queue"; value: root.queueName }
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

                        DetailField {
                            width: (techCol.width - 24) / 2
                            label: "Receipt Handle"
                            value: root.detail("receiptHandle", "").length > 0 ? root.detail("receiptHandle", "") : "None"
                        }
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

                    Rectangle {
                        width: parent.width
                        height: Math.min(300, bodyText.implicitHeight + 24)
                        radius: 8
                        color: "#14161b"
                        border.color: "#2c313c"
                        border.width: 1

                        ScrollView {
                            anchors.fill: parent
                            anchors.margins: 12
                            clip: true

                            Text {
                                id: bodyText
                                width: parent.width
                                text: root.bodyPreview.length > 0 ? root.bodyPreview : "(empty body)"
                                color: "#c4c9d1"
                                font.family: "monospace"
                                font.pixelSize: 12
                                wrapMode: Text.Wrap
                            }
                        }
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
