import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// ETS transfer servers: FTP/SFTP endpoints fronting an ESM bucket. Every row shows both what is
// running (`state`) and what was asked for (`desiredState`) - start and stop only write the
// latter, and euclid-mgr's reconciler is what makes them agree.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    property string prefix: ""
    property var servers: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    readonly property var columns: [
        { title: "Server ID", key: "serverId", fill: true },
        { title: "Protocol", key: "protocol" },
        { title: "Address", key: "address" },
        { title: "Port", key: "port" },
        { title: "Bucket", key: "bucketName" },
        { title: "State", key: "state" },
        { title: "Desired", key: "desiredState" },
        { title: "Users", key: "userIds", formatter: function (v) { return v ? v.length : 0 } },
        { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Ern", key: "ern", hidden: true }
    ]

    signal back()
    signal openServerDetails(string serverId, var details)

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view transfer servers."
            return
        }
        loading = true
        error = ""
        // "list-servers" has no paging server-side, so there is nothing to page through here.
        etsClient.fetchServers(root.prefix)
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
        target: etsClient
        function onServersLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.servers = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onServersFailed(message) {
            root.loading = false
            root.error = message
        }
        function onServersReload() {
            root.refresh()
        }
        function onServerCreated(serverId) {
            createServerDialog.creating = false
            createServerDialog.close()
        }
        function onServerCreateFailed(message) {
            createServerDialog.creating = false
            createServerDialog.errorText = message
        }
        function onServerStateFailed(message) {
            root.error = message
        }
    }

    Dialog {
        id: createServerDialog
        modal: true
        anchors.centerIn: parent
        width: 400
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

        // ComboBox's currentIndex binding gets clobbered by its own internal model-populate logic,
        // same as every other dialog's combo in this app - set it imperatively on open instead.
        onOpened: {
            serverIdField.text = ""
            protocolCombo.currentIndex = 0
            portField.text = ""
            bucketField.text = ""
            addressField.text = "0.0.0.0"
            usersField.text = ""
            createServerDialog.errorText = ""
            createServerDialog.creating = false
            serverIdField.forceActiveFocus()
        }

        contentItem: Column {
            width: createServerDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Transfer Server"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Admin only. Created stopped - start it afterwards. The bucket must already exist, and "
                          + "the port must not be used by another transfer server."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Server ID"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: serverIdField
                    width: parent.width
                    placeholderText: "e.g. ftp-inbound"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: portField.forceActiveFocus()
                }
            }

            Row {
                width: parent.width
                spacing: 12

                Column {
                    id: protocolColumn
                    width: (parent.width - 12) / 2
                    spacing: 6
                    Text { text: "Protocol"; color: "#9aa1ac"; font.pixelSize: 12 }
                    ComboBox {
                        id: protocolCombo
                        width: protocolColumn.width
                        model: [ "SFTP", "FTP" ]
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }

                Column {
                    width: (parent.width - 12) / 2
                    spacing: 6
                    Text { text: "Port"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: portField
                        width: parent.width
                        placeholderText: "e.g. 2222"
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 1; top: 65535 }
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        Keys.onReturnPressed: bucketField.forceActiveFocus()
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Bucket"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: bucketField
                    width: parent.width
                    placeholderText: "existing ESM bucket name"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: addressField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Bind address"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: addressField
                    width: parent.width
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: usersField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Allowed users"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: usersField
                    width: parent.width
                    placeholderText: "EAM user IDs, comma separated"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createServerButton.enabled) createServerButton.clicked()
                }
                Text {
                    text: createServerDialog.errorText
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
                    onClicked: createServerDialog.close()
                }

                BusyIndicator {
                    running: createServerDialog.creating
                    visible: createServerDialog.creating
                    width: 22
                    height: 22
                    anchors.right: createServerButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: createServerButton
                    text: "Create"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !createServerDialog.creating && serverIdField.text.trim().length > 0
                             && portField.acceptableInput && bucketField.text.trim().length > 0
                    onClicked: {
                        createServerDialog.errorText = ""
                        createServerDialog.creating = true
                        const users = usersField.text.split(",").map(u => u.trim()).filter(u => u.length > 0)
                        etsClient.createServer(serverIdField.text.trim(), protocolCombo.currentText,
                            parseInt(portField.text, 10), bucketField.text.trim(),
                            addressField.text.trim().length > 0 ? addressField.text.trim() : "0.0.0.0", users, [])
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
                text: "‹ Back to ETS Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Transfer Servers (" + root.totalCount + ")"
                    subtitle: "FTP and SFTP endpoints fronting ESM buckets."
                }

                Button {
                    text: "+ Add Server"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createServerDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.servers
                totalCount: root.totalCount
                // One page: "list-servers" returns every server at once.
                pageSize: root.totalCount > 0 ? root.totalCount : 1
                pageIndex: 0
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by server ID prefix..."
                emptyText: "No transfer servers defined."
                rowsClickable: true
                onRowClicked: (row) => root.openServerDetails(row.serverId, row)

                onSearchChanged: (text) => {
                    root.prefix = text
                    root.refresh()
                }
                onRefreshRequested: root.refresh()

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function(row) {
                            root.openServerDetails(row.serverId, row)
                        }
                    },
                    {
                        text: "Start",
                        enabled: function(row) {
                            return !!row && row.desiredState !== "RUNNING"
                        },
                        action: function(row) {
                            etsClient.startServer(row.serverId)
                        }
                    },
                    {
                        text: "Stop",
                        enabled: function(row) {
                            return !!row && row.desiredState === "RUNNING"
                        },
                        action: function(row) {
                            etsClient.stopServer(row.serverId)
                        }
                    },
                    {
                        text: "Delete",
                        action: function(row) {
                            etsClient.deleteServer(row.serverId)
                        }
                    }
                ]
            }
        }
    }
}
