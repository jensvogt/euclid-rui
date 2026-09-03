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

    property string prefix: ""
    property int pageIndex: 0
    readonly property int pageSize: 10
    property string sortKey: "created"
    property bool sortAscending: true

    property var allMessages: []
    property int totalMessages: 0
    property var queueLookup: ({})
    property var pendingQueueErns: []
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    readonly property var filteredMessages: prefix.length === 0
        ? allMessages
        : allMessages.filter(function (m) { return m.messageId.toLowerCase().indexOf(prefix.toLowerCase()) === 0 })

    readonly property var sortedMessages: {
        let arr = filteredMessages.slice()
        const key = root.sortKey
        const dir = root.sortAscending ? 1 : -1
        arr.sort(function (a, b) {
            const av = key === "size" ? root.byteLength(a.body) : a[key]
            const bv = key === "size" ? root.byteLength(b.body) : b[key]
            if (av === bv) return 0
            return (av < bv ? -1 : 1) * dir
        })
        return arr
    }
    readonly property var pageRows: sortedMessages.slice(pageIndex * pageSize, (pageIndex + 1) * pageSize)

    readonly property var columns: {
        let cols = [
            { title: "Message ID", key: "messageId", fill: true },
            { title: "Content Type", key: "contentType" },
            { title: "Status", key: "status", colorFor: function (v) { return root.statusColor(v) } },
            { title: "Priority", key: "priority", colorFor: function (v) { return root.priorityColor(v) } },
            { title: "Size", key: "size", formatter: function (v) { return SizeFormat.format(v) } },
            { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
            { title: "QueueErn", key: "queueErn", hidden: true },
            { title: "MessageErn", key: "ern", hidden: true }
        ]
        return cols
    }

    signal back()
    signal openMessageDetails(string messageErn, string messageId, string queueName, var details)

    // In the single-queue view every row belongs to root.queueName; in the aggregate "all
    // queues" view rows can belong to any queue, so look the name up by the row's own queueErn.
    function queueNameFor(row) {
        if (root.queueErn.length > 0)
            return root.queueName
        return root.queueLookup[row.queueErn] || "—"
    }

    function statusColor(status) {
        if (status === "AVAILABLE") return "#4cd97b"
        if (status === "DELAYED") return "#ffb545"
        if (status === "INVISIBLE") return "#4f8cff"
        return "#9aa1ac"
    }

    function priorityColor(status) {
        if (status === "HIGH") return "#d94c4c"
        if (status === "MIDDLE") return "#ffb545"
        if (status === "LOW") return "#4f8cff"
        return "#9aa1ac"
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

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view messages."
            return
        }
        allMessages = []
        queueLookup = {}
        pendingQueueErns = []
        error = ""
        loading = true
        if (root.queueErn.length > 0)
            eqsClient.fetchMessages(root.queueErn, 0, 200)
        else
            eqsClient.fetchQueues("", 0, 100)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()
    onQueueErnChanged: if (visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Live updates are off by default: a table that reloads while it is being read
        // moves rows out from under the pointer. See AppSettings::liveListUpdates().
        running: appSettings.liveListUpdates && appSettings.autoRefreshSeconds > 0
                 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: eqsClient
        function onQueuesLoaded(list, total) {
            if (!root.loading || root.queueErn.length > 0)
                return
            if (list.length === 0) {
                root.loading = false
                root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
                return
            }
            let lookup = {}
            let erns = []
            for (let i = 0; i < list.length; i++) {
                lookup[list[i].ern] = list[i].name
                erns.push(list[i].ern)
            }
            root.queueLookup = lookup
            root.pendingQueueErns = erns
            for (let i = 0; i < list.length; i++)
                eqsClient.fetchMessages(list[i].ern, 0, 200)
            root.totalMessages = total;
        }
        function onQueuesFailed(message) {
            if (!root.loading || root.queueErn.length > 0)
                return
            root.loading = false
            root.error = message
        }
        function onMessagesLoaded(ern, list, total) {
            if (!root.loading)
                return
            root.allMessages = root.allMessages.concat(list)
            if (root.queueErn.length > 0) {
                if (ern === root.queueErn) {
                    root.loading = false
                    root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
                }
                return
            }
            root.pendingQueueErns = root.pendingQueueErns.filter(function (e) { return e !== ern })
            if (root.pendingQueueErns.length === 0) {
                root.loading = false
                root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
            }
        }
        function onMessagesFailed(ern, message) {
            if (!root.loading)
                return
            root.error = message
            if (root.queueErn.length > 0) {
                if (ern === root.queueErn)
                    root.loading = false
                return
            }
            root.pendingQueueErns = root.pendingQueueErns.filter(function (e) { return e !== ern })
            if (root.pendingQueueErns.length === 0)
                root.loading = false
        }

        function onMessagesReload() {
            refresh()
        }

        function onMessageSent(ern) {
            addMessageDialog.sending = false
            addMessageDialog.close()
        }
        function onMessageSendFailed(message) {
            addMessageDialog.sending = false
            addMessageDialog.errorText = message
        }
    }

    Dialog {
        id: addMessageDialog
        modal: true
        anchors.centerIn: parent
        width: 800
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool sending: false
        property string errorText: ""
        property var attributeRows: [{ key: "", value: "" }]
        property string selectedMessagePriority: "MIDDLE"

        function addAttributeRow() {
            let rows = attributeRows.slice()
            rows.push({ key: "", value: "" })
            attributeRows = rows
        }
        function removeAttributeRow(index) {
            let rows = attributeRows.slice()
            rows.splice(index, 1)
            if (rows.length === 0)
                rows.push({ key: "", value: "" })
            attributeRows = rows
        }
        function updateAttributeRow(index, field, value) {
            let rows = attributeRows.slice()
            rows[index] = Object.assign({}, rows[index])
            rows[index][field] = value
            attributeRows = rows
        }
        function buildAttributes() {
            let map = {}
            for (let i = 0; i < attributeRows.length; i++) {
                const k = attributeRows[i].key.trim()
                if (k.length > 0)
                    map[k] = attributeRows[i].value
            }
            return map
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            bodyField.text = ""
            errorText = ""
            sending = false
            attributeRows = [{ key: "", value: "" }]
            messagePriorityCombo.currentIndex = 1
            Qt.callLater(function () { tabBar.currentIndex = 0 })
            bodyField.forceActiveFocus()
        }

        contentItem: Column {
            id: dialogContent
            width: addMessageDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Message"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Send a new message to this queue."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Rectangle {
                width: parent.width
                height: 120
                radius: 10
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8

                    // Queue details
                    Column {
                        width: parent.width
                        spacing: 1

                        Text { text: "Queue"; color: "#6b7280"; font.pixelSize: 10 }
                        Text { text: root.queueName; color: "#c4c9d1"; font.pixelSize: 12 }
                        Text {
                            text: root.queueErn
                            color: "#6b7280"
                            font.pixelSize: 10
                            elide: Text.ElideMiddle
                            width: parent.width
                        }
                    }

                    // Added ComboBox
                    Column {
                        width: parent.width
                        spacing: 4

                        Text { text: "Message Type"; color: "#9aa1ac"; font.pixelSize: 11 }

                        ComboBox {
                            id: messagePriorityCombo
                            width: parent.width
                            implicitHeight: 36
                            model: ["HIGH", "MIDDLE", "LOW"]
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"

                            onCurrentTextChanged: {
                                addMessageDialog.selectedMessagePriority = currentText
                            }
                        }
                    }
                }
            }

            TabBar {
                id: tabBar
                width: parent.width
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"

                TabButton { text: "Body" }
                TabButton { text: "Attributes" }
            }

            Item {
                width: parent.width
                height: 180

                Column {
                    id: bodyTab
                    width: parent.width
                    visible: tabBar.currentIndex === 0
                    spacing: 6

                    Text { text: "Message body"; color: "#9aa1ac"; font.pixelSize: 12 }
                    ScrollView {
                        width: parent.width
                        height: 150
                        clip: true

                        TextArea {
                            id: bodyField
                            width: parent.width
                            placeholderText: "Enter the message body..."
                            wrapMode: TextArea.Wrap
                            Material.accent: "#4f8cff"
                            background: Rectangle {
                                radius: 6
                                color: "#20242e"
                                border.color: "#2c313c"
                                border.width: 1
                            }
                        }
                    }
                }

                Column {
                    id: attributesTab
                    width: parent.width
                    visible: tabBar.currentIndex === 1
                    spacing: 10

                    ScrollView {
                        width: parent.width
                        height: 150
                        clip: true

                        Column {
                            width: attributesTab.width
                            spacing: 8

                            Repeater {
                                model: addMessageDialog.attributeRows.length
                                delegate: Row {
                                    id: attrRow
                                    property int rowIndex: index
                                    width: attributesTab.width
                                    spacing: 8

                                    TextField {
                                        width: (parent.width - 8 - 8 - 36) / 2
                                        placeholderText: "Key"
                                        text: addMessageDialog.attributeRows[attrRow.rowIndex].key
                                        Material.accent: "#4f8cff"
                                        onTextEdited: addMessageDialog.updateAttributeRow(attrRow.rowIndex, "key", text)
                                    }
                                    TextField {
                                        width: (parent.width - 8 - 8 - 36) / 2
                                        placeholderText: "Value"
                                        text: addMessageDialog.attributeRows[attrRow.rowIndex].value
                                        Material.accent: "#4f8cff"
                                        onTextEdited: addMessageDialog.updateAttributeRow(attrRow.rowIndex, "value", text)
                                    }
                                    Button {
                                        text: "×"
                                        flat: true
                                        width: 36
                                        Material.theme: Material.Dark
                                        onClicked: addMessageDialog.removeAttributeRow(attrRow.rowIndex)
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        text: "+ Add attribute"
                        flat: true
                        Material.theme: Material.Dark
                        onClicked: addMessageDialog.addAttributeRow()
                    }
                }
            }

            Text {
                text: addMessageDialog.errorText
                color: "#ff6b6b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                width: parent.width
                visible: text.length > 0
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
                    onClicked: addMessageDialog.close()
                }

                BusyIndicator {
                    running: addMessageDialog.sending
                    visible: addMessageDialog.sending
                    width: 22
                    height: 22
                    anchors.right: sendButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: sendButton
                    text: "Send"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !addMessageDialog.sending && bodyField.text.trim().length > 0
                    onClicked: {
                        addMessageDialog.errorText = ""
                        addMessageDialog.sending = true
                        eqsClient.sendMessage(root.queueErn, bodyField.text, addMessageDialog.selectedMessagePriority,
                            addMessageDialog.buildAttributes())
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
                text: "‹ Back"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: messagesSectionHeader.implicitHeight

                SectionHeader {
                    id: messagesSectionHeader
                    title: root.queueErn.length > 0 ? "Messages · " + root.queueName + " (" + root.totalMessages + ")" : "Messages (" + root.totalMessages + ")"
                    subtitle: root.queueErn.length > 0
                        ? "Messages currently in the \"" + root.queueName + "\" queue."
                        : "Messages across all queues in the " + root.namespaceName + " namespace."
                }

                Row {
                    id: headerButtonsRow
                    anchors.right: parent.right
                    anchors.verticalCenter: messagesSectionHeader.verticalCenter
                    spacing: 8
                    visible: root.queueErn.length > 0

                    Button {
                        text: "- Purge"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        onClicked: eqsClient.purgeQueue(root.queueErn)
                    }

                    Button {
                        text: "+ Add Message"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: addMessageDialog.open()
                    }
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.pageRows
                totalCount: root.filteredMessages.length
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by message id prefix..."
                emptyText: "No messages found."
                rowsClickable: false
                sortKey: root.sortKey
                sortAscending: root.sortAscending

                onSearchChanged: (text) => {
                    root.prefix = text
                    root.pageIndex = 0
                }
                onRefreshRequested: root.refresh()
                onPageChanged: (index) => root.pageIndex = index
                onSortRequested: (key, ascending) => {
                    root.sortKey = key
                    root.sortAscending = ascending
                    root.pageIndex = 0
                }

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function(row) {
                            root.openMessageDetails(row.ern, row.messageId, root.queueNameFor(row), row)
                        }
                    },
                    {
                        text: "Delete",
                        action: function(row) {
                            eqsClient.deleteSqsMessage(row.queueErn, row.messageId)
                        }
                    }
                ]
            }
        }
    }
}
