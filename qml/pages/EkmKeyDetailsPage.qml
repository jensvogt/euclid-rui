import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string keyErn: ""
    property string keyName: ""
    property var details: ({})

    signal back()

    function statusColor(status) {
        if (status === "AVAILABLE") return "#4cd97b"
        if (status === "REVOKED" || status === "UPLOADED") return "#ffb545"
        if (status === "PENDING_DELETION") return "#ff4f5e"
        return "#9aa1ac"
    }

    // Erns look like ern:ekm:{region}:{accountId}:key:{keyId} - no namespace segment, since keys
    // are keyed by a randomly generated ID rather than a user-chosen, namespace-scoped name.
    function ernPart(index) {
        const parts = root.keyErn.split(":")
        return index < parts.length ? parts[index] : "—"
    }

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function tagList() {
        const tags = detail("tags", {})
        return tags ? Object.keys(tags) : []
    }

    // No "get single key" action exists server-side to re-fetch after a mutation, so apply the
    // now-confirmed change to the local details snapshot instead (reassigned, not mutated in
    // place, so the "var" property change notification actually fires).
    function addTagLocally(key, value) {
        const tags = Object.assign({}, detail("tags", {}))
        tags[key] = value
        root.details = Object.assign({}, root.details, { tags: tags })
    }

    function removeTagLocally(key) {
        const tags = Object.assign({}, detail("tags", {}))
        delete tags[key]
        root.details = Object.assign({}, root.details, { tags: tags })
    }

    Connections {
        target: ekmClient
        function onKeyTagAdded(keyErn, key, value) {
            if (keyErn !== root.keyErn) return
            addTagDialog.saving = false
            addTagDialog.close()
            root.addTagLocally(key, value)
        }
        function onKeyTagAddFailed(message) {
            addTagDialog.saving = false
            addTagDialog.errorText = message
        }
        function onKeyTagDeleted(keyErn, key) {
            if (keyErn !== root.keyErn) return
            root.removeTagLocally(key)
        }
    }

    readonly property string status: detail("status", "")
    readonly property string deletionDate: detail("deletionDate", "")

    ScrollView {
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            width: parent.width
            spacing: 20

            Button {
                text: "‹ Back to Keys"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.keyName
                    subtitle: root.keyErn
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: "- Revoke"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ffb545"
                        enabled: root.status === "AVAILABLE"
                        onClicked: ekmClient.revokeKey(root.keyErn)
                    }

                    Button {
                        text: "Delete"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        enabled: root.status !== "PENDING_DELETION"
                        onClicked: ekmClient.deleteKey(root.keyName)
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard { title: "Algorithm"; value: root.detail("algorithm", "—"); trend: "cipher"; trendUp: true; accent: "#4f8cff" }
                StatCard { title: "Length"; value: root.detail("length", 0) + " bit"; trend: "key size"; trendUp: true; accent: "#c56bff" }
                StatCard {
                    title: "Status"
                    value: root.status.length > 0 ? root.status : "—"
                    trend: root.status === "AVAILABLE" ? "usable" : "restricted"
                    trendUp: root.status === "AVAILABLE"
                    accent: root.statusColor(root.status)
                    width: 440
                }
                StatCard {
                    title: "Scheduled Deletion"
                    value: root.deletionDate.length > 0 ? DateFormat.format(root.deletionDate) : "None"
                    trend: root.deletionDate.length > 0 ? "pending" : "not scheduled"
                    trendUp: root.deletionDate.length === 0
                    accent: "#ffb545"
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.ernPart(2) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.ernPart(3) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
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

                    Item {
                        width: parent.width
                        height: tagsHeaderRow.implicitHeight

                        Row {
                            id: tagsHeaderRow
                            Text { text: "Tags"; color: "white"; font.pixelSize: 15; font.bold: true }
                        }

                        Button {
                            text: "+ Add"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: tagsHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: addTagDialog.open()
                        }
                    }

                    Text {
                        visible: root.tagList().length === 0
                        text: "No tags set for this key."
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
                                width: chipRow.implicitWidth + 20

                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData + ": " + root.detail("tags", {})[modelData]
                                        color: "#c4c9d1"
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "×"
                                        color: removeArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                        font.pixelSize: 13
                                        font.bold: true

                                        MouseArea {
                                            id: removeArea
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: ekmClient.deleteKeyTag(root.keyErn, modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: addTagDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            tagKeyField.text = ""
            tagValueField.text = ""
            addTagDialog.errorText = ""
            addTagDialog.saving = false
            tagKeyField.forceActiveFocus()
        }

        contentItem: Column {
            width: addTagDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Tag"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Set a key/value tag on this key."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Key"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: tagKeyField
                    width: parent.width
                    placeholderText: "e.g. environment"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: tagValueField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Value"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: tagValueField
                    width: parent.width
                    placeholderText: "e.g. production"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (saveTagButton.enabled) saveTagButton.clicked()
                }
                Text {
                    text: addTagDialog.errorText
                    color: "#ff6b6b"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                    visible: text.length > 0
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
                    onClicked: addTagDialog.close()
                }

                BusyIndicator {
                    running: addTagDialog.saving
                    visible: addTagDialog.saving
                    width: 22
                    height: 22
                    anchors.right: saveTagButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: saveTagButton
                    text: "Add"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !addTagDialog.saving && tagKeyField.text.trim().length > 0
                    onClicked: {
                        addTagDialog.errorText = ""
                        addTagDialog.saving = true
                        ekmClient.addKeyTag(root.keyErn, tagKeyField.text.trim(), tagValueField.text)
                    }
                }
            }
        }
    }
}
