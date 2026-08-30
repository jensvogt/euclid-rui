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
    property string sortColumn: "name"
    property bool sortAscending: true

    property var accounts: []
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

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view accounts."
            return
        }
        loading = true
        error = ""
        eamClient.fetchAccounts(root.prefix, root.pageIndex, root.pageSize,
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
        target: eamClient
        function onAccountsLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.accounts = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onAccountsFailed(message) {
            root.loading = false
            root.error = message
        }
        function onAccountsReload() {
            refresh()
        }
        function onAccountCreated(accountId) {
            createAccountDialog.creating = false
            createAccountDialog.close()
        }
        function onAccountCreateFailed(message) {
            createAccountDialog.creating = false
            createAccountDialog.errorText = message
        }
    }

    Dialog {
        id: createAccountDialog
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
            accountIdField.text = ""
            nameField.text = ""
            descriptionField.text = ""
            createAccountDialog.errorText = ""
            createAccountDialog.creating = false
            accountIdField.forceActiveFocus()
        }

        contentItem: Column {
            width: createAccountDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Account"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Global-admin only. Account IDs are unique across the deployment."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Account ID"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: accountIdField
                    width: parent.width
                    placeholderText: "e.g. 000000000001"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: nameField.forceActiveFocus()
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
                    text: createAccountDialog.errorText
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
                    onClicked: createAccountDialog.close()
                }

                BusyIndicator {
                    running: createAccountDialog.creating
                    visible: createAccountDialog.creating
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
                    enabled: !createAccountDialog.creating && accountIdField.text.trim().length > 0 && nameField.text.trim().length > 0
                    onClicked: {
                        createAccountDialog.errorText = ""
                        createAccountDialog.creating = true
                        eamClient.createAccount(accountIdField.text.trim(), nameField.text.trim(), descriptionField.text.trim())
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
                    title: "Accounts (" + root.totalCount + ")"
                    subtitle: "All accounts in this deployment."
                }

                Button {
                    text: "+ Add Account"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createAccountDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.accounts
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by account name prefix..."
                emptyText: "No accounts found."
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
                        text: "Delete",
                        action: function(row) {
                            eamClient.deleteAccount(row.accountId)
                        }
                    }
                ]
            }
        }
    }
}
