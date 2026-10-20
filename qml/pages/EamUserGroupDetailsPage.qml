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

    // The two halves of root.users, which carries every user in the deployment flagged with
    // whether they are in this group. The table below shows the members; the add dialog offers
    // what is left, so neither has to filter the same list twice.
    readonly property var members: root.users.filter(u => u.member)
    readonly property var nonMembers: root.users.filter(u => !u.member)

    function memberCount() {
        return root.members.length
    }

    // Filter, page and sort for the member table. All client-side: fetchGroupMembers() answers
    // with every user at once and EAM has no paged read of a group's membership, so the table is
    // handed one page's worth out of what is already in hand - the same arrangement
    // EapApplicationDetailsPage uses for its instance pool.
    property string memberFilter: ""
    property int memberPageIndex: 0
    property int memberPageSize: 10
    property string memberSortColumn: "userId"
    property bool memberSortAscending: true

    readonly property var filteredMembers: {
        const needle = root.memberFilter.toLowerCase()
        const matched = needle.length === 0 ? root.members.slice() : root.members.filter(u =>
            String(u.userId).toLowerCase().indexOf(needle) >= 0
            || String(u.email).toLowerCase().indexOf(needle) >= 0
            // By ERN too, because that is what the grants tiles elsewhere name a principal by -
            // so an ERN copied from one of those finds its user here.
            || String(u.ern).toLowerCase().indexOf(needle) >= 0)

        const key = root.memberSortColumn
        const direction = root.memberSortAscending ? 1 : -1
        // Every column here is text, so one comparison covers all of them.
        return matched.sort((a, b) => String(a[key]).localeCompare(String(b[key])) * direction)
    }

    // Clamped rather than left where it was: removing the last member of the last page would
    // otherwise leave the table showing nothing with no way to tell why.
    readonly property int memberPageCount: Math.max(1, Math.ceil(root.filteredMembers.length / root.memberPageSize))
    readonly property int clampedMemberPage: Math.min(root.memberPageIndex, root.memberPageCount - 1)
    readonly property var memberPage: root.filteredMembers.slice(
        root.clampedMemberPage * root.memberPageSize,
        root.clampedMemberPage * root.memberPageSize + root.memberPageSize)

    // The clamp above keeps the wrong page from being shown; this keeps the stored index from
    // staying out of range behind it, so a group that shrank to one page and then grew again does
    // not jump back to page two on its own.
    onFilteredMembersChanged: {
        if (root.memberPageIndex > root.memberPageCount - 1)
            root.memberPageIndex = root.memberPageCount - 1
    }

    readonly property var memberColumns: [
        { title: "User ID", key: "userId", fill: true },
        // A user registered without one shows a dash rather than an empty cell, which reads as a
        // rendering fault rather than as an absent address.
        { title: "Email", key: "email",
          formatter: function (value) { return String(value).length > 0 ? value : "—" } },
        // Searchable but not shown: an ERN is wider than the rest of the row put together, and
        // the two columns above already say who this is. Same choice the users table makes.
        { title: "User ERN", key: "ern", hidden: true }
    ]

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

            Breadcrumb {
                width: parent.width
                leaf: root.groupName
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

            // A group is a principal in its own right, and usually the better one to grant to: a
            // grant written once for the people who do a job outlives whoever currently does it.
            // Every member is checked against these as well as against their own grants.
            RoleGrants {
                width: parent.width
                loggedIn: root.loggedIn
                principalErn: root.groupErn
                principalLabel: root.groupName
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

                    Item {
                        width: parent.width
                        height: membersHeading.implicitHeight

                        Text {
                            id: membersHeading
                            text: "Members"
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Button {
                            text: "Add Member…"
                            anchors.right: parent.right
                            anchors.verticalCenter: membersHeading.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            // Nothing to offer once everybody is already in: the dialog would open
                            // on an empty list, which says less than a disabled button does.
                            enabled: root.nonMembers.length > 0
                            onClicked: addMemberDialog.open()
                        }
                    }

                    Text {
                        width: parent.width
                        text: "The users in this group. Adding or removing one here is the same grant "
                              + "EamUserDetailsPage edits from the user's side."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    DataTable {
                        width: parent.width
                        columns: root.memberColumns
                        rows: root.memberPage
                        totalCount: root.filteredMembers.length
                        pageSize: root.memberPageSize
                        pageIndex: root.clampedMemberPage
                        // Never true: the membership arrives with the page's own read, and a
                        // spinner here would only repeat what the page already shows.
                        loading: false
                        error: root.usersError
                        searchPlaceholder: "Filter by user, email or ERN..."
                        emptyText: root.memberFilter.length > 0
                                   ? "No member matches that."
                                   : "This group has no members yet."
                        rowsClickable: false
                        sortKey: root.memberSortColumn
                        sortAscending: root.memberSortAscending

                        onSearchChanged: (text) => {
                            root.memberFilter = text
                            root.memberPageIndex = 0
                        }
                        onRefreshRequested: root.refresh()
                        onPageChanged: (index) => { root.memberPageIndex = index }
                        // Back to the first page: page four of fifty-row pages is not page four of
                        // ten-row pages.
                        onPageSizeRequested: (size) => {
                            root.memberPageSize = size
                            root.memberPageIndex = 0
                        }
                        onSortRequested: (key, ascending) => {
                            root.memberSortColumn = key
                            root.memberSortAscending = ascending
                        }

                        contextMenuActions: [
                            {
                                text: "Remove from Group",
                                action: function (row) {
                                    root.usersError = ""
                                    eamClient.removeUserFromGroup(root.groupErn, row.ern)
                                }
                            }
                        ]
                    }
                }
            }
        }
    }

    // Stays open after each add, because adding several people to a group is one job rather than
    // several: the row leaves the list as soon as the membership comes back, so the list itself is
    // the record of what has been done.
    Dialog {
        id: addMemberDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string filter: ""

        readonly property var candidates: {
            const needle = addMemberDialog.filter.toLowerCase()
            if (needle.length === 0)
                return root.nonMembers.slice()
            return root.nonMembers.filter(u =>
                String(u.userId).toLowerCase().indexOf(needle) >= 0
                || String(u.email).toLowerCase().indexOf(needle) >= 0
                || String(u.ern).toLowerCase().indexOf(needle) >= 0)
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            addMemberDialog.filter = ""
            candidateFilterField.text = ""
            candidateFilterField.forceActiveFocus()
        }

        contentItem: Column {
            width: addMemberDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Member"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    width: parent.width
                    text: "Everyone not already in \"" + root.groupName + "\". Click a user to add them."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            TextField {
                id: candidateFilterField
                width: parent.width
                placeholderText: "Filter by user, email or ERN..."
                Material.accent: "#4f8cff"
                selectByMouse: true
                onTextChanged: addMemberDialog.filter = text
            }

            // The page's own error line is behind this dialog while it is modal, so a refused add
            // would otherwise leave the row simply not disappearing and nothing to say why.
            Text {
                visible: root.usersError.length > 0
                width: parent.width
                text: root.usersError
                color: "#ff6b6b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Text {
                visible: addMemberDialog.candidates.length === 0
                width: parent.width
                text: root.nonMembers.length === 0
                      ? "Every user in the deployment is already in this group."
                      : "No user matches that."
                color: "#6b7280"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // Bounded rather than grown to fit: a deployment's whole user list would push the
            // buttons below off the bottom of the screen.
            ListView {
                id: candidateList
                width: parent.width
                height: Math.min(addMemberDialog.candidates.length * 44, 264)
                visible: addMemberDialog.candidates.length > 0
                clip: true
                model: addMemberDialog.candidates
                ScrollBar.vertical: ScrollBar {}

                delegate: Rectangle {
                    id: candidateRow
                    required property var modelData

                    width: candidateList.width - (candidateList.contentHeight > candidateList.height ? 12 : 0)
                    height: 44
                    radius: 8
                    color: candidateArea.containsMouse ? "#2c3648" : "transparent"

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        Text {
                            width: parent.width
                            text: candidateRow.modelData.userId
                            color: "#e5e7eb"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: String(candidateRow.modelData.email).length > 0
                                  ? candidateRow.modelData.email : candidateRow.modelData.ern
                            color: "#6b7280"
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                        }
                    }

                    MouseArea {
                        id: candidateArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.usersError = ""
                            eamClient.addUserToGroup(root.groupErn, candidateRow.modelData.ern)
                        }
                    }
                }
            }

            Button {
                text: "Done"
                anchors.right: parent.right
                highlighted: true
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
                onClicked: addMemberDialog.close()
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
