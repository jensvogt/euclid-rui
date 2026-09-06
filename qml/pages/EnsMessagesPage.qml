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

    property string prefix: ""
    property int pageIndex: 0
    property int pageSize: 10
    property string sortKey: "created"
    property bool sortAscending: false

    property var allMessages: []
    // What the server says the topic holds, which is not what was fetched - see totalCount on the
    // table below.
    property int totalMessages: 0
    // How much of each topic the merged view takes. It has to bound it somehow: every topic is
    // fetched in full before anything can be sorted across them.
    readonly property int mergedFetchLimit: 200
    property var topicLookup: ({})
    property var pendingTopicErns: []
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    // One topic is paged by the server: the page on screen is the page that was asked for. The
    // "all topics" view cannot be - it merges one list per topic, and no single query spans them -
    // so there the window still fetches a bounded block per topic and slices it itself.
    readonly property bool singleTopic: root.topicErn.length > 0

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
    // Already one page's worth when the server did the paging, so it is only sliced in the merged
    // view. The prefix filter still applies either way, and in the paged view it can only match
    // what this page holds - "list-messages" takes no prefix, so there is nothing to ask for.
    readonly property var pageRows: root.singleTopic
        ? root.filteredMessages
        : root.sortedMessages.slice(pageIndex * pageSize, (pageIndex + 1) * pageSize)

    readonly property var columns: {
        let cols = [
            { title: "Message ID", key: "messageId", fill: true },
            { title: "Content Type", key: "contentType" },
            { title: "Status", key: "status", formatter: function (v) { return v && v.length > 0 ? v : "—" }, colorFor: function (v) { return root.statusColor(v) } },
            { title: "Size", key: "size", formatter: function (v, row) { return SizeFormat.format(root.byteLength(row.body)) } },
            { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Modified", key: "modified", formatter: function (v) { return v && v.indexOf("1970-01-01") === 0 ? "—" : DateFormat.format(v) } },
            { title: "TopicErn", key: "topicErn", hidden: true },
            { title: "MessageErn", key: "ern", hidden: true }
        ]
        return cols
    }

    signal back()
    signal openMessageDetails(string messageErn, string messageId, string topicName, var details)

    function statusColor(status) {
        if (status === "PUBLISHED") return "#4cd97b"
        return "#9aa1ac"
    }

    // In the single-topic view every row belongs to root.topicName; in the aggregate "all
    // topics" view rows can belong to any topic, so look the name up by the row's own topicErn.
    function topicNameFor(row) {
        if (root.topicErn.length > 0)
            return root.topicName
        return root.topicLookup[row.topicErn] || "—"
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
        totalMessages = 0
        topicLookup = {}
        pendingTopicErns = []
        error = ""
        loading = true
        if (root.singleTopic)
            ensClient.fetchMessages(root.topicErn, root.pageIndex, root.pageSize,
                                    root.sortKey, root.sortAscending ? "asc" : "desc")
        else
            ensClient.fetchTopics("", 0, 100)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()
    // Page one of the topic just opened, not whatever page the previous view was on.
    onTopicErnChanged: {
        root.pageIndex = 0
        if (visible) refresh()
    }

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
        target: ensClient
        function onTopicsLoaded(list, total) {
            if (!root.loading || root.topicErn.length > 0)
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
            root.topicLookup = lookup
            root.pendingTopicErns = erns
            for (let i = 0; i < list.length; i++)
                ensClient.fetchMessages(list[i].ern, 0, root.mergedFetchLimit)
        }
        function onTopicsFailed(message) {
            if (!root.loading || root.topicErn.length > 0)
                return
            root.loading = false
            root.error = message
        }
        function onMessagesLoaded(ern, list, total) {
            if (!root.loading)
                return
            root.allMessages = root.allMessages.concat(list)
            // The topic's own count, summed across topics in the merged view.
            root.totalMessages += total
            if (root.topicErn.length > 0) {
                if (ern === root.topicErn) {
                    root.loading = false
                    root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
                }
                return
            }
            root.pendingTopicErns = root.pendingTopicErns.filter(function (e) { return e !== ern })
            if (root.pendingTopicErns.length === 0) {
                root.loading = false
                root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
            }
        }
        function onMessagesFailed(ern, message) {
            if (!root.loading)
                return
            root.error = message
            if (root.topicErn.length > 0) {
                if (ern === root.topicErn)
                    root.loading = false
                return
            }
            root.pendingTopicErns = root.pendingTopicErns.filter(function (e) { return e !== ern })
            if (root.pendingTopicErns.length === 0)
                root.loading = false
        }

        function onMessagesReload() {
            refresh()
        }

        function onMessagePublished(ern) {
            addMessageDialog.sending = false
            addMessageDialog.close()
        }
        function onMessagePublishFailed(message) {
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
                Text { text: "Publish Message"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Publish a new message to this topic."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Rectangle {
                width: parent.width
                height: 68
                radius: 10
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 1

                    Text { text: "Topic"; color: "#6b7280"; font.pixelSize: 10 }
                    Text { text: root.topicName; color: "#c4c9d1"; font.pixelSize: 12 }
                    Text {
                        text: root.topicErn
                        color: "#6b7280"
                        font.pixelSize: 10
                        elide: Text.ElideMiddle
                        width: parent.width
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
                    text: "Publish"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !addMessageDialog.sending && bodyField.text.trim().length > 0
                    onClicked: {
                        addMessageDialog.errorText = ""
                        addMessageDialog.sending = true
                        ensClient.publishMessage(root.topicErn, bodyField.text, addMessageDialog.buildAttributes())
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
                    title: root.topicErn.length > 0 ? "Messages · " + root.topicName : "Messages"
                    subtitle: root.topicErn.length > 0
                        ? "Messages published to the \"" + root.topicName + "\" topic."
                        : "Messages across all topics in the " + root.namespaceName + " namespace."
                }

                Row {
                    id: headerButtonsRow
                    anchors.right: parent.right
                    anchors.verticalCenter: messagesSectionHeader.verticalCenter
                    spacing: 8
                    visible: root.topicErn.length > 0

                    Button {
                        text: "- Purge"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        onClicked: ensClient.purgeTopic(root.topicErn)
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
                // What there is to page through: the server's count of the topic when it is doing
                // the paging, and what was actually merged when this window is.
                totalCount: root.singleTopic ? root.totalMessages : root.filteredMessages.length
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: root.singleTopic ? "Filter this page by message id prefix..."
                                                    : "Filter by message id prefix..."
                emptyText: "No messages found."
                rowsClickable: false
                sortKey: root.sortKey
                sortAscending: root.sortAscending

                onSearchChanged: (text) => {
                    root.prefix = text
                    root.pageIndex = 0
                }
                onRefreshRequested: root.refresh()
                // Each of these re-queries when the server is doing the paging, and only moves the
                // window when this page is.
                onPageChanged: (index) => {
                    root.pageIndex = index
                    if (root.singleTopic) root.refresh()
                }
                onPageSizeRequested: (size) => {
                    root.pageSize = size
                    root.pageIndex = 0
                    if (root.singleTopic) root.refresh()
                }
                onSortRequested: (key, ascending) => {
                    root.sortKey = key
                    root.sortAscending = ascending
                    root.pageIndex = 0
                    if (root.singleTopic) root.refresh()
                }

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function(row) {
                            root.openMessageDetails(row.ern, row.messageId, root.topicNameFor(row), row)
                        }
                    }
                ]
            }
        }
    }
}
