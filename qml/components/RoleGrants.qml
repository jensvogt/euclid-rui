import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// What a principal - a user or a user group - may do, as euclid actually decides it: a list of
// grants, each giving one role in named namespaces over named resources.
//
// One component for both kinds because a grant does not care which it is holding: grant-role takes
// an ERN and the ERN says whether it named a user or a group. Groups are usually the better unit -
// a grant written once for "the people who run imports" outlives everyone who is currently one of
// them - but nothing here has to know that.
Item {
    id: root

    // The principal these grants belong to, and what to call it in the dialog.
    property string principalErn: ""
    property string principalLabel: ""
    property bool loggedIn: false

    property var grants: []
    property var roles: []
    property string error: ""
    property bool loading: false

    // Off the tile's own implicit height, which is the content's - a Rectangle does not take one
    // from its children, so binding this to a plain "height:" expression on the tile left root
    // sizeless. The pages put this in a Column, and a Column reads implicitHeight: at zero the tile
    // was laid out on top of whatever came next, and fell outside the scrollable area entirely when
    // it came last.
    implicitHeight: tile.implicitHeight

    readonly property bool ready: root.loggedIn && root.principalErn.length > 0

    function refresh() {
        if (!root.ready)
            return
        root.loading = true
        root.error = ""
        eamClient.fetchGrants(root.principalErn)
        // For the dialog's picker. Asked for alongside rather than on open, so the roles are
        // already there when somebody reaches for them.
        eamClient.fetchRoles()
    }

    onPrincipalErnChanged: refresh()
    onLoggedInChanged: refresh()
    // The detail pages are built once and shown and hidden by route, so opening the same principal
    // twice does not change principalErn and would otherwise leave the grants from the first visit
    // on screen - including any granted from a different window since.
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()

    // "*" is every namespace of the account, and every resource - said in words, because a lone
    // asterisk in a table reads like something is missing.
    function scopeText(values, everything) {
        if (!values || values.length === 0) return "—"
        if (values.indexOf("*") >= 0) return everything
        return values.join(", ")
    }

    function roleDescription(name) {
        const role = root.roles.find(r => r.name === name)
        return role ? role.description : ""
    }

    Connections {
        target: eamClient

        function onGrantsLoaded(principalErn, list) {
            if (principalErn !== root.principalErn) return
            root.loading = false
            root.error = ""
            root.grants = list
        }
        function onGrantsFailed(principalErn, message) {
            if (principalErn !== root.principalErn) return
            root.loading = false
            root.error = message
        }
        function onRolesLoaded(list) {
            root.roles = list
        }
        function onRolesFailed(message) {
            // Not the tile's error: the grants may have read perfectly well, and only the picker is
            // the poorer for this.
            grantDialog.errorText = message
        }
        function onRoleGranted(principalErn, grantId) {
            if (principalErn !== root.principalErn) return
            grantDialog.saving = false
            grantDialog.close()
            root.refresh()
        }
        function onRoleGrantFailed(message) {
            grantDialog.saving = false
            grantDialog.errorText = message
        }
        function onRoleRevoked(principalErn, grantId) {
            if (principalErn !== root.principalErn) return
            root.refresh()
        }
        function onRoleRevokeFailed(message) {
            root.error = message
        }
    }

    Rectangle {
        id: tile
        width: parent.width
        implicitHeight: grantsCol.implicitHeight + 40
        height: implicitHeight
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
                height: headerRow.implicitHeight

                Row {
                    id: headerRow
                    spacing: 10
                    Text { text: "Roles"; color: "white"; font.pixelSize: 15; font.bold: true }
                    BusyIndicator {
                        running: root.loading
                        visible: root.loading
                        width: 18
                        height: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Button {
                    text: "+ Grant role"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: headerRow.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: root.ready
                    onClicked: grantDialog.open()
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "Every request is checked against these: a role has to apply in the account and namespace "
                      + "the request is made in, and hold the permission the action needs. Members of the "
                      + "administrator group are not checked at all."
            }

            Text {
                visible: root.error.length > 0
                width: parent.width
                text: root.error
                color: "#ff6b6b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Text {
                visible: !root.loading && root.error.length === 0 && root.grants.length === 0
                text: "No roles granted. This principal is refused anything that is checked."
                color: "#6b7280"
                font.pixelSize: 12
            }

            Repeater {
                model: root.grants

                delegate: Rectangle {
                    id: grantRow
                    required property var modelData

                    width: grantsCol.width
                    height: grantCol.implicitHeight + 20
                    radius: 10
                    color: "#1b1e25"
                    border.color: "#2c313c"
                    border.width: 1

                    Column {
                        id: grantCol
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 10
                        spacing: 4

                        Item {
                            width: parent.width
                            height: roleRow.implicitHeight

                            Row {
                                id: roleRow
                                spacing: 8

                                Text {
                                    text: grantRow.modelData.role
                                    color: "#e5e7eb"
                                    font.pixelSize: 13
                                    font.bold: true
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: root.roleDescription(grantRow.modelData.role)
                                    color: "#6b7280"
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                text: "Revoke"
                                color: revokeArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                font.pixelSize: 11
                                anchors.right: parent.right
                                anchors.verticalCenter: roleRow.verticalCenter

                                MouseArea {
                                    id: revokeArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    // A grant's scope is fixed once written, so there is no editing
                                    // one: narrowing means revoking it and granting what is left.
                                    onClicked: eamClient.revokeRole(grantRow.modelData.grantId, root.principalErn)
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: "#9aa1ac"
                            font.pixelSize: 11
                            text: "In " + root.scopeText(grantRow.modelData.namespaces, "every namespace")
                                  + " · over " + root.scopeText(grantRow.modelData.resources, "every resource")
                                  + " · account " + grantRow.modelData.accountId
                        }

                        Text {
                            width: parent.width
                            color: "#6b7280"
                            font.pixelSize: 11
                            text: "Granted " + DateFormat.format(grantRow.modelData.granted)
                                  + (String(grantRow.modelData.grantedBy).length > 0
                                     ? " by " + grantRow.modelData.grantedBy : "")
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: grantDialog
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

        readonly property var selectedRole: root.roles.length > 0 && roleCombo.currentIndex >= 0
                                            ? root.roles[roleCombo.currentIndex] : null

        // Both are required by the server, and both default to everything - which is what the
        // built-in roles are written to be used with.
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
            roleCombo.currentIndex = 0
            namespacesField.text = "*"
            resourcesField.text = "*"
        }

        contentItem: Column {
            width: grantDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Grant Role"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "To " + (root.principalLabel.length > 0 ? root.principalLabel : root.principalErn)
                          + ". Administrator rights are required, and the grant takes effect on the next request."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                id: roleColumn
                width: parent.width
                spacing: 6
                Text { text: "Role"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: roleCombo
                    width: roleColumn.width
                    model: root.roles.map(r => r.name)
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: grantDialog.selectedRole
                          ? grantDialog.selectedRole.description + " · "
                            + grantDialog.selectedRole.permissionCount + " permission(s)"
                            + (grantDialog.selectedRole.builtin ? " · built in" : "")
                          : "No roles could be read."
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Namespaces"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: namespacesField
                    width: parent.width
                    placeholderText: "* for every namespace, or a comma-separated list"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
                Text {
                    text: "Where the role applies. A grant that applies in no namespace grants nothing, so this "
                          + "cannot be empty."
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
                    id: resourcesField
                    width: parent.width
                    placeholderText: "* for every resource, or ERN patterns"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
                Text {
                    text: "ERN patterns, each exact or ending in \"*\" - so one queue, or every queue of a "
                          + "namespace. This is what makes a wide role narrow."
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
                    enabled: !grantDialog.saving && grantDialog.selectedRole !== null
                    onClicked: {
                        grantDialog.errorText = ""
                        grantDialog.saving = true
                        eamClient.grantRole(grantDialog.selectedRole.name, root.principalErn,
                                            grantDialog.listFrom(namespacesField.text),
                                            grantDialog.listFrom(resourcesField.text))
                    }
                }
            }
        }
    }
}
