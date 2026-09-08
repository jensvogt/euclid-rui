import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string secretErn: ""
    property string secretName: ""
    property var details: ({})

    signal back()

    // Erns look like ern:ess:{region}:{accountId}:{namespace}:secret:{name} - namespace-scoped,
    // since a secret's name is only unique within one.
    function ernPart(index) {
        const parts = root.secretErn.split(":")
        return index < parts.length ? parts[index] : "—"
    }

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function tagList() {
        const tags = detail("tags", {})
        return tags ? Object.keys(tags) : []
    }

    // The key name out of "ern:ekm:{region}:{accountId}:key:{name}".
    function keyName(keyErn) {
        if (!keyErn || keyErn.length === 0) return "—"
        const parts = String(keyErn).split(":")
        return parts[parts.length - 1]
    }

    // A create, a rotation and a re-key all answer with the secret as it now stands, so the
    // snapshot this page was handed is replaced with it rather than re-fetched (reassigned, not
    // mutated in place, so the "var" property change notification actually fires).
    function applySecret(secret) {
        root.details = Object.assign({}, root.details, secret)
    }

    function addTagLocally(key, value) {
        const tags = Object.assign({}, detail("tags", {}))
        tags[key] = value
        root.details = Object.assign({}, root.details, { tags: tags })
    }

    function removeTagLocally(key) {
        const tags = Object.assign({}, detail("tags", {}))
        delete tags[key]
        root.details = Object.assign({}, root.details, { tags: tags })
    }

    readonly property string description: detail("description", "")
    readonly property string encryptionKeyErn: detail("encryptionKeyErn", "")
    readonly property int version: Number(detail("version", 0))
    readonly property string rotated: detail("rotated", "")

    property bool descriptionSaving: false
    property string descriptionError: ""

    // The decrypted value, held only while it is on screen. Nothing else on this page reads it and
    // nothing writes it into `details`, so leaving the page (below) is enough to be rid of it.
    property string revealedValue: ""
    property bool revealed: false
    property bool revealing: false
    property string revealError: ""

    function hideValue() {
        root.revealedValue = ""
        root.revealed = false
        root.revealing = false
        root.revealError = ""
        hideTimer.stop()
    }

    // Navigating away drops it. A secret left uncovered on a page nobody is looking at is the
    // shoulder-surfing case this whole screen is otherwise careful about.
    onVisibleChanged: if (!visible) hideValue()
    onSecretNameChanged: hideValue()

    Timer {
        id: hideTimer
        // Long enough to read it or paste it somewhere, short enough that an unattended screen
        // does not keep showing it.
        interval: 60000
        onTriggered: root.hideValue()
    }

    Connections {
        target: essClient
        function onSecretValueLoaded(name, value, secret) {
            if (name !== root.secretName) return
            root.revealing = false
            root.revealError = ""
            root.revealedValue = value
            root.revealed = true
            // get-secret answers with the metadata too, so this is the one place the page gets a
            // genuinely fresh view of the secret rather than the listing's snapshot.
            root.applySecret(secret)
            hideTimer.restart()
        }
        function onSecretValueFailed(name, message) {
            if (name !== root.secretName) return
            root.revealing = false
            root.revealError = message
        }

        function onSecretRotated(name, secret) {
            if (name !== root.secretName) return
            rotateDialog.saving = false
            rotateDialog.close()
            // What is on screen is the previous value, and it is no longer the secret.
            root.hideValue()
            root.applySecret(secret)
        }
        function onSecretRotateFailed(message) {
            rotateDialog.saving = false
            rotateDialog.errorText = message
        }

        function onSecretReKeyed(name, secret) {
            if (name !== root.secretName) return
            reKeyDialog.saving = false
            reKeyDialog.close()
            root.applySecret(secret)
        }
        function onSecretReKeyFailed(message) {
            reKeyDialog.saving = false
            reKeyDialog.errorText = message
        }

        // Writing the saved text back into the snapshot is what moves the editor's baseline, so the
        // "unsaved" marker clears without the editor being reloaded from underneath the user.
        function onSecretDescriptionChanged(name, description) {
            if (name !== root.secretName) return
            root.descriptionSaving = false
            root.descriptionError = ""
            root.details = Object.assign({}, root.details, { description: description })
        }
        function onSecretDescriptionFailed(message) {
            root.descriptionSaving = false
            root.descriptionError = message
        }

        function onSecretTagAdded(name, key, value) {
            if (name !== root.secretName) return
            addTagDialog.saving = false
            addTagDialog.close()
            root.addTagLocally(key, value)
        }
        function onSecretTagAddFailed(message) {
            addTagDialog.saving = false
            addTagDialog.errorText = message
        }
        function onSecretTagDeleted(name, key) {
            if (name !== root.secretName) return
            root.removeTagLocally(key)
        }

        // Nothing left to show, so the page goes back to the list rather than sitting on a secret
        // that is not there any more.
        function onSecretDeleted(name) {
            if (name !== root.secretName || !root.visible) return
            root.back()
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
                text: "‹ Back to Secrets"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.secretName
                    subtitle: root.secretErn
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: "Rotate"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: rotateDialog.open()
                    }

                    Button {
                        text: "Delete"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        onClicked: deleteDialog.open()
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "Version"
                    value: String(root.version)
                    trend: root.version > 1 ? "rotations included" : "never rotated"
                    trendUp: root.version > 1
                    accent: "#4f8cff"
                }
                StatCard {
                    title: "Last Rotated"
                    value: root.rotated.length > 0 ? DateFormat.format(root.rotated) : "—"
                    trend: "value last changed"
                    trendUp: true
                    accent: "#c56bff"
                    width: 320
                }
                StatCard {
                    title: "Encryption Key"
                    value: root.keyName(root.encryptionKeyErn)
                    trend: "EKM key the value is sealed with"
                    trendUp: true
                    accent: "#4cd97b"
                    width: 440
                }
                StatCard {
                    title: "Tags"
                    value: String(root.tagList().length)
                    trend: "set on this secret"
                    trendUp: root.tagList().length > 0
                    accent: "#ffb545"
                }
            }

            // The value. Not shown until it is asked for: reading one is an action the server
            // records against the user who did it, and it should be as deliberate here as it is
            // in the audit log.
            Rectangle {
                width: parent.width
                height: valueCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: valueCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: valueHeaderRow.implicitHeight

                        Row {
                            id: valueHeaderRow
                            spacing: 10
                            Text { text: "Value"; color: "white"; font.pixelSize: 15; font.bold: true }
                            Text {
                                text: "· visible"
                                color: "#e0a458"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.revealed
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: valueHeaderRow.verticalCenter
                            spacing: 8

                            BusyIndicator {
                                running: root.revealing
                                visible: root.revealing
                                width: 22
                                height: 22
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                text: "Copy"
                                flat: true
                                Material.theme: Material.Dark
                                visible: root.revealed
                                onClicked: {
                                    valueClipboard.text = root.revealedValue
                                    valueClipboard.selectAll()
                                    valueClipboard.copy()
                                }
                            }

                            Button {
                                text: root.revealed ? "Hide" : "Reveal"
                                highlighted: !root.revealed
                                flat: root.revealed
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                enabled: !root.revealing && root.loggedIn
                                onClicked: {
                                    if (root.revealed) {
                                        root.hideValue()
                                        return
                                    }
                                    root.revealError = ""
                                    root.revealing = true
                                    essClient.fetchSecretValue(root.secretName)
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.max(48, valueText.implicitHeight + 24)
                        radius: 10
                        color: "#181b21"
                        border.color: root.revealed ? "#3a4152" : "#2c313c"
                        border.width: 1

                        TextEdit {
                            id: valueText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 12
                            // Selectable so it can be picked out by hand, read-only so what is on
                            // screen is always what the server answered with.
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.WrapAnywhere
                            font.family: "monospace"
                            font.pixelSize: 13
                            color: root.revealed ? "#c4c9d1" : "#6b7280"
                            text: root.revealed ? root.revealedValue : "••••••••••••••••"
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 11
                        visible: root.revealError.length === 0
                        text: root.revealed
                              ? "Hidden again in a minute, or as soon as this page is left."
                              : "Revealing decrypts the value under its EKM key and is logged server-side with who asked."
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        visible: root.revealError.length > 0
                        text: root.revealError
                    }
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

                    Item {
                        width: parent.width
                        height: identityHeaderRow.implicitHeight

                        Row {
                            id: identityHeaderRow
                            Text { text: "Identity"; color: "white"; font.pixelSize: 15; font.bold: true }
                        }

                        Button {
                            text: "Change key"
                            flat: true
                            anchors.right: parent.right
                            anchors.verticalCenter: identityHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: reKeyDialog.open()
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.ernPart(2) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.ernPart(3) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Namespace"; value: root.ernPart(4) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Rotated"; value: root.rotated.length > 0 ? DateFormat.format(root.rotated) : "—" }
                    }

                    DetailField { width: identityCol.width; label: "Secret ERN"; value: root.secretErn; copyable: true }
                    DetailField {
                        width: identityCol.width
                        label: "Encryption Key ERN"
                        value: root.encryptionKeyErn.length > 0 ? root.encryptionKeyErn : "—"
                        copyable: root.encryptionKeyErn.length > 0
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: descriptionCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: descriptionCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: descriptionHeaderRow.implicitHeight

                        Row {
                            id: descriptionHeaderRow
                            spacing: 10
                            Text { text: "Description"; color: "white"; font.pixelSize: 15; font.bold: true }
                            Text {
                                text: "· unsaved"
                                color: "#e0a458"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                                visible: descriptionView.modified
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: descriptionHeaderRow.verticalCenter
                            spacing: 8

                            Button {
                                text: "Revert"
                                flat: true
                                Material.theme: Material.Dark
                                visible: descriptionView.modified
                                enabled: !root.descriptionSaving
                                onClicked: {
                                    root.descriptionError = ""
                                    descriptionView.reset()
                                }
                            }

                            BusyIndicator {
                                running: root.descriptionSaving
                                visible: root.descriptionSaving
                                width: 22
                                height: 22
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Button {
                                text: "Save"
                                highlighted: true
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                enabled: descriptionView.modified && !root.descriptionSaving
                                onClicked: {
                                    root.descriptionError = ""
                                    root.descriptionSaving = true
                                    // Sent as typed, empty included: clearing the box is how a
                                    // description is removed.
                                    essClient.setSecretDescription(root.secretName, descriptionView.text)
                                }
                            }
                        }
                    }

                    EditableText {
                        id: descriptionView
                        width: parent.width
                        height: 120
                        showHeader: false
                        contentType: "text/plain"
                        wrapMode: TextArea.Wrap
                        content: root.description
                        emptyText: "What this secret is for - which system it opens, who owns it, how often it should be rotated. Never any part of the value: anyone who may list secrets can read this."
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        visible: root.descriptionError.length > 0
                        text: root.descriptionError
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: tagsCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: tagsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: tagsHeaderRow.implicitHeight

                        Row {
                            id: tagsHeaderRow
                            Text { text: "Tags"; color: "white"; font.pixelSize: 15; font.bold: true }
                        }

                        Button {
                            text: "+ Add"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: tagsHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: addTagDialog.open()
                        }
                    }

                    Text {
                        visible: root.tagList().length === 0
                        text: "No tags set for this secret."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: root.tagList().length > 0

                        Repeater {
                            model: root.tagList()
                            delegate: Rectangle {
                                radius: 8
                                color: "#2c3648"
                                height: 26
                                width: chipRow.implicitWidth + 20

                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData + ": " + root.detail("tags", {})[modelData]
                                        color: "#c4c9d1"
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "×"
                                        color: removeArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                        font.pixelSize: 13
                                        font.bold: true

                                        MouseArea {
                                            id: removeArea
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: essClient.deleteSecretTag(root.secretName, modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Hidden TextEdit is the standard QML idiom for clipboard access, and the same one
    // DetailField uses - TextEdit.copy() reaches the system clipboard with no extra import.
    TextEdit {
        id: valueClipboard
        visible: false
        text: ""
    }

    Dialog {
        id: rotateDialog
        modal: true
        anchors.centerIn: parent
        width: 440
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            newValueField.text = ""
            newValueField.echoMode = TextInput.Password
            rotateDialog.errorText = ""
            rotateDialog.saving = false
            newValueField.forceActiveFocus()
        }
        onClosed: newValueField.text = ""

        contentItem: Column {
            width: rotateDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Rotate Secret"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: root.secretName + "  ·  version " + root.version
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6

                Item {
                    width: parent.width
                    height: newValueLabel.implicitHeight

                    Text { id: newValueLabel; text: "New value"; color: "#9aa1ac"; font.pixelSize: 12 }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: newValueLabel.verticalCenter
                        text: newValueField.echoMode === TextInput.Password ? "Show" : "Hide"
                        color: showNewValueArea.containsMouse ? "#4f8cff" : "#6b7280"
                        font.pixelSize: 11

                        MouseArea {
                            id: showNewValueArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: newValueField.echoMode = newValueField.echoMode === TextInput.Password
                                                                ? TextInput.Normal : TextInput.Password
                        }
                    }
                }

                TextField {
                    id: newValueField
                    width: parent.width
                    echoMode: TextInput.Password
                    placeholderText: "The replacement password, token or connection string"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (rotateButton.enabled) rotateButton.clicked()
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#e0a458"
                font.pixelSize: 12
                text: "⚠  The previous value is gone: euclid keeps one version, and this becomes version "
                      + (root.version + 1) + ". Anything still using the old one has to be updated."
            }

            Text {
                text: rotateDialog.errorText
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
                    onClicked: rotateDialog.close()
                }

                BusyIndicator {
                    running: rotateDialog.saving
                    visible: rotateDialog.saving
                    width: 22
                    height: 22
                    anchors.right: rotateButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: rotateButton
                    text: "Rotate"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !rotateDialog.saving && newValueField.text.length > 0
                    onClicked: {
                        rotateDialog.errorText = ""
                        rotateDialog.saving = true
                        essClient.rotateSecret(root.secretName, newValueField.text)
                    }
                }
            }
        }
    }

    Dialog {
        id: reKeyDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            newKeyField.text = ""
            reKeyDialog.errorText = ""
            reKeyDialog.saving = false
            newKeyField.forceActiveFocus()
        }

        contentItem: Column {
            width: reKeyDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Change Encryption Key"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Currently " + root.keyName(root.encryptionKeyErn)
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "New key ERN"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: newKeyField
                    width: parent.width
                    placeholderText: "ern:ekm:…  ·  copy it from EKM › Keys"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (reKeyButton.enabled) reKeyButton.clicked()
                }
                Text {
                    text: "The value is decrypted under the current key and stored again under the new one. It does "
                          + "not change, so this is not a rotation: the version and the rotation date stay as they are. "
                          + "The key has to be one EKM will still encrypt with."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Text {
                    text: reKeyDialog.errorText
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
                    onClicked: reKeyDialog.close()
                }

                BusyIndicator {
                    running: reKeyDialog.saving
                    visible: reKeyDialog.saving
                    width: 22
                    height: 22
                    anchors.right: reKeyButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: reKeyButton
                    text: "Re-encrypt"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !reKeyDialog.saving && newKeyField.text.trim().length > 0
                    onClicked: {
                        reKeyDialog.errorText = ""
                        reKeyDialog.saving = true
                        essClient.reKeySecret(root.secretName, newKeyField.text.trim())
                    }
                }
            }
        }
    }

    Dialog {
        id: addTagDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            tagKeyField.text = ""
            tagValueField.text = ""
            addTagDialog.errorText = ""
            addTagDialog.saving = false
            tagKeyField.forceActiveFocus()
        }

        contentItem: Column {
            width: addTagDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Tag"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Set a key/value tag on this secret. Readable by anyone who may list secrets, so it says "
                          + "what the secret is for and never anything about its value."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Key"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: tagKeyField
                    width: parent.width
                    placeholderText: "e.g. owner"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: tagValueField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Value"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: tagValueField
                    width: parent.width
                    placeholderText: "e.g. payroll"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (saveTagButton.enabled) saveTagButton.clicked()
                }
                Text {
                    text: addTagDialog.errorText
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
                    onClicked: addTagDialog.close()
                }

                BusyIndicator {
                    running: addTagDialog.saving
                    visible: addTagDialog.saving
                    width: 22
                    height: 22
                    anchors.right: saveTagButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: saveTagButton
                    text: "Add"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !addTagDialog.saving && tagKeyField.text.trim().length > 0
                    onClicked: {
                        addTagDialog.errorText = ""
                        addTagDialog.saving = true
                        essClient.addSecretTag(root.secretName, tagKeyField.text.trim(), tagValueField.text)
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 440
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
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Delete Secret"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: root.secretName
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#e0a458"
                font.pixelSize: 12
                text: "⚠  The value is gone with it, and euclid holds no other copy. Anything reading this "
                      + "secret by name starts failing the next time it asks."
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
                        essClient.deleteSecret(root.secretName)
                        deleteDialog.close()
                    }
                }
            }
        }
    }
}
