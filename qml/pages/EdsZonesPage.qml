import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// EDS hosted zones: the domains this installation answers for authoritatively. A zone's name is
// unique across the whole installation, not just within the account - a DNS question carries no
// account, so two accounts holding "corp.example" would leave EDS nothing to choose by.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    property string prefix: ""
    property var zones: []
    property int totalCount: 0
    property int pageIndex: 0
    property int pageSize: 10
    property bool loading: false
    property string error: ""
    property string note: ""
    property string lastUpdatedText: "—"

    readonly property var columns: [
        {
            title: "Zone",
            key: "name",
            fill: true,
            sortable: false,
            tooltip: "The domain the zone answers for. Records in it are named relative to this."
        },
        {
            title: "Records",
            key: "recordCount",
            sortable: false,
            tooltip: "Stored record sets - one per name and type. The SOA and NS records every zone "
                     + "answers with are added automatically and not counted."
        },
        {
            title: "TTL",
            key: "ttl",
            sortable: false,
            tooltip: "The default time to live, in seconds, of records that do not set their own.",
            formatter: function (v) { return v + " s" }
        },
        {
            title: "Description",
            key: "description",
            sortable: false,
            formatter: function (v) { return v && v.length > 0 ? v : "—" }
        },
        {
            title: "Modified",
            key: "modified",
            sortable: false,
            tooltip: "The zone's last change. Its SOA serial is this time in seconds, so it moves "
                     + "forward with every write.",
            formatter: function (v) { return DateFormat.format(v) }
        },
        { title: "Ern", key: "ern", hidden: true }
    ]

    signal back()
    signal openZoneDetails(string zoneName, var details)

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view DNS zones."
            return
        }
        loading = true
        error = ""
        edsClient.fetchZones(root.prefix, root.pageIndex, root.pageSize)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()
    onNamespaceNameChanged: if (visible) { root.pageIndex = 0; refresh() }

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Live updates are off by default: a table that reloads while it is being read moves rows
        // out from under the pointer. See AppSettings::liveListUpdates().
        running: appSettings.liveListUpdates && appSettings.autoRefreshSeconds > 0
                 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: edsClient
        function onZonesLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.zones = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onZonesFailed(message) {
            root.loading = false
            root.error = message
        }
        function onZonesReload() {
            if (root.visible) root.refresh()
        }
        function onZoneCreated(zone) {
            createZoneDialog.creating = false
            createZoneDialog.close()
            root.note = "Zone " + zone.name + " created. Add its records from the zone's page."
        }
        function onZoneCreateFailed(message) {
            createZoneDialog.creating = false
            createZoneDialog.errorText = message
        }
        function onZoneDeleted(name, deletedRecords) {
            deleteZoneDialog.deleting = false
            deleteZoneDialog.close()
            root.note = "Zone " + name + " deleted, with " + deletedRecords + " record set(s)."
        }
        function onZoneDeleteFailed(message) {
            deleteZoneDialog.deleting = false
            deleteZoneDialog.errorText = message
        }
    }

    Dialog {
        id: createZoneDialog
        modal: true
        anchors.centerIn: parent
        width: 440
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
            zoneNameField.text = ""
            zoneTtlField.text = ""
            zoneDescriptionField.text = ""
            createZoneDialog.errorText = ""
            createZoneDialog.creating = false
            zoneNameField.forceActiveFocus()
        }

        contentItem: Column {
            width: createZoneDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Zone"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "The name must be unique across the whole installation, and cannot be inside "
                          + "euclid.internal, which belongs to the service names. SOA and NS records are "
                          + "added automatically."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Zone name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: zoneNameField
                    width: parent.width
                    placeholderText: "e.g. corp.example"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: zoneTtlField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Default TTL (seconds)"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: zoneTtlField
                    width: parent.width
                    placeholderText: "300"
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 1; top: 2147483647 }
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: zoneDescriptionField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Description"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: zoneDescriptionField
                    width: parent.width
                    placeholderText: "optional, e.g. office network"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createZoneButton.enabled) createZoneButton.clicked()
                }
                Text {
                    text: createZoneDialog.errorText
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
                    onClicked: createZoneDialog.close()
                }

                BusyIndicator {
                    running: createZoneDialog.creating
                    visible: createZoneDialog.creating
                    width: 22
                    height: 22
                    anchors.right: createZoneButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: createZoneButton
                    text: "Create"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !createZoneDialog.creating && zoneNameField.text.trim().length > 0
                             && (zoneTtlField.text.length === 0 || zoneTtlField.acceptableInput)
                    onClicked: {
                        createZoneDialog.errorText = ""
                        createZoneDialog.creating = true
                        edsClient.createZone(zoneNameField.text.trim(),
                                             zoneTtlField.text.length > 0 ? parseInt(zoneTtlField.text, 10) : 0,
                                             zoneDescriptionField.text.trim())
                    }
                }
            }
        }
    }

    // Deleting a zone takes every record in it, and the names stop resolving at once - so it is
    // asked, not done from the menu outright.
    Dialog {
        id: deleteZoneDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property var zone: null
        property bool deleting: false
        property string errorText: ""

        function openFor(zone) {
            deleteZoneDialog.zone = zone
            deleteZoneDialog.errorText = ""
            deleteZoneDialog.deleting = false
            deleteZoneDialog.open()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: deleteZoneDialog.availableWidth
            spacing: 16

            Text { text: "Delete Zone"; color: "white"; font.pixelSize: 18; font.bold: true }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#c4c9d1"
                font.pixelSize: 13
                text: deleteZoneDialog.zone
                      ? "Delete " + deleteZoneDialog.zone.name + " and its " + deleteZoneDialog.zone.recordCount
                        + " record set(s)? Its names stop resolving straight away. This cannot be undone."
                      : ""
            }
            Text {
                text: deleteZoneDialog.errorText
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
                    onClicked: deleteZoneDialog.close()
                }

                BusyIndicator {
                    running: deleteZoneDialog.deleting
                    visible: deleteZoneDialog.deleting
                    width: 22
                    height: 22
                    anchors.right: deleteZoneButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: deleteZoneButton
                    text: "Delete"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#ff6b6b"
                    enabled: !deleteZoneDialog.deleting && deleteZoneDialog.zone !== null
                    onClicked: {
                        deleteZoneDialog.errorText = ""
                        deleteZoneDialog.deleting = true
                        edsClient.deleteZone(deleteZoneDialog.zone.name)
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

            Breadcrumb {
                width: parent.width
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "DNS Zones (" + root.totalCount + ")"
                    subtitle: "Domains EDS answers for authoritatively in the " + root.namespaceName + " namespace."
                }

                Button {
                    text: "+ Create Zone"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createZoneDialog.open()
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#e0a458"
                font.pixelSize: 12
                visible: root.note.length > 0
                text: root.note
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.zones
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by zone name prefix..."
                // list-zones matches by prefix only.
                matchTypeSelectable: false
                emptyText: root.prefix.length > 0 ? "No zone starts with that name." : "No zones yet."
                rowsClickable: true
                onRowClicked: (row) => root.openZoneDetails(row.name, row)

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
                onPageSizeRequested: (size) => {
                    root.pageSize = size
                    root.pageIndex = 0
                    root.refresh()
                }

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function (row) { root.openZoneDetails(row.name, row) }
                    },
                    {
                        text: "Delete",
                        action: function (row) {
                            root.note = ""
                            deleteZoneDialog.openFor(row)
                        }
                    }
                ]
            }
        }
    }
}
