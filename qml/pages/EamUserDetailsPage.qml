import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// What EAM actually lets an admin change about an existing user: group membership and namespace
// grants. Everything else on the user record (email, region, home account, password, the admin
// flag) is fixed at registration - there is no "update-user" action server-side - so those are
// shown read-only rather than as fields that would silently do nothing.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string userId: ""
    property string userErn: ""
    property var details: ({})

    // Every group in the deployment, each flagged with whether this user is in it.
    property var groups: []
    property string groupsError: ""

    // Local copy of details.accountGrants. There is no "get user" action to re-read after a
    // mutation, and re-running the users list would replace what the users table is showing, so
    // confirmed changes are mirrored here instead (same approach as EkmKeyDetailsPage's tags).
    property var grants: []
    property string grantsError: ""

    property bool deleting: false

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function grantsFromDetails() {
        const source = root.detail("accountGrants", [])
        const copy = []
        for (const grant of source) {
            copy.push({
                accountId: grant.accountId,
                namespaces: (grant.namespaces || []).slice(),
                isAdmin: grant.isAdmin === true,
                granted: grant.granted
            })
        }
        return copy
    }

    function namespaceGrantCount() {
        let count = 0
        for (const grant of root.grants) count += grant.namespaces.length
        return count
    }

    function memberGroupCount() {
        return root.groups.filter(g => g.member).length
    }

    // Mirrors a grant/revoke the server has already confirmed. Rebuilds the list rather than
    // mutating it in place, so the "var" property change notification actually fires.
    function applyGrant(accountId, namespaceName, granted) {
        const next = []
        let found = false
        for (const grant of root.grants) {
            if (grant.accountId !== accountId) {
                next.push(grant)
                continue
            }
            found = true
            const namespaces = grant.namespaces.filter(n => n !== namespaceName)
            if (granted) namespaces.push(namespaceName)
            // An account whose last namespace was revoked drops out entirely, matching what the
            // server does to the stored grant.
            if (namespaces.length > 0)
                next.push({ accountId: accountId, namespaces: namespaces, isAdmin: grant.isAdmin, granted: grant.granted })
        }
        if (granted && !found)
            next.push({ accountId: accountId, namespaces: [namespaceName], isAdmin: false, granted: "" })
        root.grants = next
    }

    function refresh() {
        if (!root.loggedIn || root.userId.length === 0)
            return
        root.groupsError = ""
        eamClient.fetchGroupMemberships(root.userId)
    }

    onDetailsChanged: root.grants = grantsFromDetails()
    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Connections {
        target: eamClient

        function onGroupMembershipsLoaded(userId, list) {
            if (userId !== root.userId) return
            root.groups = list
            root.groupsError = ""
        }
        function onGroupMembershipsFailed(message) {
            root.groupsError = message
        }
        function onGroupMembershipChanged(groupErn, userErn, member) {
            if (userErn !== root.userErn) return
            // Re-read rather than patch: membership is stored on the group, so the group list is
            // the authority on it and one extra call keeps this honest.
            root.refresh()
        }
        function onGroupMembershipFailed(message) {
            root.groupsError = message
            root.refresh()
        }

        function onNamespaceAccessChanged(userErn, accountId, namespaceName, granted) {
            if (userErn !== root.userErn) return
            grantDialog.saving = false
            grantDialog.close()
            root.grantsError = ""
            root.applyGrant(accountId, namespaceName, granted)
        }
        function onNamespaceAccessFailed(message) {
            grantDialog.saving = false
            if (grantDialog.opened) grantDialog.errorText = message
            else root.grantsError = message
        }

        // deleteUser() reports success by asking the users table to reload - there is no
        // per-user deleted signal - so only treat it as ours while a delete is in flight.
        function onUsersReload() {
            if (!root.deleting) return
            root.deleting = false
            root.back()
        }
        function onUsersFailed(message) {
            if (!root.deleting) return
            root.deleting = false
            root.grantsError = message
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
                text: "‹ Back to Users"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.userId
                    subtitle: root.userErn
                }

                Button {
                    text: "Delete User"
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

                StatCard { title: "Account ID"; value: root.detail("accountId", "—"); trend: "home account"; trendUp: true; accent: "#4f8cff" }
                StatCard { title: "Region"; value: root.detail("region", "—"); trend: "registered in"; trendUp: true; accent: "#c56bff" }
                StatCard {
                    title: "Group Memberships"
                    value: String(root.memberGroupCount())
                    trend: "of " + root.groups.length + " groups"
                    trendUp: root.memberGroupCount() > 0
                    accent: "#4cd97b"
                    width: 440
                }
                StatCard {
                    title: "Namespace Grants"
                    value: String(root.namespaceGrantCount())
                    trend: root.grants.length + " account(s)"
                    trendUp: root.namespaceGrantCount() > 0
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "User ID"; value: root.userId }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Email"; value: root.detail("email", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.detail("accountId", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.detail("region", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    DetailField { width: identityCol.width; label: "User ERN"; value: root.userErn; copyable: true }

                    Text {
                        width: parent.width
                        text: "Email, region, home account and password are set at registration and cannot be changed here."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: groupsCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: groupsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Group Membership"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        visible: root.groupsError.length > 0
                        width: parent.width
                        text: root.groupsError
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.groups.length === 0 && root.groupsError.length === 0
                        text: "No user groups exist yet."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.groups
                        delegate: Row {
                            id: groupDelegate
                            required property var modelData

                            width: root.width - 96
                            height: 34
                            spacing: 12

                            Column {
                                id: groupLabels
                                width: groupDelegate.width - 58
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    text: groupDelegate.modelData.name
                                    color: "#e5e7eb"
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                    width: groupLabels.width
                                }
                                Text {
                                    text: groupDelegate.modelData.description.length > 0
                                          ? groupDelegate.modelData.description
                                          : groupDelegate.modelData.ern
                                    color: "#6b7280"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    width: groupLabels.width
                                }
                            }

                            ToggleSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: groupDelegate.modelData.member
                                onToggled: (checked) => {
                                    root.groupsError = ""
                                    if (checked) eamClient.addUserToGroup(groupDelegate.modelData.ern, root.userErn)
                                    else eamClient.removeUserFromGroup(groupDelegate.modelData.ern, root.userErn)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: grantsCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: grantsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: grantsHeaderRow.implicitHeight

                        Row {
                            id: grantsHeaderRow
                            Text { text: "Namespace Access"; color: "white"; font.pixelSize: 15; font.bold: true }
                        }

                        Button {
                            text: "+ Grant"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: grantsHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: grantDialog.open()
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Namespaces this user may reach in addition to their home account. Granting requires "
                              + "administrator rights on the account being granted."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.grantsError.length > 0
                        width: parent.width
                        text: root.grantsError
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.grants.length === 0
                        text: "No additional namespace grants."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.grants
                        delegate: Column {
                            id: grantDelegate
                            required property var modelData

                            // Each chip carries its own account, so the inner delegate needs
                            // nothing from this one's scope to know what a revoke would target.
                            readonly property var chipModel: modelData.namespaces.map(
                                n => ({ accountId: grantDelegate.modelData.accountId, name: n }))

                            width: grantsCol.width
                            spacing: 8

                            Row {
                                spacing: 8
                                Text {
                                    text: "Account " + grantDelegate.modelData.accountId
                                    color: "#c4c9d1"
                                    font.pixelSize: 12
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Rectangle {
                                    visible: grantDelegate.modelData.isAdmin
                                    radius: 6
                                    color: "#3a2f1c"
                                    height: 20
                                    width: adminLabel.implicitWidth + 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        id: adminLabel
                                        anchors.centerIn: parent
                                        text: "account admin"
                                        color: "#ffb545"
                                        font.pixelSize: 10
                                    }
                                }
                            }

                            Flow {
                                width: parent.width
                                spacing: 8

                                Repeater {
                                    model: grantDelegate.chipModel
                                    delegate: Rectangle {
                                        id: chip
                                        required property var modelData

                                        radius: 8
                                        color: "#2c3648"
                                        height: 26
                                        width: chipRow.implicitWidth + 20

                                        Row {
                                            id: chipRow
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: chip.modelData.name
                                                color: "#c4c9d1"
                                                font.pixelSize: 11
                                            }

                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "×"
                                                color: revokeArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                                font.pixelSize: 13
                                                font.bold: true

                                                MouseArea {
                                                    id: revokeArea
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.grantsError = ""
                                                        eamClient.revokeNamespaceAccess(root.userErn, chip.modelData.accountId, chip.modelData.name)
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
            }
        }
    }

    Dialog {
        id: grantDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            grantAccountField.text = root.detail("accountId", "")
            grantNamespaceField.text = ""
            grantDialog.errorText = ""
            grantDialog.saving = false
            grantNamespaceField.forceActiveFocus()
        }

        contentItem: Column {
            width: grantDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Grant Namespace Access"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Gives " + root.userId + " access to one namespace of an account. The namespace must already exist."
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
                    id: grantAccountField
                    width: parent.width
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: grantNamespaceField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Namespace"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: grantNamespaceField
                    width: parent.width
                    placeholderText: "e.g. development"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (grantButton.enabled) grantButton.clicked()
                }
                Text {
                    text: grantDialog.errorText
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
                    onClicked: grantDialog.close()
                }

                BusyIndicator {
                    running: grantDialog.saving
                    visible: grantDialog.saving
                    width: 22
                    height: 22
                    anchors.right: grantButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: grantButton
                    text: "Grant"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !grantDialog.saving && grantAccountField.text.trim().length > 0
                             && grantNamespaceField.text.trim().length > 0
                    onClicked: {
                        grantDialog.errorText = ""
                        grantDialog.saving = true
                        eamClient.grantNamespaceAccess(root.userErn, grantAccountField.text.trim(), grantNamespaceField.text.trim())
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
                Text { text: "Delete User"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Permanently deletes \"" + root.userId + "\", including their access keys and grants. "
                          + "Group memberships are not cleaned up server-side. This cannot be undone."
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
                        eamClient.deleteUser(root.userId)
                    }
                }
            }
        }
    }
}
