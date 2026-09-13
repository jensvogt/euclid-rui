import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// EAM roles: the named sets of permissions that grants hand out.
//
// Two kinds live here side by side. The six built-ins come with the installation, are the same in
// every account, and cannot be changed or deleted - they are not rows in the account at all, which
// is why they carry no created or modified date. Everything else was made here, and is as narrow as
// whoever made it decided.
//
// Administrators only, and the server agrees: every action on this page requires it.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    property var roles: []
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"
    property string actionNote: ""

    // Every permission a role may hold, for the create dialog. Fetched once with the list rather
    // than per dialog: it is a fixed vocabulary that only changes when euclid itself does.
    property var permissions: []
    property var unbindableModules: []

    readonly property bool isAdmin: euclidClient.isAdmin
    readonly property int totalCount: root.roles.length

    signal back()
    signal openRoleDetails(string roleName, var details)

    readonly property var columns: [
        { title: "Role", key: "name", fill: true },
        { title: "Description", key: "description" },
        {
            title: "Permissions",
            key: "permissionCount",
            formatter: function (v, row) {
                // "*:*" is one entry and every permission there is, which "1" would say the
                // opposite of.
                if (row && row.permissions && row.permissions.indexOf("*:*") >= 0) return "everything"
                return String(Number(v))
            }
        },
        {
            title: "Kind",
            key: "builtin",
            formatter: function (v) { return v ? "built in" : "custom" },
            // The ones that can actually be edited are the ones worth picking out.
            colorFor: function (v) { return v ? "#9aa1ac" : "#4f8cff" }
        },
        { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Ern", key: "ern", hidden: true }
    ]

    function refresh() {
        if (!root.loggedIn) {
            root.error = "Sign in to view roles."
            return
        }
        if (!root.isAdmin) {
            root.error = "Roles are only shown to administrators."
            return
        }
        root.loading = true
        root.error = ""
        eamClient.fetchRoles()
        eamClient.fetchPermissions()
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Live updates are off by default: a table that reloads while it is being read
        // moves rows out from under the pointer. See AppSettings::liveListUpdates().
        running: appSettings.liveListUpdates && appSettings.autoRefreshSeconds > 0
                 && root.visible && root.loggedIn && root.isAdmin
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: eamClient

        function onRolesLoaded(list) {
            root.loading = false
            root.error = ""
            // Custom roles first, then the built-ins: what somebody made here is what they came to
            // look at, and the six that are the same everywhere read as a footnote to it.
            root.roles = list.slice().sort((a, b) => {
                if (a.builtin !== b.builtin) return a.builtin ? 1 : -1
                return String(a.name).localeCompare(String(b.name))
            })
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onRolesFailed(message) {
            root.loading = false
            root.error = message
        }
        function onRolesReload() {
            root.refresh()
        }
        function onPermissionsLoaded(permissions, modules, unbindable) {
            root.permissions = permissions
            root.unbindableModules = unbindable
        }
        function onPermissionsFailed(message) {
            // Not the table's error: the roles may have read perfectly well, and only the create
            // dialog's picker is the poorer for this.
            createDialog.errorText = message
        }
        function onRoleCreated(name, role) {
            createDialog.saving = false
            createDialog.close()
            root.actionNote = "Role '" + name + "' created with " + role.permissionCount + " permission(s). "
                              + "Nothing holds it until it is granted."
        }
        function onRoleCreateFailed(message) {
            createDialog.saving = false
            createDialog.errorText = message
        }
        function onRoleDeleted(name) {
            root.actionNote = "Role '" + name + "' deleted."
        }
        function onRoleDeleteFailed(message) {
            root.error = message
        }
    }

    Dialog {
        id: createDialog
        modal: true
        anchors.centerIn: parent
        width: 560
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""
        property string filter: ""
        // What the role will hold. A set rather than a list, so clicking the same permission twice
        // is not two of it.
        property var selected: ({})

        readonly property var selectedNames: Object.keys(createDialog.selected).sort()

        readonly property var shown: {
            const needle = createDialog.filter.trim().toLowerCase()
            if (needle.length === 0) return root.permissions
            return root.permissions.filter(p => String(p).toLowerCase().indexOf(needle) >= 0)
        }

        function toggle(permission, on) {
            const next = Object.assign({}, createDialog.selected)
            if (on) next[permission] = true
            else delete next[permission]
            createDialog.selected = next
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            roleNameField.text = ""
            roleDescriptionField.text = ""
            createDialog.selected = ({})
            createDialog.filter = ""
            permissionFilterField.text = ""
            createDialog.errorText = ""
            createDialog.saving = false
            roleNameField.forceActiveFocus()
        }

        contentItem: Column {
            width: createDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Role"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "A named set of permissions, which granting then hands to a user or a group. It needs at "
                          + "least one - a role that grants nothing is a mistake rather than a starting point."
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
                    id: roleNameField
                    width: parent.width
                    placeholderText: "e.g. metrics-pusher"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: roleDescriptionField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Description"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: roleDescriptionField
                    width: parent.width
                    placeholderText: "what it is for"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
            }

            Column {
                width: parent.width
                spacing: 6

                Item {
                    width: parent.width
                    height: 36

                    Text {
                        id: permissionsLabel
                        text: "Permissions (" + createDialog.selectedNames.length + " selected)"
                        color: "#9aa1ac"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextField {
                        id: permissionFilterField
                        width: 220
                        height: 34
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        placeholderText: "filter, e.g. eqs:"
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        onTextChanged: createDialog.filter = text
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 220
                    radius: 8
                    color: "#14161b"
                    border.color: "#2c313c"
                    border.width: 1
                    clip: true

                    ListView {
                        id: permissionList
                        anchors.fill: parent
                        anchors.margins: 8
                        model: createDialog.shown
                        clip: true
                        spacing: 2

                        delegate: CheckBox {
                            required property string modelData
                            width: permissionList.width
                            text: modelData
                            checked: createDialog.selected[modelData] === true
                            font.family: "monospace"
                            font.pixelSize: 12
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onToggled: createDialog.toggle(modelData, checked)
                        }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: root.permissions.length === 0
                          ? "No permissions could be read, so none can be picked."
                          : root.permissions.length + " permissions across the modules a role can reach."
                            + (root.unbindableModules.length > 0
                               ? " " + root.unbindableModules.join(" and ").toUpperCase()
                                 + " are not among them: they gate themselves, so no role can name them."
                               : "")
                }
            }

            Text {
                text: createDialog.errorText
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
                    onClicked: createDialog.close()
                }

                BusyIndicator {
                    running: createDialog.saving
                    visible: createDialog.saving
                    width: 22
                    height: 22
                    anchors.right: createRoleButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: createRoleButton
                    text: "Create"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !createDialog.saving && roleNameField.text.trim().length > 0
                             && createDialog.selectedNames.length > 0
                    onClicked: {
                        createDialog.errorText = ""
                        createDialog.saving = true
                        root.actionNote = ""
                        eamClient.createRole(roleNameField.text.trim(), createDialog.selectedNames,
                                             roleDescriptionField.text.trim())
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 28
        standardButtons: Dialog.NoButton

        property string roleName: ""

        function openFor(row) {
            deleteDialog.roleName = row.name
            deleteDialog.open()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: deleteDialog.availableWidth
            spacing: 18

            Text { text: "Delete Role"; color: "white"; font.pixelSize: 18; font.bold: true }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#9aa1ac"
                font.pixelSize: 12
                text: "\"" + deleteDialog.roleName + "\". The server refuses while anything still holds it - revoke "
                      + "those grants first, which the role's own page lists."
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
                        root.actionNote = ""
                        eamClient.deleteRole(deleteDialog.roleName)
                        deleteDialog.close()
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

            Breadcrumb {
                width: parent.width
                segments: [
                    { label: "EAM", action: () => root.back() },
                    { label: "Roles" }
                ]
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Roles (" + root.totalCount + ")"
                    subtitle: "What a grant hands out: a named set of permissions."
                }

                Button {
                    text: "+ Add Role"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    visible: root.isAdmin
                    onClicked: createDialog.open()
                }
            }

            // Shown instead of the table rather than beside it: an empty table under a permission
            // message reads like there are no roles.
            Rectangle {
                width: parent.width
                height: 120
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                visible: !root.isAdmin

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "Roles are only shown to administrators."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }

            DataTable {
                width: parent.width
                visible: root.isAdmin
                columns: root.columns
                rows: root.roles
                totalCount: root.totalCount
                // One page: "list-roles" answers with every role at once, so there is no size to pick.
                pageSizeSelectable: false
                pageSize: root.totalCount > 0 ? root.totalCount : 1
                pageIndex: 0
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                // The listing takes no prefix, and the six built-ins plus a handful of custom roles
                // are not a list anybody needs to search.
                searchable: false
                emptyText: "No roles."
                rowsClickable: true
                onRowClicked: (row) => root.openRoleDetails(row.name, row)
                onRefreshRequested: root.refresh()

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function(row) { root.openRoleDetails(row.name, row) }
                    },
                    {
                        // The built-ins are the same in every installation and the server refuses
                        // to touch them, so offering it would make refusal the usual outcome.
                        text: "Delete…",
                        enabled: function(row) { return !!row && row.builtin !== true },
                        action: function(row) { deleteDialog.openFor(row) }
                    }
                ]
            }

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
