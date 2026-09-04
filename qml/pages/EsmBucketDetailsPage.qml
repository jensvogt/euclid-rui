import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string bucketErn: ""
    property string bucketName: ""
    property var details: ({})

    signal back()
    signal viewObjects(string bucketErn, string bucketName)

    // Erns look like ern:esm:{region}:{accountId}:{namespace}:bucket:{name}
    function ernPart(index) {
        const parts = root.bucketErn.split(":")
        return index < parts.length ? parts[index] : "—"
    }

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function tagList() {
        const tags = detail("tags", {})
        return tags ? Object.keys(tags) : []
    }

    // No "get single bucket" action exists server-side to re-fetch after a mutation, so apply the
    // now-confirmed change to the local details snapshot instead (reassigned, not mutated in
    // place, so the "var" property change notification actually fires).
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

    // Same reason as the tag helpers above: nothing re-reads the bucket, so the confirmed setting
    // is written into the local snapshot.
    function setEncryptionLocally(keyErn) {
        root.details = Object.assign({}, root.details, { encrypted: keyErn.length > 0, encryptionKeyErn: keyErn })
    }

    // Whether the *next* object written here is encrypted. Says nothing about what the bucket
    // already holds, which is the whole point of the warnings below.
    readonly property bool encrypted: !!detail("encrypted", false)
    readonly property string encryptionKeyErn: detail("encryptionKeyErn", "")
    // What the last enable/disable reported, kept on screen because it is the number an operator
    // has to act on and nothing else will tell them again.
    property string encryptionNote: ""

    // One instance of this page serves every bucket, so a note about the last one must not follow
    // the user to the next.
    onBucketErnChanged: {
        root.encryptionNote = ""
        root.purgeNote = ""
    }

    Connections {
        target: esmClient
        function onBucketEncryptionEnabled(bucketErn, keyErn, keyId, algorithm, keyCreated, existingObjects) {
            if (bucketErn !== root.bucketErn) return
            encryptionDialog.saving = false
            encryptionDialog.close()
            root.setEncryptionLocally(keyErn)
            root.encryptionNote = "Encrypting under " + (keyCreated ? "new " : "") + algorithm + " key " + keyId + ". "
                    + (existingObjects > 0
                       ? existingObjects + " object(s) already in this bucket are still stored unencrypted - copy or re-upload them to encrypt them."
                       : "The bucket was empty, so everything it holds from now on is encrypted.")
        }
        function onBucketEncryptionDisabled(bucketErn, previousKeyErn, previousKeyId, encryptedObjects) {
            if (bucketErn !== root.bucketErn) return
            encryptionDialog.saving = false
            encryptionDialog.close()
            root.setEncryptionLocally("")
            root.encryptionNote = encryptedObjects > 0
                    ? encryptedObjects + " object(s) are still stored encrypted and are still read back through their key"
                      + (previousKeyId.length > 0 ? " (" + previousKeyId + ")" : "")
                      + " - do not delete it in EKM while they exist."
                    : "Nothing in this bucket is stored encrypted any more."
        }
        function onBucketEncryptionFailed(message) {
            encryptionDialog.saving = false
            encryptionDialog.errorText = message
        }
        function onBucketTagAdded(bucketErn, key, value) {
            if (bucketErn !== root.bucketErn) return
            addTagDialog.saving = false
            addTagDialog.close()
            root.addTagLocally(key, value)
        }
        function onBucketTagAddFailed(message) {
            addTagDialog.saving = false
            addTagDialog.errorText = message
        }
        function onBucketTagDeleted(bucketErn, key) {
            if (bucketErn !== root.bucketErn) return
            root.removeTagLocally(key)
        }
        function onBucketPurged(bucketErn, async, objects) {
            if (bucketErn !== root.bucketErn) return
            root.purgeNote = async
                    ? "Purging " + objects + " object(s) in the background. The counts above fall as it works through them."
                    : "Purged " + objects + " object(s)."
        }
    }

    readonly property int objects: Number(detail("objects", 0))

    // See EsmBucketsPage: past this many objects a synchronous purge outlasts its own request.
    readonly property int asyncPurgeThreshold: 1000
    // What the last purge did; a background one is still running when the answer arrives.
    property string purgeNote: ""

    ScrollView {
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            width: parent.width
            spacing: 20

            Button {
                text: "‹ Back to Buckets"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.bucketName
                    subtitle: root.bucketErn
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: "- Purge"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        enabled: root.objects > 0
                        onClicked: {
                            // Same rule as the buckets table: a bucket of any size goes to the
                            // server's background purge rather than being waited for, and that is
                            // asked rather than assumed.
                            if (root.objects > root.asyncPurgeThreshold) purgeDialog.open()
                            else esmClient.purgeBucket(root.bucketErn, false)
                        }
                    }

                    Button {
                        text: "View Objects"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: root.viewObjects(root.bucketErn, root.bucketName)
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#4cd97b"
                font.pixelSize: 12
                visible: root.purgeNote.length > 0
                text: root.purgeNote
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard { title: "Objects"; value: String(root.objects); trend: "in bucket"; trendUp: true; accent: "#4cd97b" }
                StatCard { title: "Size"; value: SizeFormat.format(root.detail("size", 0)); trend: "on disk"; trendUp: true; accent: "#c56bff" }
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Owner"; value: root.detail("owner", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.ernPart(2) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.ernPart(3) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Namespace"; value: root.ernPart(4) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    DetailField { width: identityCol.width; label: "Bucket ERN"; value: root.bucketErn; copyable: true }
                }
            }

            Rectangle {
                width: parent.width
                height: encryptionCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: encryptionCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Encryption at Rest"; color: "white"; font.pixelSize: 15; font.bold: true }

                    CheckBox {
                        id: encryptionCheck
                        text: "Encrypt objects written to this bucket"
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        checked: root.encrypted
                        // The box never flips on its own: the click asks, the server answers, and
                        // the binding above is what shows the bucket's actual setting meanwhile.
                        onClicked: {
                            checked = Qt.binding(function () { return root.encrypted })
                            encryptionDialog.openFor(!root.encrypted)
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#9aa1ac"
                        font.pixelSize: 12
                        text: root.encrypted
                              ? "Objects written from here on are encrypted with the bucket's EKM key before they reach the disk and decrypted on the way back out. Uploads and downloads are unchanged."
                              : "Objects written from here on are stored in the clear. Objects written while encryption was on stay encrypted and keep working."
                    }

                    DetailField {
                        width: encryptionCol.width
                        visible: root.encryptionKeyErn.length > 0
                        label: "Encryption key ERN"
                        value: root.encryptionKeyErn
                        copyable: true
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#e0a458"
                        font.pixelSize: 12
                        visible: root.encryptionNote.length > 0
                        text: root.encryptionNote
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
                        text: "No tags set for this bucket."
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
                                            onClicked: esmClient.deleteBucketTag(root.bucketErn, modelData)
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

    Dialog {
        id: purgeDialog
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
            width: purgeDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Purge Bucket"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: root.bucketName + "  ·  " + root.objects + " objects"
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
                text: "⚠  Every object in this bucket is deleted, and there is no undo. Objects are removed one at "
                      + "a time, so " + root.objects + " of them take a while."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "Deleting in the background hands the work to the server and answers straight away: the bucket "
                      + "is not empty when this dialog closes, and the counts above fall over the following "
                      + "refreshes. Waiting for it keeps this window on the request until every object is gone, "
                      + "which for a bucket this size can outlast the request's own timeout."
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
                    onClicked: purgeDialog.close()
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Button {
                        text: "Wait for it"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        onClicked: {
                            esmClient.purgeBucket(root.bucketErn, false)
                            purgeDialog.close()
                        }
                    }
                    Button {
                        text: "Delete in background"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: {
                            esmClient.purgeBucket(root.bucketErn, true)
                            purgeDialog.close()
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: encryptionDialog
        modal: true
        anchors.centerIn: parent
        width: 440
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        // Which way the checkbox was asking to go, captured when it was clicked rather than read
        // back from the bucket, so the dialog says the same thing for as long as it is open.
        property bool enabling: true
        property bool saving: false
        property string errorText: ""

        function openFor(enable) {
            encryptionDialog.enabling = enable
            encryptionDialog.open()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            encryptionDialog.errorText = ""
            encryptionDialog.saving = false
            keyIdField.text = ""
        }

        contentItem: Column {
            width: encryptionDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: encryptionDialog.enabling ? "Enable Encryption at Rest" : "Disable Encryption at Rest"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    text: "Bucket " + root.bucketName
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                    width: parent.width
                }
            }

            // The consequences, and they are the same in both directions: this decides what happens
            // to the *next* object written, the ones already stored are never touched, and the key
            // outlives the setting.
            Column {
                width: parent.width
                spacing: 10

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#e0a458"
                    font.pixelSize: 12
                    text: encryptionDialog.enabling
                          ? (root.objects > 0
                             ? "⚠  This applies to new uploads and puts only. The " + root.objects
                               + " object(s) already in this bucket are left exactly as they were stored - still unencrypted on disk. Copy or re-upload them if they have to be encrypted too."
                             : "⚠  This applies to new uploads and puts only. Objects already in the bucket are never re-encrypted; it holds none right now.")
                          : "⚠  This applies to new uploads and puts only. Objects already stored encrypted are NOT decrypted and NOT rewritten - each one still names its key and is still read back through it, so downloads keep working."
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#e0a458"
                    font.pixelSize: 12
                    text: encryptionDialog.enabling
                          ? "⚠  The bucket's EKM key is what its objects depend on. Deleting that key with \"ekm delete-key\" is what makes every object encrypted under it unrecoverable - there is no other copy."
                          : "⚠  The bucket's EKM key is left untouched: not revoked, not scheduled for deletion. Retire it only once nothing in this bucket is stored encrypted any more."
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    visible: encryptionDialog.enabling && root.encrypted
                    text: "This bucket is already encrypting. Naming another key rotates it: new objects go under the new key, existing ones keep the key they name."
                }
            }

            Column {
                width: parent.width
                spacing: 6
                visible: encryptionDialog.enabling

                Text { text: "EKM key (optional)"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: keyIdField
                    width: parent.width
                    placeholderText: "Key ID or ERN - leave empty to create a new key"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (confirmEncryptionButton.enabled) confirmEncryptionButton.clicked()
                }
                Text {
                    text: "Without a key, a fresh AES-256 key is created for this bucket and shows up in EKM like any other."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Text {
                text: encryptionDialog.errorText
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
                    onClicked: encryptionDialog.close()
                }

                BusyIndicator {
                    running: encryptionDialog.saving
                    visible: encryptionDialog.saving
                    width: 22
                    height: 22
                    anchors.right: confirmEncryptionButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: confirmEncryptionButton
                    text: encryptionDialog.enabling ? "Enable Encryption" : "Disable Encryption"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: encryptionDialog.enabling ? "#4f8cff" : "#ff6b6b"
                    enabled: !encryptionDialog.saving
                    onClicked: {
                        encryptionDialog.errorText = ""
                        encryptionDialog.saving = true
                        if (encryptionDialog.enabling)
                            esmClient.enableBucketEncryption(root.bucketErn, keyIdField.text.trim())
                        else
                            esmClient.disableBucketEncryption(root.bucketErn)
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
                    text: "Set a key/value tag on this bucket."
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
                    placeholderText: "e.g. environment"
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
                    placeholderText: "e.g. production"
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
                        esmClient.addBucketTag(root.bucketErn, tagKeyField.text.trim(), tagValueField.text)
                    }
                }
            }
        }
    }
}
