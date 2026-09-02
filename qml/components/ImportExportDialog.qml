import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs

// Backup and restore of the modules' own database collections, through EMM's "export"/"import".
//
// Export runs one request per module (see EmmClient::exportModules) rather than the server's
// "all", so the file grows a module at a time and a single oversized response cannot sink the
// whole thing. EMO is not offered at all: it holds monitoring samples, which nobody wants written
// back over the live ones.
Dialog {
    id: root
    modal: true
    anchors.centerIn: parent
    width: 620
    padding: 28
    topPadding: 24
    bottomPadding: 24
    standardButtons: Dialog.NoButton
    closePolicy: Popup.CloseOnEscape

    // Which module the dialog opens scoped to, or "" for everything. Set by the module pages so
    // their own "Export…" lands here with the right box ticked.
    property string scopeModule: ""

    readonly property var modules: emmClient.exportableModules()
    property var selectedModules: []

    property bool exporting: false
    property string exportPath: ""
    property string exportProgressText: ""
    property var exportResult: []
    property real exportBytes: 0
    property string exportError: ""

    property bool importing: false
    property url importFile: ""
    property var importSummary: null
    property var importModules: []
    property var importResult: null
    property string importError: ""

    // Seconds since the current export or import started. A big export is legitimately slow and a
    // gateway that has stopped answering is not, and from the outside they look identical - so at
    // least say how long it has been.
    property int elapsedSeconds: 0

    Timer {
        interval: 1000
        repeat: true
        running: root.exporting || root.importing
        onTriggered: root.elapsedSeconds += 1
    }

    function elapsedSuffix() {
        return root.elapsedSeconds > 2 ? " · " + root.elapsedSeconds + "s" : ""
    }

    // EKM carries the key material itself, so the server refuses to export it in the clear.
    readonly property bool needsPassphrase: root.selectedModules.indexOf("ekm") >= 0
    readonly property bool passphraseMismatch: passphraseField.text.length > 0
                                               && confirmField.text.length > 0
                                               && passphraseField.text !== confirmField.text

    function toggleModule(name, on) {
        const next = root.selectedModules.filter(m => m !== name)
        if (on) next.push(name)
        root.selectedModules = next
    }

    function toggleImportModule(name, on) {
        const next = root.importModules.filter(m => m !== name)
        if (on) next.push(name)
        root.importModules = next
    }

    function defaultFileName() {
        const stamp = Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss")
        const scope = root.selectedModules.length === root.modules.length
                      ? "all" : root.selectedModules.slice().sort().join("-")
        return "euclid-export-" + (scope.length > 0 ? scope : "empty") + "-" + stamp + ".json"
    }

    onOpened: {
        tabs.currentIndex = 0
        root.selectedModules = root.scopeModule.length > 0 && root.modules.indexOf(root.scopeModule) >= 0
                               ? [root.scopeModule] : root.modules.slice()
        objectsSwitch.checked = false
        passphraseField.text = ""
        confirmField.text = ""
        importPassphraseField.text = ""
        root.exporting = false
        root.exportPath = ""
        root.exportProgressText = ""
        root.exportResult = []
        root.exportBytes = 0
        root.exportError = ""
        root.importing = false
        root.importFile = ""
        root.importSummary = null
        root.importModules = []
        root.importResult = null
        root.importError = ""
    }

    background: Rectangle {
        radius: 16
        color: "#1b1e25"
        border.color: "#2c313c"
        border.width: 1
    }

    FileDialog {
        id: exportFileDialog
        title: "Save the export as"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: ["JSON files (*.json)", "All files (*)"]
        onAccepted: {
            root.exportError = ""
            root.exportResult = []
            root.exporting = true
            root.elapsedSeconds = 0
            root.exportProgressText = "Starting…"
            emmClient.exportModules(root.selectedModules, objectsSwitch.checked, selectedFile,
                                    passphraseField.text)
        }
    }

    FileDialog {
        id: importFileDialog
        title: "Select a euclid export file"
        nameFilters: ["JSON files (*.json)", "All files (*)"]
        onAccepted: {
            root.importResult = null
            root.importError = ""
            root.importFile = selectedFile
            const summary = emmClient.inspectImportFile(selectedFile)
            if (summary.error) {
                root.importSummary = null
                root.importError = summary.error
                return
            }
            root.importSummary = summary
            // Everything the file holds that this can actually restore; EMO and anything
            // unrecognised is left unticked, and the server would refuse it anyway.
            root.importModules = summary.modules.filter(m => root.modules.indexOf(m) >= 0)
        }
    }

    Connections {
        target: emmClient
        function onExportProgress(moduleName, completed, total) {
            root.exportProgressText = "Exported " + moduleName + " (" + completed + " of " + total + ")"
        }
        function onExportFinished(path, collections, bytes) {
            root.exporting = false
            root.exportPath = path
            root.exportResult = collections
            root.exportBytes = bytes
            root.exportProgressText = ""
        }
        function onExportFailed(message) {
            root.exporting = false
            root.exportProgressText = ""
            root.exportError = message
        }
        function onImportFinished(imported, skipped) {
            root.importing = false
            root.importResult = { imported: imported, skipped: skipped }
        }
        function onImportFailed(message) {
            root.importing = false
            root.importError = message
        }
    }

    contentItem: Column {
        width: root.availableWidth
        spacing: 18

        Column {
            width: parent.width
            spacing: 4
            Text { text: "Backup & Restore"; color: "white"; font.pixelSize: 18; font.bold: true }
            Text {
                width: parent.width
                text: "A JSON dump of the modules' database collections, and the way back in. "
                      + "Monitoring data (EMO) is not included - what happens to it is yours to decide."
                color: "#9aa1ac"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        TabBar {
            id: tabs
            width: parent.width
            Material.theme: Material.Dark
            Material.accent: "#4f8cff"
            TabButton { text: "Export" }
            TabButton { text: "Import" }
        }

        // ── Export ───────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 16
            visible: tabs.currentIndex === 0

            Column {
                width: parent.width
                spacing: 8
                Text { text: "Modules"; color: "#9aa1ac"; font.pixelSize: 12 }

                Flow {
                    width: parent.width
                    spacing: 16
                    Repeater {
                        model: root.modules
                        delegate: CheckBox {
                            required property string modelData
                            text: modelData.toUpperCase()
                            checked: root.selectedModules.indexOf(modelData) >= 0
                            enabled: !root.exporting
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onToggled: root.toggleModule(modelData, checked)
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 10

                ToggleSwitch {
                    id: objectsSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    enabled: !root.exporting
                }
                Column {
                    width: parent.width - objectsSwitch.width - 10
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "Include queue and topic messages, and bucket objects"; color: "#c4c9d1"; font.pixelSize: 12 }
                    Text {
                        width: parent.width
                        text: "Off exports the definitions only - queues, topics, buckets, users, groups. "
                              + "On adds everything stored inside them, which is usually far larger."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // The passphrase never reaches this file: the server derives a key from it, seals each
            // module's data, and sends back something this client could not read if it tried.
            Column {
                width: parent.width
                spacing: 6

                Text { text: "Passphrase"; color: "#9aa1ac"; font.pixelSize: 12 }

                Row {
                    width: parent.width
                    spacing: 8

                    TextField {
                        id: passphraseField
                        width: (parent.width - 8) / 2
                        placeholderText: root.needsPassphrase ? "required for EKM" : "optional"
                        echoMode: TextInput.Password
                        enabled: !root.exporting
                        Material.accent: "#4f8cff"
                    }
                    TextField {
                        id: confirmField
                        width: (parent.width - 8) / 2
                        placeholderText: "repeat it"
                        echoMode: TextInput.Password
                        enabled: !root.exporting && passphraseField.text.length > 0
                        Material.accent: "#4f8cff"
                    }
                }

                Text {
                    width: parent.width
                    text: root.passphraseMismatch
                          ? "The two do not match."
                          : (passphraseField.text.length > 0
                             ? "The file is encrypted with this. Nobody - not euclid, not us - can open it without it, so keep it somewhere you will still have it when you need the backup."
                             : (root.needsPassphrase
                                ? "EKM exports the key material itself, so it will only leave the server sealed. Set a passphrase, or untick EKM."
                                : "Without one the file is plain JSON, holding access-key secrets and password hashes in the clear."))
                    color: root.passphraseMismatch ? "#ff6b6b"
                           : (passphraseField.text.length > 0 ? "#6b7280" : "#ffb545")
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                visible: root.exporting
                text: root.exportProgressText + root.elapsedSuffix()
                color: "#4f8cff"
                font.pixelSize: 12
            }

            Text {
                visible: root.exportError.length > 0
                width: parent.width
                text: root.exportError
                color: "#ff6b6b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // Result of the last export: what was written, and how much of it.
            Rectangle {
                visible: root.exportPath.length > 0
                width: parent.width
                height: exportResultCol.implicitHeight + 24
                radius: 10
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: exportResultCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 4

                    Text {
                        width: parent.width
                        text: "Written " + root.exportPath + " (" + SizeFormat.format(root.exportBytes) + ")"
                        color: "#4cd97b"
                        font.pixelSize: 12
                        elide: Text.ElideMiddle
                    }
                    Repeater {
                        model: root.exportResult
                        delegate: Text {
                            required property var modelData
                            // A sealed frame reports -1: what it holds is not this client's to count.
                            text: modelData.documents < 0
                                  ? modelData.collection + " · sealed"
                                  : modelData.collection + " · " + modelData.documents + " documents"
                            color: "#9aa1ac"
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        // ── Import ───────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 16
            visible: tabs.currentIndex === 1

            Row {
                width: parent.width
                spacing: 8

                TextField {
                    id: importPathField
                    width: parent.width - chooseImportButton.width - 8
                    readOnly: true
                    placeholderText: "No file selected"
                    text: root.importFile.toString().length > 0 ? root.importFile.toString().replace("file://", "") : ""
                    Material.accent: "#4f8cff"
                }
                Button {
                    id: chooseImportButton
                    text: "Choose…"
                    flat: true
                    enabled: !root.importing
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: importFileDialog.open()
                }
            }

            Column {
                visible: root.importSummary !== null
                width: parent.width
                spacing: 8

                Text {
                    width: parent.width
                    text: !root.importSummary ? ""
                          : "Exported " + DateFormat.format(root.importSummary.exportedAt) + " · "
                            + (root.importSummary.encrypted
                               ? root.importSummary.frames + " sealed frames"
                               : root.importSummary.documents + " documents") + " · "
                            + (root.importSummary.full ? "with messages and objects" : "definitions only")
                    color: "#c4c9d1"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }

                // A sealed file says which modules it holds and nothing else; the counts are
                // inside the frames, and stay there until the server opens them.
                Column {
                    visible: root.importSummary !== null && root.importSummary.encrypted
                    width: parent.width
                    spacing: 6

                    Text { text: "Passphrase"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: importPassphraseField
                        width: parent.width
                        placeholderText: "the one this file was written with"
                        echoMode: TextInput.Password
                        enabled: !root.importing
                        Material.accent: "#4f8cff"
                    }
                    Text {
                        width: parent.width
                        text: "This file is encrypted. It is opened on the server, which checks the passphrase by "
                              + "decrypting - a wrong one and an altered file fail the same way, and neither writes anything."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                Flow {
                    width: parent.width
                    spacing: 16
                    Repeater {
                        model: root.importSummary ? root.importSummary.modules : []
                        delegate: CheckBox {
                            required property string modelData
                            text: modelData.toUpperCase()
                            // A module this build cannot restore - EMO, or one from a newer
                            // euclid - is shown so the file is described honestly, but not offered.
                            enabled: !root.importing && root.modules.indexOf(modelData) >= 0
                            checked: root.importModules.indexOf(modelData) >= 0
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onToggled: root.toggleImportModule(modelData, checked)
                        }
                    }
                }

                Column {
                    width: parent.width
                    Repeater {
                        model: root.importSummary ? root.importSummary.collections : []
                        delegate: Text {
                            required property var modelData
                            text: modelData.collection + " · " + modelData.documents + " documents"
                                  + (modelData.supported ? "" : "  (not restored from here)")
                            color: modelData.supported ? "#9aa1ac" : "#6b7280"
                            font.pixelSize: 11
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "Documents are matched by their ID and replaced whole. Nothing is deleted: "
                          + "anything the file does not mention stays as it is. Running modules may hold "
                          + "what they already read in memory, so restart them afterwards."
                    color: "#ffb545"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            Text {
                visible: root.importing
                text: "Importing…" + root.elapsedSuffix()
                color: "#4f8cff"
                font.pixelSize: 12
            }

            Text {
                visible: root.importError.length > 0
                width: parent.width
                text: root.importError
                color: "#ff6b6b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Rectangle {
                visible: root.importResult !== null
                width: parent.width
                height: importResultCol.implicitHeight + 24
                radius: 10
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: importResultCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12
                    spacing: 4

                    Text { text: "Imported"; color: "#4cd97b"; font.pixelSize: 12 }
                    Repeater {
                        model: root.importResult ? root.importResult.imported : []
                        delegate: Text {
                            required property var modelData
                            text: modelData.collection + " · " + modelData.imported + " documents"
                                  + (modelData.failed > 0 ? ", " + modelData.failed + " failed" : "")
                            color: modelData.failed > 0 ? "#ffb545" : "#9aa1ac"
                            font.pixelSize: 11
                        }
                    }
                    Repeater {
                        model: root.importResult ? root.importResult.skipped : []
                        delegate: Text {
                            required property var modelData
                            text: "skipped " + modelData.collection + " · " + modelData.reason
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 40

            // The same button, because there is only ever one thing to do with it: leave, or stop
            // waiting. A request the gateway never answers would otherwise hold the dialog until
            // the transfer timeout.
            Button {
                text: root.exporting || root.importing ? "Cancel" : "Close"
                flat: true
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                Material.theme: Material.Dark
                onClicked: {
                    if (root.exporting || root.importing)
                        emmClient.cancel()
                    else
                        root.close()
                }
            }

            BusyIndicator {
                running: root.exporting || root.importing
                visible: running
                width: 22
                height: 22
                anchors.right: actionButton.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
            }

            Button {
                id: actionButton
                text: tabs.currentIndex === 0 ? "Export…" : "Import"
                highlighted: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
                enabled: tabs.currentIndex === 0
                         ? !root.exporting && root.selectedModules.length > 0
                           && !root.passphraseMismatch
                           && (passphraseField.text.length === 0
                               ? !root.needsPassphrase
                               : passphraseField.text === confirmField.text)
                         : !root.importing && root.importSummary !== null && root.importModules.length > 0
                           && (!root.importSummary.encrypted || importPassphraseField.text.length > 0)

                onClicked: {
                    if (tabs.currentIndex === 0) {
                        exportFileDialog.currentFile = root.defaultFileName()
                        exportFileDialog.open()
                    } else {
                        root.importError = ""
                        root.importResult = null
                        root.importing = true
                        root.elapsedSeconds = 0
                        emmClient.importFile(root.importFile, root.importModules, importPassphraseField.text)
                    }
                }
            }
        }
    }
}
