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
    readonly property int pageSize: 10
    property string sortColumn: "available"
    property bool sortAscending: false

    property var queues: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    readonly property var columns: {
        let cols = [
            { title: "Name", key: "name", fill: true },
            { title: "Available", key: "available" },
            { title: "Delayed", key: "delayed" },
            { title: "Invisible", key: "invisible" },
            { title: "Size", key: "size", formatter: function (v) { return v + " B" } },
            { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Ern", key: "ern", hidden: true }
        ]
        return cols
    }

    signal back()
    signal openQueue(string queueErn, string queueName)
    signal openQueueDetails(string queueErn, string queueName, var details)

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view queues."
            return
        }
        loading = true
        error = ""
        eqsClient.fetchQueues(root.prefix, root.pageIndex, root.pageSize,
            root.sortColumn, root.sortAscending ? "asc" : "desc")
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: eqsClient
        function onQueuesLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.queues = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onQueuesFailed(message) {
            root.loading = false
            root.error = message
        }

        function onQueuesReload() {
            refresh()
        }

        function onQueueCreated(name) {
            createQueueDialog.creating = false
            createQueueDialog.close()
        }
        function onQueueCreateFailed(message) {
            createQueueDialog.creating = false
            createQueueDialog.errorText = message
        }
    }

    Dialog {
        id: createQueueDialog
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
            createQueueDialog.errorText = ""
            createQueueDialog.creating = false
            nameField.forceActiveFocus()
        }

        contentItem: Column {
            width: createQueueDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Queue"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Enter a name for the new queue."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Queue name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: nameField
                    width: parent.width
                    placeholderText: "e.g. orders-in"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createButton.enabled) createButton.clicked()
                }
                Text {
                    text: createQueueDialog.errorText
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
                    onClicked: createQueueDialog.close()
                }

                BusyIndicator {
                    running: createQueueDialog.creating
                    visible: createQueueDialog.creating
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
                    enabled: !createQueueDialog.creating && nameField.text.trim().length > 0
                    onClicked: {
                        createQueueDialog.errorText = ""
                        createQueueDialog.creating = true
                        eqsClient.createQueue(nameField.text.trim())
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
                text: "‹ Back to EQS Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Queues"
                    subtitle: "All queues in the " + root.namespaceName + " namespace."
                }

                Button {
                    text: "+ Add Queue"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createQueueDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.queues
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by queue name prefix..."
                emptyText: "No queues found in this namespace."
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
                onRowClicked: (row) => root.openQueue(row.ern, row.name)
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
                            root.openQueueDetails(row.ern, row.name, row)
                        }
                    },
                    {
                        text: "Purge",
                        enabled: function(row) {
                            return !!row && Number(row.available) > 0
                        },
                        action: function(row) {
                            eqsClient.purgeQueue(row.ern)
                        }
                    },
                    {
                        text: "Delete",
                        action: function(row) {
                            eqsClient.deleteQueue(row.ern)
                        }
                    }
                ]
            }
        }
    }
}
