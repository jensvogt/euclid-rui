import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs

// Stores a certificate somebody else issued, with its private key, under a name.
//
// Two files rather than one, because that is how a certificate authority hands them over, and
// because the pair is what a listener needs: the chain it presents and the key that proves it is
// entitled to. Both are read locally and sent as text - "import-certificate" takes PEM in a JSON
// body, so there is no upload in the HTTP sense happening here.
//
// Shared between the certificates list and one certificate's details page, because "import a
// certificate" and "replace this certificate" are the same call: a name that already exists is
// overwritten, which is how a real certificate takes over from the self-signed one euclid
// generated for a listener, and how a renewed one is rolled out.
Dialog {
    id: root
    modal: true
    anchors.centerIn: parent
    width: 560
    padding: 28
    topPadding: 24
    bottomPadding: 24
    standardButtons: Dialog.NoButton

    // Set when replacing a particular certificate: the name is then what addresses it and must not
    // move, so the field is filled in and locked.
    property bool nameFixed: false
    property bool saving: false
    property string errorText: ""

    property url certificateFile: ""
    property url privateKeyFile: ""

    function pathOf(fileUrl) {
        const text = String(fileUrl)
        if (text.length === 0) return ""
        return text.indexOf("file://") === 0 ? text.substring(7) : text
    }

    function openForImport() {
        root.nameFixed = false
        nameField.text = ""
        descriptionField.text = ""
        root.certificateFile = ""
        root.privateKeyFile = ""
        root.errorText = ""
        root.saving = false
        root.open()
    }

    function openForReplace(name, description) {
        root.nameFixed = true
        nameField.text = name
        descriptionField.text = description ? description : ""
        root.certificateFile = ""
        root.privateKeyFile = ""
        root.errorText = ""
        root.saving = false
        root.open()
    }

    // Refused here rather than by the server, since these are what it would refuse anyway and the
    // message reads better before the round trip. That the key belongs to the certificate is not
    // one of them: only the server can tell, and it does.
    readonly property string problem: {
        if (nameField.text.trim().length === 0) return "A certificate needs a name - the one a listener asks for."
        if (String(root.certificateFile).length === 0) return "Choose the PEM certificate file."
        if (String(root.privateKeyFile).length === 0) return "Choose the private key file that belongs to it."
        return ""
    }

    background: Rectangle {
        radius: 16
        color: "#1b1e25"
        border.color: "#2c313c"
        border.width: 1
    }

    FileDialog {
        id: certificateFileDialog
        title: "Select the PEM certificate"
        // Opens where the last file dialog was left, and records where this one ends up - see
        // AppSettings::lastFileDialogFolder.
        currentFolder: appSettings.lastFileDialogFolder
        nameFilters: ["Certificates (*.pem *.crt *.cer)", "All files (*)"]
        onAccepted: {
            appSettings.lastFileDialogFolder = currentFolder
            root.certificateFile = selectedFile
        }
    }

    FileDialog {
        id: privateKeyFileDialog
        title: "Select the private key"
        currentFolder: appSettings.lastFileDialogFolder
        nameFilters: ["Private keys (*.pem *.key)", "All files (*)"]
        onAccepted: {
            appSettings.lastFileDialogFolder = currentFolder
            root.privateKeyFile = selectedFile
        }
    }

    contentItem: Column {
        width: root.availableWidth
        spacing: 16

        Column {
            width: parent.width
            spacing: 4
            Text {
                text: root.nameFixed ? "Replace Certificate" : "Import Certificate"
                color: "white"
                font.pixelSize: 18
                font.bold: true
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.nameFixed
                      ? "The new certificate is stored under the same name, so the listener that asks for "
                        + "it serves this one from its next restart."
                      : "Store a certificate and its private key under a name. An HTTPS listener serves the "
                        + "certificate its \"certificate\" setting names, so importing under that name is how "
                        + "a real certificate replaces a self-signed one."
                color: "#9aa1ac"
                font.pixelSize: 12
            }
        }

        Column {
            width: parent.width
            spacing: 4
            Text { text: "Name"; color: "#9aa1ac"; font.pixelSize: 12 }
            TextField {
                id: nameField
                width: parent.width
                enabled: !root.nameFixed
                placeholderText: "eag-production"
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
            }
        }

        Column {
            width: parent.width
            spacing: 4
            Text { text: "Description"; color: "#9aa1ac"; font.pixelSize: 12 }
            TextField {
                id: descriptionField
                width: parent.width
                placeholderText: "What this certificate is for"
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
            }
        }

        Column {
            width: parent.width
            spacing: 6
            Text { text: "Certificate (PEM)"; color: "#9aa1ac"; font.pixelSize: 12 }
            Row {
                width: parent.width
                spacing: 12
                Button {
                    id: certificateButton
                    text: "Choose…"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: certificateFileDialog.open()
                }
                Text {
                    width: parent.width - certificateButton.width - 12
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideLeft
                    text: root.pathOf(root.certificateFile).length > 0
                          ? root.pathOf(root.certificateFile) : "No file chosen"
                    color: root.pathOf(root.certificateFile).length > 0 ? "#c4c9d1" : "#6b7280"
                    font.pixelSize: 12
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "Leaf first, with whatever intermediates it was issued with after it - that chain is "
                      + "what a client needs to reach a trust anchor it already has."
                color: "#6b7280"
                font.pixelSize: 11
            }
        }

        Column {
            width: parent.width
            spacing: 6
            Text { text: "Private key (PEM)"; color: "#9aa1ac"; font.pixelSize: 12 }
            Row {
                width: parent.width
                spacing: 12
                Button {
                    id: keyButton
                    text: "Choose…"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: privateKeyFileDialog.open()
                }
                Text {
                    width: parent.width - keyButton.width - 12
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideLeft
                    text: root.pathOf(root.privateKeyFile).length > 0
                          ? root.pathOf(root.privateKeyFile) : "No file chosen"
                    color: root.pathOf(root.privateKeyFile).length > 0 ? "#c4c9d1" : "#6b7280"
                    font.pixelSize: 12
                }
            }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "The key is checked against the certificate before either is stored, and never leaves "
                      + "the server again - it is not part of any response, so nothing can read it back out."
                color: "#6b7280"
                font.pixelSize: 11
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.errorText.length > 0
            text: root.errorText
            color: "#ff6b6b"
            font.pixelSize: 12
        }

        Item {
            width: parent.width
            height: 40

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 200
                wrapMode: Text.WordWrap
                text: root.problem
                color: "#ffb545"
                font.pixelSize: 11
                visible: root.problem.length > 0
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Button {
                    text: "Cancel"
                    flat: true
                    Material.theme: Material.Dark
                    onClicked: root.close()
                }
                Button {
                    text: root.saving ? "Importing…" : "Import"
                    highlighted: true
                    enabled: !root.saving && root.problem.length === 0
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: {
                        root.errorText = ""
                        root.saving = true
                        ekmClient.importCertificate(nameField.text.trim(), descriptionField.text.trim(),
                                                    root.certificateFile, root.privateKeyFile)
                    }
                }
            }
        }
    }
}
