import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root

    // Set from Main.qml, like every other page: the key list needs a session, and the page is
    // already visible while the login dialog is still up.
    property bool loggedIn: false

    // Access keys of whoever is signed in. There is no admin view of anyone else's - the server's
    // access-key actions all act on the caller.
    property var accessKeys: []
    property string accessKeysError: ""
    property bool creatingKey: false
    // The secret of a key just created. The server returns it exactly once, so it is held here
    // until the user dismisses it rather than being re-fetchable.
    property string newAccessKeyId: ""
    property string newSecretAccessKey: ""

    onVisibleChanged: if (visible) root.refreshAccessKeys()
    onLoggedInChanged: if (loggedIn && visible) root.refreshAccessKeys()
    Component.onCompleted: root.refreshAccessKeys()

    // What F5 calls (see Main.qml's refreshCurrentPage()). The settings themselves are local and
    // always current; the access keys are the one thing here that is read from the server.
    function refresh() {
        root.refreshAccessKeys()
    }

    function refreshAccessKeys() {
        // Bearer mode has no key to show, and an unauthenticated list call would only produce an
        // error message on a page the user has not asked anything of yet.
        if (!root.loggedIn || appSettings.authMode === "bearer")
            return
        root.accessKeysError = ""
        eamClient.fetchAccessKeys()
    }

    Connections {
        target: eamClient
        function onAccessKeysLoaded(keys) {
            root.accessKeys = keys
            root.accessKeysError = ""
        }
        function onAccessKeysFailed(message) {
            root.accessKeysError = message
        }
        function onAccessKeysReload() {
            root.refreshAccessKeys()
        }
        function onAccessKeyCreated(accessKeyId, secretAccessKey) {
            root.creatingKey = false
            root.newAccessKeyId = accessKeyId
            root.newSecretAccessKey = secretAccessKey
            // Filled in straight away: this is the only moment the secret exists outside the
            // server, and copying it by hand is exactly what this screen is here to avoid.
            appSettings.setAccessKeyId(accessKeyId)
            appSettings.setSecretAccessKey(secretAccessKey)
        }
        function onAccessKeyCreateFailed(message) {
            root.creatingKey = false
            root.accessKeysError = message
        }
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            width: parent.width
            spacing: 28

            SectionHeader {
                title: "Settings"
                subtitle: "Manage your preferences and account options."
            }

            Rectangle {
                width: parent.width
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                height: content1.implicitHeight + 40

                Column {
                    id: content1
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 18

                    Text { text: "Notifications"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Repeater {
                        model: [
                            { label: "Email notifications", desc: "Get notified about important updates via email" },
                            { label: "Push notifications", desc: "Receive push alerts on your devices" },
                            { label: "Weekly digest", desc: "A summary of activity sent every Monday" }
                        ]
                        delegate: Row {
                            width: content1.width
                            height: 40

                            Column {
                                width: parent.width - 60
                                anchors.verticalCenter: parent.verticalCenter
                                Text { text: modelData.label; color: "#e5e7eb"; font.pixelSize: 13 }
                                Text { text: modelData.desc; color: "#9aa1ac"; font.pixelSize: 11 }
                            }
                            ToggleSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: index !== 1
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                height: content2.implicitHeight + 40

                Column {
                    id: content2
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 18

                    Text { text: "Profile"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Row {
                        spacing: 20
                        width: content2.width

                        Column {
                            width: (content2.width - 20) / 2
                            spacing: 6
                            Text { text: "Display name"; color: "#9aa1ac"; font.pixelSize: 12 }
                            TextField {
                                width: parent.width
                                text: "Jens Vogt"
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                            }
                        }
                        Column {
                            width: (content2.width - 20) / 2
                            spacing: 6
                            Text { text: "Time zone"; color: "#9aa1ac"; font.pixelSize: 12 }
                            ComboBox {
                                width: parent.width
                                model: ["UTC", "Europe/Zurich", "America/New_York", "Asia/Tokyo"]
                                currentIndex: 1
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                            }
                        }
                    }

                    Column {
                        width: content2.width
                        spacing: 6

                        Row {
                            width: parent.width
                            Text { text: "UI density"; color: "#9aa1ac"; font.pixelSize: 12; width: parent.width - 40 }
                            Text { text: Math.round(densitySlider.value * 100) + "%"; color: "#c4c9d1"; font.pixelSize: 12; width: 40; horizontalAlignment: Text.AlignRight }
                        }
                        Slider {
                            id: densitySlider
                            width: parent.width
                            from: 0.5
                            to: 1.5
                            value: 1.0
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                        }
                    }

                    Column {
                        width: content2.width
                        spacing: 6

                        Text { text: "Date & time format"; color: "#9aa1ac"; font.pixelSize: 12 }
                        TextField {
                            id: dateFormatField
                            width: parent.width
                            text: DateFormat.pattern
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onEditingFinished: DateFormat.pattern = text.length > 0 ? text : "dd-MM-yyyy HH:mm:ss"
                        }
                        Text {
                            text: "Example: " + DateFormat.format(new Date().toISOString())
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                        Text {
                            text: "Tokens: dd, MM, yyyy, HH, mm, ss — applies to every date/time shown in the app."
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                    }

                    Column {
                        width: content2.width
                        spacing: 6

                        Text { text: "Auto-refresh interval (seconds)"; color: "#9aa1ac"; font.pixelSize: 12 }
                        SpinBox {
                            id: autoRefreshSpinBox
                            width: 160
                            from: 0
                            to: 3600
                            stepSize: 5
                            value: appSettings.autoRefreshSeconds
                            editable: true
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onValueModified: appSettings.autoRefreshSeconds = value
                        }
                        Text {
                            text: autoRefreshSpinBox.value === 0
                                ? "Auto-refresh is off — pages only update on manual refresh or navigation."
                                : "Dashboards, queues, buckets and objects refresh themselves every " + autoRefreshSpinBox.value + " seconds."
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                    }

                    Row {
                        spacing: 12
                        Button {
                            text: "Save changes"
                            highlighted: true
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                        }
                        Button {
                            text: "Reset"
                            flat: true
                            Material.theme: Material.Dark
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                height: content4.implicitHeight + 40

                Column {
                    id: content4
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 18

                    // How requests authenticate. The gateway accepts all three; the two signature
                    // modes replace the login token with an EAM access key on every request.
                    Text { text: "Request Authentication"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Column {
                        width: content4.width
                        spacing: 6

                        ComboBox {
                            id: authModeCombo
                            width: 260
                            // Index order must match `modes` below.
                            property var modes: [ "bearer", "sigv4", "rfc9421" ]
                            model: [ "Bearer token (login)", "AWS SigV4", "RFC 9421 message signature" ]
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            // Set imperatively rather than bound: a ComboBox clobbers a
                            // currentIndex binding while it populates its own model.
                            Component.onCompleted: currentIndex = Math.max(0, modes.indexOf(appSettings.authMode))
                            onActivated: {
                                appSettings.setAuthMode(modes[currentIndex])
                                root.refreshAccessKeys()
                            }
                        }

                        Text {
                            text: authModeCombo.currentIndex === 0
                                  ? "Requests carry the JWT the password login returns."
                                  : "Every request is signed with the access key below. Signing in with a password still "
                                    + "establishes the session; the token is then no longer sent."
                            color: "#6b7280"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            width: content4.width
                        }
                    }

                    Column {
                        id: accessKeysColumn
                        width: content4.width
                        spacing: 8
                        visible: authModeCombo.currentIndex !== 0

                        Item {
                            width: parent.width
                            height: accessKeysHeader.implicitHeight

                            Text {
                                id: accessKeysHeader
                                text: "Your access keys"
                                color: "#9aa1ac"
                                font.pixelSize: 12
                            }

                            Row {
                                anchors.right: parent.right
                                anchors.verticalCenter: accessKeysHeader.verticalCenter
                                spacing: 8

                                BusyIndicator {
                                    running: root.creatingKey
                                    visible: root.creatingKey
                                    width: 20
                                    height: 20
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Button {
                                    text: "Refresh"
                                    flat: true
                                    Material.theme: Material.Dark
                                    onClicked: root.refreshAccessKeys()
                                }
                                Button {
                                    text: "+ Create key"
                                    highlighted: true
                                    enabled: !root.creatingKey
                                    Material.theme: Material.Dark
                                    Material.accent: "#4f8cff"
                                    onClicked: {
                                        root.accessKeysError = ""
                                        root.creatingKey = true
                                        eamClient.createAccessKey()
                                    }
                                }
                            }
                        }

                        Text {
                            text: "Keys belong to the signed-in user; this lists your own, never anyone else's."
                            color: "#6b7280"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }

                        Text {
                            visible: root.accessKeysError.length > 0
                            text: root.accessKeysError
                            color: "#ff6b6b"
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            width: parent.width
                        }

                        Text {
                            visible: root.accessKeys.length === 0 && root.accessKeysError.length === 0
                            text: "No access keys yet."
                            color: "#6b7280"
                            font.pixelSize: 12
                        }

                        Repeater {
                            model: root.accessKeys
                            delegate: Row {
                                id: keyRow
                                required property var modelData

                                width: accessKeysColumn.width
                                height: 30
                                spacing: 12

                                Text {
                                    text: keyRow.modelData.accessKeyId
                                    color: "#e5e7eb"
                                    font.pixelSize: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 260
                                }
                                // The key the app is actually signing with, so a list of several
                                // says which one is in use rather than leaving it to be guessed.
                                Rectangle {
                                    visible: keyRow.modelData.accessKeyId === appSettings.accessKeyId
                                    radius: 6
                                    color: "#1e3350"
                                    height: 20
                                    width: inUseLabel.implicitWidth + 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    Text {
                                        id: inUseLabel
                                        anchors.centerIn: parent
                                        text: "in use"
                                        color: "#4f8cff"
                                        font.pixelSize: 10
                                    }
                                }
                                Text {
                                    text: keyRow.modelData.active ? "active" : "inactive"
                                    color: keyRow.modelData.active ? "#4cd97b" : "#9aa1ac"
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 60
                                }
                                Text {
                                    text: DateFormat.format(keyRow.modelData.createdAt)
                                    color: "#6b7280"
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 150
                                }
                                Text {
                                    text: "Delete"
                                    color: deleteKeyArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter

                                    MouseArea {
                                        id: deleteKeyArea
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: eamClient.deleteAccessKey(keyRow.modelData.accessKeyId)
                                    }
                                }
                            }
                        }

                        // Shown once, right after creating a key: the server never returns the
                        // secret again, and it has already been filled into the fields below.
                        Rectangle {
                            visible: root.newSecretAccessKey.length > 0
                            width: parent.width
                            height: newKeyColumn.implicitHeight + 24
                            radius: 10
                            color: "#1b2430"
                            border.color: "#2c3648"
                            border.width: 1

                            Column {
                                id: newKeyColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 12
                                spacing: 4

                                Text {
                                    text: "New key " + root.newAccessKeyId + " is now in use for signing."
                                    color: "#e5e7eb"
                                    font.pixelSize: 12
                                }
                                Text {
                                    text: "The secret is shown only now - copy it if anything else needs it."
                                    color: "#9aa1ac"
                                    font.pixelSize: 11
                                }
                                TextInput {
                                    width: parent.width
                                    text: root.newSecretAccessKey
                                    color: "#c4c9d1"
                                    font.pixelSize: 12
                                    readOnly: true
                                    selectByMouse: true
                                }
                                Button {
                                    text: "Dismiss"
                                    flat: true
                                    Material.theme: Material.Dark
                                    onClicked: {
                                        root.newAccessKeyId = ""
                                        root.newSecretAccessKey = ""
                                    }
                                }
                            }
                        }
                    }

                    Column {
                        width: content4.width
                        spacing: 6
                        visible: authModeCombo.currentIndex !== 0

                        Text { text: "Access key ID"; color: "#9aa1ac"; font.pixelSize: 12 }
                        TextField {
                            id: accessKeyIdField
                            width: 420
                            text: appSettings.accessKeyId
                            placeholderText: "e.g. AKIA..."
                            Material.accent: "#4f8cff"
                            selectByMouse: true
                            onEditingFinished: appSettings.setAccessKeyId(text)
                        }

                        Text { text: "Secret access key"; color: "#9aa1ac"; font.pixelSize: 12 }
                        TextField {
                            id: secretAccessKeyField
                            width: 420
                            text: appSettings.secretAccessKey
                            echoMode: TextInput.Password
                            Material.accent: "#4f8cff"
                            selectByMouse: true
                            onEditingFinished: appSettings.setSecretAccessKey(text)
                        }
                        Text {
                            text: "Filled in automatically by \"Create key\" above. Stored in the configuration file "
                                  + "below, which is written owner-readable only."
                            color: "#6b7280"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            width: content4.width
                        }
                    }

                    // Where the settings above (and the gateway from the sign-in dialog) end up.
                    // Worth stating outright: a config file nobody can find is barely a config file.
                    Column {
                        width: content4.width
                        spacing: 6

                        Text { text: "Configuration file"; color: "#9aa1ac"; font.pixelSize: 12 }
                        TextInput {
                            width: content4.width
                            text: appSettings.configFilePath
                            color: "#c4c9d1"
                            font.pixelSize: 12
                            readOnly: true
                            selectByMouse: true
                        }
                        Text {
                            text: "Written as JSON whenever a setting changes; edit it by hand and restart to apply."
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // Only for administrators: EMM refuses "export" and "import" to anyone else, so
            // offering it to a user who cannot use it would only produce a 403 they can do
            // nothing about. The server checks for itself regardless - this is about what is
            // worth showing, not about what is allowed.
            Rectangle {
                visible: euclidClient.isAdmin
                width: parent.width
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                height: backupContent.implicitHeight + 40

                Column {
                    id: backupContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 12

                    Text { text: "Backup & Restore"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        text: "Exports the modules' database collections as JSON - every module except EMO, "
                              + "with the messages and objects inside them optional - and imports such a file back. "
                              + "Monitoring data is not part of it."
                        color: "#9aa1ac"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Button {
                        text: "Export or import data…"
                        highlighted: true
                        enabled: root.loggedIn
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: importExportDialog.open()
                    }
                }
            }
        }
    }

    ImportExportDialog {
        id: importExportDialog
        parent: Overlay.overlay
    }
}
