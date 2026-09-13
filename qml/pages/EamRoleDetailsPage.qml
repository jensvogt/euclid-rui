import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// One role: what it permits, and who holds it.
//
// The second question is the one nothing else in the app answers. A principal's own page lists the
// roles it has; this is the other direction - every grant naming this role - which is what has to
// be emptied before a role can be deleted, and what says how much a change to it would affect.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string roleName: ""
    property var details: ({})

    property string error: ""
    property string actionNote: ""

    property var holders: []
    property bool holdersLoading: false
    property string holdersError: ""

    // The vocabulary, for the edit dialog.
    property var permissions: []

    // Who this role could be given to, for the grant dialog. Both kinds, because a grant takes
    // either - the ERN is what says which - and groups are listed first: a role granted to the
    // people who do a job outlives whoever currently does it.
    property var userGroups: []
    property var users: []

    readonly property var principalChoices: {
        const choices = []
        for (const group of root.userGroups)
            choices.push({ label: "Group · " + group.name, ern: group.ern })
        for (const user of root.users)
            choices.push({ label: "User · " + user.userId, ern: user.ern })
        return choices
    }

    signal back()
    // Switches this page to another role - used after copying one, so the new role is what is in
    // front of you rather than the built-in it came from.
    signal openRole(string roleName, var details)

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    readonly property bool builtin: root.detail("builtin", false) === true
    readonly property var rolePermissions: root.detail("permissions", [])
    // "*:*" is one entry and every permission there is.
    readonly property bool grantsEverything: root.rolePermissions.indexOf("*:*") >= 0

    // Grouped by the module they belong to, which is how a permission list is actually read: what
    // may this role do to queues, what may it do to buckets.
    readonly property var permissionsByModule: {
        const grouped = ({})
        for (const permission of root.rolePermissions) {
            const parts = String(permission).split(":")
            const module = parts.length > 1 ? parts[0] : "other"
            if (!grouped[module]) grouped[module] = []
            grouped[module].push(String(permission))
        }
        return grouped
    }

    readonly property var permissionModules: Object.keys(root.permissionsByModule).sort()

    // Set while a single-permission removal is in flight, which is its own state: the edit dialog
    // has its own, and a chip being removed should not look like the whole role is being saved.
    property bool savingPermissions: false

    // Taking one permission away is a write of everything that is left - update-role replaces the
    // list rather than merging into it, which is the only way it can be narrowed at all.
    function removePermission(permission) {
        const remaining = root.rolePermissions.filter(p => p !== permission)
        if (remaining.length === 0) {
            // The server refuses this, and rightly: a role with nothing in it grants nothing and is
            // a mistake rather than a step on the way somewhere. Said here rather than sent.
            root.error = "A role has to keep at least one permission. Delete the role instead, or add another first."
            return
        }
        root.error = ""
        root.actionNote = ""
        root.savingPermissions = true
        eamClient.updateRole(root.roleName, remaining, root.detail("description", ""))
    }

    function refresh() {
        if (!root.loggedIn || root.roleName.length === 0)
            return
        root.error = ""
        // Re-read rather than trusting the row that was clicked: a role's permissions are the point
        // of this page, and the listing that carried them may be minutes old.
        eamClient.fetchRole(root.roleName)
        root.holdersLoading = true
        eamClient.fetchRoleGrants(root.roleName)
        eamClient.fetchPermissions()
        // For the grant dialog's picker. Asked for alongside rather than on open, so the choices
        // are already there when somebody reaches for them.
        eamClient.fetchUserGroups("", 0, 500)
        eamClient.fetchUsers("", 0, 500)
    }

    onVisibleChanged: if (visible) refresh()
    onRoleNameChanged: {
        root.actionNote = ""
        root.holders = []
        if (visible) refresh()
    }

    Connections {
        target: eamClient

        function onRoleLoaded(name, role) {
            if (name !== root.roleName) return
            root.details = role
            root.error = ""
        }
        function onRoleLoadFailed(name, message) {
            if (name !== root.roleName) return
            root.error = message
        }
        function onRoleGrantsLoaded(role, grants) {
            if (role !== root.roleName) return
            root.holdersLoading = false
            root.holdersError = ""
            root.holders = grants
        }
        function onRoleGrantsFailed(role, message) {
            if (role !== root.roleName) return
            root.holdersLoading = false
            root.holdersError = message
        }
        function onPermissionsLoaded(permissions, modules, unbindable) {
            root.permissions = permissions
        }
        function onUserGroupsLoaded(list, total) {
            root.userGroups = list
        }
        function onUsersLoaded(list, total) {
            root.users = list
        }
        function onRoleGranted(principalErn, grantId) {
            // Only a grant started here: the same signal carries one made from a principal's own
            // page, which has nothing to do with what this page is showing.
            if (!grantDialog.saving) return
            grantDialog.saving = false
            grantDialog.close()
            root.actionNote = "Granted to " + grantDialog.grantedLabel + "."
            root.holdersLoading = true
            eamClient.fetchRoleGrants(root.roleName)
        }
        function onRoleGrantFailed(message) {
            if (!grantDialog.saving) return
            grantDialog.saving = false
            grantDialog.errorText = message
        }
        function onRoleUpdated(name, role) {
            if (name !== root.roleName) return
            const fromChip = root.savingPermissions
            root.savingPermissions = false
            editDialog.saving = false
            if (!fromChip) editDialog.close()
            root.details = role
            root.actionNote = (fromChip ? "Permission removed. " : "Saved. ")
                              + (root.holders.length > 0
                                 ? "The " + root.holders.length + " grant(s) holding this role are affected from "
                                   + "their next request."
                                 : "Nothing holds this role, so nobody is affected.")
        }
        function onRoleUpdateFailed(message) {
            // Routed by which of the two was in flight: putting a chip removal's failure into the
            // dialog would file it where it cannot be read, since the dialog is not open.
            if (root.savingPermissions) {
                root.savingPermissions = false
                root.error = message
                return
            }
            editDialog.saving = false
            editDialog.errorText = message
        }
        function onRoleCreated(name, role) {
            // Only a copy started here: the roles page creates roles too, and its dialog is not
            // this one.
            if (!editDialog.saving) return
            editDialog.saving = false
            editDialog.close()
            root.openRole(name, role)
        }
        function onRoleCreateFailed(message) {
            if (!editDialog.saving) return
            editDialog.saving = false
            editDialog.errorText = message
        }
        function onRoleDeleted(name) {
            if (name === root.roleName) root.back()
        }
        function onRoleDeleteFailed(message) {
            root.error = message
        }
        function onRoleRevoked(principalErn, grantId) {
            // A grant revoked from here is one of this role's own holders, so the list it came from
            // is the thing to re-read.
            root.holdersLoading = true
            eamClient.fetchRoleGrants(root.roleName)
        }
    }

    Dialog {
        id: editDialog
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
        property var selected: ({})

        // The same dialog in two modes, because it is the same decision either way: which
        // permissions. Copying is how a built-in gets narrowed - the role itself cannot be - and
        // the only difference is that it writes a new role instead of this one.
        property bool copying: false

        readonly property var selectedNames: Object.keys(editDialog.selected).sort()

        // Narrowed to what the role already holds when "only these" is on, which is what taking
        // permissions away needs: the full vocabulary is 190 entries and the role's own handful is
        // scattered through it.
        property bool onlySelected: false
        // What was selected when "only these" was switched on, rather than what is selected now:
        // filtering on the live set would make a row vanish the moment it was unticked, which is
        // both startling and the one moment you might want to tick it back.
        property var onlySelectedSnapshot: []

        readonly property var shown: {
            const needle = editDialog.filter.trim().toLowerCase()
            const source = editDialog.onlySelected ? editDialog.onlySelectedSnapshot : root.permissions
            if (needle.length === 0) return source
            return source.filter(p => String(p).toLowerCase().indexOf(needle) >= 0)
        }

        function toggle(permission, on) {
            const next = Object.assign({}, editDialog.selected)
            if (on) next[permission] = true
            else delete next[permission]
            editDialog.selected = next
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        function openFor(copying) {
            editDialog.copying = copying
            editDialog.open()
        }

        onOpened: {
            const selected = ({})
            for (const permission of root.rolePermissions) selected[permission] = true
            editDialog.selected = selected
            editDialog.filter = ""
            // A copy starts narrowed to what is being copied, because that is what is about to be
            // trimmed; an edit starts on the whole vocabulary, because adding is as likely as
            // taking away.
            editDialog.onlySelected = editDialog.copying
            editDialog.onlySelectedSnapshot = root.rolePermissions
            onlySelectedBox.checked = editDialog.copying
            editFilterField.text = ""
            copyNameField.text = editDialog.copying ? root.roleName + "-custom" : ""
            editDescriptionField.text = root.detail("description", "")
            editDialog.errorText = ""
            editDialog.saving = false
            if (editDialog.copying) copyNameField.forceActiveFocus()
        }

        contentItem: Column {
            width: editDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: editDialog.copying ? "Copy " + root.roleName : "Edit " + root.roleName
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    text: editDialog.copying
                          ? "A new role of your own, starting from this one's permissions. Untick what it should not "
                            + "have - granting something narrower is the whole point of a copy. " + root.roleName
                            + " itself is untouched, and nothing holding it changes."
                          : "Saving replaces the permission list rather than adding to it: anything unticked is taken "
                            + "away, which is the only way to narrow a role. "
                            + (root.holders.length > 0
                               ? root.holders.length + " grant(s) hold this role and are all affected."
                               : "Nothing holds this role yet.")
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                visible: editDialog.copying
                Text { text: "Name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: copyNameField
                    width: parent.width
                    placeholderText: "e.g. transfer-upload-only"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Description"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: editDescriptionField
                    width: parent.width
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

                    Row {
                        spacing: 12
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: "Permissions (" + editDialog.selectedNames.length + " selected)"
                            color: "#9aa1ac"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        CheckBox {
                            id: onlySelectedBox
                            text: "Only these"
                            checked: editDialog.onlySelected
                            font.pixelSize: 11
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            anchors.verticalCenter: parent.verticalCenter
                            onToggled: {
                                editDialog.onlySelectedSnapshot = editDialog.selectedNames
                                editDialog.onlySelected = checked
                            }
                        }
                    }

                    TextField {
                        id: editFilterField
                        width: 220
                        height: 34
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        placeholderText: "filter, e.g. eqs:"
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        onTextChanged: editDialog.filter = text
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 240
                    radius: 8
                    color: "#14161b"
                    border.color: "#2c313c"
                    border.width: 1
                    clip: true

                    ListView {
                        id: editPermissionList
                        anchors.fill: parent
                        anchors.margins: 8
                        model: editDialog.shown
                        clip: true
                        spacing: 2

                        delegate: CheckBox {
                            required property string modelData
                            width: editPermissionList.width
                            text: modelData
                            checked: editDialog.selected[modelData] === true
                            font.family: "monospace"
                            font.pixelSize: 12
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onToggled: editDialog.toggle(modelData, checked)
                        }
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: editDialog.selectedNames.length === 0 ? "#ffb545" : "#6b7280"
                    text: editDialog.selectedNames.length === 0
                          ? "A role has to keep at least one permission - one that grants nothing is a mistake "
                            + "rather than a narrower role. Delete the role instead."
                          : "Unticking removes on save: " + root.rolePermissions.length + " now, "
                            + editDialog.selectedNames.length + " after saving."
                }
            }

            Text {
                text: editDialog.errorText
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
                    onClicked: editDialog.close()
                }

                BusyIndicator {
                    running: editDialog.saving
                    visible: editDialog.saving
                    width: 22
                    height: 22
                    anchors.right: saveRoleButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: saveRoleButton
                    text: editDialog.copying ? "Create" : "Save"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !editDialog.saving && editDialog.selectedNames.length > 0
                             && (!editDialog.copying || copyNameField.text.trim().length > 0)
                    onClicked: {
                        editDialog.errorText = ""
                        editDialog.saving = true
                        root.actionNote = ""
                        if (editDialog.copying) {
                            eamClient.createRole(copyNameField.text.trim(), editDialog.selectedNames,
                                                 editDescriptionField.text.trim())
                        } else {
                            eamClient.updateRole(root.roleName, editDialog.selectedNames,
                                                 editDescriptionField.text.trim())
                        }
                    }
                }
            }
        }
    }

    // The other direction from the Roles tile on a principal's own page: there you pick a role for
    // a principal, here a principal for a role. Same call underneath.
    Dialog {
        id: grantDialog
        modal: true
        anchors.centerIn: parent
        width: 480
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""
        // Held across the call so the note afterwards can name what was granted to, rather than
        // repeating an ERN.
        property string grantedLabel: ""

        readonly property var selectedPrincipal: root.principalChoices.length > 0 && principalCombo.currentIndex >= 0
                                                 ? root.principalChoices[principalCombo.currentIndex] : null

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
            grantDialog.errorText = ""
            grantDialog.saving = false
            principalCombo.currentIndex = 0
            grantNamespacesField.text = "*"
            grantResourcesField.text = "*"
        }

        contentItem: Column {
            width: grantDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Grant " + root.roleName; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "To a user group or a user. A group is usually the better unit: every member holds what "
                          + "the group holds, and it keeps working as people come and go."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                id: principalColumn
                width: parent.width
                spacing: 6
                Text { text: "Principal"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: principalCombo
                    width: principalColumn.width
                    model: root.principalChoices.map(p => p.label)
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    font.family: "monospace"
                    text: grantDialog.selectedPrincipal ? grantDialog.selectedPrincipal.ern
                                                        : "No users or groups could be read."
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Namespaces"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: grantNamespacesField
                    width: parent.width
                    placeholderText: "* for every namespace, or a comma-separated list"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Resources"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: grantResourcesField
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
                text: grantDialog.errorText
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
                    onClicked: grantDialog.close()
                }

                BusyIndicator {
                    running: grantDialog.saving
                    visible: grantDialog.saving
                    width: 22
                    height: 22
                    anchors.right: grantRoleButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: grantRoleButton
                    text: "Grant"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !grantDialog.saving && grantDialog.selectedPrincipal !== null
                    onClicked: {
                        grantDialog.errorText = ""
                        grantDialog.saving = true
                        grantDialog.grantedLabel = grantDialog.selectedPrincipal.label
                        root.actionNote = ""
                        eamClient.grantRole(root.roleName, grantDialog.selectedPrincipal.ern,
                                            grantDialog.listFrom(grantNamespacesField.text),
                                            grantDialog.listFrom(grantResourcesField.text))
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
                text: root.holders.length > 0
                      ? "\"" + root.roleName + "\" is held by " + root.holders.length + " grant(s). The server "
                        + "refuses to delete a role anything still holds - revoke them below first."
                      : "\"" + root.roleName + "\". Nothing holds it, so nothing loses access."
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
                    enabled: root.holders.length === 0
                    onClicked: {
                        eamClient.deleteRole(root.roleName)
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
                    { label: "Roles", action: () => root.back() },
                    { label: root.roleName }
                ]
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.roleName
                    subtitle: root.detail("description", "")
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 10

                    // Offered for a built-in too: those cannot be edited, but they are exactly the
                    // ones most often handed out.
                    Button {
                        text: "+ Grant to…"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: grantDialog.open()
                    }

                    // What a built-in offers instead of Edit: the server will not change one, so
                    // narrowing it means starting a role of your own from its permissions.
                    Button {
                        text: "Copy to custom role…"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#c56bff"
                        visible: root.builtin
                        onClicked: editDialog.openFor(true)
                    }

                    Button {
                        text: "Edit…"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        // The built-ins are the same in every installation; the server refuses to
                        // redefine one, so the button is not offered for them.
                        visible: !root.builtin
                        onClicked: editDialog.openFor(false)
                    }
                    Button {
                        text: "Delete"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        visible: !root.builtin
                        onClicked: deleteDialog.open()
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: root.error.length > 0
                text: root.error
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "Permissions"
                    value: root.grantsEverything ? "all" : String(root.rolePermissions.length)
                    trend: root.grantsEverything ? "*:* - every action" : "across " + root.permissionModules.length + " module(s)"
                    trendUp: true
                    accent: "#4f8cff"
                }
                StatCard {
                    title: "Held by"
                    value: String(root.holders.length)
                    trend: root.holders.length > 0 ? "grant(s)" : "nothing holds it"
                    trendUp: root.holders.length > 0
                    accent: "#4cd97b"
                }
                StatCard {
                    title: "Kind"
                    value: root.builtin ? "built in" : "custom"
                    // A built-in is not a row in the account at all, which is why it cannot be
                    // edited and why it carries no dates.
                    trend: root.builtin ? "the same in every account" : "made here"
                    trendUp: true
                    accent: root.builtin ? "#9aa1ac" : "#c56bff"
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#4cd97b"
                font.pixelSize: 12
                visible: root.actionNote.length > 0
                text: root.actionNote
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Name"; value: root.roleName }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.detail("accountId", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.detail("region", "—") }
                        DetailField {
                            width: (identityCol.width - 48) / 3
                            label: "Created"
                            value: root.builtin ? "— (built in)" : DateFormat.format(root.detail("created", ""))
                        }
                        DetailField {
                            width: (identityCol.width - 48) / 3
                            label: "Modified"
                            value: root.builtin ? "— (built in)" : DateFormat.format(root.detail("modified", ""))
                        }
                    }

                    DetailField { width: identityCol.width; label: "Role ERN"; value: root.detail("ern", "—"); copyable: true }
                }
            }

            // ── Permissions ──────────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: permissionsCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: permissionsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Permissions"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 11
                        text: root.grantsEverything
                              ? "\"*:*\" - every action of every module a role can reach. EMM and EMD are not among "
                                + "them: they gate themselves, so no role names them."
                              : "An action is allowed when a role granted in the right account and namespace holds "
                                + "its \"<module>:<action>\" permission."
                    }

                    // Why there is no × on these, said where somebody would go looking for one. The
                    // rule is the server's - update-role refuses a built-in outright - and the way
                    // to something narrower is a role of your own, which is what the button does.
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.builtin
                        color: "#e0a458"
                        font.pixelSize: 11
                        text: "This role is built in: it is the same in every installation, and the server will not "
                              + "change or delete it - so its permissions cannot be removed here. To grant something "
                              + "narrower, copy it into a role of your own with fewer, and grant that instead."
                    }

                    Repeater {
                        model: root.permissionModules

                        delegate: Column {
                            id: moduleGroup
                            required property string modelData

                            width: permissionsCol.width
                            spacing: 6

                            Text {
                                text: moduleGroup.modelData.toUpperCase()
                                      + "  (" + root.permissionsByModule[moduleGroup.modelData].length + ")"
                                color: "#9aa1ac"
                                font.pixelSize: 12
                                font.bold: true
                            }

                            Flow {
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: root.permissionsByModule[moduleGroup.modelData]

                                    delegate: Rectangle {
                                        id: permissionChip
                                        required property string modelData
                                        radius: 6
                                        color: "#2c3648"
                                        height: 24
                                        width: chipRow.implicitWidth + 16

                                        // The × is the whole of "remove a permission": there is no
                                        // action for one, so it is an update-role carrying the list
                                        // without it - the same write the edit dialog makes, from
                                        // the one place where a single permission is in front of
                                        // you. Not offered on a built-in, which the server refuses
                                        // to change at all.
                                        Row {
                                            id: chipRow
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: permissionChip.modelData
                                                color: "#c4c9d1"
                                                font.pixelSize: 11
                                                font.family: "monospace"
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: !root.builtin
                                                text: "×"
                                                // Greyed out on the last one rather than hidden: a
                                                // role has to keep at least one permission, and the
                                                // reason is worth showing where the attempt is made.
                                                color: root.rolePermissions.length <= 1 ? "#4a5160"
                                                       : (removePermissionArea.containsMouse ? "#ff6b6b" : "#9aa1ac")
                                                font.pixelSize: 13
                                                font.bold: true

                                                MouseArea {
                                                    id: removePermissionArea
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    hoverEnabled: true
                                                    enabled: root.rolePermissions.length > 1 && !root.savingPermissions
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: root.removePermission(permissionChip.modelData)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Who holds it ─────────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: holdersCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: holdersCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Row {
                        spacing: 10
                        Text { text: "Held by"; color: "white"; font.pixelSize: 15; font.bold: true }
                        BusyIndicator {
                            running: root.holdersLoading
                            visible: root.holdersLoading
                            width: 18
                            height: 18
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 11
                        text: "Every grant naming this role. A principal is a user or a user group - the ERN says "
                              + "which - and revoking here takes the role away from that one principal, not from "
                              + "everybody."
                    }

                    Text {
                        visible: root.holdersError.length > 0
                        width: parent.width
                        text: root.holdersError
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: !root.holdersLoading && root.holdersError.length === 0 && root.holders.length === 0
                        text: "Nothing holds this role."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.holders

                        delegate: Rectangle {
                            id: holderRow
                            required property var modelData

                            width: holdersCol.width
                            height: holderCol.implicitHeight + 20
                            radius: 10
                            color: "#1b1e25"
                            border.color: "#2c313c"
                            border.width: 1

                            Column {
                                id: holderCol
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.margins: 10
                                spacing: 4

                                Item {
                                    width: parent.width
                                    height: principalText.implicitHeight

                                    Text {
                                        id: principalText
                                        text: holderRow.modelData.principal
                                        color: "#e5e7eb"
                                        font.pixelSize: 12
                                        font.family: "monospace"
                                        elide: Text.ElideMiddle
                                        width: parent.width - 70
                                    }

                                    Text {
                                        text: "Revoke"
                                        color: revokeHolderArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                        font.pixelSize: 11
                                        anchors.right: parent.right
                                        anchors.verticalCenter: principalText.verticalCenter

                                        MouseArea {
                                            id: revokeHolderArea
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: eamClient.revokeRole(holderRow.modelData.grantId,
                                                                            holderRow.modelData.principal)
                                        }
                                    }
                                }

                                Text {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    color: "#9aa1ac"
                                    font.pixelSize: 11
                                    text: "In " + (holderRow.modelData.namespaces.indexOf("*") >= 0
                                                   ? "every namespace" : holderRow.modelData.namespaces.join(", "))
                                          + " · over " + (holderRow.modelData.resources.indexOf("*") >= 0
                                                          ? "every resource" : holderRow.modelData.resources.join(", "))
                                          + " · granted " + DateFormat.format(holderRow.modelData.granted)
                                          + (String(holderRow.modelData.grantedBy).length > 0
                                             ? " by " + holderRow.modelData.grantedBy : "")
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
