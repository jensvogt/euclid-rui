import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string topicErn: ""
    property string topicName: ""
    property var details: ({})

    signal back()
    signal viewMessages(string topicErn, string topicName)

    // Erns look like ern:ens:{region}:{accountId}:{namespace}:topic:{name}
    function ernPart(index) {
        const parts = root.topicErn.split(":")
        return index < parts.length ? parts[index] : "—"
    }

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function tagList() {
        const tags = detail("tags", {})
        return tags ? Object.keys(tags) : []
    }

    // No "get single topic" action exists server-side to re-fetch after a mutation, so apply the
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

    readonly property int messages: Number(detail("messages", 0))

    property var subscriptions: []
    property bool subscriptionsLoading: false
    property string subscriptionsError: ""

    function refreshSubscriptions() {
        if (!root.loggedIn || root.topicErn.length === 0)
            return
        subscriptionsLoading = true
        subscriptionsError = ""
        ensClient.fetchSubscriptions(root.topicErn)
    }

    onVisibleChanged: if (visible) refreshSubscriptions()
    onTopicErnChanged: if (visible) refreshSubscriptions()

    Connections {
        target: ensClient
        function onSubscriptionsLoaded(topicErn, list, total) {
            if (topicErn !== root.topicErn) return
            root.subscriptions = list
            root.subscriptionsLoading = false
            root.subscriptionsError = ""
        }
        function onSubscriptionsFailed(topicErn, message) {
            if (topicErn !== root.topicErn) return
            root.subscriptionsLoading = false
            root.subscriptionsError = message
        }
        function onSubscriptionCreated(topicErn) {
            if (topicErn !== root.topicErn) return
            addSubscriptionDialog.subscribing = false
            addSubscriptionDialog.close()
            root.refreshSubscriptions()
        }
        function onSubscriptionCreateFailed(message) {
            addSubscriptionDialog.subscribing = false
            addSubscriptionDialog.errorText = message
        }
        function onTopicTagAdded(topicErn, key, value) {
            if (topicErn !== root.topicErn) return
            addTagDialog.saving = false
            addTagDialog.close()
            root.addTagLocally(key, value)
        }
        function onTopicTagAddFailed(message) {
            addTagDialog.saving = false
            addTagDialog.errorText = message
        }
        function onTopicTagDeleted(topicErn, key) {
            if (topicErn !== root.topicErn) return
            root.removeTagLocally(key)
        }
    }

    Dialog {
        id: addSubscriptionDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool subscribing: false
        property string errorText: ""
        property var availableQueues: []

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            addSubscriptionDialog.errorText = ""
            addSubscriptionDialog.subscribing = false
            addSubscriptionDialog.availableQueues = []
            queueCombo.currentIndex = -1
            eqsClient.fetchQueues("", 0, 100)
        }

        Connections {
            target: eqsClient
            function onQueuesLoaded(list, total) {
                if (!addSubscriptionDialog.visible) return
                addSubscriptionDialog.availableQueues = list
            }
            function onQueuesFailed(message) {
                if (!addSubscriptionDialog.visible) return
                addSubscriptionDialog.errorText = message
            }
        }

        contentItem: Column {
            width: addSubscriptionDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Subscription"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Subscribe an EQS queue to receive messages published to this topic."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Queue"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: queueCombo
                    width: parent.width
                    implicitHeight: 36
                    model: addSubscriptionDialog.availableQueues
                    textRole: "name"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    visible: addSubscriptionDialog.availableQueues.length === 0
                    text: "No queues found in this namespace."
                    color: "#6b7280"
                    font.pixelSize: 12
                }
                Text {
                    text: addSubscriptionDialog.errorText
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
                    onClicked: addSubscriptionDialog.close()
                }

                BusyIndicator {
                    running: addSubscriptionDialog.subscribing
                    visible: addSubscriptionDialog.subscribing
                    width: 22
                    height: 22
                    anchors.right: subscribeButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: subscribeButton
                    text: "Subscribe"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !addSubscriptionDialog.subscribing && queueCombo.currentIndex >= 0
                             && queueCombo.currentIndex < addSubscriptionDialog.availableQueues.length
                    onClicked: {
                        addSubscriptionDialog.errorText = ""
                        addSubscriptionDialog.subscribing = true
                        const queue = addSubscriptionDialog.availableQueues[queueCombo.currentIndex]
                        ensClient.subscribe(root.topicErn, "SQS", queue.ern)
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
                    text: "Set a key/value tag on this topic."
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
                        ensClient.addTopicTag(root.topicErn, tagKeyField.text.trim(), tagValueField.text)
                    }
                }
            }
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

            Button {
                text: "‹ Back to Topics"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.topicName
                    subtitle: root.topicErn
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
                        enabled: root.messages > 0
                        onClicked: ensClient.purgeTopic(root.topicErn)
                    }

                    Button {
                        text: "View Messages"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: root.viewMessages(root.topicErn, root.topicName)
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard { title: "Messages"; value: String(root.messages); trend: "published"; trendUp: true; accent: "#4cd97b" }
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

                    DetailField { width: identityCol.width; label: "Topic ERN"; value: root.topicErn; copyable: true }
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

                        DetailField { width: (configCol.width - 48) / 3; label: "Max Message Length"; value: SizeFormat.format(root.detail("maxMessageLength", 0)) }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: subscriptionsCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: subscriptionsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: subsHeaderRow.implicitHeight

                        Row {
                            id: subsHeaderRow
                            spacing: 10
                            Text { text: "Subscriptions"; color: "white"; font.pixelSize: 15; font.bold: true }
                            BusyIndicator {
                                running: root.subscriptionsLoading
                                visible: root.subscriptionsLoading
                                width: 16; height: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Button {
                            text: "+ Add"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: subsHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: addSubscriptionDialog.open()
                        }
                    }

                    Text {
                        visible: root.subscriptionsError.length > 0
                        text: root.subscriptionsError
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Text {
                        visible: root.subscriptionsError.length === 0 && root.subscriptions.length === 0 && !root.subscriptionsLoading
                        text: "No subscriptions for this topic."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Column {
                        width: parent.width
                        spacing: 0
                        visible: root.subscriptions.length > 0

                        Row {
                            width: parent.width
                            height: 28
                            Text { width: parent.width * 0.15; text: "Protocol"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                            Text { width: parent.width * 0.55; text: "Target"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                            Text { width: parent.width * 0.3; text: "Created"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                        }

                        Repeater {
                            model: root.subscriptions
                            delegate: Row {
                                width: subscriptionsCol.width
                                height: 32
                                Text {
                                    width: parent.width * 0.15
                                    text: modelData.type
                                    color: "#c4c9d1"
                                    font.pixelSize: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    width: parent.width * 0.55
                                    text: modelData.targetErn
                                    color: "#c4c9d1"
                                    font.pixelSize: 12
                                    elide: Text.ElideMiddle
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    width: parent.width * 0.3
                                    text: DateFormat.format(modelData.created)
                                    color: "#c4c9d1"
                                    font.pixelSize: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
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
                        text: "No tags set for this topic."
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
                                            onClicked: ensClient.deleteTopicTag(root.topicErn, modelData)
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
}
