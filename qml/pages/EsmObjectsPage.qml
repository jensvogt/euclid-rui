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

    Connections {
        target: esmClient
        function onBucketsLoaded(list, total) {
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
