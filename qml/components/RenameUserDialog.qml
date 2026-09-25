import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// One dialog for both ways into a rename - the row menu on the user list and the button on a user's
// details page - for the same reason ChangePasswordDialog is one: the request behind them is the
// same, and what it does to everything else naming this user is worth stating once.
//
// A rename is an administrator's action on somebody, never on yourself by default: both ids are
// named outright rather than one of them meaning "me" when left out.
Dialog {
    id: root

    // Who is being renamed. Never empty when this is opened; the caller sets it before open().
    property string userId: ""

    property bool renaming: false
    property string errorText: ""

    // The renamed user as EAM now describes them - including the rebuilt ERN, which is why this
    // carries the whole map and not just the new id. Whoever opened the dialog has to take it:
    // anything still holding the old ERN is asking about a principal that no longer resolves.
    signal renamed(string oldUserId, string newUserId, var user)

    readonly property string newUserId: newIdField.text.trim()

    // Locally checkable, and kept apart from errorText the way ChangePasswordDialog does: this one
    // is about what is in the form and updates as it is typed, where errorText is the server's
    // answer to a request already sent. The server refuses this one too (400), but there is no
    // reason to make it say so.
    readonly property string formError: root.newUserId.length > 0 && root.newUserId === root.userId
                                        ? "That is the id this user already has."
                                        : ""

    readonly property bool submittable: root.newUserId.length > 0
                                        && root.formError.length === 0
                                        && !root.renaming

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
        // Prefilled with the current id rather than left empty: a rename is usually a correction to
        // what is already there, and it is selected so typing over it still costs one keystroke.
        newIdField.text = root.userId
        root.errorText = ""
        root.renaming = false
        newIdField.forceActiveFocus()
        newIdField.selectAll()
    }

    function submit() {
        if (!root.submittable)
            return
        root.errorText = ""
        root.renaming = true
        eamClient.renameUser(root.userId, root.newUserId)
    }

    Connections {
        target: eamClient
        // Both guards matter, as with the password dialog: `renaming` keeps a dialog that is merely
        // open from reacting to somebody else's request, and the userId keeps the list page's
        // dialog from closing on the details page's result when both are instantiated at once.
        function onUserRenamed(userId, newUserId, user) {
            if (!root.renaming || userId !== root.userId)
                return
            root.renaming = false
            root.close()
            root.renamed(userId, newUserId, user)
        }
        function onUserRenameFailed(message) {
            if (!root.renaming)
                return
            root.renaming = false
            root.errorText = message
        }
    }

    contentItem: Column {
        width: root.availableWidth
        spacing: 16

        Column {
            width: parent.width
            spacing: 4
            Text { text: "Rename User"; color: "white"; font.pixelSize: 18; font.bold: true }
            Text {
                width: parent.width
                text: "Administrator only. \"" + root.userId + "\" is the id they have now."
                color: "#9aa1ac"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        Column {
            width: parent.width
            spacing: 6
            Text { text: "New user ID"; color: "#9aa1ac"; font.pixelSize: 12 }
            TextField {
                id: newIdField
                width: parent.width
                placeholderText: "e.g. jane.doe"
                Material.accent: "#4f8cff"
                selectByMouse: true
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

        // What an administrator would otherwise have to find out by looking. The first line is the
        // reassuring half and the second is not, and both are things somebody deciding whether to
        // rename would want to know before rather than after.
        Column {
            width: parent.width
            spacing: 4

            Text {
                width: parent.width
                text: "Their ERN is built from the id, so it changes too. The roles granted to them and the "
                      + "groups they are in follow the new one."
                color: "#6b7280"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: "What does not follow: audit history, and whoever is recorded as the owner of a bucket, "
                      + "queue or object - those name who acted, not who exists now. Access keys keep their ids "
                      + "and go on signing."
                color: "#6b7280"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: "Any session this user already has stays signed in until its token expires, and cannot be "
                      + "refreshed after that."
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
                enabled: !root.renaming
                onClicked: root.close()
            }

            Button {
                text: root.renaming ? "Renaming…" : "Rename"
                highlighted: true
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
                enabled: root.submittable
                onClicked: root.submit()
            }
        }
    }
}
