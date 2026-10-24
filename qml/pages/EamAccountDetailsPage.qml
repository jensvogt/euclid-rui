import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// What EAM lets an admin change about an existing account: the namespaces inside it, and who may
// work in it. Name and description are fixed at creation - there is no "update-account" action -
// so they are shown read-only.
//
// Adding a user here writes a role grant scoped to this account, which is the only way somebody
// comes to work in more than one: a user is registered in exactly one home account and that is
// not editable, so every further account they reach, they reach through a grant. It is also what
// puts the account in their picker at sign-in - the login dialog offers the accounts a grant
// names. Narrowing or withdrawing a grant is still done where the grant is shown: on the user's
// own page, or per namespace on the namespace page.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string accountId: ""
    property string accountName: ""
    property var details: ({})

    property var namespaces: []
    property string namespacesError: ""

    // Every user, annotated with their relationship to this account (see fetchAccountUsers).
    property var users: []
    property string usersError: ""

    // The roles this account can bind, read when the add-user dialog opens rather than with the
    // page: nothing else here needs them, and they are the one thing on this page that is about
    // what is being written rather than about what is there.
    property var roles: []

    property bool deleting: false

    signal back()
    signal openNamespaceDetails(string accountId, string namespaceName, var details)

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    // Users with any reason to touch this account: it is their home account, or they hold a
    // namespace grant in it.
    function relatedUsers() {
        return root.users.filter(u => u.home || u.namespaces.length > 0)
    }

    // Everyone who is not in this account yet - the only people a grant here would change anything
    // for. Somebody registered in it already works here, and somebody who holds a grant is better
    // served by editing the grant they have than by being given a second one beside it.
    function addableUsers() {
        return root.users.filter(u => !u.home && u.namespaces.length === 0)
    }

    function refresh() {
        if (!root.loggedIn || root.accountId.length === 0)
            return
        root.namespacesError = ""
        root.usersError = ""
        eamClient.fetchAccountNamespaces(root.accountId)
        eamClient.fetchAccountUsers(root.accountId)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()
    onAccountIdChanged: if (visible) refresh()

    Connections {
        target: eamClient

        function onAccountNamespacesLoaded(accountId, list) {
            if (accountId !== root.accountId) return
            root.namespaces = list
            root.namespacesError = ""
        }
        function onAccountNamespacesFailed(message) {
            root.namespacesError = message
        }
        function onAccountUsersLoaded(accountId, list) {
            if (accountId !== root.accountId) return
            root.users = list
            root.usersError = ""
        }
        function onAccountUsersFailed(message) {
            root.usersError = message
        }

        // Guarded on the dialog being open, not on the page being visible: rolesLoaded and
        // roleGranted are installation-wide signals, and a user details page with a grants tile
        // asks for the same things.
        function onRolesLoaded(list) {
            if (!addUserDialog.opened) return
            root.roles = list
        }
        function onRolesFailed(message) {
            if (!addUserDialog.opened) return
            addUserDialog.errorText = message
        }
        function onRoleGranted(principalErn, grantId) {
            if (!addUserDialog.saving) return
            addUserDialog.saving = false
            addUserDialog.close()
            // Re-read rather than patch: the tile shows what the account's grants say, and the
            // server is the one that just wrote one.
            root.refresh()
        }
        function onRoleGrantFailed(message) {
            if (!addUserDialog.saving) return
            addUserDialog.saving = false
            addUserDialog.errorText = message
        }

        // create/deleteNamespace report success by asking the namespaces table to reload; this
        // page just re-reads its own list when that happens, whoever triggered it.
        function onNamespacesReload() {
            if (root.visible) root.refresh()
        }
        function onNamespaceCreated(name) {
            createNamespaceDialog.creating = false
            createNamespaceDialog.close()
        }
        function onNamespaceCreateFailed(message) {
            createNamespaceDialog.creating = false
            createNamespaceDialog.errorText = message
        }
        function onNamespacesFailed(message) {
            if (root.visible) root.namespacesError = message
        }

        // deleteAccount() reports success the same way for the accounts table - only ours while
        // a delete is in flight. It fails with 409 while the account still has namespaces or
        // grants, which is why the confirmation says so.
        function onAccountsReload() {
            if (!root.deleting) return
            root.deleting = false
            root.back()
        }
        function onAccountsFailed(message) {
            if (!root.deleting) return
            root.deleting = false
            root.namespacesError = message
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

            Breadcrumb {
                width: parent.width
                leaf: root.accountName.length > 0 ? root.accountName : root.accountId
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.accountName.length > 0 ? root.accountName : root.accountId
                    subtitle: root.detail("ern", root.accountId)
                }

                Button {
                    text: "Delete Account"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#ff6b6b"
                    enabled: !root.deleting
                    onClicked: deleteDialog.open()
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard { title: "Account ID"; value: root.accountId.length > 0 ? root.accountId : "—"; trend: "identifier"; trendUp: true; accent: "#4f8cff" }
                StatCard {
                    title: "Namespaces"
                    value: String(root.namespaces.length)
                    trend: "in this account"
                    trendUp: root.namespaces.length > 0
                    accent: "#4cd97b"
                }
                StatCard {
                    title: "Users"
                    value: String(root.relatedUsers().length)
                    trend: "home or granted"
                    trendUp: root.relatedUsers().length > 0
                    accent: "#c56bff"
                    width: 440
                }
                StatCard {
                    title: "Created"
                    value: DateFormat.format(root.detail("created", ""))
                    trend: "modified " + DateFormat.format(root.detail("modified", ""))
                    trendUp: true
                    accent: "#ffb545"
                    width: 440
                }
            }

            Rectangle {
                width: parent.width
                height: identityCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: identityCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Identity"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.accountId }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Name"; value: root.accountName.length > 0 ? root.accountName : "—" }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    DetailField {
                        width: identityCol.width
                        label: "Description"
                        value: root.detail("description", "").length > 0 ? root.detail("description", "") : "—"
                    }
                    DetailField { width: identityCol.width; label: "Account ERN"; value: root.detail("ern", "—"); copyable: true }

                    Text {
                        width: parent.width
                        text: "Name and description are set when the account is created and cannot be changed here."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: namespacesCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: namespacesCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: namespacesHeaderRow.implicitHeight

                        Row {
                            id: namespacesHeaderRow
                            Text { text: "Namespaces"; color: "white"; font.pixelSize: 15; font.bold: true }
                        }

                        Button {
                            text: "+ Add Namespace"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: namespacesHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: createNamespaceDialog.open()
                        }
                    }

                    Text {
                        visible: root.namespacesError.length > 0
                        width: parent.width
                        text: root.namespacesError
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.namespaces.length === 0 && root.namespacesError.length === 0
                        text: "This account has no namespaces."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.namespaces
                        delegate: Row {
                            id: namespaceDelegate
                            required property var modelData

                            width: root.width - 96
                            height: 34
                            spacing: 12

                            Column {
                                id: namespaceLabels
                                width: namespaceDelegate.width - 180
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    text: namespaceDelegate.modelData.name
                                    color: "#e5e7eb"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    width: namespaceLabels.width
                                }
                                Text {
                                    text: namespaceDelegate.modelData.description.length > 0
                                          ? namespaceDelegate.modelData.description
                                          : namespaceDelegate.modelData.ern
                                    color: "#6b7280"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    width: namespaceLabels.width
                                }
                            }

                            Button {
                                text: "Details"
                                flat: true
                                anchors.verticalCenter: parent.verticalCenter
                                Material.theme: Material.Dark
                                onClicked: root.openNamespaceDetails(root.accountId, namespaceDelegate.modelData.name, namespaceDelegate.modelData)
                            }

                            Button {
                                text: "Delete"
                                flat: true
                                anchors.verticalCenter: parent.verticalCenter
                                Material.theme: Material.Dark
                                Material.accent: "#ff6b6b"
                                onClicked: {
                                    root.namespacesError = ""
                                    eamClient.deleteNamespace(root.accountId, namespaceDelegate.modelData.name)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: usersCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: usersCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: usersHeader.implicitHeight

                        Text {
                            id: usersHeader
                            text: "Users"
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Button {
                            text: "Add User…"
                            anchors.right: parent.right
                            anchors.verticalCenter: usersHeader.verticalCenter
                            flat: true
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            enabled: root.loggedIn && root.accountId.length > 0 && root.addableUsers().length > 0
                            onClicked: addUserDialog.open()
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Users registered in this account, or holding a grant in it. A user's home account is "
                              + "where they were registered and cannot be changed; a grant is how they come to work "
                              + "in a second account, and is what puts this account in their picker at sign-in."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.usersError.length > 0
                        width: parent.width
                        text: root.usersError
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.relatedUsers().length === 0 && root.usersError.length === 0
                        text: "No users are registered in or granted access to this account."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.relatedUsers()
                        delegate: Row {
                            id: userDelegate
                            required property var modelData

                            width: root.width - 96
                            height: 34
                            spacing: 10

                            Column {
                                id: userLabels
                                width: userDelegate.width - 320
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    text: userDelegate.modelData.userId
                                    color: "#e5e7eb"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    width: userLabels.width
                                }
                                Text {
                                    text: userDelegate.modelData.email.length > 0 ? userDelegate.modelData.email : userDelegate.modelData.ern
                                    color: "#6b7280"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    width: userLabels.width
                                }
                            }

                            Rectangle {
                                visible: userDelegate.modelData.home
                                radius: 6
                                color: "#1e3350"
                                height: 20
                                width: homeLabel.implicitWidth + 14
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    id: homeLabel
                                    anchors.centerIn: parent
                                    text: "home account"
                                    color: "#4f8cff"
                                    font.pixelSize: 10
                                }
                            }

                            Text {
                                text: userDelegate.modelData.namespaces.length > 0
                                      ? "grants: " + userDelegate.modelData.namespaces.join(", ")
                                      : ""
                                color: "#9aa1ac"
                                font.pixelSize: 11
                                elide: Text.ElideRight
                                width: 280
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }

    // Gives a user who was registered elsewhere a grant in this account - which is what "having
    // rights in several accounts" is made of. There is no second home account to hand out: a user
    // is registered in one account and holds grants in the others, and this writes one of those.
    Dialog {
        id: addUserDialog
        modal: true
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 480
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""

        // Snapshotted when the dialog opens rather than read live: the page refreshes underneath
        // it, and a list that reorders while somebody is choosing from it changes who they picked.
        property var candidates: []

        readonly property var selectedUser: addUserDialog.candidates.length > 0 && userCombo.currentIndex >= 0
                                            ? addUserDialog.candidates[userCombo.currentIndex] : null
        readonly property var selectedRole: root.roles.length > 0 && roleCombo.currentIndex >= 0
                                            ? root.roles[roleCombo.currentIndex] : null

        // Both are required by the server and both default to everything, as in the grants tile on
        // a user's own page - "*" here is what puts the user in the whole account rather than in
        // one namespace of it.
        function listFrom(text) {
            const parts = String(text).split(",").map(p => p.trim()).filter(p => p.length > 0)
            return parts.length > 0 ? parts : ["*"]
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            addUserDialog.errorText = ""
            addUserDialog.saving = false
            addUserDialog.candidates = root.addableUsers()
            root.roles = []
            userCombo.currentIndex = 0
            roleCombo.currentIndex = 0
            addNamespacesField.text = "*"
            addResourcesField.text = "*"
            eamClient.fetchRoles(root.accountId)
        }

        contentItem: Column {
            width: addUserDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add User to Account"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    width: parent.width
                    text: "Grants a role in " + (root.accountName.length > 0 ? root.accountName : root.accountId)
                          + " to a user registered elsewhere. They keep their own home account; this is what lets "
                          + "them choose this one when they sign in."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            Column {
                id: userColumn
                width: parent.width
                spacing: 6
                Text { text: "User"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: userCombo
                    width: userColumn.width
                    model: addUserDialog.candidates.map(u => u.userId + (u.email.length > 0 ? "  ·  " + u.email : ""))
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: addUserDialog.candidates.length > 0
                          ? "Everyone not already in this account. Somebody registered here, or already holding a "
                            + "grant, is edited through the grant they have rather than given a second one."
                          : "Everyone is already registered in or granted access to this account."
                }
            }

            Column {
                id: addRoleColumn
                width: parent.width
                spacing: 6
                Text { text: "Role"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: roleCombo
                    width: addRoleColumn.width
                    model: root.roles.map(r => r.name)
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: addUserDialog.selectedRole
                          ? addUserDialog.selectedRole.description + " · "
                            + addUserDialog.selectedRole.permissionCount + " permission(s)"
                            + (addUserDialog.selectedRole.builtin ? " · built in" : "")
                          : "Reading the roles this account can bind…"
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Namespaces"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: addNamespacesField
                    width: parent.width
                    placeholderText: "* for every namespace, or a comma-separated list"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
                Text {
                    text: "Where the role applies. \"*\" is every namespace of this account, including its root - "
                          + "which is what it means to be in the account rather than in one namespace of it."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Resources"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: addResourcesField
                    width: parent.width
                    placeholderText: "* for every resource, or ERN patterns"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
                Text {
                    text: "ERN patterns, each exact or ending in \"*\". This is what makes a wide role narrow."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Text {
                text: addUserDialog.errorText
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
                    enabled: !addUserDialog.saving
                    onClicked: addUserDialog.close()
                }

                Button {
                    text: addUserDialog.saving ? "Adding…" : "Add User"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !addUserDialog.saving && addUserDialog.selectedUser !== null
                             && addUserDialog.selectedRole !== null
                    onClicked: {
                        addUserDialog.errorText = ""
                        addUserDialog.saving = true
                        eamClient.grantRole(addUserDialog.selectedRole.name,
                                            addUserDialog.selectedUser.ern,
                                            addUserDialog.listFrom(addNamespacesField.text),
                                            addUserDialog.listFrom(addResourcesField.text),
                                            root.accountId)
                    }
                }
            }
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
            namespaceNameField.text = ""
            namespaceDescriptionField.text = ""
            createNamespaceDialog.errorText = ""
            createNamespaceDialog.creating = false
            namespaceNameField.forceActiveFocus()
        }

        contentItem: Column {
            width: createNamespaceDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Namespace"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Creates a namespace in account " + root.accountId + ". Requires administrator rights on it."
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
                    id: namespaceNameField
                    width: parent.width
                    placeholderText: "e.g. staging"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: namespaceDescriptionField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Description"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: namespaceDescriptionField
                    width: parent.width
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createNamespaceButton.enabled) createNamespaceButton.clicked()
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
                    anchors.right: createNamespaceButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: createNamespaceButton
                    text: "Create"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !createNamespaceDialog.creating && namespaceNameField.text.trim().length > 0
                    onClicked: {
                        createNamespaceDialog.errorText = ""
                        createNamespaceDialog.creating = true
                        eamClient.createNamespace(root.accountId, namespaceNameField.text.trim(), namespaceDescriptionField.text.trim())
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: deleteDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Delete Account"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Permanently deletes account " + root.accountId + ". The server refuses while it still has "
                          + "namespaces or user grants - remove those first. This cannot be undone."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
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
                    onClicked: deleteDialog.close()
                }

                Button {
                    text: "Delete"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#ff6b6b"
                    onClicked: {
                        root.deleting = true
                        deleteDialog.close()
                        eamClient.deleteAccount(root.accountId)
                    }
                }
            }
        }
    }
}
