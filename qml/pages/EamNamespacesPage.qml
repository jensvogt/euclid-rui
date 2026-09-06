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
    property string sortColumn: "name"
    property bool sortAscending: true

    property var namespaces: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    readonly property var columns: {
        let cols = [
            { title: "Name", key: "name", fill: true },
            { title: "Account ID", key: "accountId" },
            { title: "Description", key: "description" },
            { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Ern", key: "ern", hidden: true }
        ]
        return cols
    }

    signal back()
    signal openNamespaceDetails(string accountId, string namespaceName, var details)

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view namespaces."
            return
        }
        loading = true
        error = ""
        eamClient.fetchNamespaces(euclidClient.accountId, root.prefix, root.pageIndex, root.pageSize,
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
        target: eamClient
        function onNamespacesLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.namespaces = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onNamespacesFailed(message) {
            root.loading = false
            root.error = message
        }
        function onNamespacesReload() {
            refresh()
        }
        function onNamespaceCreated(name) {
            createNamespaceDialog.creating = false
            createNamespaceDialog.close()
        }
        function onNamespaceCreateFailed(message) {
            createNamespaceDialog.creating = false
            createNamespaceDialog.errorText = message
        }
    }

    Dialog {
        id: createNamespaceDialog
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
            descriptionField.text = ""
            createNamespaceDialog.errorText = ""
            createNamespaceDialog.creating = false
            nameField.forceActiveFocus()
        }

        contentItem: Column {
            width: createNamespaceDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Namespace"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Creates a namespace under account " + euclidClient.accountId + "."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: nameField
                    width: parent.width
                    placeholderText: "e.g. staging"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: descriptionField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Description (optional)"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: descriptionField
                    width: parent.width
                    placeholderText: "e.g. Staging environment"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createButton.enabled) createButton.clicked()
                }
                Text {
                    text: createNamespaceDialog.errorText
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
                    onClicked: createNamespaceDialog.close()
                }

                BusyIndicator {
                    running: createNamespaceDialog.creating
                    visible: createNamespaceDialog.creating
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
                    enabled: !createNamespaceDialog.creating && nameField.text.trim().length > 0
                    onClicked: {
                        createNamespaceDialog.errorText = ""
                        createNamespaceDialog.creating = true
                        eamClient.createNamespace(euclidClient.accountId, nameField.text.trim(), descriptionField.text.trim())
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
                text: "‹ Back to EAM Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Namespaces (" + root.totalCount + ")"
                    subtitle: "All namespaces in account " + euclidClient.accountId + "."
                }

                Button {
                    text: "+ Add Namespace"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createNamespaceDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.namespaces
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by namespace name prefix..."
                emptyText: "No namespaces found in this account."
                rowsClickable: true
                onRowClicked: (row) => root.openNamespaceDetails(row.accountId, row.name, row)
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
                            root.openNamespaceDetails(row.accountId, row.name, row)
                        }
                    },
                    {
                        text: "Delete",
                        action: function(row) {
                            eamClient.deleteNamespace(row.accountId, row.name)
                        }
                    }
                ]
            }
        }
    }
}
