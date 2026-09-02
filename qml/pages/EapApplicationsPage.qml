import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import "../components"

// EAP applications: artifacts out of an ESM bucket that euclid-mgr runs as processes. Every row
// shows what is running (`state`, `instances`) next to what was asked for (`desiredState`) - start
// and stop only write the latter, and the reconciler is what makes them agree.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    property string prefix: ""
    property var applications: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    function stateColor(state) {
        if (state === "RUNNING") return "#4cd97b"
        if (state === "STOPPED") return "#ffb545"
        return "#9aa1ac"
    }

    readonly property var columns: [
        { title: "Application ID", key: "applicationId", fill: true },
        { title: "Runtime", key: "runtime" },
        { title: "Artifact", key: "artifactKey" },
        { title: "Version", key: "version" },
        { title: "Runs as", key: "userId" },
        { title: "State", key: "state", colorFor: function (v) { return root.stateColor(v) } },
        { title: "Desired", key: "desiredState", colorFor: function (v) { return root.stateColor(v) } },
        { title: "Instances", key: "instances" },
        { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Ern", key: "ern", hidden: true }
    ]

    signal back()
    signal openApplicationDetails(string applicationId, var details)

    // {name, ern, ...} for every bucket in the namespace. EAP names the bucket by *name* when
    // creating an application, but an upload needs its ERN, so both are kept.
    property var bucketChoices: []

    function bucketErnFor(name) {
        const bucket = root.bucketChoices.find(b => b.name === name)
        return bucket ? bucket.ern : ""
    }

    Connections {
        target: esmClient
        function onBucketsLoaded(list, total) {
            root.bucketChoices = list
        }
        // The artifact is uploaded first and the application created once it is actually in the
        // bucket - EAP refuses an artifact it cannot find, so the order matters.
        function onObjectUploaded(bucketErn, key) {
            if (!createApplicationDialog.uploading) return
            createApplicationDialog.uploading = false
            createApplicationDialog.pendingFile = ""
            createApplicationDialog.submit()
        }
        function onObjectUploadFailed(message) {
            if (!createApplicationDialog.uploading) return
            createApplicationDialog.uploading = false
            createApplicationDialog.creating = false
            createApplicationDialog.errorText = message
        }
        function onUploadProgress(bucketErn, key, bytesSent, bytesTotal) {
            if (!createApplicationDialog.uploading) return
            createApplicationDialog.bytesSent = bytesSent
            createApplicationDialog.bytesTotal = bytesTotal
        }
    }

    FileDialog {
        id: artifactFileDialog
        title: "Select the application artifact"
        onAccepted: {
            createApplicationDialog.pendingFile = selectedFile
            // The key defaults to the file's own name, which is what an operator would type anyway.
            const path = selectedFile.toString()
            artifactField.text = path.substring(path.lastIndexOf("/") + 1)
        }
    }

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view applications."
            return
        }
        loading = true
        error = ""
        // "list-applications" has no paging server-side, so there is nothing to page through here.
        eapClient.fetchApplications(root.prefix)
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
        target: eapClient
        function onApplicationsLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.applications = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onApplicationsFailed(message) {
            root.loading = false
            root.error = message
        }
        function onApplicationsReload() {
            root.refresh()
        }
        function onApplicationCreated(applicationId) {
            createApplicationDialog.creating = false
            createApplicationDialog.close()
        }
        function onApplicationCreateFailed(message) {
            createApplicationDialog.creating = false
            createApplicationDialog.errorText = message
        }
        function onApplicationStateFailed(message) {
            root.error = message
        }
    }

    Dialog {
        id: createApplicationDialog
        modal: true
        anchors.centerIn: parent
        width: 400
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool creating: false
        property string errorText: ""
        // Set when an artifact was picked from disk: it is uploaded on Create, and the application
        // is created afterwards. Empty means the artifact is already in the bucket.
        property url pendingFile: ""
        property bool uploading: false
        property real bytesSent: 0
        property real bytesTotal: 0

        // Everything after the artifact exists in the bucket.
        function submit() {
            const names = (text) => text.split(",").map(n => n.trim()).filter(n => n.length > 0)
            eapClient.createApplication(applicationIdField.text.trim(), runtimeCombo.currentText,
                bucketCombo.currentText, artifactField.text.trim(), userField.text.trim(),
                names(bucketsField.text), names(queuesField.text))
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        // ComboBox's currentIndex is set imperatively on open, same as every other dialog here -
        // its own model-populate logic clobbers a binding.
        onOpened: {
            // The bucket list is the dialog's own: nothing else on this page needs it.
            esmClient.fetchBuckets("", 0, 100)
            applicationIdField.text = ""
            runtimeCombo.currentIndex = 0
            bucketCombo.currentIndex = 0
            artifactField.text = ""
            createApplicationDialog.pendingFile = ""
            createApplicationDialog.uploading = false
            createApplicationDialog.bytesSent = 0
            createApplicationDialog.bytesTotal = 0
            bucketsField.text = ""
            queuesField.text = ""
            // Empty on purpose: the default is a dedicated technical principal, not the operator.
            userField.text = ""
            createApplicationDialog.errorText = ""
            createApplicationDialog.creating = false
            applicationIdField.forceActiveFocus()
        }

        contentItem: Column {
            width: createApplicationDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Application"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Admin only. Created stopped - start it afterwards. The artifact is either already in "
                          + "the bucket or uploaded from here as part of creating the application."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Application ID"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: applicationIdField
                    width: parent.width
                    placeholderText: "e.g. inbox"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: bucketField.forceActiveFocus()
                }
            }

            Column {
                id: runtimeColumn
                width: parent.width
                spacing: 6
                Text { text: "Runtime"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: runtimeCombo
                    width: runtimeColumn.width
                    model: [ "JAVA", "PYTHON", "NODEJS", "BINARY" ]
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
            }

            Column {
                id: bucketColumn
                width: parent.width
                spacing: 6
                Text { text: "Bucket"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: bucketCombo
                    width: bucketColumn.width
                    model: root.bucketChoices.map(b => b.name)
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    text: root.bucketChoices.length === 0 ? "Loading buckets…"
                          : "Where the artifact lives; the application is materialised out of it on start."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                id: artifactColumn
                width: parent.width
                spacing: 6
                Text { text: "Artifact"; color: "#9aa1ac"; font.pixelSize: 12 }

                Row {
                    width: parent.width
                    spacing: 8

                    TextField {
                        id: artifactField
                        width: artifactColumn.width - uploadButton.width - 8
                        placeholderText: "object key, e.g. euclid-inbox-app.jar"
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        Keys.onReturnPressed: bucketsField.forceActiveFocus()
                    }
                    Button {
                        id: uploadButton
                        text: "Upload…"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        enabled: !createApplicationDialog.creating
                        onClicked: artifactFileDialog.open()
                    }
                }

                Text {
                    // Two ways in: name an object already in the bucket, or pick a file and let
                    // this upload it under that key first.
                    text: createApplicationDialog.pendingFile.toString().length > 0
                          ? "Will be uploaded to \"" + bucketCombo.currentText + "\" as this key when you press Create."
                          : "An object already in the bucket, or pick a file to upload."
                    color: createApplicationDialog.pendingFile.toString().length > 0 ? "#4f8cff" : "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Text {
                    visible: createApplicationDialog.uploading && createApplicationDialog.bytesTotal > 0
                    text: "Uploading " + SizeFormat.format(createApplicationDialog.bytesSent) + " of "
                          + SizeFormat.format(createApplicationDialog.bytesTotal) + "…"
                    color: "#9aa1ac"
                    font.pixelSize: 11
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Allowed buckets and queues"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: bucketsField
                    width: parent.width
                    placeholderText: "bucket names, comma separated"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: queuesField.forceActiveFocus()
                }
                TextField {
                    id: queuesField
                    width: parent.width
                    placeholderText: "queue names, comma separated"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: userField.forceActiveFocus()
                }
                Text {
                    text: "Resolved to ERNs and enforced by ESM and EQS. Leave both empty to let it reach "
                          + "everything in its own account."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Runs as (optional)"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: userField
                    width: parent.width
                    placeholderText: "leave empty for a dedicated principal"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createApplicationButton.enabled) createApplicationButton.clicked()
                }
                Text {
                    text: userField.text.trim().length === 0
                          ? "EAP creates \"app-" + (applicationIdField.text.trim().length > 0 ? applicationIdField.text.trim() : "<id>")
                            + "\" with its own access key and deletes it with the application, so no person's "
                            + "credentials are involved."
                          : "The application acts as this user, who must already exist and already have an access key."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Text {
                    text: createApplicationDialog.errorText
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
                    onClicked: createApplicationDialog.close()
                }

                BusyIndicator {
                    running: createApplicationDialog.creating
                    visible: createApplicationDialog.creating
                    width: 22
                    height: 22
                    anchors.right: createApplicationButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: createApplicationButton
                    text: "Create"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !createApplicationDialog.creating && applicationIdField.text.trim().length > 0
                             && bucketCombo.currentText.length > 0 && artifactField.text.trim().length > 0
                    onClicked: {
                        createApplicationDialog.errorText = ""
                        createApplicationDialog.creating = true
                        if (createApplicationDialog.pendingFile.toString().length > 0) {
                            createApplicationDialog.uploading = true
                            esmClient.uploadObject(root.bucketErnFor(bucketCombo.currentText),
                                                   artifactField.text.trim(), createApplicationDialog.pendingFile)
                        } else {
                            createApplicationDialog.submit()
                        }
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
                text: "‹ Back to EAP Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Applications (" + root.totalCount + ")"
                    subtitle: "Artifacts euclid runs as processes."
                }

                Button {
                    text: "+ Add Application"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createApplicationDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.applications
                totalCount: root.totalCount
                // One page: "list-applications" returns every application at once.
                pageSize: root.totalCount > 0 ? root.totalCount : 1
                pageIndex: 0
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by application ID prefix..."
                emptyText: "No applications defined."
                rowsClickable: true
                onRowClicked: (row) => root.openApplicationDetails(row.applicationId, row)

                onSearchChanged: (text) => {
                    root.prefix = text
                    root.refresh()
                }
                onRefreshRequested: root.refresh()

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function(row) {
                            root.openApplicationDetails(row.applicationId, row)
                        }
                    },
                    {
                        text: "Start",
                        enabled: function(row) {
                            return !!row && row.desiredState !== "RUNNING"
                        },
                        action: function(row) {
                            eapClient.startApplication(row.applicationId)
                        }
                    },
                    {
                        text: "Stop",
                        enabled: function(row) {
                            return !!row && row.desiredState === "RUNNING"
                        },
                        action: function(row) {
                            eapClient.stopApplication(row.applicationId)
                        }
                    },
                    {
                        text: "Delete",
                        action: function(row) {
                            eapClient.deleteApplication(row.applicationId)
                        }
                    }
                ]
            }
        }
    }
}
