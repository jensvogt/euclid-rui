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

    property int step: 0 // 0 = credentials, 1 = namespace picker
    property string selectedNamespace: ""
    property string autoNamespace: ""
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
    function autoLogin(user, password, namespaceHint) {
        usernameField.text = user
        passwordField.text = password
        root.autoNamespace = namespaceHint
        root.autoLoginActive = true
        errorText.text = ""
        euclidClient.login(user, password)
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
            namespaceErrorText.text = ""
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
                text: root.step === 0 ? "Enter your credentials to continue." : "Choose a namespace for this session."
                color: "#9aa1ac"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        Item {
            width: parent.width
            height: Math.max(credentialsStep.implicitHeight, namespaceStep.implicitHeight)

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
                id: namespaceStep
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
                visible: root.step === 1
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
        function onNamespacesLoaded(namespaces) {
            namespaceCombo.model = namespaces
            namespaceCombo.currentIndex = 0
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
            }
        }
        function onNamespacesFailed(message) {
            root.step = 1
            if (root.autoLoginActive) {
                root.autoLoginActive = false
                root.revealWithError(1, message, true)
            } else {
                namespaceErrorText.text = message
            }
        }
    }
}
