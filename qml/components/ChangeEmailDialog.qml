import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// One dialog wherever an address is changed, as RenameUserDialog is one for renames: the request
// behind it is the same and what it means for the user is worth stating once.
//
// Administrator's action on somebody, never on yourself by default - the user is named outright.
// An address is a way in rather than a detail about somebody: login accepts one in place of a user
// id, so changing it changes who can sign in as this account.
Dialog {
    id: root

    // Who the address belongs to. Never empty when this is opened; the caller sets it before open().
    property string userId: ""

    // What they have now, so the field can be prefilled and the "that is the one they already have"
    // case caught here instead of at the server.
    property string currentEmail: ""

    property bool saving: false
    property string errorText: ""

    // The user as EAM now describes them. Nothing is keyed on the address, so nobody has to
    // re-point anything the way a rename makes them - this is here so a page showing the details
    // shows what was stored, timestamp included.
    signal emailUpdated(string userId, var user)

    readonly property string newEmail: emailField.text.trim()

    // Checked here and again at the server. Locally so the button says no while it is being typed,
    // at the server because this dialog is not the only way in. Kept apart from errorText the way
    // RenameUserDialog keeps its formError: this one is about what is in the field, that one is the
    // server's answer to a request already sent.
    readonly property string formError: {
        if (root.newEmail.length === 0)
            return ""
        if (root.newEmail === root.currentEmail)
            return "That is the address this user already has."
        // Enough of an address to be one, and no more - the same line the server draws. A pattern
        // that tries to decide which addresses exist refuses valid ones.
        const at = root.newEmail.indexOf("@")
        if (at <= 0 || at === root.newEmail.length - 1
                || root.newEmail.indexOf("@", at + 1) !== -1
                || root.newEmail.indexOf(".", at) === -1
                || root.newEmail.endsWith("."))
            return "That does not look like an email address."
        return ""
    }

    readonly property bool submittable: root.newEmail.length > 0
                                        && root.formError.length === 0
                                        && !root.saving

    modal: true
    anchors.centerIn: parent
    width: 420
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
        // Prefilled and selected, as in RenameUserDialog: changing an address is usually a
        // correction to the one that is there, and typing over it still costs one keystroke.
        emailField.text = root.currentEmail
        root.errorText = ""
        root.saving = false
        emailField.forceActiveFocus()
        emailField.selectAll()
    }

    function submit() {
        if (!root.submittable)
            return
        root.errorText = ""
        root.saving = true
        eamClient.changeEmail(root.userId, root.newEmail)
    }

    Connections {
        target: eamClient
        // Both guards matter: `saving` keeps a dialog that is merely open from reacting to somebody
        // else's request, and the userId keeps one page's dialog from closing on another's result.
        function onEmailChanged(userId, user) {
            if (!root.saving || userId !== root.userId)
                return
            root.saving = false
            root.close()
            root.emailUpdated(userId, user)
        }
        function onEmailChangeFailed(message) {
            if (!root.saving)
                return
            root.saving = false
            root.errorText = message
        }
    }

    contentItem: Column {
        width: root.availableWidth
        spacing: 16

        Column {
            width: parent.width
            spacing: 4
            Text { text: "Change Email"; color: "white"; font.pixelSize: 18; font.bold: true }
            Text {
                width: parent.width
                text: "Administrator only. " + (root.currentEmail.length > 0
                                                ? "\"" + root.currentEmail + "\" is the address \"" + root.userId + "\" has now."
                                                : "\"" + root.userId + "\" has no address on record.")
                color: "#9aa1ac"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        Column {
            width: parent.width
            spacing: 6
            Text { text: "Email address"; color: "#9aa1ac"; font.pixelSize: 12 }
            TextField {
                id: emailField
                width: parent.width
                placeholderText: "e.g. jane.doe@example.com"
                Material.accent: "#4f8cff"
                selectByMouse: true
                inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
                Keys.onReturnPressed: root.submit()
            }
            Text {
                width: parent.width
                text: "Has to be free - another user holding it is refused rather than merged."
                color: "#6b7280"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }

        // What somebody deciding whether to change it would want to know beforehand. The first line
        // is why it matters at all, the second is the reassuring half.
        Column {
            width: parent.width
            spacing: 4

            Text {
                width: parent.width
                text: "Sign-in accepts an email address in place of a user ID, so this changes how the user "
                      + "signs in. The user ID keeps working either way."
                color: "#6b7280"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: "Nothing else moves: the ERN, the roles granted to them, the groups they are in and their "
                      + "access keys are untouched, and any session they already have stays signed in."
                color: "#6b7280"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
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
                enabled: !root.saving
                onClicked: root.close()
            }

            Button {
                text: root.saving ? "Saving…" : "Save"
                highlighted: true
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
                enabled: root.submittable
                onClicked: root.submit()
            }
        }
    }
}
