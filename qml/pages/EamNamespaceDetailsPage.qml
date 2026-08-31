import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// The namespace side of the grants EamUserDetailsPage edits per user: who may reach this
// namespace. Name and description are fixed at creation - there is no "update-namespace" action -
// so they are shown read-only.
Item {
    id: root
    property bool loggedIn: false
    // The namespace this page is about. `namespaceName` is deliberately not called that on the
    // other pages' pattern (there it means the session's namespace); here it is the subject.
    property string accountId: ""
    property string namespaceName: ""
    property var details: ({})

    // Every user, annotated with the namespaces they hold in this account (see fetchAccountUsers).
    property var users: []
    property string usersError: ""
    property bool deleting: false

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function isGranted(user) {
        return user.namespaces.indexOf(root.namespaceName) >= 0
    }

    function grantedCount() {
        return root.users.filter(u => root.isGranted(u)).length
    }

    function refresh() {
        if (!root.loggedIn || root.accountId.length === 0 || root.namespaceName.length === 0)
            return
        root.usersError = ""
        eamClient.fetchAccountUsers(root.accountId)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()
    onNamespaceNameChanged: if (visible) refresh()

    Connections {
        target: eamClient

        function onAccountUsersLoaded(accountId, list) {
            if (accountId !== root.accountId) return
            root.users = list
            root.usersError = ""
        }
        function onAccountUsersFailed(message) {
            root.usersError = message
        }

        // Shared with EamUserDetailsPage - that page filters by user, this one by the namespace
        // it is showing, so the same grant/revoke calls serve both directions.
        function onNamespaceAccessChanged(userErn, accountId, namespaceName, granted) {
            if (accountId !== root.accountId || namespaceName !== root.namespaceName) return
            root.refresh()
        }
        function onNamespaceAccessFailed(message) {
            root.usersError = message
            root.refresh()
        }

        // deleteNamespace() reports success by asking the namespaces table to reload - only ours
        // while a delete is in flight.
        function onNamespacesReload() {
            if (!root.deleting) return
            root.deleting = false
            root.back()
        }
        function onNamespacesFailed(message) {
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
                text: "‹ Back"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.namespaceName
                    subtitle: root.detail("ern", root.accountId + " · " + root.namespaceName)
                }

                Button {
                    text: "Delete Namespace"
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

                StatCard { title: "Account ID"; value: root.accountId.length > 0 ? root.accountId : "—"; trend: "owning account"; trendUp: true; accent: "#4f8cff" }
                StatCard {
                    title: "Granted Users"
                    value: String(root.grantedCount())
                    trend: "of " + root.users.length + " users"
                    trendUp: root.grantedCount() > 0
                    accent: "#4cd97b"
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Name"; value: root.namespaceName }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.accountId }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    DetailField {
                        width: identityCol.width
                        label: "Description"
                        value: root.detail("description", "").length > 0 ? root.detail("description", "") : "—"
                    }
                    DetailField { width: identityCol.width; label: "Namespace ERN"; value: root.detail("ern", "—"); copyable: true }

                    Text {
                        width: parent.width
                        text: "Name and description are set when the namespace is created and cannot be changed here."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
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

                    Text { text: "Access"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        text: "Every user in the deployment; switch one on to grant access to this namespace. "
                              + "Requires administrator rights on account " + root.accountId + ". Account administrators "
                              + "reach every namespace regardless of what is set here."
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
                                          + (userDelegate.modelData.home ? "  ·  home account" : "")
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

                            ToggleSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: root.isGranted(userDelegate.modelData)
                                onToggled: (checked) => {
                                    root.usersError = ""
                                    if (checked) eamClient.grantNamespaceAccess(userDelegate.modelData.ern, root.accountId, root.namespaceName)
                                    else eamClient.revokeNamespaceAccess(userDelegate.modelData.ern, root.accountId, root.namespaceName)
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
                Text { text: "Delete Namespace"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Permanently deletes \"" + root.namespaceName + "\" from account " + root.accountId
                          + ". The server refuses while any user still holds a grant for it - revoke those above "
                          + "first. This cannot be undone."
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
                        eamClient.deleteNamespace(root.accountId, root.namespaceName)
                    }
                }
            }
        }
    }
}
