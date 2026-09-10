import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    property string prefix: ""
    property int pageIndex: 0
    property int pageSize: 10
    property string sortColumn: "messages"
    property bool sortAscending: false

    property var topics: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    // What the last Stop or Start did. Kept next to the table because nothing in the table itself
    // changes: a topic's rows say how many messages it holds, and stopping delivery does not move
    // one - it only stops them being fanned out.
    property string actionNote: ""

    readonly property var columns: {
        let cols = [
            { title: "Name", key: "name", fill: true },
            { title: "Messages", key: "messages" },
            { title: "Size", key: "size", formatter: function (v) { return SizeFormat.format(v) } },
            {
                // A stopped topic is invisible in every other column: it goes on accepting
                // publishes and its message count goes on climbing, the messages just sit there
                // held instead of being fanned out.
                title: "State",
                key: "status",
                formatter: function (v) { return root.isStopped({ status: v }) ? "STOPPED" : "RUNNING" },
                colorFor: function (v) { return root.isStopped({ status: v }) ? "#ffb545" : "#4cd97b" }
            },
            { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Ern", key: "ern", hidden: true }
        ]
        return cols
    }

    signal back()
    signal openTopic(string topicErn, string topicName)
    signal openTopicDetails(string topicErn, string topicName, var details)

    // A topic that is holding what is published to it instead of delivering it. Anything that is not
    // "STOPPED" reads as running, including a listing from a server old enough not to send the field
    // at all - which is the safe way round: it offers "Stop delivery", which the server can answer,
    // rather than "Start" on a topic that was never stopped.
    function isStopped(row) {
        return !!row && String(row.status) === "STOPPED"
    }

    // The topic's name if it is on this page, and the tail of the ERN otherwise - which is the name
    // anyway, since that is what an ERN ends with.
    function topicNameForErn(ern) {
        const row = root.topics.find(t => t.ern === ern)
        if (row) return row.name
        const parts = String(ern).split(":")
        return parts.length > 0 ? parts[parts.length - 1] : ern
    }

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view topics."
            return
        }
        loading = true
        error = ""
        ensClient.fetchTopics(root.prefix, root.pageIndex, root.pageSize,
            root.sortColumn, root.sortAscending ? "asc" : "desc")
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

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
            root.loading = false
            root.error = ""
            root.topics = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onTopicsFailed(message) {
            root.loading = false
            root.error = message
        }

        function onTopicsReload() {
            refresh()
        }

        function onTopicCreated(name) {
            createTopicDialog.creating = false
            createTopicDialog.close()
        }
        function onTopicCreateFailed(message) {
            createTopicDialog.creating = false
            createTopicDialog.errorText = message
        }
        function onTopicDeliveryChanged(topicErn, status, released) {
            const name = root.topicNameForErn(topicErn)
            if (status === "STOPPED") {
                root.actionNote = "Delivery stopped for '" + name + "'. Publishing still works - each message is "
                                  + "held until the topic is started again, and nothing already delivered comes back."
                return
            }
            root.actionNote = released > 0
                ? "Delivery started for '" + name + "': " + released + " held message(s) went out to its "
                  + "subscriptions, oldest first."
                : "Delivery started for '" + name + "'. Nothing was held, so nothing went out."
        }
        function onTopicDeliveryFailed(message) {
            root.error = message
        }
    }

    Dialog {
        id: createTopicDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool creating: false
        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            nameField.text = ""
            createTopicDialog.errorText = ""
            createTopicDialog.creating = false
            nameField.forceActiveFocus()
        }

        contentItem: Column {
            width: createTopicDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Topic"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Enter a name for the new topic."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Topic name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: nameField
                    width: parent.width
                    placeholderText: "e.g. order-events"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createButton.enabled) createButton.clicked()
                }
                Text {
                    text: createTopicDialog.errorText
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
                    onClicked: createTopicDialog.close()
                }

                BusyIndicator {
                    running: createTopicDialog.creating
                    visible: createTopicDialog.creating
                    width: 22
                    height: 22
                    anchors.right: createButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: createButton
                    text: "Create"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !createTopicDialog.creating && nameField.text.trim().length > 0
                    onClicked: {
                        createTopicDialog.errorText = ""
                        createTopicDialog.creating = true
                        ensClient.createTopic(nameField.text.trim())
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
                text: "‹ Back to ENS Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Topics"
                    subtitle: "All topics in the " + root.namespaceName + " namespace."
                }

                Button {
                    text: "+ Add Topic"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createTopicDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.topics
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by topic name prefix..."
                emptyText: "No topics found in this namespace."
                rowsClickable: true
                sortKey: root.sortColumn
                sortAscending: root.sortAscending

                onSearchChanged: (text) => {
                    root.prefix = text
                    root.pageIndex = 0
                    root.refresh()
                }
                onRefreshRequested: root.refresh()
                onPageChanged: (index) => {
                    root.pageIndex = index
                    root.refresh()
                }
                // Back to the first page: page four of fifty-row pages is not page four of
                // ten-row pages, and the query has to be made again at the new size anyway.
                onPageSizeRequested: (size) => {
                    root.pageSize = size
                    root.pageIndex = 0
                    root.refresh()
                }
                onRowClicked: (row) => root.openTopic(row.ern, row.name)
                onSortRequested: (key, ascending) => {
                    root.sortColumn = key
                    root.sortAscending = ascending
                    root.pageIndex = 0
                    root.refresh()
                }

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function(row) {
                            root.openTopicDetails(row.ern, row.name, row)
                        }
                    },
                    {
                        text: "Purge",
                        enabled: function(row) {
                            return !!row && Number(row.messages) > 0
                        },
                        action: function(row) {
                            ensClient.purgeTopic(row.ern)
                        }
                    },
                    {
                        // Two entries rather than one that changes its meaning with the row under
                        // the cursor: each is greyed out when the topic is already in that state,
                        // which also says which state it is in before anything is clicked.
                        text: "Stop delivery",
                        enabled: function(row) { return !root.isStopped(row) },
                        action: function(row) {
                            root.actionNote = ""
                            ensClient.stopTopic(row.ern)
                        }
                    },
                    {
                        text: "Start delivery",
                        enabled: function(row) { return root.isStopped(row) },
                        action: function(row) {
                            root.actionNote = ""
                            ensClient.startTopic(row.ern)
                        }
                    },
                    {
                        text: "Delete",
                        action: function(row) {
                            ensClient.deleteTopic(row.ern)
                        }
                    }
                ]
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#4cd97b"
                font.pixelSize: 12
                visible: root.actionNote.length > 0
                text: root.actionNote
            }
        }
    }
}
