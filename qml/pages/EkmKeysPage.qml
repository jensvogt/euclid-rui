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
    property string sortColumn: "created"
    property bool sortAscending: false

    property var keys: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    function statusColor(status) {
        if (status === "AVAILABLE") return "#4cd97b"
        if (status === "REVOKED" || status === "UPLOADED") return "#ffb545"
        if (status === "PENDING_DELETION") return "#ff4f5e"
        return "#9aa1ac"
    }

    readonly property var columns: {
        let cols = [
            { title: "Key ID", key: "name", fill: true },
            { title: "Algorithm", key: "algorithm" },
            { title: "Length", key: "length", formatter: function (v) { return v + " bit" } },
            { title: "Status", key: "status", colorFor: function (v) { return root.statusColor(v) } },
            { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Ern", key: "ern", hidden: true },
        ]
        return cols
    }

    signal back()
    signal openKeyDetails(string keyErn, string keyName, var details)

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view keys."
            return
        }
        loading = true
        error = ""
        ekmClient.fetchKeys(root.prefix, root.pageIndex, root.pageSize,
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

    // Events are what actually changed something; the timer above stays as the fallback for an
    // installation without the event service, and for anything that changes without an event.
    Connections {
        target: eventStream
        function onEventReceived(eventType, payload) {
            if (!root.visible || !root.loggedIn)
                return
            if (["ekm.key.created"].indexOf(eventType) >= 0) {
                root.refresh()
            }
        }
    }

    Connections {
        target: ekmClient
        function onKeysLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.keys = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onKeysFailed(message) {
            root.loading = false
            root.error = message
        }

        function onKeysReload() {
            refresh()
        }

        function onKeyCreated(name) {
            createKeyDialog.creating = false
            createKeyDialog.close()
        }
        function onKeyCreateFailed(message) {
            createKeyDialog.creating = false
            createKeyDialog.errorText = message
        }
    }

    Dialog {
        id: createKeyDialog
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
            algorithmCombo.currentIndex = 0
            lengthSpinBox.value = 256
            createKeyDialog.errorText = ""
            createKeyDialog.creating = false
        }

        contentItem: Column {
            width: createKeyDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Key"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Generates a new encryption key. Keys are identified by a generated ID, not a chosen name."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Algorithm"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: algorithmCombo
                    width: parent.width
                    implicitHeight: 36
                    model: ["AES", "RSA", "ECC"]
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Length (bits)"; color: "#9aa1ac"; font.pixelSize: 12 }
                SpinBox {
                    id: lengthSpinBox
                    width: parent.width
                    from: 64
                    to: 8192
                    stepSize: 64
                    editable: true
                    value: 256
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    text: createKeyDialog.errorText
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
                    onClicked: createKeyDialog.close()
                }

                BusyIndicator {
                    running: createKeyDialog.creating
                    visible: createKeyDialog.creating
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
                    enabled: !createKeyDialog.creating
                    onClicked: {
                        createKeyDialog.errorText = ""
                        createKeyDialog.creating = true
                        ekmClient.createKey(algorithmCombo.currentText, lengthSpinBox.value)
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
                text: "‹ Back to EKM Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Keys"
                    subtitle: "All encryption keys in the " + root.namespaceName + " namespace."
                }

                Button {
                    text: "+ Add Key"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createKeyDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.keys
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by key ID prefix..."
                emptyText: "No keys found in this namespace."
                rowsClickable: false
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
                            root.openKeyDetails(row.ern, row.name, row)
                        }
                    },
                    {
                        text: "Revoke",
                        enabled: function(row) {
                            return !!row && row.status === "AVAILABLE"
                        },
                        action: function(row) {
                            ekmClient.revokeKey(row.ern)
                        }
                    },
                    {
                        text: "Delete",
                        enabled: function(row) {
                            return !!row && row.status !== "PENDING_DELETION"
                        },
                        action: function(row) {
                            ekmClient.deleteKey(row.name)
                        }
                    }
                ]
            }
        }
    }
}
