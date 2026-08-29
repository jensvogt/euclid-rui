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
    property string sortColumn: "objects"
    property bool sortAscending: false

    property var buckets: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    readonly property var columns: {
        let cols = [
            { title: "Name", key: "name", fill: true },
            { title: "Objects", key: "objects" },
            { title: "Size", key: "size", formatter: function (v) { return SizeFormat.format(v) } },
            { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Ern", key: "ern", hidden: true }
        ]
        return cols
    }

    signal back()
    signal openBucket(string bucketErn, string bucketName)
    signal openBucketDetails(string bucketErn, string bucketName, var details)

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view buckets."
            return
        }
        loading = true
        error = ""
        esmClient.fetchBuckets(root.prefix, root.pageIndex, root.pageSize,
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
        target: esmClient
        function onBucketsLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.buckets = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onBucketsFailed(message) {
            root.loading = false
            root.error = message
        }

        function onBucketsReload() {
            refresh()
        }

        function onBucketCreated(name) {
            createBucketDialog.creating = false
            createBucketDialog.close()
        }
        function onBucketCreateFailed(message) {
            createBucketDialog.creating = false
            createBucketDialog.errorText = message
        }
    }

    Dialog {
        id: createBucketDialog
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
            createBucketDialog.errorText = ""
            createBucketDialog.creating = false
            nameField.forceActiveFocus()
        }

        contentItem: Column {
            width: createBucketDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Bucket"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Enter a name for the new bucket."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Bucket name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: nameField
                    width: parent.width
                    placeholderText: "e.g. orders-in"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createButton.enabled) createButton.clicked()
                }
                Text {
                    text: createBucketDialog.errorText
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
                    onClicked: createBucketDialog.close()
                }

                BusyIndicator {
                    running: createBucketDialog.creating
                    visible: createBucketDialog.creating
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
                    enabled: !createBucketDialog.creating && nameField.text.trim().length > 0
                    onClicked: {
                        createBucketDialog.errorText = ""
                        createBucketDialog.creating = true
                        esmClient.createBucket(nameField.text.trim())
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
                text: "‹ Back to ESM Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Buckets"
                    subtitle: "All buckets in the " + root.namespaceName + " namespace."
                }

                Button {
                    text: "+ Add Bucket"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createBucketDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.buckets
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by bucket name prefix..."
                emptyText: "No buckets found in this namespace."
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
                onRowClicked: (row) => root.openBucket(row.ern, row.name)
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
                            root.openBucketDetails(row.ern, row.name, row)
                        }
                    },
                    {
                        text: "Purge",
                        enabled: function(row) {
                            return !!row && Number(row.objects) > 0
                        },
                        action: function(row) {
                            esmClient.purgeBucket(row.ern)
                        }
                    },
                    {
                        text: "Delete",
                        action: function(row) {
                            esmClient.deleteBucket(row.ern)
                        }
                    }
                ]
            }
        }
    }
}
