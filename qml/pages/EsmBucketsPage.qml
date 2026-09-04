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
    // What the last purge did. Kept next to the table because a background purge is still running
    // when the answer arrives, and nothing else on screen would say so.
    property string purgeNote: ""

    readonly property var columns: {
        let cols = [
            { title: "Name", key: "name", fill: true },
            { title: "Objects", key: "objects" },
            { title: "Size", key: "size", formatter: function (v) { return SizeFormat.format(v) } },
            // Says what happens to the next object written, not that everything in the bucket is
            // encrypted - a bucket holds objects written under whatever setting was in force at the
            // time. Not sortable: the server derives "encrypted" from the bucket's key ERN, so
            // there is no stored field behind it to sort on.
            {
                title: "Encrypted",
                key: "encrypted",
                sortable: false,
                formatter: function (v) { return v ? "Yes" : "No" },
                colorFor: function (v) { return v ? "#4cd97b" : "#6b7280" }
            },
            { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Ern", key: "ern", hidden: true }
        ]
        return cols
    }

    // Above this many objects a purge is handed to the server's background worker instead of being
    // waited for. A synchronous purge deletes them one request at a time and a bucket of any real
    // size outlives the request's transfer timeout, which leaves the caller with an error and the
    // server still deleting - the worst of both.
    readonly property int asyncPurgeThreshold: 1000

    // Purges outright when there is little to do, and asks first when there is not.
    function purge(row) {
        if (Number(row.objects) > root.asyncPurgeThreshold) {
            purgeDialog.openFor(row)
            return
        }
        esmClient.purgeBucket(row.ern, false)
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
        esmClient.fetchBuckets(root.prefix, root.pageIndex, root.pageSize, root.sortColumn, root.sortAscending ? "asc" : "desc")
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

        function onBucketPurged(bucketErn, async, objects) {
            root.purgeNote = async
                    ? "Purging " + objects + " object(s) in the background. The bucket's counts fall as it works through them."
                    : "Purged " + objects + " object(s)."
        }

        function onBucketCreated(name) {
            createBucketDialog.creating = false
            createBucketDialog.close()
        }
        function onBucketCreateFailed(message) {
            createBucketDialog.creating = false
            createBucketDialog.errorText = message
        }
        function onBucketRenamed(name, ern, objects, subscriptions) {
            renameBucketDialog.renaming = false
            renameBucketDialog.close()
        }
        function onBucketRenameFailed(message) {
            renameBucketDialog.renaming = false
            renameBucketDialog.errorText = message
        }
    }

    // Asked rather than assumed: a background purge answers immediately and keeps deleting, so the
    // bucket is not empty when the dialog closes and anything watching it will see the count fall
    // over the following minutes. That is worth saying before starting one.
    Dialog {
        id: purgeDialog
        modal: true
        anchors.centerIn: parent
        width: 440
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property var bucket: null
        readonly property string bucketName: bucket ? String(bucket.name) : ""
        readonly property int objectCount: bucket ? Number(bucket.objects) : 0

        function openFor(row) {
            purgeDialog.bucket = row
            purgeDialog.open()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: purgeDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Purge Bucket"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: purgeDialog.bucketName + "  ·  " + purgeDialog.objectCount + " objects"
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#e0a458"
                font.pixelSize: 12
                text: "⚠  Every object in this bucket is deleted, and there is no undo. Objects are removed one at "
                      + "a time, so " + purgeDialog.objectCount + " of them take a while."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "Deleting in the background hands the work to the server and answers straight away: the bucket "
                      + "is not empty when this dialog closes, and its counts fall over the following refreshes. "
                      + "Waiting for it keeps this window on the request until every object is gone, which for a "
                      + "bucket this size can outlast the request's own timeout."
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
                    onClicked: purgeDialog.close()
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Button {
                        text: "Wait for it"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        onClicked: {
                            esmClient.purgeBucket(purgeDialog.bucket.ern, false)
                            purgeDialog.close()
                        }
                    }
                    Button {
                        text: "Delete in background"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: {
                            esmClient.purgeBucket(purgeDialog.bucket.ern, true)
                            purgeDialog.close()
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: renameBucketDialog
        modal: true
        anchors.centerIn: parent
        width: 400
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property var bucket: null
        property bool renaming: false
        property string errorText: ""

        readonly property string currentName: bucket ? bucket.name : ""
        readonly property int objectCount: bucket ? Number(bucket.objects) : 0

        function openFor(bucket) {
            renameBucketDialog.bucket = bucket
            renameBucketDialog.open()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            errorText = ""
            renaming = false
            newBucketNameField.text = renameBucketDialog.currentName
            newBucketNameField.selectAll()
            newBucketNameField.forceActiveFocus()
        }

        contentItem: Column {
            width: renameBucketDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Rename Bucket"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    // Not a cosmetic change: the name is part of the bucket's ERN and of every
                    // object ERN under it, so everything holding one has to be rewritten.
                    text: renameBucketDialog.objectCount > 0
                          ? "The bucket's ERN changes, and so does the ERN of each of its "
                            + renameBucketDialog.objectCount + " object(s). Subscriptions follow automatically."
                          : "The bucket's ERN changes with its name. Subscriptions follow automatically."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 1
                Text { text: "Current name"; color: "#6b7280"; font.pixelSize: 10 }
                Text {
                    text: renameBucketDialog.currentName
                    color: "#c4c9d1"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "New name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: newBucketNameField
                    width: parent.width
                    placeholderText: "e.g. reports-2026"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (renameBucketButton.enabled) renameBucketButton.clicked()
                }
                Text {
                    // Worth saying before the round trip: this is the one refusal an operator can
                    // do nothing about from here.
                    text: "A bucket served by a transfer server cannot be renamed while that server runs."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Text {
                    text: renameBucketDialog.errorText
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
                    onClicked: renameBucketDialog.close()
                }

                BusyIndicator {
                    running: renameBucketDialog.renaming
                    visible: renameBucketDialog.renaming
                    width: 22
                    height: 22
                    anchors.right: renameBucketButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: renameBucketButton
                    text: "Rename"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    // The server refuses the current name outright, so it is caught here.
                    enabled: !renameBucketDialog.renaming
                             && newBucketNameField.text.trim().length > 0
                             && newBucketNameField.text.trim() !== renameBucketDialog.currentName
                    onClicked: {
                        renameBucketDialog.errorText = ""
                        renameBucketDialog.renaming = true
                        esmClient.renameBucket(renameBucketDialog.bucket.ern, newBucketNameField.text.trim())
                    }
                }
            }
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
                    title: "Buckets (" + totalCount + ")"
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
                id: bucketTable
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
                        text: "Rename…",
                        action: function(row) {
                            renameBucketDialog.openFor(row)
                        }
                    },
                    {
                        text: "Purge",
                        enabled: function(row) {
                            return !!row && Number(row.objects) > 0
                        },
                        action: function(row) {
                            root.purge(row)
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
