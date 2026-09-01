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
            if (addUserDialog.opened) addUserDialog.errorText = message
            else root.error = message
        }
        function onServerStateChanged(serverId, desiredState) {
            if (serverId !== root.serverId) return
            root.savingAccess = false
            addUserDialog.close()
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

            Button {
                text: "‹ Back to Transfer Servers"
                flat: true
                onClicked: root.back()
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

                        Button {
                            text: "+ Add user"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: accessHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            enabled: !root.savingAccess
                            onClicked: addUserDialog.open()
                        }
                    }

                    Text {
                        width: parent.width
                        text: "EAM users listed directly, plus every member of the listed groups - a union, not an "
                              + "intersection. A running server keeps its current list until the reconciler next "
                              + "restarts it. Groups are edited through the ETS API."
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
                                width: groupChipText.implicitWidth + 20
                                Text {
                                    id: groupChipText
                                    anchors.centerIn: parent
                                    text: "group · " + groupChip.modelData
                                    color: "#c4c9d1"
                                    font.pixelSize: 11
                                }
                            }
                        }
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
