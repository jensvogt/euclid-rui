import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string queueErn: ""
    property string queueName: ""
    property var details: ({})

    signal back()
    signal viewMessages(string queueErn, string queueName)

    // Erns look like ern:eqs:{region}:{accountId}:{namespace}:queue:{name}
    function ernPart(index) {
        const parts = root.queueErn.split(":")
        return index < parts.length ? parts[index] : "—"
    }

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function tagList() {
        const tags = detail("tags", {})
        return tags ? Object.keys(tags) : []
    }

    readonly property int available: Number(detail("available", 0))
    readonly property int delayed: Number(detail("delayed", 0))
    readonly property int invisible: Number(detail("invisible", 0))

    ScrollView {
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            width: parent.width
            spacing: 20

            Button {
                text: "‹ Back to Queues"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.queueName
                    subtitle: root.queueErn
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: "- Purge"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        enabled: root.available > 0
                        onClicked: eqsClient.purgeQueue(root.queueErn)
                    }

                    Button {
                        text: "View Messages"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: root.viewMessages(root.queueErn, root.queueName)
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard { title: "Available"; value: String(root.available); trend: "messages"; trendUp: true; accent: "#4cd97b" }
                StatCard { title: "Delayed"; value: String(root.delayed); trend: "messages"; trendUp: root.delayed === 0; accent: "#ffb545" }
                StatCard { title: "Invisible"; value: String(root.invisible); trend: "messages"; trendUp: root.invisible === 0; accent: "#4f8cff" }
                StatCard { title: "Size"; value: SizeFormat.format(root.detail("size", 0)); trend: "on disk"; trendUp: true; accent: "#c56bff" }
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Owner"; value: root.detail("owner", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.ernPart(2) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.ernPart(3) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Namespace"; value: root.ernPart(4) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: configCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: configCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Configuration"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (configCol.width - 48) / 3; label: "Delay"; value: root.detail("delay", 0) + " s" }
                        DetailField { width: (configCol.width - 48) / 3; label: "Visibility Timeout"; value: root.detail("visibility", 0) + " s" }
                        DetailField { width: (configCol.width - 48) / 3; label: "Max Receive Count"; value: String(root.detail("maxReceiveCount", 0)) }
                        DetailField { width: (configCol.width - 48) / 3; label: "Max Message Length"; value: SizeFormat.format(root.detail("maxMessageLength", 0)) }
                        DetailField {
                            width: (configCol.width * 2 / 3)
                            label: "Dead Letter Queue"
                            value: root.detail("deadLetterQueueArn", "").length > 0 ? root.detail("deadLetterQueueArn", "") : "None"
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: tagsCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: tagsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Tags"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        visible: root.tagList().length === 0
                        text: "No tags set for this queue."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: root.tagList().length > 0

                        Repeater {
                            model: root.tagList()
                            delegate: Rectangle {
                                radius: 8
                                color: "#2c3648"
                                height: 26
                                width: tagText.implicitWidth + 20
                                Text {
                                    id: tagText
                                    anchors.centerIn: parent
                                    text: modelData + ": " + root.detail("tags", {})[modelData]
                                    color: "#c4c9d1"
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
