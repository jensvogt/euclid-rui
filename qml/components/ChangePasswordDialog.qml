import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// One dialog for both ways into a password change - the row menu on the user list and the button
// on a user's details page - because the request behind them is the same one and the rules about
// what it needs are worth stating once.
//
// Which request it is depends on who the target is, and that is EAM's rule rather than this
// dialog's: changing your own password needs the current one, an administrator resetting somebody
// else's does not. So the form asks for the current password only when the target is the signed-in
// user, and says which of the two is happening either way - a reset that silently did not need a
// password would otherwise look like the field had simply been forgotten.
Dialog {
    id: root

    // Whose password. Never empty when this is opened; the caller sets it before open().
    property string userId: ""

    // EAM decides own-vs-reset from the userId alone, so this mirrors that comparison rather than
    // reading anything into which page the dialog was opened from. euclidClient.userId is the name
    // EAM knows the caller by, which is not necessarily what was typed to sign in.
    readonly property bool ownPassword: root.userId.length > 0 && root.userId === euclidClient.userId

    property bool changing: false
    property string errorText: ""

    // Locally checkable problems, kept apart from errorText: this one is about what is in the form
    // and updates as it is typed, where errorText is the server's answer to a request already
    // sent. Empty means there is nothing stopping the request.
    // Only once there is something in the confirmation to disagree with: a mismatch reported
    // against an empty field is just a complaint that the form is not finished yet, which the
    // disabled button already says without the red text.
    readonly property string formError: confirmField.text.length > 0 && confirmField.text !== newField.text
                                        ? "The two new passwords do not match."
                                        : ""

    readonly property bool submittable: newField.text.length > 0
                                        && confirmField.text === newField.text
                                        && (!root.ownPassword || currentField.text.length > 0)
                                        && !root.changing

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

    onOpened: {
        currentField.text = ""
        newField.text = ""
        confirmField.text = ""
        root.errorText = ""
        root.changing = false
        if (root.ownPassword)
            currentField.forceActiveFocus()
        else
            newField.forceActiveFocus()
    }

    // Passwords do not sit in a closed dialog waiting to be read out of it again.
    onClosed: {
        currentField.text = ""
        newField.text = ""
        confirmField.text = ""
    }

    function submit() {
        if (!root.submittable)
            return
        root.errorText = ""
        root.changing = true
        eamClient.changePassword(root.userId, currentField.text, newField.text)
    }

    Connections {
        target: eamClient
        // Both guards matter: `changing` keeps a dialog that is merely open from reacting to
        // somebody else's request, and the userId keeps the list page's dialog from closing on the
        // details page's result when both are instantiated at once.
        function onPasswordChanged(userId) {
            if (!root.changing || userId !== root.userId)
                return
            root.changing = false
            root.close()
        }
        function onPasswordChangeFailed(message) {
            if (!root.changing)
                return
            root.changing = false
            root.errorText = message
        }
    }

    contentItem: Column {
        width: root.availableWidth
        spacing: 16

        Column {
            width: parent.width
            spacing: 4
            Text { text: "Change Password"; color: "white"; font.pixelSize: 18; font.bold: true }
            Text {
                width: parent.width
                text: root.ownPassword
                      ? "Your own password. The current one is needed to replace it."
                      : "Administrator reset for " + root.userId + ". Their current password is not needed."
                color: "#9aa1ac"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        Column {
            width: parent.width
            spacing: 6
            visible: root.ownPassword
            Text { text: "Current password"; color: "#9aa1ac"; font.pixelSize: 12 }
            TextField {
                id: currentField
                width: parent.width
                echoMode: TextInput.Password
                Material.accent: "#4f8cff"
                selectByMouse: true
                Keys.onReturnPressed: newField.forceActiveFocus()
            }
        }

        Column {
            width: parent.width
            spacing: 6
            Text { text: "New password"; color: "#9aa1ac"; font.pixelSize: 12 }
            TextField {
                id: newField
                width: parent.width
                echoMode: TextInput.Password
                Material.accent: "#4f8cff"
                selectByMouse: true
                Keys.onReturnPressed: confirmField.forceActiveFocus()
            }
        }

        Column {
            width: parent.width
            spacing: 6
            Text { text: "Confirm new password"; color: "#9aa1ac"; font.pixelSize: 12 }
            TextField {
                id: confirmField
                width: parent.width
                echoMode: TextInput.Password
                Material.accent: "#4f8cff"
                selectByMouse: true
                Keys.onReturnPressed: root.submit()
            }
        }

        // The session outliving the change is worth saying rather than leaving to be discovered:
        // an administrator who has just reset somebody's password would reasonably expect them to
        // be shut out now, and they are not until their token runs out.
        Text {
            width: parent.width
            text: root.ownPassword
                  ? "This session stays signed in; the new password applies from the next sign-in."
                  : "Any session this user already has stays signed in until its token expires."
            color: "#6b7280"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Text {
            width: parent.width
            text: root.formError.length > 0 ? root.formError : root.errorText
            color: "#ff6b6b"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
            visible: text.length > 0
        }

        Row {
            anchors.right: parent.right
            spacing: 12

            Button {
                text: "Cancel"
                flat: true
                Material.theme: Material.Dark
                enabled: !root.changing
                onClicked: root.close()
            }

            Button {
                text: root.changing ? "Changing…" : (root.ownPassword ? "Change" : "Reset")
                highlighted: true
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
                enabled: root.submittable
                onClicked: root.submit()
            }
        }
    }
}
