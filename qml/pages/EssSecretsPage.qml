import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    property string prefix: ""
    property int pageIndex: 0
    property int pageSize: 10
    property string sortColumn: "name"
    property bool sortAscending: true

    property var secrets: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    // The key name out of "ern:ekm:{region}:{accountId}:key:{name}". The whole ERN is too wide for
    // a column and its interesting part is the last segment; the details page shows it in full.
    function keyName(keyErn) {
        if (!keyErn || keyErn.length === 0) return "—"
        const parts = String(keyErn).split(":")
        return parts[parts.length - 1]
    }

    readonly property var columns: [
        { title: "Name", key: "name", fill: true },
        { title: "Description", key: "description" },
        { title: "Version", key: "version" },
        { title: "Rotated", key: "rotated", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Key", key: "encryptionKeyErn", formatter: function (v) { return root.keyName(v) } },
        { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Ern", key: "ern", hidden: true }
    ]

    signal back()
    signal openSecretDetails(string secretErn, string secretName, var details)

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view secrets."
            return
        }
        loading = true
        error = ""
        essClient.fetchSecrets(root.prefix, root.pageIndex, root.pageSize,
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
        target: essClient
        function onSecretsLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.secrets = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onSecretsFailed(message) {
            root.loading = false
            root.error = message
        }

        function onSecretsReload() {
            refresh()
        }

        function onSecretCreated(name, secret) {
            createSecretDialog.creating = false
            createSecretDialog.close()
        }
        function onSecretCreateFailed(message) {
            createSecretDialog.creating = false
            createSecretDialog.errorText = message
        }
        function onSecretDeleteFailed(message) {
            root.error = message
        }
    }

    Dialog {
        id: createSecretDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool creating: false
        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            nameField.text = ""
            descriptionField.text = ""
            valueField.text = ""
            keyErnField.text = ""
            // Masked again on every open: the last secret typed here should not be readable
            // because the box was left switched to plain text.
            valueField.echoMode = TextInput.Password
            createSecretDialog.errorText = ""
            createSecretDialog.creating = false
            nameField.forceActiveFocus()
        }
        // The value only ever lives in the field, so closing the dialog is what disposes of it -
        // including when it was closed by clicking away rather than by cancelling.
        onClosed: valueField.text = ""

        contentItem: Column {
            width: createSecretDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Secret"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Stored encrypted under an EKM key and readable afterwards only through \"Reveal\"."
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
                    placeholderText: "e.g. payroll-db-password"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: valueField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6

                Item {
                    width: parent.width
                    height: valueLabel.implicitHeight

                    Text { id: valueLabel; text: "Value"; color: "#9aa1ac"; font.pixelSize: 12 }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: valueLabel.verticalCenter
                        text: valueField.echoMode === TextInput.Password ? "Show" : "Hide"
                        color: showValueArea.containsMouse ? "#4f8cff" : "#6b7280"
                        font.pixelSize: 11

                        MouseArea {
                            id: showValueArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: valueField.echoMode = valueField.echoMode === TextInput.Password
                                                             ? TextInput.Normal : TextInput.Password
                        }
                    }
                }

                TextField {
                    id: valueField
                    width: parent.width
                    // Masked by default: this is typed in front of whoever is in the room, and the
                    // "Show" above is there for the times that is not a problem.
                    echoMode: TextInput.Password
                    placeholderText: "The password, token or connection string"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
                Text {
                    text: "An empty value is refused: it is almost always a paste that did not happen."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Description"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: descriptionField
                    width: parent.width
                    placeholderText: "What it is for - readable by anyone who may list secrets"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Encryption key ERN (optional)"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: keyErnField
                    width: parent.width
                    placeholderText: "ern:ekm:…  ·  empty uses the namespace's own secrets key"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createButton.enabled) createButton.clicked()
                }
                Text {
                    text: createSecretDialog.errorText
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
                    onClicked: createSecretDialog.close()
                }

                BusyIndicator {
                    running: createSecretDialog.creating
                    visible: createSecretDialog.creating
                    width: 22
                    height: 22
                    anchors.right: createButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: createButton
                    text: "Create"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !createSecretDialog.creating && nameField.text.trim().length > 0
                             && valueField.text.length > 0
                    onClicked: {
                        createSecretDialog.errorText = ""
                        createSecretDialog.creating = true
                        essClient.createSecret(nameField.text.trim(), valueField.text,
                                               descriptionField.text.trim(), keyErnField.text.trim())
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

        property var secret: null
        readonly property string secretName: secret ? String(secret.name) : ""

        function openFor(row) {
            deleteDialog.secret = row
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
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Delete Secret"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: deleteDialog.secretName
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
                // Asked for, unlike the other list actions here, because there is nothing to undo
                // with and no copy anywhere: the stored value is the only one euclid has.
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
                        essClient.deleteSecret(deleteDialog.secretName)
                        deleteDialog.close()
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
                text: "‹ Back to ESS Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Secrets"
                    subtitle: "All stored secrets in the " + root.namespaceName + " namespace. Values are not listed."
                }

                Button {
                    text: "+ Add Secret"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createSecretDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.secrets
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by name prefix..."
                emptyText: "No secrets found in this namespace."
                rowsClickable: true
                sortKey: root.sortColumn
                sortAscending: root.sortAscending

                onRowClicked: (row) => root.openSecretDetails(row.ern, row.name, row)
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
                        action: function(row) {
                            root.openSecretDetails(row.ern, row.name, row)
                        }
                    },
                    {
                        // Revealing, rotating and re-keying all live on the details page: each of
                        // them is a decision, and a context menu is where they would be clicked by
                        // accident.
                        text: "Delete",
                        action: function(row) {
                            deleteDialog.openFor(row)
                        }
                    }
                ]
            }
        }
    }
}
