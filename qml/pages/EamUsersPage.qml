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
    property string sortColumn: "userId"
    property bool sortAscending: true

    property var users: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    readonly property var columns: {
        let cols = [
            { title: "User ID", key: "userId", fill: true },
            { title: "Email", key: "email" },
            { title: "Account ID", key: "accountId" },
            { title: "Region", key: "region" },
            { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Ern", key: "ern", hidden: true }
        ]
        return cols
    }

    signal back()
    signal openUserDetails(string userErn, string userId, var details)

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view users."
            return
        }
        loading = true
        error = ""
        // ListUserRequest has no sortDirection field server-side, so sortAscending isn't sent.
        eamClient.fetchUsers(root.prefix, root.pageIndex, root.pageSize, root.sortColumn)
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
        function onUsersLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.users = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onUsersFailed(message) {
            root.loading = false
            root.error = message
        }
        function onUsersReload() {
            refresh()
        }
        function onUserCreated(userId) {
            createUserDialog.creating = false
            createUserDialog.close()
        }
        function onUserCreateFailed(message) {
            createUserDialog.creating = false
            createUserDialog.errorText = message
        }
    }

    Dialog {
        id: createUserDialog
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
            userIdField.text = ""
            passwordField.text = ""
            emailField.text = ""
            accountIdField.text = euclidClient.accountId
            regionField.text = euclidClient.region
            adminCheck.checked = false
            createUserDialog.errorText = ""
            createUserDialog.creating = false
            userIdField.forceActiveFocus()
        }

        contentItem: Column {
            width: createUserDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create User"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Admin only. The very first user ever registered always becomes an administrator."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "User ID"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: userIdField
                    width: parent.width
                    placeholderText: "e.g. jane.doe"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: passwordField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Password"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: passwordField
                    width: parent.width
                    echoMode: TextInput.Password
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: emailField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Email"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: emailField
                    width: parent.width
                    placeholderText: "e.g. jane.doe@example.com"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: accountIdField.forceActiveFocus()
                }
            }

            Row {
                width: parent.width
                spacing: 12

                Column {
                    width: (parent.width - 12) / 2
                    spacing: 6
                    Text { text: "Account ID"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: accountIdField
                        width: parent.width
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                    }
                }

                Column {
                    width: (parent.width - 12) / 2
                    spacing: 6
                    Text { text: "Region"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: regionField
                        width: parent.width
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                    }
                }
            }

            CheckBox {
                id: adminCheck
                text: "Grant administrator access"
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
            }

            Text {
                text: createUserDialog.errorText
                color: "#ff6b6b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                width: parent.width
                visible: text.length > 0
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
                    onClicked: createUserDialog.close()
                }

                BusyIndicator {
                    running: createUserDialog.creating
                    visible: createUserDialog.creating
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
                    enabled: !createUserDialog.creating && userIdField.text.trim().length > 0
                             && passwordField.text.length > 0 && accountIdField.text.trim().length > 0
                             && regionField.text.trim().length > 0
                    onClicked: {
                        createUserDialog.errorText = ""
                        createUserDialog.creating = true
                        eamClient.createUser(userIdField.text.trim(), passwordField.text, emailField.text.trim(),
                            accountIdField.text.trim(), regionField.text.trim(), adminCheck.checked)
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
                    title: "Users (" + root.totalCount + ")"
                    subtitle: "All users in this deployment."
                }

                Button {
                    text: "+ Add User"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createUserDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.users
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by user ID prefix..."
                emptyText: "No users found."
                rowsClickable: true
                onRowClicked: (row) => root.openUserDetails(row.ern, row.userId, row)
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
                            root.openUserDetails(row.ern, row.userId, row)
                        }
                    },
                    {
                        text: "Delete",
                        action: function(row) {
                            eamClient.deleteUser(row.userId)
                        }
                    }
                ]
            }
        }
    }
}
