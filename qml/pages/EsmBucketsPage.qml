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
    property string sortColumn: "objects"
    property bool sortAscending: false

    // euclid's own buckets - the one applications are deployed from and the like - are left out of
    // list-buckets for everyone. An administrator can ask for them, because for them the
    // installation itself is the subject; the switch is not even shown to anyone else, and the
    // server would ignore the request anyway.
    readonly property bool isAdmin: euclidClient.isAdmin
    property bool showInternal: false

    property var buckets: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"
    // What the last purge or touch did. Kept next to the table because neither is visible in it
    // when the answer arrives: a background purge is still running, and a touch never shows up at
    // all - it changes nothing a listing displays.
    property string actionNote: ""

    readonly property var columns: {
        let cols = [
            // Internal buckets are only ever in this list when an administrator asked for them,
            // and then they are marked: without it euclid's own plumbing sits among the user's
            // buckets looking like something somebody created.
            {
                title: "Name",
                key: "name",
                fill: true,
                formatter: function (v, row) { return row && row.internal ? v + "  (internal)" : String(v) },
                colorFor: function (v, row) { return row && row.internal ? "#9aa1ac" : "#c4c9d1" }
            },
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
        esmClient.fetchBuckets(root.prefix, root.pageIndex, root.pageSize, root.sortColumn,
            root.sortAscending ? "asc" : "desc", root.isAdmin && root.showInternal)
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

        // Both of these answer for whoever started them, and the object list can start a touch
        // too - so a note is only taken while this page is the one on screen. Otherwise a touch
        // done from the object tree would leave a message here to be found on the next visit,
        // describing something that happened somewhere else.
        function onBucketPurged(bucketErn, async, objects) {
            if (!root.visible) return
            root.actionNote = async
                    ? "Purging " + objects + " object(s) in the background. The bucket's counts fall as it works through them."
                    : "Purged " + objects + " object(s)."
        }

        function onObjectsTouched(bucketErn, prefix, async, objects) {
            if (!root.visible) return
            // Said out loud because a touch leaves no trace on this page: the objects, their
            // timestamps and the bucket's counts are all exactly as they were, so without this
            // nothing would tell an operator whether anything happened.
            root.actionNote = async
                    ? "Announcing " + objects + " object(s) in the background. Subscribers receive them over the "
                      + "next few minutes; nothing in this table changes."
                    : "Announced " + objects + " object(s). Nothing about them was modified."
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

    // Always asked, unlike the purge dialog, which only appears once a bucket is big enough to be
    // worth doing in the background. Size is not what makes a touch worth a second thought: it is
    // a replay, so every subscriber of the bucket hears about every object again, including the
    // ones it already processed. A consumer that is not idempotent does its work twice, and on a
    // whole bucket it does it twice for everything - which is true of three objects as much as of
    // thirty thousand.
    Dialog {
        id: touchDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property var bucket: null
        readonly property string bucketName: bucket ? String(bucket.name) : ""
        readonly property int objectCount: bucket ? Number(bucket.objects) : 0
        // The same threshold the purge dialog uses, for the same reason: announcing them inline
        // outlasts the request's own timeout long before the announcing itself finishes.
        readonly property bool large: touchDialog.objectCount > root.asyncPurgeThreshold

        function openFor(row) {
            touchDialog.bucket = row
            touchDialog.open()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: touchDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Touch All Objects"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: touchDialog.bucketName + "  ·  " + touchDialog.objectCount + " objects"
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#c4c9d1"
                font.pixelSize: 12
                text: "Every object in this bucket is announced again, as though it had just been uploaded: the "
                      + "same event and the same subscription deliveries an upload would have produced. Nothing "
                      + "about the objects changes - not a byte of them, and not their timestamps."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#e0a458"
                font.pixelSize: 12
                text: "⚠  This is a replay, not a repair of one. Every subscriber hears about all "
                      + touchDialog.objectCount + " object(s), including the ones it already processed - so run it "
                      + "only where the consumers are idempotent. Touching a narrower prefix from the object list "
                      + "is usually safer than touching the whole bucket."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: touchDialog.large
                      ? "Announcing in the background hands the work to the server and answers straight away. "
                        + "Waiting for it keeps this window on the request until every object has been announced, "
                        + "which for a bucket this size can outlast the request's own timeout. Neither is "
                        + "resumable: a run that is interrupted has simply announced fewer objects."
                      : "Announcing in the background hands the work to the server and answers straight away; "
                        + "waiting for it keeps this window on the request until it is done. For a bucket this "
                        + "size either finishes quickly. Neither is resumable: a run that is interrupted has "
                        + "simply announced fewer objects."
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
                    onClicked: touchDialog.close()
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Button {
                        text: "Wait for it"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: {
                            root.actionNote = ""
                            // Whole bucket: no prefix. Narrowing one is what the object list is
                            // for, where there is a key in front of you to narrow it to.
                            esmClient.touchObjects(touchDialog.bucket.ern, "", false)
                            touchDialog.close()
                        }
                    }
                    Button {
                        text: "Announce in background"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: {
                            root.actionNote = ""
                            esmClient.touchObjects(touchDialog.bucket.ern, "", true)
                            touchDialog.close()
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

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 16

                    Row {
                        spacing: 8
                        visible: root.isAdmin
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: "Internal buckets"
                            color: "#9aa1ac"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        ToggleSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.showInternal
                            // Back to the first page: the listing is a different one now, and page
                            // three of the old one is not page three of the new one.
                            onToggled: (checked) => {
                                root.showInternal = checked
                                root.pageIndex = 0
                                root.refresh()
                            }
                        }
                    }

                    Button {
                        text: "+ Add Bucket"
                        highlighted: true
                        anchors.verticalCenter: parent.verticalCenter
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: createBucketDialog.open()
                    }
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
                // Back to the first page: page four of fifty-row pages is not page four of
                // ten-row pages, and the query has to be made again at the new size anyway.
                onPageSizeRequested: (size) => {
                    root.pageSize = size
                    root.pageIndex = 0
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
                        text: "Touch all…",
                        // Nothing to announce in an empty bucket, and the answer would be "0
                        // objects" - which reads like a failure rather than like an empty bucket.
                        enabled: function(row) {
                            return !!row && Number(row.objects) > 0
                        },
                        action: function(row) {
                            touchDialog.openFor(row)
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

            // What the last purge or touch did. Neither is visible in the table above when the
            // answer arrives - a background purge is still running, and a touch changes nothing a
            // listing shows at all - so this is the only thing that says anything happened.
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
