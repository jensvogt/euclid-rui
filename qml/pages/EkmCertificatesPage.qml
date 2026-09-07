import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs
import "../components"

// EKM: the X.509 certificates the installation holds, and what they are still good for.
//
// Here rather than under EAG, even though the API gateway is what serves them, because a
// certificate is key material and this is where euclid keeps key material - one place that knows
// what exists, who it belongs to and when it expires. A gateway listener names one of these; see
// the EAG listeners page for which port is serving which.
//
// Two ways one gets here. Generated: self-signed, for an installation that has to speak HTTPS
// before anybody has bought it a certificate - nobody has vouched for it and clients refuse it
// until they are told to trust it. Imported: somebody's real certificate and its key, which is
// also how a generated one is replaced and how a renewal is rolled out, since importing under an
// existing name overwrites it.
//
// The private key is never part of any response, so "download" saves the certificate only. That is
// what a client needs to trust the listener, and not what would let anything impersonate it.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    property string prefix: ""
    property int pageIndex: 0
    property int pageSize: 10
    property string sortColumn: "name"
    property bool sortAscending: true

    property var certificates: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    // What the last action did, kept next to the table: a listener picks up a replaced certificate
    // at its next restart rather than visibly here.
    property string actionNote: ""

    signal back()
    signal openCertificateDetails(string name, var details)

    // Days until it stops being accepted, or NaN when there is nothing to count.
    function daysLeft(row) {
        if (!row || !row.notAfter) return NaN
        const notAfter = new Date(row.notAfter)
        if (isNaN(notAfter.getTime())) return NaN
        return Math.floor((notAfter.getTime() - Date.now()) / 86400000)
    }

    function expiryText(row) {
        const days = root.daysLeft(row)
        if (isNaN(days)) return DateFormat.format(row ? row.notAfter : "")
        if (days < 0) return "expired " + (-days) + " d ago"
        return DateFormat.format(row.notAfter) + " (" + days + " d)"
    }

    function expiryColor(row) {
        const days = root.daysLeft(row)
        if (isNaN(days)) return "#9aa1ac"
        if (days < 0) return "#ff4f5e"
        if (days < 30) return "#ffb545"
        return "#4cd97b"
    }

    // A fingerprint is 64 hex characters and unreadable in a table. The ends are what somebody
    // actually compares when checking one by eye; the details page has all of it.
    function shortFingerprint(value) {
        const text = String(value ? value : "")
        if (text.length <= 20) return text
        return text.substring(0, 10) + "…" + text.substring(text.length - 10)
    }

    readonly property var columns: [
        { title: "Name", key: "name", fill: true },
        { title: "Subject", key: "subject", sortable: false },
        {
            title: "Issued by",
            key: "generated",
            sortable: false,
            formatter: function (v, row) { return v ? "euclid (self-signed)" : String(row ? row.issuer : "") },
            // Self-signed is not broken, but it is refused by every client that has not been told
            // about it - worth noticing in a list of them.
            colorFor: function (v) { return v ? "#ffb545" : "#c4c9d1" }
        },
        {
            title: "Fingerprint",
            key: "fingerprint",
            sortable: false,
            formatter: function (v) { return root.shortFingerprint(v) }
        },
        {
            title: "Expires",
            key: "notAfter",
            formatter: function (v, row) { return root.expiryText(row) },
            colorFor: function (v, row) { return root.expiryColor(row) }
        },
        { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Ern", key: "ern", hidden: true }
    ]

    function refresh() {
        if (!root.loggedIn) {
            root.error = "Sign in to view certificates."
            return
        }
        root.loading = true
        root.error = ""
        ekmClient.fetchCertificates(root.prefix, root.pageIndex, root.pageSize,
                                    root.sortColumn, root.sortAscending ? "asc" : "desc")
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Live updates are off by default: a table that reloads while it is being read
        // moves rows out from under the pointer. See AppSettings::liveListUpdates().
        running: appSettings.liveListUpdates && appSettings.autoRefreshSeconds > 0
                 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: ekmClient
        function onCertificatesLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.certificates = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onCertificatesFailed(message) {
            root.loading = false
            root.error = message
        }
        function onCertificatesReload() {
            root.refresh()
        }
        function onCertificateCreated(name, certificate) {
            createDialog.saving = false
            createDialog.close()
            root.actionNote = "Certificate '" + name + "' generated. It is self-signed, so a caller refuses it "
                              + "until it is given this certificate as a trust anchor of its own."
        }
        function onCertificateCreateFailed(message) {
            createDialog.saving = false
            createDialog.errorText = message
        }
        function onCertificateImported(name, certificate) {
            importDialog.saving = false
            importDialog.close()
            root.actionNote = "Certificate '" + name + "' stored. A listener serving it picks it up at its "
                              + "next restart."
        }
        function onCertificateImportFailed(message) {
            importDialog.saving = false
            importDialog.errorText = message
        }
        function onCertificateExported(name, path) {
            root.actionNote = "Certificate '" + name + "' saved to " + path + ". The private key stays on the "
                              + "server and is not in the file."
        }
        function onCertificateExportFailed(message) {
            root.actionNote = ""
            root.error = message
        }
        function onCertificateDeleted(name) {
            root.actionNote = "Certificate '" + name + "' deleted. A listener already serving it keeps the copy "
                              + "it loaded until it restarts."
        }
        function onCertificateDeleteFailed(message) {
            root.error = message
        }
    }

    CertificateImportDialog {
        id: importDialog
    }

    // Generates a self-signed certificate. Separate from importing rather than a mode of it: the
    // fields have nothing in common, and one of them produces key material while the other stores
    // somebody else's.
    Dialog {
        id: createDialog
        modal: true
        anchors.centerIn: parent
        width: 520
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""

        function openForCreate() {
            createNameField.text = ""
            createDescriptionField.text = ""
            commonNameField.text = ""
            altNamesField.text = "localhost, 127.0.0.1"
            validDaysField.value = 825
            keyBitsCombo.currentIndex = 0
            createDialog.errorText = ""
            createDialog.saving = false
            createDialog.open()
        }

        // Comma or whitespace separated, because that is how somebody types a list of host names.
        function altNameList() {
            return altNamesField.text.split(/[,\s]+/).map(n => n.trim()).filter(n => n.length > 0)
        }

        readonly property string problem: {
            if (createNameField.text.trim().length === 0) return "A certificate needs a name - the one a listener asks for."
            return ""
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: createDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Generate Certificate"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Self-signed, for an installation that has to serve HTTPS before anybody has bought "
                          + "it a certificate. Nobody has vouched for the result: a client rejects it until it "
                          + "is given this certificate as a trust anchor of its own."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: createNameField
                    width: parent.width
                    placeholderText: "eag-development"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "A listener with no \"certificate\" setting looks for eag-<namespace>, or eag when it "
                          + "is bound to no namespace."
                    color: "#6b7280"
                    font.pixelSize: 11
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Common name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: commonNameField
                    width: parent.width
                    placeholderText: "the host name callers will use (default: the certificate name)"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Also valid for"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: altNamesField
                    width: parent.width
                    placeholderText: "localhost, 127.0.0.1, gateway.example.com"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "Every host name or address a caller might use, separated by commas. A client checks "
                          + "the name it dialled against these, so one that is missing is a certificate that "
                          + "works from one machine and not another."
                    color: "#6b7280"
                    font.pixelSize: 11
                }
            }

            Row {
                width: parent.width
                spacing: 24

                Column {
                    width: (parent.width - 24) / 2
                    spacing: 4
                    Text { text: "Valid for (days)"; color: "#9aa1ac"; font.pixelSize: 12 }
                    SpinBox {
                        id: validDaysField
                        width: parent.width
                        from: 1
                        to: 3650
                        stepSize: 30
                        editable: true
                        value: 825
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }

                Column {
                    width: (parent.width - 24) / 2
                    spacing: 4
                    Text { text: "Key size"; color: "#9aa1ac"; font.pixelSize: 12 }
                    ComboBox {
                        id: keyBitsCombo
                        width: parent.width
                        model: ["2048", "3072", "4096"]
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Description"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: createDescriptionField
                    width: parent.width
                    placeholderText: "What this certificate is for"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: createDialog.errorText.length > 0
                text: createDialog.errorText
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
                    text: createDialog.problem
                    color: "#ffb545"
                    font.pixelSize: 11
                    visible: createDialog.problem.length > 0
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Button {
                        text: "Cancel"
                        flat: true
                        Material.theme: Material.Dark
                        onClicked: createDialog.close()
                    }
                    Button {
                        text: createDialog.saving ? "Generating…" : "Generate"
                        highlighted: true
                        enabled: !createDialog.saving && createDialog.problem.length === 0
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: {
                            createDialog.errorText = ""
                            createDialog.saving = true
                            ekmClient.createCertificate(createNameField.text.trim(),
                                                        commonNameField.text.trim(),
                                                        createDialog.altNameList(),
                                                        validDaysField.value,
                                                        parseInt(keyBitsCombo.currentText),
                                                        createDescriptionField.text.trim())
                        }
                    }
                }
            }
        }
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

        // Which certificate is being saved. Held here because the dialog is asynchronous and the
        // row the menu was opened on is long gone by the time it is accepted.
        property string certificateName: ""

        onAccepted: {
            appSettings.lastFileDialogFolder = currentFolder
            root.error = ""
            ekmClient.exportCertificate(saveFileDialog.certificateName, selectedFile)
        }
    }

    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        standardButtons: Dialog.NoButton

        property var certificate: null

        function openFor(row) {
            deleteDialog.certificate = row
            deleteDialog.open()
        }

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
                text: deleteDialog.certificate
                      ? "\"" + deleteDialog.certificate.name + "\" and its private key are removed at once - "
                        + "there is no grace period, because unlike a key nothing becomes unreadable."
                      : ""
                color: "#c4c9d1"
                font.pixelSize: 12
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "A listener already serving it keeps the copy it loaded until it restarts, and one that "
                      + "restarts without it generates a self-signed replacement under the same name. Import a "
                      + "certificate instead if what you mean is to replace this one."
                color: "#9aa1ac"
                font.pixelSize: 11
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
                            ekmClient.deleteCertificate(deleteDialog.certificate.name)
                            deleteDialog.close()
                        }
                    }
                }
            }
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
                text: "‹ Back to EKM Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Certificates (" + root.totalCount + ")"
                    subtitle: "X.509 certificates in the " + root.namespaceName + " namespace, and what an "
                              + "HTTPS gateway listener can be pointed at."
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: "⭱ Import…"
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: importDialog.openForImport()
                    }
                    Button {
                        text: "+ Generate"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: createDialog.openForCreate()
                    }
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.certificates
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by certificate name prefix..."
                emptyText: root.prefix.length > 0
                           ? "No certificate matches that name."
                           : "No certificates in this namespace."
                rowsClickable: true
                sortKey: root.sortColumn
                sortAscending: root.sortAscending

                onRowClicked: (row) => root.openCertificateDetails(row.name, row)
                onSearchChanged: (text) => {
                    root.prefix = text
                    root.pageIndex = 0
                    root.refresh()
                }
                onRefreshRequested: root.refresh()
                onPageChanged: (index) => {
                    root.pageIndex = index
                    root.refresh()
                }
                // Back to the first page: page four of fifty-row pages is not page four of
                // ten-row pages, and the query has to be made again at the new size anyway.
                onPageSizeRequested: (size) => {
                    root.pageSize = size
                    root.pageIndex = 0
                    root.refresh()
                }
                onSortRequested: (key, ascending) => {
                    root.sortColumn = key
                    root.sortAscending = ascending
                    root.pageIndex = 0
                    root.refresh()
                }

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function(row) { root.openCertificateDetails(row.name, row) }
                    },
                    {
                        text: "Download…",
                        action: function(row) {
                            saveFileDialog.certificateName = row.name
                            saveFileDialog.currentFile = row.name + ".pem"
                            saveFileDialog.open()
                        }
                    },
                    {
                        text: "Replace…",
                        action: function(row) { importDialog.openForReplace(row.name, row.description) }
                    },
                    {
                        text: "Delete…",
                        action: function(row) { deleteDialog.openFor(row) }
                    }
                ]
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#4cd97b"
                font.pixelSize: 12
                visible: root.actionNote.length > 0
                text: root.actionNote
            }
        }
    }
}
