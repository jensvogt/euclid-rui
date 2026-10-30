import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "components"

Dialog {
    id: root
    modal: true
    closePolicy: Popup.CloseOnEscape
    anchors.centerIn: parent
    width: 380
    padding: 28
    topPadding: 24
    bottomPadding: 24
    standardButtons: Dialog.NoButton

    property int step: 0 // 0 = credentials, 1 = account and namespace picker
    property string selectedNamespace: ""
    property string autoNamespace: ""
    // The namespace to land on when the list is refilled for another account: the one that was
    // picked before the switch, so moving between accounts that share a "dev" keeps "dev".
    property string preferredNamespace: ""

    // The accounts this user may work in, as the server reports them after login: their home
    // account plus every account a grant of theirs names. Each entry is
    // {accountId, name, description, ern, home}.
    property var accounts: []
    property string homeAccountId: ""
    property string autoAccount: ""

    // One line per account: its name when it has one worth showing, then the id a request will
    // actually carry, then which of them is home - the three things somebody choosing needs.
    readonly property var accountLabels: root.accounts.map(function (account) {
        const named = account.name && account.name.length > 0 && account.name !== account.accountId
        return (named ? account.name + " · " : "") + account.accountId + (account.home ? "   (home)" : "")
    })

    // Asking somebody to choose from one option is not a choice, it is a click - so the account
    // picker is shown only when there is something to decide. The account is still set either way,
    // and the step says which one it was.
    readonly property bool accountChoice: root.accounts.length > 1

    // The account the session is in, named the way the picker names it. Falls back to the id the
    // client is carrying, which is what a server too old to list accounts leaves behind.
    readonly property string activeAccountLabel: {
        const active = euclidClient.accountId
        const match = root.accounts.find(a => a.accountId === active)
        if (!match)
            return active
        const named = match.name && match.name.length > 0 && match.name !== match.accountId
        return (named ? match.name + " · " : "") + match.accountId
    }
    property bool autoLoginActive: false
    property bool suppressOpenReset: false
    // Whether there is a session behind this dialog; see onRejected.
    property bool signedIn: false

    signal loggedIn(string username, string namespaceName)

    // Escape arrives here as reject(): closePolicy sends it through Popup's closeOrReject(), which
    // rejects a Dialog rather than merely closing it, and every successful path below closes with
    // close(). So a rejection is always a dismissal, never a sign-in.
    //
    // Dismissing the way in is a decision to leave, and on startup there is nothing behind this
    // dialog to go back to - so the application goes with it. Reopened from the avatar to switch
    // user there *is* a live session behind it, and Escape there means "never mind", not "quit".
    onRejected: if (!root.signedIn) Qt.quit()

    // Applies whatever gateway the connection fields currently show. Persisted by AppSettings and
    // pushed into euclidClient from main.cpp, so it takes effect from the very next request - the
    // sign-in below already goes to the new host.
    function applyGateway() {
        appSettings.setHost(hostField.text)
        appSettings.setPort(parseInt(portField.text, 10))
        appSettings.setUseTls(tlsSwitch.checked)
    }

    // Signs in without showing the dialog (e.g. credentials supplied via
    // --user/--password command-line options). Reuses the normal login/
    // namespace-selection flow below; if it fails, the dialog reveals itself
    // with the error already filled in so the user can retry manually.
    function autoLogin(user, password, namespaceHint, accountHint) {
        usernameField.text = user
        passwordField.text = password
        root.autoNamespace = namespaceHint
        root.autoAccount = accountHint !== undefined ? accountHint : ""
        root.autoLoginActive = true
        errorText.text = ""
        euclidClient.login(user, password)
    }

    // Settles which account the session works in and moves on to its namespaces. The account has
    // to be set before they are asked for: a namespace belongs to an account, and the request that
    // lists them carries whichever one the session is in.
    function useAccount(accountId) {
        euclidClient.setAccountId(accountId)
        euclidClient.fetchNamespaces()
    }

    // The account to start on when nobody has chosen: what was asked for on the command line if it
    // is one of theirs, else home. Home rather than the first row because home is where the user's
    // own things are, and it is the account every session worked in before this step existed.
    function defaultAccountIndex() {
        if (root.autoAccount.length > 0) {
            const asked = root.accounts.findIndex(a => a.accountId === root.autoAccount)
            if (asked >= 0) return asked
        }
        const home = root.accounts.findIndex(a => a.home === true)
        return home >= 0 ? home : 0
    }

    background: Rectangle {
        radius: 16
        color: "#1b1e25"
        border.color: "#2c313c"
        border.width: 1
    }

    onOpened: {
        if (root.suppressOpenReset) {
            root.suppressOpenReset = false
        } else {
            step = 0
            usernameField.text = ""
            passwordField.text = ""
            errorText.text = ""
            accountErrorText.text = ""
            namespaceErrorText.text = ""
            root.accounts = []
            root.homeAccountId = ""
            root.preferredNamespace = ""
            namespaceCombo.model = []
        }
        // Always re-read the gateway fields, including on the suppressed-reset path: they show
        // where the attempt that just failed was actually sent, which is half the diagnosis.
        hostField.text = appSettings.host
        portField.text = appSettings.port
        tlsSwitch.checked = appSettings.useTls
        usernameField.forceActiveFocus()
    }

    onClosed: passwordField.text = ""

    contentItem: Column {
        width: root.availableWidth
        spacing: 20

        Column {
            width: parent.width
            spacing: 4

            Row {
                spacing: 10
                Image {
                    source: "qrc:/EuclidRui/dist/branding/euclid-icon.svg"
                    width: 34
                    height: 34
                    sourceSize.width: 68
                    sourceSize.height: 68
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    text: "Sign in to Euclid"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            Text {
                width: parent.width
                text: root.step === 0 ? "Enter your credentials to continue."
                                      : (root.accountChoice ? "Choose the account and namespace for this session."
                                                            : "Choose a namespace for this session.")
                color: "#9aa1ac"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        Item {
            width: parent.width
            height: Math.max(credentialsStep.implicitHeight, selectionStep.implicitHeight)

            Column {
                id: credentialsStep
                width: parent.width
                spacing: 16
                opacity: root.step === 0 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                // Which euclid-mgr to talk to. Editable here rather than in the settings page
                // because a wrong gateway and a wrong password fail at the same moment, and this
                // is where you are when that happens.
                Column {
                    width: parent.width
                    spacing: 6

                    Text { text: "Gateway"; color: "#9aa1ac"; font.pixelSize: 12 }

                    Row {
                        width: parent.width
                        spacing: 8

                        TextField {
                            id: hostField
                            width: parent.width - portField.width - 8
                            placeholderText: "hostname or IP"
                            Material.accent: "#4f8cff"
                            selectByMouse: true
                            KeyNavigation.tab: portField
                        }
                        TextField {
                            id: portField
                            width: 84
                            placeholderText: "port"
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 1; top: 65535 }
                            Material.accent: "#4f8cff"
                            selectByMouse: true
                            KeyNavigation.tab: usernameField
                        }
                    }

                    Row {
                        width: parent.width
                        height: 26
                        spacing: 10

                        ToggleSwitch {
                            id: tlsSwitch
                            anchors.verticalCenter: parent.verticalCenter
                            checked: true
                        }
                        Text {
                            // The gateway only serves https when euclid.gateway.tls.enabled is set
                            // server-side, and that defaults to off - so this has to be a choice.
                            text: "TLS (https)"
                            color: "#c4c9d1"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: (tlsSwitch.checked ? "https://" : "http://")
                                  + (hostField.text.length > 0 ? hostField.text : "…") + ":" + portField.text
                            color: "#6b7280"
                            font.pixelSize: 11
                            elide: Text.ElideMiddle
                            width: parent.width - tlsSwitch.width - 100
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: "Username or email"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: usernameField
                        width: parent.width
                        placeholderText: "e.g. jvogt or jens@euclid.dev"
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        KeyNavigation.tab: passwordField
                    }
                }
                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: "Password"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: passwordField
                        width: parent.width
                        placeholderText: "••••••••"
                        echoMode: TextInput.Password
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        Keys.onReturnPressed: signInButton.clicked()
                    }
                }
                Text {
                    id: errorText
                    width: parent.width
                    color: "#ff6b6b"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    visible: text.length > 0
                }
            }

            // The account and the namespace on one page: a namespace belongs to an account, so the
            // two are one decision, and changing the account below refills the namespaces in place
            // rather than sending somebody back a step to see what the other account holds.
            Column {
                id: selectionStep
                width: parent.width
                spacing: 16
                opacity: root.step === 1 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Rectangle {
                    width: parent.width
                    height: 44
                    radius: 10
                    color: "#20242e"
                    border.color: "#2c313c"
                    border.width: 1

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Rectangle {
                            width: 26
                            height: 26
                            radius: 13
                            color: "#2c3648"
                            Text { anchors.centerIn: parent; text: "✓"; color: "#4cd97b"; font.pixelSize: 12 }
                        }
                        Column {
                            spacing: 1
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                text: "Signed in as " + usernameField.text
                                color: "#c4c9d1"
                                font.pixelSize: 12
                            }
                            // Which account this session is about to work in, when there is no picker
                            // below to say so - most people have one account, and "no choice was
                            // offered" and "the choice went somewhere unexpected" look identical
                            // without it.
                            Text {
                                text: "Account · " + root.activeAccountLabel
                                color: "#6b7280"
                                font.pixelSize: 11
                                visible: !root.accountChoice && root.activeAccountLabel.length > 0
                            }
                        }
                    }
                }

                // Asking somebody to choose from one option is not a choice, so the picker is only
                // shown when there is something to decide. The account is set either way.
                Column {
                    width: parent.width
                    spacing: 6
                    visible: root.accountChoice

                    Text { text: "Account"; color: "#9aa1ac"; font.pixelSize: 12 }
                    ComboBox {
                        id: accountCombo
                        width: parent.width
                        Material.accent: "#4f8cff"
                        model: root.accountLabels
                        // Held while a namespace listing is in flight: the reply does not say which
                        // account it was for, so a second switch before it lands could fill the
                        // namespaces of one account in under the name of another.
                        enabled: count > 0 && !euclidClient.busy

                        // onActivated rather than onCurrentIndexChanged: only a choice somebody made
                        // goes to the server, not the default the dialog sets itself.
                        onActivated: (index) => {
                            accountErrorText.text = ""
                            namespaceErrorText.text = ""
                            root.preferredNamespace = namespaceCombo.currentText
                            namespaceCombo.model = []
                            root.useAccount(root.accounts[index].accountId)
                        }
                    }
                    Text {
                        width: parent.width
                        text: "Your home account, and every account a role granted to you - or to a group you are "
                              + "in - covers. Everything this session does happens in the one you pick."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                Text {
                    id: accountErrorText
                    width: parent.width
                    color: "#ff6b6b"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    visible: text.length > 0
                }

                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: "Namespace"; color: "#9aa1ac"; font.pixelSize: 12 }
                    ComboBox {
                        id: namespaceCombo
                        width: parent.width
                        Material.accent: "#4f8cff"
                        model: []
                        enabled: count > 0 && !euclidClient.busy
                    }
                }

                Text {
                    id: namespaceErrorText
                    width: parent.width
                    color: "#ff6b6b"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    visible: text.length > 0
                }
            }
        }

        Item {
            width: parent.width
            height: 40

            Button {
                id: backButton
                text: "Back"
                flat: true
                visible: root.step > 0
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                Material.theme: Material.Dark
                onClicked: root.step = 0
            }

            BusyIndicator {
                running: euclidClient.busy
                visible: euclidClient.busy
                width: 22
                height: 22
                anchors.right: signInButton.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
            }

            Button {
                id: signInButton
                text: root.step === 0 ? "Sign In" : "Continue"
                highlighted: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
                enabled: !euclidClient.busy && (root.step === 0
                    ? usernameField.text.length > 0 && passwordField.text.length > 0
                      && hostField.text.trim().length > 0 && portField.acceptableInput
                    : namespaceCombo.count > 0)

                onClicked: {
                    if (root.step === 0) {
                        errorText.text = ""
                        root.applyGateway()
                        euclidClient.login(usernameField.text, passwordField.text)
                    } else {
                        root.selectedNamespace = namespaceCombo.currentText
                        root.loggedIn(usernameField.text, root.selectedNamespace)
                        root.close()
                    }
                }
            }
        }
    }

    // Reveals the dialog after a failed auto-login attempt (see autoLogin()),
    // with the error filled in afterwards - onOpened() resets errorText et al.
    // synchronously, so the message has to be applied after that runs.
    function revealWithError(step_, message, isNamespaceError) {
        root.step = step_
        root.suppressOpenReset = true
        root.open()
        Qt.callLater(function () {
            if (isNamespaceError)
                namespaceErrorText.text = message
            else
                errorText.text = message
        })
    }

    Connections {
        target: euclidClient
        function onLoginFailed(message) {
            if (root.autoLoginActive) {
                root.autoLoginActive = false
                root.revealWithError(0, message, false)
            } else {
                errorText.text = message
            }
        }
        // Login ends by asking which accounts this user may work in. The default one is settled at
        // once and its namespaces fetched, so the step opens with both pickers filled; choosing
        // another account there refetches (see accountCombo.onActivated).
        function onAccountsLoaded(accounts, homeAccountId) {
            root.accounts = accounts
            root.homeAccountId = homeAccountId
            accountCombo.currentIndex = root.defaultAccountIndex()
            root.useAccount(accounts.length > 0 ? accounts[accountCombo.currentIndex].accountId
                                                : euclidClient.accountId)
        }
        function onAccountsFailed(message) {
            // The session is live; only the question of where else this user may work went
            // unanswered. So carry on with the account login already put on the session - the home
            // one - rather than stranding somebody who is signed in on a step with nothing to
            // choose from. Said rather than swallowed, because the absence of a choice is otherwise
            // indistinguishable from having only one account.
            accountErrorText.text = "Could not list your accounts: " + message
                                    + ". Continuing in your home account."
            euclidClient.fetchNamespaces()
        }

        function onNamespacesLoaded(namespaces) {
            namespaceCombo.model = namespaces
            const kept = root.preferredNamespace.length > 0 ? namespaces.indexOf(root.preferredNamespace) : -1
            namespaceCombo.currentIndex = kept >= 0 ? kept : 0
            root.step = 1

            if (root.autoLoginActive) {
                root.autoLoginActive = false
                if (namespaces.length > 0) {
                    const idx = root.autoNamespace.length > 0 ? namespaces.indexOf(root.autoNamespace) : -1
                    namespaceCombo.currentIndex = idx >= 0 ? idx : 0
                    root.selectedNamespace = namespaceCombo.currentText
                    root.loggedIn(usernameField.text, root.selectedNamespace)
                    root.close()
                } else {
                    root.revealWithError(1, "This account has no namespaces available.", true)
                }
            } else if (namespaces.length === 0) {
                // Said rather than left as an empty, disabled picker: with more than one account
                // the way on is to choose another, which an unexplained dead end does not suggest.
                namespaceErrorText.text = "This account has no namespaces available."
            }
        }
        function onNamespacesFailed(message) {
            // Still the selection step: with more than one account, choosing another is the way out.
            root.step = 1
            namespaceCombo.model = []
            if (root.autoLoginActive) {
                root.autoLoginActive = false
                root.revealWithError(1, message, true)
            } else {
                namespaceErrorText.text = message
            }
        }
    }
}
