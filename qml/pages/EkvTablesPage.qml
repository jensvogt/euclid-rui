import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// EKV: the namespace's tables, and what each of them keys its items on.
//
// A table is its key schema and nothing else - there are no columns to declare, because an item is
// arbitrary JSON and two items in the same table need not look alike. What is fixed is how an item
// is found: a partition key every item carries, and optionally a sort key that orders the items
// within one partition. Neither can be changed afterwards, which is why the create dialog is the
// one place on this page that asks anything.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    property string prefix: ""
    property int pageIndex: 0
    property int pageSize: 10
    property string sortColumn: "name"
    property bool sortAscending: true

    property var tables: []
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    // What the last action did, said next to the table: creating and deleting a table both take
    // effect immediately, and a deleted table's items go with it silently.
    property string actionNote: ""

    // The three types a key attribute may be. Binary is offered because the store accepts it, and
    // marked because nothing here can write one: it has no JSON spelling, so a value for it cannot
    // be sent over this wire at all - see Database::Entity::EKV::Value.
    readonly property var keyTypes: ["string", "number", "binary"]

    // "customer (string)" - the attribute and its type read as one thing, and separating them into
    // two columns would put the types in a column of their own that nobody scans.
    function keyText(name, type) {
        if (!name || String(name).length === 0) return "—"
        return String(name) + " (" + String(type) + ")"
    }

    readonly property var columns: [
        { title: "Table", key: "name", fill: true },
        {
            title: "Partition key",
            key: "partitionKey",
            formatter: function (v, row) { return root.keyText(v, row ? row.partitionKeyType : "") }
        },
        {
            title: "Sort key",
            key: "sortKey",
            formatter: function (v, row) { return root.keyText(v, row ? row.sortKeyType : "") },
            // A table without one is not lacking anything - it is a table whose partition key
            // identifies an item on its own - so the dash is not coloured as a fault.
            colorFor: function (v) { return !v || String(v).length === 0 ? "#6b7280" : "#c4c9d1" }
        },
        {
            title: "Items",
            key: "itemCount",
            // Counted by the server when asked rather than kept, so it is right rather than close.
            formatter: function (v) { return String(Number(v)) }
        },
        { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Ern", key: "ern", hidden: true }
    ]

    signal back()
    signal openTableDetails(string tableName, var details)

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view tables."
            return
        }
        loading = true
        error = ""
        ekvClient.fetchTables(root.prefix, root.pageIndex, root.pageSize,
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
        target: ekvClient
        function onTablesLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.tables = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onTablesFailed(message) {
            root.loading = false
            root.error = message
        }
        function onTablesReload() {
            root.refresh()
        }
        function onTableCreated(name, table) {
            createTableDialog.creating = false
            createTableDialog.close()
            root.actionNote = "Table '" + name + "' created, keyed on "
                              + root.keyText(table.partitionKey, table.partitionKeyType)
                              + (table.sortKey.length > 0 ? " and sorted by " + root.keyText(table.sortKey, table.sortKeyType) : "")
                              + "."
        }
        function onTableCreateFailed(message) {
            createTableDialog.creating = false
            createTableDialog.errorText = message
        }
        function onTableDeleted(name, deletedItems) {
            root.actionNote = "Table '" + name + "' deleted, with " + deletedItems + " item(s) in it."
        }
        function onTableDeleteFailed(message) {
            root.error = message
        }
    }

    Dialog {
        id: createTableDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool creating: false
        property string errorText: ""

        readonly property bool sorted: sortKeyField.text.trim().length > 0
        // The one mistake the server refuses that a form can catch first: the same attribute cannot
        // be both keys, because then it would have to be unique and repeated at once.
        readonly property bool keysCollide: createTableDialog.sorted
                                            && sortKeyField.text.trim() === partitionKeyField.text.trim()

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        // ComboBox's currentIndex is set imperatively on open, same as every other dialog here -
        // its own model-populate logic clobbers a binding.
        onOpened: {
            tableNameField.text = ""
            partitionKeyField.text = ""
            sortKeyField.text = ""
            partitionTypeCombo.currentIndex = 0
            sortTypeCombo.currentIndex = 0
            createTableDialog.errorText = ""
            createTableDialog.creating = false
            tableNameField.forceActiveFocus()
        }

        contentItem: Column {
            width: createTableDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Table"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "The key schema is fixed once the table exists: every item is stored under it, so there "
                          + "is no call to change it afterwards. Nothing else is declared - an item is JSON, and "
                          + "two items in one table need not look alike."
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
                    id: tableNameField
                    width: parent.width
                    placeholderText: "e.g. orders"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: partitionKeyField.forceActiveFocus()
                }
            }

            Column {
                id: partitionColumn
                width: parent.width
                spacing: 6
                Text { text: "Partition key"; color: "#9aa1ac"; font.pixelSize: 12 }

                Row {
                    width: parent.width
                    spacing: 8

                    TextField {
                        id: partitionKeyField
                        width: partitionColumn.width - 132
                        placeholderText: "attribute, e.g. customerId"
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        Keys.onReturnPressed: sortKeyField.forceActiveFocus()
                    }
                    ComboBox {
                        id: partitionTypeCombo
                        width: 124
                        model: root.keyTypes
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }

                Text {
                    text: "What every item is found by. An attribute name may not be empty, start with \"$\" or "
                          + "contain \".\"."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                id: sortColumnGroup
                width: parent.width
                spacing: 6
                Text { text: "Sort key (optional)"; color: "#9aa1ac"; font.pixelSize: 12 }

                Row {
                    width: parent.width
                    spacing: 8

                    TextField {
                        id: sortKeyField
                        width: sortColumnGroup.width - 132
                        placeholderText: "leave empty for one item per partition key"
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        Keys.onReturnPressed: if (createTableButton.enabled) createTableButton.clicked()
                    }
                    ComboBox {
                        id: sortTypeCombo
                        width: 124
                        enabled: createTableDialog.sorted
                        model: root.keyTypes
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }

                Text {
                    text: "Orders the items inside one partition, and is what \"query\" narrows by. Without it a "
                          + "partition holds exactly one item and a write replaces it."
                    color: "#6b7280"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#e0a458"
                font.pixelSize: 11
                visible: partitionTypeCombo.currentText === "binary"
                         || (createTableDialog.sorted && sortTypeCombo.currentText === "binary")
                text: "⚠ A binary key can be declared, but nothing can be written under one from here: binary has "
                      + "no JSON spelling, so no value for it can be sent."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: createTableDialog.keysCollide
                text: "The partition key and the sort key have to be different attributes."
            }

            Text {
                text: createTableDialog.errorText
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
                    onClicked: createTableDialog.close()
                }

                BusyIndicator {
                    running: createTableDialog.creating
                    visible: createTableDialog.creating
                    width: 22
                    height: 22
                    anchors.right: createTableButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: createTableButton
                    text: "Create"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !createTableDialog.creating && tableNameField.text.trim().length > 0
                             && partitionKeyField.text.trim().length > 0 && !createTableDialog.keysCollide
                    onClicked: {
                        createTableDialog.errorText = ""
                        createTableDialog.creating = true
                        root.actionNote = ""
                        ekvClient.createTable(tableNameField.text.trim(), partitionKeyField.text.trim(),
                            partitionTypeCombo.currentText, sortKeyField.text.trim(), sortTypeCombo.currentText)
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 28
        standardButtons: Dialog.NoButton

        property string tableName: ""
        property int itemCount: 0

        function openFor(row) {
            deleteDialog.tableName = row.name
            deleteDialog.itemCount = Number(row.itemCount)
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

            Text { text: "Delete Table"; color: "white"; font.pixelSize: 18; font.bold: true }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#9aa1ac"
                font.pixelSize: 12
                text: "\"" + deleteDialog.tableName + "\" and the "
                      + deleteDialog.itemCount + " item(s) in it. There is no undo and no copy: "
                      + "anything reading these items by key starts failing the next time it asks."
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
                        root.actionNote = ""
                        ekvClient.deleteTable(deleteDialog.tableName)
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
                text: "‹ Back to EKV Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Tables (" + root.totalCount + ")"
                    subtitle: "Items keyed by name, read one at a time."
                }

                Button {
                    text: "+ Add Table"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: createTableDialog.open()
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.tables
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by table name prefix..."
                emptyText: root.prefix.length > 0 ? "No table matches that name."
                                                  : "No tables in the " + root.namespaceName + " namespace."
                rowsClickable: true
                sortKey: root.sortColumn
                sortAscending: root.sortAscending

                onRowClicked: (row) => root.openTableDetails(row.name, row)
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
                        action: function(row) { root.openTableDetails(row.name, row) }
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
