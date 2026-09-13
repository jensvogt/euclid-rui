import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// One transfer server definition. The two states are shown side by side on purpose: start and stop
// only write `desiredState`, and euclid-mgr's reconciler is what eventually makes `state` match -
// a server stuck at RUNNING/STOPPED is the module telling you it could not start.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string serverId: ""
    property var details: ({})

    property string error: ""
    property bool deleting: false
    property bool savingAccess: false

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    // Not "state": QQuickItem already has one (the Item state machine), and shadowing it
    // silently changes what every state-related binding on this page means.
    readonly property string serverState: detail("state", "")
    readonly property string desiredState: detail("desiredState", "")
    readonly property bool ftp: detail("protocol", "") === "FTP"

    // "update-server" replaces each field it is given, so adding or removing one user means
    // sending the resulting list - the server has no add/remove for these.
    function addUser(userId) {
        const users = root.detail("userIds", []).slice()
        if (users.indexOf(userId) >= 0) {
            root.error = "\"" + userId + "\" is already allowed to log in."
            return
        }
        users.push(userId)
        root.error = ""
        root.savingAccess = true
        etsClient.updateServer(root.serverId, { userIds: users })
    }

    function removeUser(userId) {
        root.error = ""
        root.savingAccess = true
        etsClient.updateServer(root.serverId, { userIds: root.detail("userIds", []).filter(u => u !== userId) })
    }

    // Every EAM user group, for the picker and for working out who a group already covers.
    // TransferServer::userGroups holds names rather than ERNs - see TransferAuthenticator, which
    // resolves each with findUserGroupByName - so a name is what goes in the list.
    property var eamGroups: []

    function groupMembers(name) {
        const group = root.eamGroups.find(g => g.name === name)
        return group ? group.userIds.map(u => String(u)) : []
    }

    // Users listed individually who are already members of the named group. Access is a union, so
    // each of these is allowed twice over - and the individual entry is the one that goes stale,
    // because it stays behind when somebody leaves the group.
    function usersCoveredBy(name) {
        const members = root.groupMembers(name)
        return root.detail("userIds", []).map(u => String(u)).filter(u => members.indexOf(u) >= 0)
    }

    function addGroup(name) {
        const groups = root.detail("userGroups", []).map(g => String(g))
        if (groups.indexOf(name) >= 0) {
            root.error = "\"" + name + "\" is already allowed to log in."
            return
        }
        groups.push(name)

        // Written in the same call as the group that makes them redundant, so the list is never
        // briefly saying two things at once.
        const covered = root.usersCoveredBy(name)
        const users = root.detail("userIds", []).map(u => String(u)).filter(u => covered.indexOf(u) < 0)

        root.error = ""
        root.savingAccess = true
        etsClient.updateServer(root.serverId, { userGroups: groups, userIds: users })
    }

    function removeGroup(name) {
        root.error = ""
        root.savingAccess = true
        // Only the group. Whoever it was letting in loses access unless they are listed some other
        // way - putting them all back as individuals would be a different decision, and not one a
        // × should make on somebody's behalf.
        etsClient.updateServer(root.serverId,
                               { userGroups: root.detail("userGroups", []).filter(g => String(g) !== name) })
    }

    // ── Default directories ──────────────────────────────────────────────────

    // The same normalisation TransferPaths::HomePrefix applies before a key is built: empty, "."
    // and ".." segments are dropped and the slashes collapsed, so "/incoming//mix/" and
    // "incoming/mix" are one directory and no ".." can survive into a key. Mirrored here so the
    // page can show what will actually be stored rather than refuse what would have been fine.
    function normalisePath(path) {
        const segments = String(path).split("/").filter(s => s.length > 0 && s !== "." && s !== "..")
        return segments.length > 0 ? segments.join("/") : ""
    }

    // What a directory becomes for one client: the home template with {user} substituted, then the
    // directory under it. The example user is a real one off this server where there is one,
    // because "jvo/incoming/mix/" says more than "{user}/incoming/mix/".
    readonly property string exampleUser: {
        const users = root.detail("userIds", [])
        if (users.length > 0) return String(users[0])
        const groups = root.detail("userGroups", [])
        for (const group of groups) {
            const members = root.groupMembers(String(group))
            if (members.length > 0) return members[0]
        }
        return "{user}"
    }

    function resolvedPath(directory) {
        const home = root.normalisePath(String(root.detail("homeDirectory", "")).replace(/\{user\}/g, root.exampleUser))
        const under = root.normalisePath(directory)
        if (under.length === 0) return ""
        return (home.length > 0 ? home + "/" : "") + under + "/"
    }

    function addDirectory(path) {
        const normalised = root.normalisePath(path)
        if (normalised.length === 0) {
            root.error = "That is not a directory: it normalises to nothing."
            return
        }
        const directories = root.detail("directories", []).map(d => String(d))
        if (directories.indexOf(normalised) >= 0) {
            root.error = "\"" + normalised + "\" is already created at login."
            return
        }
        directories.push(normalised)
        root.error = ""
        root.savingDirectories = true
        etsClient.updateServer(root.serverId, { directories: directories })
    }

    function removeDirectory(path) {
        root.error = ""
        root.savingDirectories = true
        // Only the definition. What is already in the bucket stays: these are ordinary objects by
        // the time they exist, and forgetting to create one again is not a reason to delete what
        // clients have since put in it.
        etsClient.updateServer(root.serverId,
                               { directories: root.detail("directories", []).filter(d => String(d) !== path) })
    }

    property bool savingDirectories: false

    function serverStateColor(value) {
        if (value === "RUNNING") return "#4cd97b"
        if (value === "STOPPED") return "#ffb545"
        return "#9aa1ac"
    }

    function refresh() {
        if (!root.loggedIn || root.serverId.length === 0)
            return
        root.error = ""
        // No per-server refresh is needed beyond the list: "get-server" returns the same fields,
        // and the list is what keeps every other view in sync.
        etsClient.fetchServers("")
        // The groups this server could allow, and who is in each. Needed for the picker and to work
        // out which individually listed users a group already covers.
        eamClient.fetchUserGroups("", 0, 500)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Worth polling here specifically: after a start or stop this page is where the user is
        // watching for `state` to catch up with `desiredState`.
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: eamClient
        function onUserGroupsLoaded(list, total) {
            root.eamGroups = list
        }
    }

    Connections {
        target: etsClient

        function onServersLoaded(list, total) {
            for (const server of list) {
                if (server.serverId !== root.serverId) continue
                root.details = server
                root.error = ""
                return
            }
            // Gone from the list: deleted, by this page or from somewhere else.
            if (root.deleting) {
                root.deleting = false
                root.back()
            }
        }
        function onServersFailed(message) {
            root.error = message
        }
        function onServerStateFailed(message) {
            root.deleting = false
            root.savingAccess = false
            root.savingDirectories = false
            if (addDirectoryDialog.opened) addDirectoryDialog.errorText = message
            else if (addUserDialog.opened) addUserDialog.errorText = message
            else if (addGroupDialog.opened) addGroupDialog.errorText = message
            else root.error = message
        }
        function onServerStateChanged(serverId, desiredState) {
            if (serverId !== root.serverId) return
            root.savingAccess = false
            root.savingDirectories = false
            addUserDialog.close()
            addGroupDialog.close()
            addDirectoryDialog.close()
            // The change is already stored; re-reading is what puts the new list on screen.
            root.refresh()
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
                    { label: "Transfer Servers", action: () => root.back() },
                    { label: root.serverId }
                ]
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.serverId
                    subtitle: root.detail("ern", "")
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: "Start"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4cd97b"
                        enabled: root.desiredState !== "RUNNING"
                        onClicked: {
                            root.error = ""
                            etsClient.startServer(root.serverId)
                        }
                    }

                    Button {
                        text: "Stop"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ffb545"
                        enabled: root.desiredState === "RUNNING"
                        onClicked: {
                            root.error = ""
                            etsClient.stopServer(root.serverId)
                        }
                    }

                    Button {
                        text: "Delete"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        enabled: !root.deleting
                        onClicked: deleteDialog.open()
                    }
                }
            }

            Text {
                visible: root.error.length > 0
                width: parent.width
                text: root.error
                color: "#ff6b6b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "State"
                    value: root.serverState.length > 0 ? root.serverState : "—"
                    trend: root.serverState === root.desiredState ? "as requested" : "reconciling to " + root.desiredState
                    trendUp: root.serverState === "RUNNING"
                    accent: root.serverStateColor(root.serverState)
                    width: 440
                }
                StatCard {
                    title: "Endpoint"
                    value: root.detail("address", "—") + ":" + root.detail("port", 0)
                    trend: root.detail("protocol", "—")
                    trendUp: true
                    accent: "#4f8cff"
                    width: 440
                }
                StatCard {
                    title: "Bucket"
                    value: root.detail("bucketName", "—")
                    trend: "storage behind it"
                    trendUp: true
                    accent: "#c56bff"
                    width: 440
                }
                StatCard {
                    title: "Allowed"
                    value: String(root.detail("userIds", []).length + root.detail("userGroups", []).length)
                    trend: root.detail("userIds", []).length + " user(s), " + root.detail("userGroups", []).length + " group(s)"
                    trendUp: root.detail("userIds", []).length + root.detail("userGroups", []).length > 0
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

                    Text { text: "Definition"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (identityCol.width - 48) / 3; label: "Server ID"; value: root.serverId }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Protocol"; value: root.detail("protocol", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Bind address"; value: root.detail("address", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Port"; value: String(root.detail("port", 0)) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.detail("accountId", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.detail("region", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Requested state"; value: root.desiredState.length > 0 ? root.desiredState : "—" }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                        // FTP only - SFTP has no passive port range, and showing 6000-6100 next to
                        // an SFTP server would suggest ports it never opens.
                        DetailField {
                            visible: root.ftp
                            width: (identityCol.width - 48) / 3
                            label: "Passive ports"
                            value: root.detail("pasvMin", 0) + " – " + root.detail("pasvMax", 0)
                        }
                    }

                    DetailField { width: identityCol.width; label: "Bucket ERN"; value: root.detail("bucketErn", "—"); copyable: true }
                    DetailField { width: identityCol.width; label: "Server ERN"; value: root.detail("ern", "—"); copyable: true }
                }
            }

            Rectangle {
                width: parent.width
                height: accessCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: accessCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: accessHeaderRow.implicitHeight

                        Row {
                            id: accessHeaderRow
                            spacing: 10
                            Text { text: "Who may log in"; color: "white"; font.pixelSize: 15; font.bold: true }
                            BusyIndicator {
                                running: root.savingAccess
                                visible: root.savingAccess
                                width: 18
                                height: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: accessHeaderRow.verticalCenter
                            spacing: 8

                            Button {
                                text: "+ Add group"
                                flat: true
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                enabled: !root.savingAccess
                                onClicked: addGroupDialog.open()
                            }

                            Button {
                                text: "+ Add user"
                                highlighted: true
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                enabled: !root.savingAccess
                                onClicked: addUserDialog.open()
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: "EAM users listed directly, plus every member of the listed groups - a union, not an "
                              + "intersection. A running server keeps its current list until the reconciler next "
                              + "restarts it. Adding a group drops anyone it already covers from the individual list, "
                              + "since a second way in is one more thing to remember to take away."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.detail("userIds", []).length === 0 && root.detail("userGroups", []).length === 0
                        text: "Nobody is allowed to log in yet."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Flow {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.detail("userIds", [])
                            delegate: Rectangle {
                                id: userChip
                                required property string modelData

                                radius: 8
                                color: "#2c3648"
                                height: 26
                                width: userChipRow.implicitWidth + 20
                                Row {
                                    id: userChipRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        id: userChipText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "user · " + userChip.modelData
                                        color: "#c4c9d1"
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "×"
                                        color: removeUserArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                        font.pixelSize: 13
                                        font.bold: true

                                        MouseArea {
                                            id: removeUserArea
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: !root.savingAccess
                                            onClicked: root.removeUser(userChip.modelData)
                                        }
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: root.detail("userGroups", [])
                            delegate: Rectangle {
                                id: groupChip
                                required property string modelData

                                radius: 8
                                color: "#31384a"
                                height: 26
                                width: groupChipRow.implicitWidth + 20

                                Row {
                                    id: groupChipRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        id: groupChipText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "group · " + groupChip.modelData
                                              + " (" + root.groupMembers(groupChip.modelData).length + ")"
                                        color: "#c4c9d1"
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "×"
                                        color: removeGroupArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                        font.pixelSize: 13
                                        font.bold: true

                                        MouseArea {
                                            id: removeGroupArea
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: !root.savingAccess
                                            onClicked: root.removeGroup(groupChip.modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Default directories ──────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: directoriesCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: directoriesCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: directoriesHeaderRow.implicitHeight

                        Row {
                            id: directoriesHeaderRow
                            spacing: 10
                            Text { text: "Default Directories"; color: "white"; font.pixelSize: 15; font.bold: true }
                            BusyIndicator {
                                running: root.savingDirectories
                                visible: root.savingDirectories
                                width: 18
                                height: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Button {
                            text: "+ Add directory"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: directoriesHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            enabled: !root.savingDirectories
                            onClicked: addDirectoryDialog.open()
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 11
                        text: "Created under each session's home when a client logs in, intermediate levels and all - "
                              + "a client that has to deliver into a folder cannot be asked to create it first. "
                              + "Relative to the home below, so one entry is a different key for every client."
                    }

                    DetailField {
                        width: directoriesCol.width
                        label: "Home directory"
                        // The template, not a path: "{user}" is substituted per session, and an
                        // empty one roots every client at the bucket root.
                        value: String(root.detail("homeDirectory", "")).length > 0
                               ? root.detail("homeDirectory", "") : "— (the bucket root)"
                    }

                    Text {
                        visible: root.detail("directories", []).length === 0
                        text: "None. A session finds whatever is already in the bucket and nothing is created for it."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.detail("directories", [])

                        delegate: Rectangle {
                            id: directoryRow
                            required property string modelData

                            width: directoriesCol.width
                            height: 34
                            radius: 8
                            color: "#1b1e25"
                            border.color: "#2c313c"
                            border.width: 1

                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: directoryRow.modelData
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                font.family: "monospace"
                            }

                            Text {
                                anchors.right: removeDirectoryText.left
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                // What it actually becomes for one client, which is the thing worth
                                // checking: a home template and a relative path are easy to get
                                // right separately and wrong together.
                                text: "→ " + root.resolvedPath(directoryRow.modelData)
                                color: "#6b7280"
                                font.pixelSize: 11
                                font.family: "monospace"
                                elide: Text.ElideLeft
                                width: Math.min(implicitWidth, directoryRow.width / 2)
                            }

                            Text {
                                id: removeDirectoryText
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Remove"
                                color: removeDirectoryArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                font.pixelSize: 11

                                MouseArea {
                                    id: removeDirectoryArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.savingDirectories
                                    onClicked: root.removeDirectory(directoryRow.modelData)
                                }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.detail("directories", []).length > 0
                        color: "#6b7280"
                        font.pixelSize: 11
                        text: "Removing one stops it being created for new sessions. What is already in the bucket "
                              + "stays - by then it is an ordinary object, and clients may have put things in it."
                    }
                }
            }
        }
    }

    Dialog {
        id: addDirectoryDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string errorText: ""

        readonly property string normalised: root.normalisePath(directoryField.text)
        readonly property bool valid: addDirectoryDialog.normalised.length > 0
                                      && root.detail("directories", []).map(d => String(d))
                                             .indexOf(addDirectoryDialog.normalised) < 0

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            directoryField.text = ""
            addDirectoryDialog.errorText = ""
            directoryField.forceActiveFocus()
        }

        contentItem: Column {
            width: addDirectoryDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Default Directory"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Relative to each session's home. Existing sessions are unaffected - it is created at "
                          + "login, so it appears for the next client that connects."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Directory"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: directoryField
                    width: parent.width
                    placeholderText: "e.g. incoming/mix"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    font.family: "monospace"
                    Keys.onReturnPressed: if (addDirectoryButton.enabled) addDirectoryButton.clicked()
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.pixelSize: 11
                    color: directoryField.text.length === 0 ? "#6b7280"
                           : (addDirectoryDialog.valid ? "#6b7280" : "#ffb545")
                    // Normalisation is shown rather than enforced: the server drops empty, "." and
                    // ".." segments on its way to a key, so "../incoming/" is not refused - it is
                    // simply "incoming". Saying so is more use than rejecting it.
                    text: {
                        if (directoryField.text.length === 0)
                            return "Slashes separate levels; each level is created in turn."
                        if (addDirectoryDialog.normalised.length === 0)
                            return "This normalises to nothing - \".\" and \"..\" segments are dropped."
                        if (!addDirectoryDialog.valid)
                            return "\"" + addDirectoryDialog.normalised + "\" is already in the list."
                        return "Stored as \"" + addDirectoryDialog.normalised + "\", created as \""
                               + root.resolvedPath(directoryField.text) + "\" for "
                               + (root.exampleUser === "{user}" ? "each client" : root.exampleUser) + "."
                    }
                }
            }

            Text {
                text: addDirectoryDialog.errorText
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
                    onClicked: addDirectoryDialog.close()
                }

                BusyIndicator {
                    running: root.savingDirectories
                    visible: root.savingDirectories
                    width: 22
                    height: 22
                    anchors.right: addDirectoryButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: addDirectoryButton
                    text: "Add"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !root.savingDirectories && addDirectoryDialog.valid
                    onClicked: {
                        addDirectoryDialog.errorText = ""
                        root.addDirectory(directoryField.text)
                    }
                }
            }
        }
    }

    Dialog {
        id: addGroupDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string errorText: ""

        // Only groups this server does not already allow. One that is already on it is not a choice.
        readonly property var choices: {
            const listed = root.detail("userGroups", []).map(g => String(g))
            return root.eamGroups.filter(g => listed.indexOf(String(g.name)) < 0)
        }

        readonly property var selectedGroup: addGroupDialog.choices.length > 0 && groupCombo.currentIndex >= 0
                                             ? addGroupDialog.choices[groupCombo.currentIndex] : null

        // Who the chosen group would make redundant, worked out before anything is written so the
        // dialog can say it rather than have it happen quietly.
        readonly property var covered: addGroupDialog.selectedGroup
                                       ? root.usersCoveredBy(addGroupDialog.selectedGroup.name) : []

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            addGroupDialog.errorText = ""
            groupCombo.currentIndex = 0
        }

        contentItem: Column {
            width: addGroupDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add User Group"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Every member may log in, and stays able to as the group's membership changes - which is "
                          + "the point of listing a group rather than the people in it."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                id: groupColumn
                width: parent.width
                spacing: 6
                Text { text: "Group"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: groupCombo
                    width: groupColumn.width
                    model: addGroupDialog.choices.map(g => g.name + "  (" + g.userIds.length + " member(s))")
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: addGroupDialog.choices.length === 0
                          ? (root.eamGroups.length === 0 ? "No user groups could be read."
                                                         : "Every group is already allowed on this server.")
                          : (addGroupDialog.selectedGroup
                             ? (String(addGroupDialog.selectedGroup.description).length > 0
                                ? addGroupDialog.selectedGroup.description
                                : "Members: " + addGroupDialog.selectedGroup.userIds.join(", "))
                             : "")
                }
            }

            // The other half of what this does, said before it is done.
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: addGroupDialog.covered.length > 0
                color: "#e0a458"
                font.pixelSize: 11
                text: "Also removes " + addGroupDialog.covered.length + " user(s) from the individual list - "
                      + addGroupDialog.covered.join(", ") + " - who are in this group and would otherwise be "
                      + "allowed in twice over. They keep access through the group; the entry that would have gone "
                      + "stale is the one being dropped."
            }

            Text {
                text: addGroupDialog.errorText
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
                    onClicked: addGroupDialog.close()
                }

                BusyIndicator {
                    running: root.savingAccess
                    visible: root.savingAccess
                    width: 22
                    height: 22
                    anchors.right: addGroupButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: addGroupButton
                    text: "Add"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !root.savingAccess && addGroupDialog.selectedGroup !== null
                    onClicked: {
                        addGroupDialog.errorText = ""
                        root.addGroup(addGroupDialog.selectedGroup.name)
                    }
                }
            }
        }
    }

    Dialog {
        id: addUserDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            userIdField.text = ""
            addUserDialog.errorText = ""
            userIdField.forceActiveFocus()
        }

        contentItem: Column {
            width: addUserDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Allow a user to log in"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "The EAM user ID, as it appears under EAM · users. The transfer server authenticates "
                          + "logins against EAM, so the user needs no separate FTP password."
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
                    placeholderText: "e.g. jvo"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (addUserButton.enabled) addUserButton.clicked()
                }
                Text {
                    text: addUserDialog.errorText
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
                    onClicked: addUserDialog.close()
                }

                BusyIndicator {
                    running: root.savingAccess
                    visible: root.savingAccess
                    width: 22
                    height: 22
                    anchors.right: addUserButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: addUserButton
                    text: "Add"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !root.savingAccess && userIdField.text.trim().length > 0
                    onClicked: {
                        addUserDialog.errorText = ""
                        root.addUser(userIdField.text.trim())
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
                Text { text: "Delete Transfer Server"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Permanently deletes the definition of \"" + root.serverId + "\". The reconciler tears the "
                          + "running server down on its next tick; the bucket and its contents are untouched. This "
                          + "cannot be undone."
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
                        etsClient.deleteServer(root.serverId)
                    }
                }
            }
        }
    }
}
