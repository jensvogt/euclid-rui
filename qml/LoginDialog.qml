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

    property int step: 0 // 0 = credentials, 1 = account picker, 2 = namespace picker
    property string selectedNamespace: ""
    property string autoNamespace: ""

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

    // Asking somebody to choose from one option is not a choice, it is a click - so the step is
    // shown only when there is something to decide. The account is still set either way, and the
    // namespace step says which one it was.
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
                                      : (root.step === 1 ? "Choose the account to work in."
                                                         : "Choose a namespace for this session.")
                color: "#9aa1ac"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        Item {
            width: parent.width
            height: Math.max(credentialsStep.implicitHeight, accountStep.implicitHeight, namespaceStep.implicitHeight)

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

            Column {
                id: accountStep
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
                        Text {
                            text: "Signed in as " + usernameField.text
                            color: "#c4c9d1"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: "Account"; color: "#9aa1ac"; font.pixelSize: 12 }
                    ComboBox {
                        id: accountCombo
                        width: parent.width
                        Material.accent: "#4f8cff"
                        model: root.accountLabels
                        enabled: count > 0
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
            }

            Column {
                id: namespaceStep
                width: parent.width
                spacing: 16
                opacity: root.step === 2 ? 1 : 0
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
                            // Which account this session is about to work in. Said even when there
                            // was nothing to choose - most people have one account and never see
                            // the step before this, and "no choice was offered" and "the choice
                            // went somewhere unexpected" look identical without it.
                            Text {
                                text: "Account · " + root.activeAccountLabel
                                color: "#6b7280"
                                font.pixelSize: 11
                                visible: root.activeAccountLabel.length > 0
                            }
                        }
                    }
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
                        enabled: count > 0
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
                // Back from the namespaces lands on the accounts only when there was a choice to
                // make there; otherwise that step was never shown and going "back" to it would be
                // a dead end with one row in it.
                onClicked: root.step = (root.step === 2 && root.accountChoice) ? 1 : 0
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
                    : (root.step === 1 ? accountCombo.count > 0 : namespaceCombo.count > 0))

                onClicked: {
                    if (root.step === 0) {
                        errorText.text = ""
                        root.applyGateway()
                        euclidClient.login(usernameField.text, passwordField.text)
                    } else if (root.step === 1) {
                        accountErrorText.text = ""
                        namespaceErrorText.text = ""
                        root.useAccount(root.accounts[accountCombo.currentIndex].accountId)
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
        // Login now ends by asking which accounts this user may work in, so this is the step that
        // follows a password rather than the namespaces.
        function onAccountsLoaded(accounts, homeAccountId) {
            root.accounts = accounts
            root.homeAccountId = homeAccountId
            accountCombo.currentIndex = root.defaultAccountIndex()

            // One account is not a decision: set it and carry straight on to the namespaces, which
            // is exactly what this dialog did before an account could be chosen at all.
            if (!root.accountChoice) {
                root.useAccount(accounts.length > 0 ? accounts[accountCombo.currentIndex].accountId
                                                    : euclidClient.accountId)
                return
            }

            // An auto-login that named an account, or one that did not and gets home: a session
            // started from the command line should not stop to ask.
            if (root.autoLoginActive) {
                root.useAccount(accounts[accountCombo.currentIndex].accountId)
                return
            }

            root.step = 1
        }
        function onAccountsFailed(message) {
            // The session is live; only the question of where else this user may work went
            // unanswered. So carry on with the account login already put on the session - the home
            // one - rather than stranding somebody who is signed in on a step with nothing to
            // choose from. Said on the next step rather than swallowed, because the absence of a
            // choice is otherwise indistinguishable from having only one account.
            namespaceErrorText.text = "Could not list your accounts: " + message
                                      + ". Continuing in your home account."
            euclidClient.fetchNamespaces()
        }

        function onNamespacesLoaded(namespaces) {
            namespaceCombo.model = namespaces
            namespaceCombo.currentIndex = 0
            root.step = 2

            if (root.autoLoginActive) {
                root.autoLoginActive = false
                if (namespaces.length > 0) {
                    const idx = root.autoNamespace.length > 0 ? namespaces.indexOf(root.autoNamespace) : -1
                    namespaceCombo.currentIndex = idx >= 0 ? idx : 0
                    root.selectedNamespace = namespaceCombo.currentText
                    root.loggedIn(usernameField.text, root.selectedNamespace)
                    root.close()
                } else {
                    root.revealWithError(2, "This account has no namespaces available.", true)
                }
            }
        }
        function onNamespacesFailed(message) {
            // Step 2, the namespace step, which these errors are about. It was step 1 until the
            // account step was put in front of it, and landing on that one instead showed an
            // account picker that nothing had filled in.
            root.step = 2
            if (root.autoLoginActive) {
                root.autoLoginActive = false
                root.revealWithError(2, message, true)
            } else {
                namespaceErrorText.text = message
            }
        }
    }
}
