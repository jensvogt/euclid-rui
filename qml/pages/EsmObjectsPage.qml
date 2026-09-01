import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string bucketErn: ""
    property string bucketName: ""

    // Filter text, matched as a case-insensitive substring of the whole key by the tree.
    property string prefix: ""

    property var allObjects: []
    property int totalCount: 0
    property var bucketLookup: ({})
    // {name, ern, ...} for every bucket in the namespace - what the copy dialog offers as targets.
    // A copy names its target by ERN, so a name on its own is not enough to send.
    property var bucketChoices: []
    property var pendingBucketErns: []
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    signal back()
    signal openObjectDetails(string objectErn, string objectKey, string bucketName, var details)

    // In the single-bucket view every row belongs to root.bucketName; in the aggregate "all
    // buckets" view rows can belong to any bucket, so look the name up by the row's own bucketErn.
    function bucketNameFor(row) {
        if (root.bucketErn.length > 0)
            return root.bucketName
        return root.bucketLookup[row.bucketErn] || "—"
    }

    function statusColor(status) {
        if (status === "COMPLETED") return "#4cd97b"
        if (status === "UPLOADING" || status === "UPLOADED") return "#ffb545"
        if (status === "CREATED") return "#4f8cff"
        return "#9aa1ac"
    }

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view objects."
            return
        }
        allObjects = []
        totalCount = 0
        bucketLookup = {}
        pendingBucketErns = []
        error = ""
        loading = true
        if (root.bucketErn.length > 0)
            esmClient.fetchObjects(root.bucketErn, "", 0, 200, "key", "asc", true)
        else
            esmClient.fetchBuckets("", 0, 100)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()
    onBucketErnChanged: if (visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    // Events are what actually changed something; the timer above stays as the fallback for an
    // installation without the event service.
    Connections {
        target: eventStream
        function onEventReceived(eventType, payload) {
            if (!root.visible || !root.loggedIn)
                return
            if (eventType !== "esm.object.created" && eventType !== "esm.object.updated"
                    && eventType !== "esm.object.deleted")
                return
            // Unlike the bucket list, this page shows one bucket at a time (or all of them), so an
            // object event elsewhere is not worth a re-fetch of what is on screen.
            if (root.bucketErn.length > 0 && payload.bucketErn !== root.bucketErn)
                return
            root.refresh()
        }
    }

    Connections {
        target: esmClient
        function onBucketsLoaded(list, total) {
            // Captured before the guard below: in single-bucket mode that returns early, and the
            // copy dialog needs the bucket list precisely in that mode.
            root.bucketChoices = list
            if (!root.loading || root.bucketErn.length > 0)
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
            root.bucketLookup = lookup
            root.pendingBucketErns = erns
            for (let i = 0; i < list.length; i++)
                esmClient.fetchObjects(list[i].ern, "", 0, 200, "key", "asc", true)
        }
        function onBucketsFailed(message) {
            if (!root.loading || root.bucketErn.length > 0)
                return
            root.loading = false
            root.error = message
        }
        function onObjectsLoaded(ern, list, total) {
            if (!root.loading)
                return
            root.allObjects = root.allObjects.concat(list)
            // Set before the single-bucket branch returns - it used to be assigned only on the
            // aggregate path below, so a single bucket always reported a total of 0.
            root.totalCount = root.bucketErn.length > 0 ? total : root.totalCount + total
            if (root.bucketErn.length > 0) {
                if (ern === root.bucketErn) {
                    root.loading = false
                    root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
                }
                return
            }
            root.pendingBucketErns = root.pendingBucketErns.filter(function (e) { return e !== ern })
            if (root.pendingBucketErns.length === 0) {
                root.loading = false
                root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
            }
        }
        function onObjectsFailed(ern, message) {
            if (!root.loading)
                return
            root.error = message
            if (root.bucketErn.length > 0) {
                if (ern === root.bucketErn)
                    root.loading = false
                return
            }
            root.pendingBucketErns = root.pendingBucketErns.filter(function (e) { return e !== ern })
            if (root.pendingBucketErns.length === 0)
                root.loading = false
        }

        function onObjectsReload() {
            refresh()
        }

        function onObjectUploaded(ern, key) {
            addObjectDialog.uploading = false
            addObjectDialog.close()
        }

        function onObjectRenamed(ern, key) {
            transferDialog.busy = false
            transferDialog.close()
        }
        function onObjectCopied(ern, key) {
            transferDialog.busy = false
            transferDialog.close()
        }
        function onObjectMoved(ern, key) {
            transferDialog.busy = false
            transferDialog.close()
        }
        // Reported in the dialog rather than in the page's error line: the dialog is what the user
        // is looking at, and a target key that is already taken is something to correct there and
        // try again, not a reason to close it.
        function onObjectTransferFailed(message) {
            transferDialog.busy = false
            transferDialog.errorText = message
        }
        function onObjectUploadFailed(message) {
            addObjectDialog.uploading = false
            addObjectDialog.errorText = message
        }
        function onUploadProgress(ern, key, bytesSent, bytesTotal) {
            addObjectDialog.bytesSent = bytesSent
            addObjectDialog.bytesTotal = bytesTotal
        }
    }

    function baseName(fileUrl) {
        const path = fileUrl.toString()
        const idx = path.lastIndexOf("/")
        return idx >= 0 ? path.substring(idx + 1) : path
    }

    FileDialog {
        id: fileDialog
        title: "Select a file to upload"
        onAccepted: {
            addObjectDialog.selectedFileUrl = selectedFile
            addObjectDialog.open()
        }
    }

    Dialog {
        id: addObjectDialog
        modal: true
        anchors.centerIn: parent
        width: 480
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property url selectedFileUrl: ""
        property bool uploading: false
        property string errorText: ""
        property real bytesSent: 0
        property real bytesTotal: 0

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            keyField.text = root.baseName(selectedFileUrl)
            errorText = ""
            uploading = false
            bytesSent = 0
            bytesTotal = 0
            keyField.forceActiveFocus()
        }

        contentItem: Column {
            width: addObjectDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Upload Object"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Upload the selected file to the \"" + root.bucketName + "\" bucket."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 1
                Text { text: "File"; color: "#6b7280"; font.pixelSize: 10 }
                Text {
                    text: addObjectDialog.selectedFileUrl.toString().replace("file://", "")
                    color: "#c4c9d1"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Object key"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: keyField
                    width: parent.width
                    placeholderText: "e.g. images/logo.png"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (uploadButton.enabled) uploadButton.clicked()
                }
                Text {
                    text: addObjectDialog.errorText
                    color: "#ff6b6b"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                    visible: text.length > 0
                }
            }

            Column {
                width: parent.width
                spacing: 6
                visible: addObjectDialog.uploading && addObjectDialog.bytesTotal > 0

                ProgressBar {
                    width: parent.width
                    from: 0
                    to: addObjectDialog.bytesTotal
                    value: addObjectDialog.bytesSent
                    Material.accent: "#4f8cff"
                }
                Text {
                    text: SizeFormat.format(addObjectDialog.bytesSent) + " of " + SizeFormat.format(addObjectDialog.bytesTotal)
                        + " (" + Math.round(100 * addObjectDialog.bytesSent / addObjectDialog.bytesTotal) + "%)"
                    color: "#9aa1ac"
                    font.pixelSize: 11
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
                    onClicked: addObjectDialog.close()
                }

                BusyIndicator {
                    running: addObjectDialog.uploading
                    visible: addObjectDialog.uploading
                    width: 22
                    height: 22
                    anchors.right: uploadButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: uploadButton
                    text: "Upload"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !addObjectDialog.uploading && keyField.text.trim().length > 0
                    onClicked: {
                        addObjectDialog.errorText = ""
                        addObjectDialog.uploading = true
                        esmClient.uploadObject(root.bucketErn, keyField.text.trim(), addObjectDialog.selectedFileUrl)
                    }
                }
            }
        }
    }

    // Rename and copy in one dialog: they ask for the same thing - a key the object should end up
    // under - and differ only in whether the original stays. Two dialogs would be the same fields
    // twice.
    Dialog {
        id: transferDialog
        modal: true
        anchors.centerIn: parent
        width: 480
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        // "rename", "copy" or "move".
        property string mode: "rename"
        property var object: null
        property bool busy: false
        property string errorText: ""

        readonly property bool renaming: mode === "rename"
        readonly property bool moving: mode === "move"
        // Rename is the only one that cannot leave its bucket, so it is the only one without a
        // target bucket to choose.
        readonly property bool crossesBuckets: !renaming
        readonly property string sourceKey: object ? object.key : ""
        // A key ending in "/" is a directory marker, and acting on it acts on that one zero-byte
        // object - not on everything filed under it.
        readonly property bool directoryMarker: sourceKey.length > 0 && sourceKey.charAt(sourceKey.length - 1) === "/"

        function openFor(requestedMode, object) {
            transferDialog.mode = requestedMode
            transferDialog.object = object
            // In single-bucket mode nothing has fetched the bucket list yet, and the target combo
            // needs it; harmless to refresh it either way.
            if (requestedMode !== "rename")
                esmClient.fetchBuckets("", 0, 100)
            transferDialog.open()
        }

        // The bucket the copy lands in, resolved back to the ERN the server wants. Falls back to
        // the source bucket, which is what a copy meant only to rename a key needs.
        readonly property string targetBucketErn: {
            const chosen = root.bucketChoices.find(b => b.name === targetBucketCombo.currentText)
            return chosen ? chosen.ern : (transferDialog.object ? transferDialog.object.bucketErn : "")
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            errorText = ""
            busy = false
            targetKeyField.text = transferDialog.sourceKey
            // Preselect the bucket the object is in, so a copy that only changes the key needs no
            // thought about the target - set imperatively, since a ComboBox clobbers a binding on
            // currentIndex while it populates.
            const sourceName = root.bucketNameFor(transferDialog.object || ({}))
            targetBucketCombo.currentIndex = Math.max(0, targetBucketCombo.model.indexOf(sourceName))
            targetKeyField.forceActiveFocus()
            // Selecting the file name only - the part that is usually being changed - so typing
            // replaces it without wiping the path that leads to it.
            const slash = transferDialog.sourceKey.lastIndexOf("/", transferDialog.sourceKey.length - 2)
            targetKeyField.select(slash + 1, transferDialog.sourceKey.length)
        }

        contentItem: Column {
            width: transferDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: transferDialog.renaming ? "Rename Object"
                          : transferDialog.moving ? "Move Object" : "Copy Object"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    text: transferDialog.renaming
                        ? "The object keeps its content, checksum and attributes; only the key changes."
                        : transferDialog.moving
                          ? "The object itself moves: nothing is left behind at the old key, and its ERN changes with it."
                          : "The copy gets its own bytes, so the two objects can be changed or deleted independently."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 1
                Text { text: "Current key"; color: "#6b7280"; font.pixelSize: 10 }
                Text {
                    text: transferDialog.sourceKey
                    color: "#c4c9d1"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    width: parent.width
                }
            }

            Column {
                id: targetBucketColumn
                width: parent.width
                spacing: 6
                // Renaming stays inside the bucket by definition - "rename-object" has no target
                // bucket - so this is a copy-only choice.
                visible: transferDialog.crossesBuckets

                Text { text: "Target bucket"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: targetBucketCombo
                    width: targetBucketColumn.width
                    model: root.bucketChoices.map(b => b.name)
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    text: root.bucketChoices.length === 0
                          ? "Loading buckets…"
                          : transferDialog.moving
                            ? "The object can be moved to any bucket of this account."
                            : "The copy can land in any bucket of this account."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text {
                    text: transferDialog.renaming ? "New key" : "Target key"
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
                TextField {
                    id: targetKeyField
                    width: parent.width
                    placeholderText: "e.g. reports/2026/q3.csv"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (confirmButton.enabled) confirmButton.clicked()
                }
                Text {
                    // A key is a path only by convention, so a rename can move an object between
                    // what the tree shows as folders. Worth saying, since that is not what a
                    // rename does in a file system.
                    text: "A \"/\" in the key is what makes a folder here, so this can move the object to another one."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                    visible: !transferDialog.directoryMarker
                }
                Text {
                    text: "This is a directory marker. Only the marker itself is affected - the objects filed under it keep their keys."
                    color: "#ffb545"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                    visible: transferDialog.directoryMarker
                }
                Text {
                    text: transferDialog.errorText
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
                    onClicked: transferDialog.close()
                }

                BusyIndicator {
                    running: transferDialog.busy
                    visible: transferDialog.busy
                    width: 22
                    height: 22
                    anchors.right: confirmButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: confirmButton
                    text: transferDialog.renaming ? "Rename" : transferDialog.moving ? "Move" : "Copy"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    // The server refuses a target that is already taken, and the source key is
                    // always taken - so this one case is worth catching before the round trip.
                    // The server refuses a target identical to the source - which once a bucket is
                    // in play means same bucket *and* same key, since a different bucket makes the
                    // same key a perfectly good target.
                    enabled: !transferDialog.busy
                             && targetKeyField.text.trim().length > 0
                             && (targetKeyField.text.trim() !== transferDialog.sourceKey
                                 || (transferDialog.crossesBuckets && transferDialog.object
                                     && transferDialog.targetBucketErn !== transferDialog.object.bucketErn))
                    onClicked: {
                        const target = targetKeyField.text.trim()
                        transferDialog.errorText = ""
                        transferDialog.busy = true
                        if (transferDialog.renaming)
                            esmClient.renameObject(transferDialog.object.bucketErn, transferDialog.sourceKey, target)
                        else if (transferDialog.moving)
                            esmClient.moveObject(transferDialog.object.bucketErn, transferDialog.sourceKey,
                                                 transferDialog.targetBucketErn, target)
                        else
                            esmClient.copyObject(transferDialog.object.bucketErn, transferDialog.sourceKey,
                                                 transferDialog.targetBucketErn, target)
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
                height: objectsSectionHeader.implicitHeight

                SectionHeader {
                    id: objectsSectionHeader
                    title: root.bucketErn.length > 0 ? "Objects · " + root.bucketName + " (" + root.totalCount + ")": "Objects (" + root.totalCount + ")"
                    subtitle: root.bucketErn.length > 0
                        ? "Objects currently in the \"" + root.bucketName + "\" bucket."
                        : "Objects across all buckets in the " + root.namespaceName + " namespace."
                }

                Row {
                    id: headerButtonsRow
                    anchors.right: parent.right
                    anchors.verticalCenter: objectsSectionHeader.verticalCenter
                    spacing: 8
                    visible: root.bucketErn.length > 0

                    Button {
                        text: "- Purge"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        onClicked: esmClient.purgeBucket(root.bucketErn)
                    }

                    Button {
                        text: "+ Add Object"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: fileDialog.open()
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: treeCol.implicitHeight + 32
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: treeCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 16
                    spacing: 12

                    Item {
                        width: parent.width
                        height: 36

                        TextField {
                            id: filterField
                            width: Math.min(320, parent.width - 260)
                            height: 40
                            anchors.verticalCenter: parent.verticalCenter
                            placeholderText: "Filter by any part of the key..."
                            Material.accent: "#4f8cff"
                            selectByMouse: true
                            onTextChanged: root.prefix = text
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            Text {
                                text: root.loading ? "Loading…"
                                      : root.allObjects.length + " of " + root.totalCount + " object(s) · updated " + root.lastUpdatedText
                                color: "#6b7280"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Button {
                                text: "Expand all"
                                flat: true
                                Material.theme: Material.Dark
                                onClicked: objectTree.expandAll()
                            }
                            Button {
                                text: "Collapse all"
                                flat: true
                                Material.theme: Material.Dark
                                onClicked: objectTree.collapseAll()
                            }
                            Button {
                                text: "⟳"
                                flat: true
                                font.pixelSize: 16
                                implicitWidth: 32
                                Material.theme: Material.Dark
                                onClicked: root.refresh()
                            }
                        }
                    }

                    Text {
                        visible: root.error.length > 0
                        width: parent.width
                        text: root.error
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: !root.loading && root.error.length === 0 && objectTree.visibleRows.length === 0
                        text: root.prefix.length > 0 ? "No objects match \"" + root.prefix + "\"." : "No objects found."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    ObjectTree {
                        id: objectTree
                        width: parent.width
                        objects: root.allObjects
                        filter: root.prefix
                        onOpenObject: (object) => root.openObjectDetails(object.ern, object.key, root.bucketNameFor(object), object)
                        onDeleteObject: (object) => esmClient.deleteObject(object.bucketErn, object.ern)
                        onRenameObject: (object) => transferDialog.openFor("rename", object)
                        onCopyObject: (object) => transferDialog.openFor("copy", object)
                        onMoveObject: (object) => transferDialog.openFor("move", object)
                    }

                    // The listing is capped at 200 objects per bucket; without saying so, a
                    // truncated tree looks like a complete one.
                    Text {
                        visible: root.totalCount > root.allObjects.length
                        width: parent.width
                        text: "Showing the first " + root.allObjects.length + " of " + root.totalCount
                              + " objects - narrow the filter to reach the rest."
                        color: "#ffb545"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }
    }
}
