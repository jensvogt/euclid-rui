import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// What EAM actually lets an admin change about an existing user: group membership, namespace
// grants, and the password - the last through its own action rather than as a field, because
// replacing a password is not editing a record. Everything else (email, region, home account, the
// admin flag) is fixed at registration - there is no "update-user" action server-side - so those
// are shown read-only rather than as fields that would silently do nothing.
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

    // Errors from the page's own actions (deleting the user), not from the grants tile - that one
    // reads and reports its own.
    property string grantsError: ""

    property bool deleting: false

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function memberGroupCount() {
        return root.groups.filter(g => g.member).length
    }

    function refresh() {
        if (!root.loggedIn || root.userId.length === 0)
            return
        root.groupsError = ""
        eamClient.fetchGroupMemberships(root.userId)
    }

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

            Breadcrumb {
                width: parent.width
                segments: [
                    { label: "Users", action: () => root.back() },
                    { label: root.userId }
                ]
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.userId
                    subtitle: root.userErn
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 12

                    Button {
                        text: "Change Password…"
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        enabled: !root.deleting && root.userId.length > 0
                        onClicked: {
                            changePasswordDialog.userId = root.userId
                            changePasswordDialog.open()
                        }
                    }

                    Button {
                        text: "Delete User"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        enabled: !root.deleting
                        onClicked: deleteDialog.open()
                    }
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
                    // Counted off the tile below, which is the thing that actually read them - a
                    // user carries no grants of their own any more, they are records that name a
                    // principal.
                    title: "Roles Granted"
                    value: String(grantsTile.grants.length)
                    trend: grantsTile.grants.length > 0 ? "see Roles below" : "nothing is permitted"
                    trendUp: grantsTile.grants.length > 0
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
                        text: "Email, region and home account are set at registration and cannot be changed here. "
                              + "The password can be replaced with \"Change Password\" above."
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

            // What this user may do, as euclid decides it now: role grants. The tile this replaced
            // read details.accountGrants, a field the server stopped sending when grants became
            // records of their own - so it showed an empty list whatever the user actually held.
            RoleGrants {
                id: grantsTile
                width: parent.width
                loggedIn: root.loggedIn
                principalErn: root.userErn
                principalLabel: root.userId
            }
        }
    }

    ChangePasswordDialog {
        id: changePasswordDialog
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
