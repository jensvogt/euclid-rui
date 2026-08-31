import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// The group-side view of the same relationship EamUserDetailsPage edits from the user side:
// membership. Name, description, account and region are fixed at creation - EAM has no
// "update-user-group" action - so they are shown read-only rather than as fields that would
// silently do nothing.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string groupName: ""
    property string groupErn: ""
    property var details: ({})

    // Every user in the deployment, each flagged with whether they are in this group.
    property var users: []
    property string usersError: ""
    property bool deleting: false

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function memberCount() {
        return root.users.filter(u => u.member).length
    }

    function refresh() {
        if (!root.loggedIn || root.groupErn.length === 0)
            return
        root.usersError = ""
        eamClient.fetchGroupMembers(root.groupErn)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()
    onGroupErnChanged: if (visible) refresh()

    Connections {
        target: eamClient

        function onGroupMembersLoaded(groupErn, list) {
            if (groupErn !== root.groupErn) return
            root.users = list
            root.usersError = ""
        }
        function onGroupMembersFailed(message) {
            root.usersError = message
        }
        // Shared with EamUserDetailsPage - that page filters the signal by user, this one by
        // group, so the same add/remove calls serve both directions of the relationship.
        function onGroupMembershipChanged(groupErn, userErn, member) {
            if (groupErn !== root.groupErn) return
            root.refresh()
        }
        function onGroupMembershipFailed(message) {
            root.usersError = message
            root.refresh()
        }

        // deleteUserGroup() reports success by asking the groups table to reload - there is no
        // per-group deleted signal - so only treat it as ours while a delete is in flight.
        function onUserGroupsReload() {
            if (!root.deleting) return
            root.deleting = false
            root.back()
        }
        function onUserGroupsFailed(message) {
            if (!root.deleting) return
            root.deleting = false
            root.usersError = message
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
                text: "‹ Back to User Groups"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.groupName
                    subtitle: root.groupErn
                }

                Button {
                    text: "Delete Group"
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

                StatCard { title: "Account ID"; value: root.detail("accountId", "—"); trend: "owning account"; trendUp: true; accent: "#4f8cff" }
                StatCard { title: "Region"; value: root.detail("region", "—"); trend: "created in"; trendUp: true; accent: "#c56bff" }
                StatCard {
                    title: "Members"
                    value: String(root.memberCount())
                    trend: "of " + root.users.length + " users"
                    trendUp: root.memberCount() > 0
                    accent: "#4cd97b"
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Name"; value: root.groupName }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.detail("accountId", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.detail("region", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    DetailField {
                        width: identityCol.width
                        label: "Description"
                        value: root.detail("description", "").length > 0 ? root.detail("description", "") : "—"
                    }
                    DetailField { width: identityCol.width; label: "Group ERN"; value: root.groupErn; copyable: true }

                    Text {
                        width: parent.width
                        text: "Name and description are set when the group is created and cannot be changed here."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: membersCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: membersCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Members"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        text: "Every user in the deployment; switch one on to add them to this group."
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
                        visible: root.users.length === 0 && root.usersError.length === 0
                        text: "No users exist yet."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.users
                        delegate: Row {
                            id: userDelegate
                            required property var modelData

                            width: root.width - 96
                            height: 34
                            spacing: 12

                            Column {
                                id: userLabels
                                width: userDelegate.width - 58
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
                                    text: userDelegate.modelData.email.length > 0
                                          ? userDelegate.modelData.email
                                          : userDelegate.modelData.ern
                                    color: "#6b7280"
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    width: userLabels.width
                                }
                            }

                            ToggleSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: userDelegate.modelData.member
                                onToggled: (checked) => {
                                    root.usersError = ""
                                    if (checked) eamClient.addUserToGroup(root.groupErn, userDelegate.modelData.ern)
                                    else eamClient.removeUserFromGroup(root.groupErn, userDelegate.modelData.ern)
                                }
                            }
                        }
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
                Text { text: "Delete User Group"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Permanently deletes \"" + root.groupName + "\". Its " + root.memberCount()
                          + " member(s) are not deleted, they just lose this membership. This cannot be undone."
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
                        eamClient.deleteUserGroup(root.groupName)
                    }
                }
            }
        }
    }
}
