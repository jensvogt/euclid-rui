import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string bucketName: ""
    property string objectErn: ""
    property string objectKey: ""
    property var details: ({})

    signal back()

    // Erns look like ern:esm:{region}:{accountId}:{namespace}:object:{key}
    function ernPart(index) {
        const parts = root.objectErn.split(":")
        return index < parts.length ? parts[index] : "—"
    }

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function statusColor(status) {
        if (status === "COMPLETED") return "#4cd97b"
        if (status === "UPLOADING" || status === "UPLOADED") return "#ffb545"
        if (status === "CREATED") return "#4f8cff"
        return "#9aa1ac"
    }

    readonly property string status: detail("status", "")
    readonly property string contentType: detail("contentType", "")
    readonly property string bucketErn: detail("bucketErn", "")
    readonly property int objectSize: Number(detail("size", 0))

    // The object's bytes, for the ones worth showing. Nothing is fetched until the content type
    // says it can be displayed and the object is small enough - a preview that downloads a 2 GB
    // archive to then refuse to render it is worse than no preview.
    //
    // An image is fetched base64 encoded and a text object as text, because those are the forms the
    // two viewers read; only one of them is ever filled.
    property string objectContent: ""
    property string objectImageData: ""
    property string contentError: ""
    property bool contentLoading: false
    // Also handed to the server as the cutoff it enforces, so an object at or above this never
    // arrives at all rather than arriving and being rejected here. Images get more room than text:
    // a photograph is routinely larger than any document worth reading in a details page, and
    // showing one costs a decode rather than laying out a million lines.
    readonly property int maxPreviewBytes: 512 * 1024
    readonly property int maxImageBytes: 8 * 1024 * 1024

    // Which of the two viewers, if either, can show this object. Both verdicts come from the
    // viewers themselves (declared in the content card below; ids are visible file-wide) rather
    // than a third list here that could disagree with them. The image viewer is asked first: an
    // SVG is XML as well, and an image is what someone looking at one wants to see.
    readonly property bool previewIsImage: imageView.format.length > 0
    readonly property bool previewIsText: !root.previewIsImage && contentView.format.length > 0
    readonly property int previewLimit: root.previewIsImage ? root.maxImageBytes : root.maxPreviewBytes

    // Why there is no preview, empty when there is one (or when it is still loading).
    readonly property string previewSkipReason: {
        if (!root.previewIsImage && !root.previewIsText) {
            // An image format this build has no decoder for is worth saying so about, rather than
            // reporting it as "an image" that simply will not appear.
            const description = contentView.normalizedType(root.contentType).startsWith("image/")
                              ? imageView.typeDescription(root.contentType)
                              : contentView.typeDescription(root.contentType)
            return "Cannot preview " + description + "."
        }
        if (root.objectSize >= root.previewLimit)
            return "This object is " + SizeFormat.format(root.objectSize) + ", past the "
                   + SizeFormat.format(root.previewLimit) + " this view will render. Download it instead."
        if (root.status !== "COMPLETED")
            return "The object is " + (root.status.length > 0 ? root.status.toLowerCase() : "not stored yet")
                   + ", so its content cannot be read."
        return ""
    }

    property bool downloading: false
    property string downloadStatus: ""
    property string downloadError: ""

    // A key is a path within the bucket, so the last segment is the file name the user expects the
    // save dialog to offer.
    function suggestedFileName() {
        const index = root.objectKey.lastIndexOf("/")
        return index >= 0 ? root.objectKey.substring(index + 1) : root.objectKey
    }

    function refreshContent() {
        root.objectContent = ""
        root.objectImageData = ""
        root.contentError = ""
        root.contentLoading = false
        // Also runs on every navigation, so a message about the previous object's download does
        // not stay on screen for the next one. A download already in flight keeps running; its
        // reply is dropped by the bucket/key check in the handlers above.
        root.downloading = false
        root.downloadStatus = ""
        root.downloadError = ""
        if (!root.loggedIn || root.objectKey.length === 0 || root.bucketErn.length === 0)
            return
        if (root.previewSkipReason.length > 0)
            return
        root.contentLoading = true
        if (root.previewIsImage)
            esmClient.fetchObjectContentBase64(root.bucketErn, root.objectKey, root.previewLimit)
        else
            esmClient.fetchObjectContent(root.bucketErn, root.objectKey, root.previewLimit)
    }

    // The object's user-defined attributes, {name: {type, value}}. Seeded from the listing that
    // opened this page so the card is populated immediately, then re-read from
    // "list-object-attributes" - the authoritative source, and the only thing that reflects a
    // change made anywhere else.
    property var attributes: ({})
    property string attributesError: ""

    onDetailsChanged: {
        root.attributes = root.detail("attributes", ({}))
        // Deferred, and through callLater so several of these collapse into one: the page's ern,
        // key and details are assigned one after another, and a fetch started on the first of them
        // would be reading the previous object's content type and size.
        Qt.callLater(root.refreshContent)
    }
    onObjectErnChanged: {
        root.refreshAttributes()
        Qt.callLater(root.refreshContent)
    }
    onVisibleChanged: if (visible) {
        root.refreshAttributes()
        Qt.callLater(root.refreshContent)
    }

    // What F5 calls (see Main.qml's refreshCurrentPage()): both halves of this page that are read
    // from the server.
    function refresh() {
        root.refreshAttributes()
        root.refreshContent()
    }

    function refreshAttributes() {
        if (!root.loggedIn || root.objectErn.length === 0)
            return
        esmClient.fetchObjectAttributes(root.objectErn)
    }

    function attributeNames() {
        return Object.keys(root.attributes).sort()
    }

    // Attribute values arrive typed - a bool prints as true/false, a number without quotes - so
    // the row shows the value as stored rather than everything as a string.
    function attributeText(name) {
        const attribute = root.attributes[name]
        if (!attribute) return ""
        return String(attribute.value)
    }

    function attributeType(name) {
        const attribute = root.attributes[name]
        return attribute && attribute.type ? attribute.type : "string"
    }

    // Add and set are separate actions server-side and each is strict - add refuses a name that
    // already exists, set refuses one that doesn't - so which to call follows from whether the
    // dialog was opened on an existing attribute.
    function saveAttribute(name, type, value, editing) {
        root.attributesError = ""
        if (editing) esmClient.setObjectAttribute(root.objectErn, name, type, value)
        else esmClient.addObjectAttribute(root.objectErn, name, type, value)
    }

    function removeAttribute(name) {
        root.attributesError = ""
        esmClient.deleteObjectAttribute(root.objectErn, name)
    }

    Connections {
        target: esmClient
        function onObjectAttributesLoaded(objectErn, attributes) {
            if (objectErn !== root.objectErn) return
            root.attributes = attributes
            root.attributesError = ""
        }
        // A mutation returns only the attribute it touched, so the list is re-read rather than
        // patched - that also picks up anything changed from elsewhere in the same round trip.
        function onObjectAttributeChanged(objectErn, name) {
            if (objectErn !== root.objectErn) return
            attributeDialog.saving = false
            attributeDialog.close()
            root.refreshAttributes()
        }
        function onObjectAttributesFailed(message) {
            attributeDialog.saving = false
            if (attributeDialog.opened) attributeDialog.errorText = message
            else root.attributesError = message
        }
        function onObjectContentLoaded(bucketErn, key, content) {
            if (key !== root.objectKey || bucketErn !== root.bucketErn) return
            root.contentLoading = false
            root.contentError = ""
            root.objectContent = content
        }
        function onObjectContentBase64Loaded(bucketErn, key, base64) {
            if (key !== root.objectKey || bucketErn !== root.bucketErn) return
            root.contentLoading = false
            root.contentError = ""
            root.objectImageData = base64
        }
        function onObjectContentFailed(bucketErn, key, message) {
            if (key !== root.objectKey || bucketErn !== root.bucketErn) return
            root.contentLoading = false
            root.contentError = message
        }
        function onDownloadProgress(bucketErn, key, bytesReceived, bytesTotal) {
            if (key !== root.objectKey || bucketErn !== root.bucketErn) return
            root.downloadStatus = "Downloading… " + SizeFormat.format(bytesReceived) + " of " + SizeFormat.format(bytesTotal)
        }
        function onObjectDownloaded(bucketErn, key, path) {
            if (key !== root.objectKey || bucketErn !== root.bucketErn) return
            root.downloading = false
            root.downloadStatus = "Saved to " + path
        }
        // No bucket/key to match on: a failure can happen before the download has one (a path that
        // cannot be written), and only one download runs from this page at a time.
        function onObjectDownloadFailed(message) {
            root.downloading = false
            root.downloadStatus = ""
            root.downloadError = message
        }
    }

    FileDialog {
        id: saveFileDialog
        title: "Save object as"
        fileMode: FileDialog.SaveFile
        onAccepted: {
            root.downloadError = ""
            root.downloadStatus = "Starting…"
            root.downloading = true
            esmClient.downloadObject(root.bucketErn, root.objectKey, selectedFile)
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
                text: "‹ Back to Objects"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.objectKey
                    subtitle: root.objectErn
                }

                Button {
                    text: "- Delete"
                    flat: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#ff6b6b"
                    onClicked: {
                        esmClient.deleteObject(root.detail("bucketErn", ""), root.objectErn)
                        root.back()
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "Status"
                    value: root.status.length > 0 ? root.status : "—"
                    trend: root.status === "COMPLETED" ? "stored" : "processing"
                    trendUp: root.status === "COMPLETED"
                    accent: root.statusColor(root.status)
                }
                StatCard { title: "Size"; value: SizeFormat.format(root.detail("size", 0)); trend: "on disk"; trendUp: true; accent: "#c56bff" }
                // Twice the standard card width: a content type is a full MIME type, sometimes with
                // parameters, and does not fit what a count or a size needs.
                StatCard {
                    title: "Content Type"
                    value: root.detail("contentType", "—")
                    trend: "format"
                    trendUp: true
                    accent: "#4f8cff"
                    width: implicitWidth * 2
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

                    Text { text: "Identity"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (identityCol.width - 48) / 3; label: "Bucket"; value: root.bucketName; copyable: true }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.ernPart(2) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.ernPart(3) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Namespace"; value: root.ernPart(4) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    // Both on their own row and copyable: a key is a path and an ERN contains one,
                    // so either is long enough to elide in a third of the tile, and both are what
                    // the CLI and every other client want pasted in.
                    DetailField { width: identityCol.width; label: "Key"; value: root.objectKey; copyable: true }
                    DetailField { width: identityCol.width; label: "Object ERN"; value: root.objectErn; copyable: true }
                    DetailField { width: identityCol.width; label: "Bucket ERN"; value: root.bucketErn; copyable: true }
                }
            }

            Rectangle {
                width: parent.width
                height: techCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: techCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Technical Details"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Grid {
                        width: parent.width
                        columns: 2
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (techCol.width - 24) / 2; label: "MD5 Sum"; value: root.detail("md5Sum", "—"); copyable: true }
                    }
                }
            }

            FoldableTile {
                id: contentTile
                width: parent.width
                title: "Content"
                expanded: true

                headerContent: [
                    BusyIndicator {
                        running: root.contentLoading || root.downloading
                        visible: running
                        implicitWidth: 20
                        implicitHeight: 20
                    },
                    Button {
                        text: "Reload"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        // Nothing to reload when there is nothing this view will show.
                        visible: root.previewSkipReason.length === 0
                        enabled: !root.contentLoading
                        onClicked: root.refreshContent()
                    },
                    Button {
                        // The way out for everything the viewer refuses - an archive, an image, or
                        // simply an object past the preview limit - and it works for the rest too.
                        text: "Download…"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        enabled: !root.downloading && root.objectKey.length > 0 && root.bucketErn.length > 0
                        onClicked: {
                            saveFileDialog.currentFile = root.suggestedFileName()
                            saveFileDialog.open()
                        }
                    }
                ]

                contentData: [
                    Column {
                        width: contentTile.width - 32
                        spacing: 12

                        // Both viewers are declared, and each decides for itself whether the content
                        // type is one it can show - which is what previewIsImage/previewIsText read
                        // above. Only one of them is ever handed any bytes.
                        //
                        // Read-only: this shows what is stored. Writing an edit back would be a
                        // put-object that replaces the object, which is not what a details page does.
                        EditableText {
                            id: contentView
                            width: parent.width
                            height: 360
                            visible: root.previewIsText && root.objectContent.length > 0
                            contentType: root.contentType
                            content: root.objectContent
                            maxLength: root.maxPreviewBytes
                            readOnly: true
                        }

                        ImageViewer {
                            id: imageView
                            width: parent.width
                            height: 360
                            visible: root.previewIsImage && root.objectImageData.length > 0
                            contentType: root.contentType
                            base64Data: root.objectImageData
                            maxBytes: root.maxImageBytes
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: "#6b7280"
                            font.pixelSize: 12
                            visible: root.previewSkipReason.length > 0
                            text: root.previewSkipReason
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: "#ff6b6b"
                            font.pixelSize: 12
                            visible: root.contentError.length > 0
                            text: root.contentError
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: root.downloadError.length > 0 ? "#ff6b6b" : "#4cd97b"
                            font.pixelSize: 12
                            visible: text.length > 0
                            text: root.downloadError.length > 0 ? root.downloadError : root.downloadStatus
                        }
                    }
                ]
            }

            Rectangle {
                width: parent.width
                height: attributesCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: attributesCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: attributesHeaderRow.implicitHeight

                        Row {
                            id: attributesHeaderRow
                            Text { text: "Attributes"; color: "white"; font.pixelSize: 15; font.bold: true }
                        }

                        Button {
                            text: "+ Add"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: attributesHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: attributeDialog.openFor("", "string", "")
                        }
                    }

                    Text {
                        width: parent.width
                        text: "User-defined, typed values stored with the object. Each one is added, changed or removed "
                              + "on its own; a name can only be added once."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.attributesError.length > 0
                        width: parent.width
                        text: root.attributesError
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.attributeNames().length === 0
                        text: "No attributes set on this object."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.attributeNames()
                        delegate: Row {
                            id: attributeRow
                            required property string modelData

                            width: attributesCol.width
                            height: 30
                            spacing: 12

                            Text {
                                text: attributeRow.modelData
                                color: "#e5e7eb"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                width: Math.min(220, attributeRow.width * 0.3)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Rectangle {
                                radius: 6
                                color: "#2c3648"
                                height: 20
                                width: typeLabel.implicitWidth + 14
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    id: typeLabel
                                    anchors.centerIn: parent
                                    text: root.attributeType(attributeRow.modelData)
                                    color: "#9aa1ac"
                                    font.pixelSize: 10
                                }
                            }
                            Text {
                                text: root.attributeText(attributeRow.modelData)
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: attributeRow.width - Math.min(220, attributeRow.width * 0.3) - typeLabel.implicitWidth - 160
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Edit"
                                color: editArea.containsMouse ? "#4f8cff" : "#9aa1ac"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    id: editArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: attributeDialog.openFor(attributeRow.modelData,
                                        root.attributeType(attributeRow.modelData),
                                        root.attributeText(attributeRow.modelData))
                                }
                            }
                            Text {
                                text: "Remove"
                                color: removeArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    id: removeArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeAttribute(attributeRow.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: attributeDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""
        // Non-empty while editing an existing attribute: its name is then fixed, since renaming
        // would be a remove plus an add rather than one write.
        property string editingName: ""

        // The ComboBox's currentIndex is set here rather than bound, same as every other dialog in
        // this app - its own model-populate logic clobbers a binding.
        function openFor(name, type, value) {
            attributeDialog.editingName = name
            attributeDialog.errorText = ""
            attributeDialog.saving = false
            attributeDialog.open()
            nameField.text = name
            valueField.text = value
            typeCombo.currentIndex = Math.max(0, typeCombo.model.indexOf(type))
            if (name.length === 0) nameField.forceActiveFocus()
            else valueField.forceActiveFocus()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: attributeDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: attributeDialog.editingName.length > 0 ? "Edit Attribute" : "Add Attribute"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    text: "Stored with the object and typed - the type decides how the value comes back out."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: nameField
                    width: parent.width
                    placeholderText: "e.g. source-system"
                    enabled: attributeDialog.editingName.length === 0
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: valueField.forceActiveFocus()
                }
            }

            Column {
                id: typeColumn
                width: parent.width
                spacing: 6
                Text { text: "Type"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: typeCombo
                    width: typeColumn.width
                    // Everything Dto::COM::Variant can read back except "binary", which would need
                    // base64 the user has no way to produce here.
                    model: [ "string", "int", "long", "float", "double", "bool" ]
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Value"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: valueField
                    width: parent.width
                    placeholderText: typeCombo.currentText === "bool" ? "true or false" : ""
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (saveAttributeButton.enabled) saveAttributeButton.clicked()
                }
                Text {
                    text: attributeDialog.errorText
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
                    onClicked: attributeDialog.close()
                }

                BusyIndicator {
                    running: attributeDialog.saving
                    visible: attributeDialog.saving
                    width: 22
                    height: 22
                    anchors.right: saveAttributeButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: saveAttributeButton
                    text: "Save"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !attributeDialog.saving && nameField.text.trim().length > 0
                    onClicked: {
                        const type = typeCombo.currentText
                        const raw = valueField.text.trim()

                        // Checked here rather than server-side: Variant reads the JSON type the
                        // "type" field names, so a non-numeric "long" would be rejected as a bad
                        // request with nothing pointing at the field that caused it.
                        let value = raw
                        if (type === "bool") {
                            const lowered = raw.toLowerCase()
                            if (lowered !== "true" && lowered !== "false") {
                                attributeDialog.errorText = "A bool attribute must be true or false."
                                return
                            }
                            value = lowered === "true"
                        } else if (type !== "string") {
                            const parsed = Number(raw)
                            if (raw.length === 0 || isNaN(parsed)) {
                                attributeDialog.errorText = "A " + type + " attribute needs a number."
                                return
                            }
                            if ((type === "int" || type === "long") && !Number.isInteger(parsed)) {
                                attributeDialog.errorText = "A " + type + " attribute needs a whole number."
                                return
                            }
                            value = parsed
                        }

                        attributeDialog.errorText = ""
                        attributeDialog.saving = true
                        root.saveAttribute(nameField.text.trim(), type, value,
                            attributeDialog.editingName.length > 0)
                    }
                }
            }
        }
    }
}
