import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import "../components"

// One certificate: what it says about itself, who vouched for it, and how long it has left.
//
// The private key is not here and cannot be. It stays on the server and is part of no response, so
// what this page can offer is the certificate - which is what a client needs in order to trust the
// listener serving it, and not what would let anything impersonate that listener.
//
// The two questions worth arriving with are "will this stop working" and "has anybody vouched for
// this", which is why the validity period and the self-signed flag are the first things on it.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string certificateName: ""
    property var details: ({})

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    readonly property bool generated: !!detail("generated", false)
    readonly property string subject: String(detail("subject", "—"))
    readonly property string issuer: String(detail("issuer", "—"))
    readonly property string pem: String(detail("certificate", ""))
    readonly property var altNames: detail("subjectAltNames", [])

    readonly property int daysLeft: {
        const raw = root.detail("notAfter", "")
        if (!raw) return NaN
        const notAfter = new Date(raw)
        if (isNaN(notAfter.getTime())) return NaN
        return Math.floor((notAfter.getTime() - Date.now()) / 86400000)
    }
    readonly property bool expired: !isNaN(root.daysLeft) && root.daysLeft < 0

    property string actionNote: ""
    property string error: ""

    function refresh() {
        if (!root.loggedIn || root.certificateName.length === 0)
            return
        ekmClient.fetchCertificate(root.certificateName)
    }

    onVisibleChanged: if (visible) refresh()
    onCertificateNameChanged: if (visible) refresh()

    Connections {
        target: ekmClient
        function onCertificateLoaded(name, certificate) {
            if (name !== root.certificateName) return
            root.details = certificate
            root.error = ""
        }
        function onCertificatesFailed(message) {
            root.error = message
        }
        function onCertificateImported(name, certificate) {
            if (name !== root.certificateName) return
            importDialog.saving = false
            importDialog.close()
            root.details = certificate
            root.actionNote = "Replaced. A listener serving this name picks the new certificate up at its "
                              + "next restart."
        }
        function onCertificateImportFailed(message) {
            importDialog.saving = false
            importDialog.errorText = message
        }
        function onCertificateExported(name, path) {
            if (name !== root.certificateName) return
            root.actionNote = "Saved to " + path + ". The private key stays on the server and is not in the file."
        }
        function onCertificateExportFailed(message) {
            root.actionNote = ""
            root.error = message
        }
        function onCertificateDeleted(name) {
            // Nothing left to show; the list is where a deleted certificate's absence makes sense.
            if (name === root.certificateName) root.back()
        }
        function onCertificateDeleteFailed(message) {
            root.error = message
        }
    }

    CertificateImportDialog {
        id: importDialog
    }

    FileDialog {
        id: saveFileDialog
        title: "Save the certificate as"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "pem"
        // Opens where the last file dialog was left, and records where this one ends up - see
        // AppSettings::lastFileDialogFolder.
        currentFolder: appSettings.lastFileDialogFolder
        nameFilters: ["Certificates (*.pem *.crt)", "All files (*)"]
        onAccepted: {
            appSettings.lastFileDialogFolder = currentFolder
            root.error = ""
            ekmClient.exportCertificate(root.certificateName, selectedFile)
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
                text: "‹ Back to Certificates"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.certificateName
                    subtitle: "Held by EKM in the " + root.namespaceName + " namespace."
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: "Download…"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: {
                            saveFileDialog.currentFile = root.certificateName + ".pem"
                            saveFileDialog.open()
                        }
                    }
                    Button {
                        text: "Replace…"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: importDialog.openForReplace(root.certificateName, root.detail("description", ""))
                    }
                    Button {
                        text: "Delete"
                        flat: true
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
                    title: "Validity"
                    value: root.expired ? "EXPIRED"
                                        : (isNaN(root.daysLeft) ? "—" : root.daysLeft + " d")
                    trend: root.expired
                           ? "callers refuse it"
                           : (isNaN(root.daysLeft) ? "no expiry recorded" : "until " + DateFormat.format(root.detail("notAfter", "")))
                    trendUp: !root.expired
                    accent: root.expired ? "#ff4f5e" : (root.daysLeft < 30 ? "#ffb545" : "#4cd97b")
                }
                StatCard {
                    title: "Vouched for by"
                    value: root.generated ? "NOBODY" : "AN ISSUER"
                    trend: root.generated ? "self-signed, generated by euclid" : root.issuer
                    trendUp: !root.generated
                    accent: root.generated ? "#ffb545" : "#4cd97b"
                }
                StatCard {
                    title: "Valid for"
                    value: root.altNames && root.altNames.length > 0 ? String(root.altNames.length) : "—"
                    trend: root.altNames && root.altNames.length > 0 ? "names and addresses" : "no alternative names"
                    trendUp: root.altNames && root.altNames.length > 0
                    accent: "#4f8cff"
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

                    DetailField { width: identityCol.width; label: "Subject"; value: root.subject; copyable: true }
                    DetailField { width: identityCol.width; label: "Issuer"; value: root.issuer; copyable: true }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (identityCol.width - 48) / 3; label: "Serial number"; value: root.detail("serialNumber", "—"); copyable: true }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Valid from"; value: DateFormat.format(root.detail("notBefore", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Valid until"; value: DateFormat.format(root.detail("notAfter", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Origin"; value: root.generated ? "generated by euclid" : "imported" }
                    }

                    // What somebody compares against when asked whether to trust a self-signed
                    // certificate, so it is here in full rather than shortened as in the table.
                    DetailField { width: identityCol.width; label: "SHA-256 fingerprint"; value: root.detail("fingerprint", "—"); copyable: true }
                    DetailField { width: identityCol.width; label: "Certificate ERN"; value: root.detail("ern", "—"); copyable: true }
                    DetailField {
                        width: identityCol.width
                        label: "Valid for"
                        value: root.altNames && root.altNames.length > 0 ? root.altNames.join(", ") : "—"
                        copyable: true
                    }
                    DetailField {
                        width: identityCol.width
                        label: "Description"
                        value: String(root.detail("description", "")).length > 0 ? root.detail("description", "") : "—"
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: trustCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                visible: root.generated || root.expired

                Column {
                    id: trustCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 10

                    Text { text: "Worth knowing"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.generated
                        color: "#e0a458"
                        font.pixelSize: 12
                        text: "⚠ Self-signed. Euclid generated this itself because a listener needed something to "
                              + "start with, which is what lets an installation serve HTTPS before anybody has "
                              + "bought it a certificate. No client accepts it until it is given this certificate "
                              + "as a trust anchor of its own - download it above, or replace it with a real one "
                              + "under the same name."
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.expired
                        color: "#ff8f8f"
                        font.pixelSize: 12
                        text: "⚠ Expired. A listener serving this keeps answering - euclid reports an expired "
                              + "certificate rather than refusing to start, since taking the port down would take "
                              + "away the one thing still working while a replacement is fetched - but callers "
                              + "that check will refuse it."
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: pemCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                visible: root.pem.length > 0

                Column {
                    id: pemCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 12

                    Text { text: "Certificate (PEM)"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 11
                        text: "Leaf first, with whatever intermediates it was issued with after it. The private "
                              + "key is not here: it stays on the server and is part of no response."
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.min(pemText.implicitHeight + 24, 320)
                        radius: 10
                        color: "#171a21"
                        border.color: "#2c313c"
                        border.width: 1
                        clip: true

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 12
                            contentHeight: pemText.implicitHeight
                            clip: true

                            TextEdit {
                                id: pemText
                                width: parent.width
                                readOnly: true
                                selectByMouse: true
                                wrapMode: TextEdit.WrapAnywhere
                                text: root.pem
                                color: "#9aa1ac"
                                font.pixelSize: 11
                                font.family: "monospace"
                            }
                        }
                    }

                    Button {
                        text: "Copy"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: {
                            pemText.selectAll()
                            pemText.copy()
                            pemText.deselect()
                            root.actionNote = "Certificate copied to the clipboard."
                        }
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#4cd97b"
                font.pixelSize: 12
                visible: root.actionNote.length > 0 && root.error.length === 0
                text: root.actionNote
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: root.error.length > 0
                text: root.error
            }
        }
    }

    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        standardButtons: Dialog.NoButton

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: deleteDialog.availableWidth
            spacing: 16

            Text { text: "Delete Certificate"; color: "white"; font.pixelSize: 18; font.bold: true }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "\"" + root.certificateName + "\" and its private key are removed at once - there is no "
                      + "grace period, because unlike a key nothing becomes unreadable. A listener already "
                      + "serving it keeps the copy it loaded until it restarts, and one that restarts without "
                      + "it generates a self-signed replacement under the same name. To put a different "
                      + "certificate on that listener, replace this one instead."
                color: "#c4c9d1"
                font.pixelSize: 12
            }

            Item {
                width: parent.width
                height: 40

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Button {
                        text: "Cancel"
                        flat: true
                        Material.theme: Material.Dark
                        onClicked: deleteDialog.close()
                    }
                    Button {
                        text: "Delete"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        onClicked: {
                            ekmClient.deleteCertificate(root.certificateName)
                            deleteDialog.close()
                        }
                    }
                }
            }
        }
    }
}
