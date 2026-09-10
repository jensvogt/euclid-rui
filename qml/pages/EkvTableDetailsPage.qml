import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// One EKV table, and its items.
//
// The two ways to read a table are the two the store offers, and they are not interchangeable: a
// scan walks every item in no particular order, a query reads one partition in sort-key order and
// is the one that is cheap. So this page does both and says which it is doing, rather than hiding
// the difference behind a single "search" that would sometimes be a table walk.
//
// An item is arbitrary JSON, so it is shown and edited as JSON. There is no partial update in EKV -
// a put replaces whatever was under the key - which is why the editor holds the whole item and
// saving it is a write of all of it.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string tableName: ""
    property var details: ({})

    property string error: ""
    property string actionNote: ""

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    readonly property string partitionKey: String(detail("partitionKey", ""))
    readonly property string partitionKeyType: String(detail("partitionKeyType", "string"))
    readonly property string sortKey: String(detail("sortKey", ""))
    readonly property string sortKeyType: String(detail("sortKeyType", "string"))
    readonly property bool hasSortKey: root.sortKey.length > 0
    readonly property int itemCount: Number(detail("itemCount", 0))

    signal back()

    // ── Items ────────────────────────────────────────────────────────────────

    // "scan" or "query". Which one is running decides what the table below is showing and what the
    // count under it means, so it is state rather than a button that fires and forgets.
    property string readMode: "scan"
    property var items: []
    property int returnedCount: 0
    property int scanTotal: 0
    property bool itemsLoading: false
    property string itemsError: ""
    property string itemsUpdatedText: "—"

    property int itemPageIndex: 0
    property int itemPageSize: 25

    // The query, as it was last run - not as it is typed. A page that re-read itself from the
    // fields would change what it is showing while somebody is still editing them.
    property string queryPartitionValue: ""
    property string querySortOperator: ""
    property string querySortValue: ""
    property string querySortUpper: ""
    property bool queryForward: true

    // The operators the server takes, in the order they read: everything, then the comparisons,
    // then the two that are neither.
    readonly property var sortOperators: ["(whole partition)", "eq", "lt", "le", "gt", "ge", "between", "begins-with"]

    // A key value as EKV wants it typed. The table says which type its key is, so a number key is
    // sent as a JSON number rather than as the text somebody typed - which is the distinction the
    // store checks the key against.
    function typedKeyValue(text, type) {
        return type === "number" ? Number(text) : String(text)
    }

    function keyTextValid(text, type) {
        if (String(text).length === 0) return false
        return type !== "number" || !isNaN(Number(text))
    }

    // The key of one row, built from what the table is keyed on. Everything else in the row is an
    // attribute, and sending it would be a caller who thinks the table is keyed on something it is
    // not - which EKV refuses rather than answering with the wrong item.
    function keyFor(row) {
        const key = ({})
        key[root.partitionKey] = row[root.partitionKey]
        if (root.hasSortKey) key[root.sortKey] = row[root.sortKey]
        return key
    }

    // EKV's own timestamps, and the JSON this page attaches - none of them are attributes, so none
    // of them belong in a count or a preview of what an item holds.
    readonly property var reservedNames: ["_created", "_modified", "_json"]

    function attributeNames(item) {
        if (!item) return []
        return Object.keys(item).filter(name =>
            root.reservedNames.indexOf(name) < 0 && name !== root.partitionKey
            && (!root.hasSortKey || name !== root.sortKey)).sort()
    }

    // A value in a cell. An attribute may be an object or a list, and String() on one of those is
    // "[object Object]", which says nothing at all.
    function cellText(value) {
        if (value === undefined || value === null) return "—"
        if (typeof value === "object") return JSON.stringify(value)
        return String(value)
    }

    // What an item holds, past its key: the first few attributes, named. A count would be the same
    // number for every row and tell nobody which item they are looking at.
    function attributeSummary(item) {
        const names = root.attributeNames(item)
        if (names.length === 0) return "—"
        const shown = names.slice(0, 3).map(name => name + ": " + root.cellText(item[name]))
        return shown.join(" · ") + (names.length > 3 ? " · +" + (names.length - 3) + " more" : "")
    }

    readonly property var itemColumns: {
        // Rebuilt when the key schema arrives: the columns of an item table are the table's own key
        // attributes, which are not known until "describe-table" has answered.
        const columns = [{
            title: root.partitionKey.length > 0 ? root.partitionKey : "Partition key",
            key: root.partitionKey,
            sortable: false,
            formatter: function (v) { return root.cellText(v) }
        }]
        if (root.hasSortKey) {
            columns.push({
                title: root.sortKey,
                key: root.sortKey,
                sortable: false,
                formatter: function (v) { return root.cellText(v) }
            })
        }
        columns.push({
            title: "Attributes",
            key: "_json",
            fill: true,
            sortable: false,
            formatter: function (v, row) { return root.attributeSummary(row) },
            colorFor: function (v, row) { return root.attributeNames(row).length === 0 ? "#6b7280" : "#c4c9d1" }
        })
        columns.push({
            title: "Modified",
            key: "_modified",
            sortable: false,
            formatter: function (v) { return DateFormat.format(v) }
        })
        return columns
    }

    // What the table is told it holds. A scan knows; a query does not - it answers with what it
    // found in the partition and counts nothing beyond it - so a full page is reported as one row
    // more than it has, which is exactly what makes "Next" available and nothing more.
    readonly property int itemTotalCount: root.readMode === "scan"
        ? root.scanTotal
        : root.itemPageIndex * root.itemPageSize + root.returnedCount
          + (root.returnedCount === root.itemPageSize ? 1 : 0)

    function loadItems() {
        if (!root.loggedIn || root.tableName.length === 0)
            return
        root.itemsLoading = true
        root.itemsError = ""
        if (root.readMode === "query") {
            ekvClient.queryItems(root.tableName,
                root.typedKeyValue(root.queryPartitionValue, root.partitionKeyType),
                root.querySortOperator,
                root.querySortOperator.length > 0 ? root.typedKeyValue(root.querySortValue, root.sortKeyType) : "",
                root.querySortOperator === "between" ? root.typedKeyValue(root.querySortUpper, root.sortKeyType) : "",
                root.queryForward, root.itemPageIndex, root.itemPageSize)
        } else {
            ekvClient.scanItems(root.tableName, root.itemPageIndex, root.itemPageSize)
        }
    }

    function refresh() {
        if (!root.loggedIn || root.tableName.length === 0)
            return
        root.error = ""
        // The count is the only thing about a table that moves, and it is counted rather than kept -
        // so the description is re-read here rather than carried over from the row that was clicked.
        ekvClient.describeTable(root.tableName)
        root.loadItems()
    }

    onVisibleChanged: if (visible) refresh()
    onTableNameChanged: {
        // A different table is a different key schema, so nothing about the last one survives.
        root.readMode = "scan"
        root.items = []
        root.itemPageIndex = 0
        root.queryPartitionValue = ""
        root.querySortOperator = ""
        root.querySortValue = ""
        root.querySortUpper = ""
        root.actionNote = ""
        if (visible) refresh()
    }

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Live updates are off by default, same as every list here: a table that reloads while it
        // is being read moves rows out from under the pointer.
        running: appSettings.liveListUpdates && appSettings.autoRefreshSeconds > 0
                 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: ekvClient

        function onTableDescribed(name, table) {
            if (name !== root.tableName) return
            root.details = table
            root.error = ""
        }
        function onTableDescribeFailed(name, message) {
            if (name !== root.tableName) return
            root.error = message
        }
        function onItemsLoaded(table, list, count, total) {
            if (table !== root.tableName) return
            root.itemsLoading = false
            root.itemsError = ""
            root.items = list
            root.returnedCount = count
            // -1 is a query, which has no total to report; the scan total is left as it was so the
            // stat card above does not blink to zero while a query is on screen.
            if (total >= 0) root.scanTotal = total
            root.itemsUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onItemsFailed(table, message) {
            if (table !== root.tableName) return
            root.itemsLoading = false
            root.itemsError = message
        }
        function onItemsReload(table) {
            if (table !== root.tableName) return
            root.refresh()
        }
        function onItemPut(table, item) {
            if (table !== root.tableName) return
            itemDialog.saving = false
            itemDialog.close()
            root.actionNote = "Item written."
        }
        function onItemPutFailed(message) {
            itemDialog.saving = false
            itemDialog.errorText = message
        }
        function onItemDeleted(table, deleted) {
            if (table !== root.tableName) return
            root.actionNote = deleted ? "Item deleted." : "Nothing was deleted: no item is stored under that key."
        }
        function onItemDeleteFailed(message) {
            root.itemsError = message
        }
        function onTableDeleted(name, deletedItems) {
            // Nothing left to show; the list is where a deleted table's absence makes sense.
            if (name === root.tableName) root.back()
        }
        function onTableDeleteFailed(message) {
            root.error = message
        }
    }

    // One dialog for reading, writing and adding: an item is its JSON either way, and the only
    // difference is whether there was one to begin with.
    Dialog {
        id: itemDialog
        modal: true
        anchors.centerIn: parent
        width: 620
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""
        // Set when an existing item is open; empty when a new one is being written. Only decides
        // what the dialog says and whether Delete is offered - the write is a put either way.
        property var editingItem: null

        readonly property bool isNew: itemDialog.editingItem === null

        function openFor(item) {
            itemDialog.editingItem = item
            itemDialog.errorText = ""
            itemDialog.saving = false
            itemDialog.open()
            // A skeleton rather than an empty box for a new item: the key attributes are not
            // optional, and nobody should have to go and look up what this table is keyed on.
            if (item) {
                itemEditor.text = String(item._json)
            } else {
                const skeleton = ({})
                skeleton[root.partitionKey] = root.partitionKeyType === "number" ? 0 : ""
                if (root.hasSortKey)
                    skeleton[root.sortKey] = root.sortKeyType === "number" ? 0 : ""
                itemEditor.text = JSON.stringify(skeleton, null, 2)
            }
            itemEditor.forceActiveFocus()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: itemDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: itemDialog.isNew ? "Add Item" : "Item"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    text: "There is no partial update: a write replaces whatever is stored under this key, so what "
                          + "is saved is the whole item. \"_created\" and \"_modified\" are EKV's own and are "
                          + "ignored on the way back in."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Rectangle {
                width: parent.width
                height: 300
                radius: 8
                color: "#14161b"
                border.color: "#2c313c"
                border.width: 1
                clip: true

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 10
                    clip: true

                    TextArea {
                        id: itemEditor
                        selectByMouse: true
                        wrapMode: TextArea.NoWrap
                        color: "#c4c9d1"
                        font.family: "monospace"
                        font.pixelSize: 12
                        Material.accent: "#4f8cff"
                        // The panel behind it already draws the frame.
                        background: null
                    }
                }
            }

            Text {
                text: itemDialog.errorText
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
                    text: "Close"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    onClicked: itemDialog.close()
                }

                Button {
                    text: "Delete"
                    flat: true
                    anchors.left: parent.left
                    anchors.leftMargin: 88
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !itemDialog.isNew
                    Material.theme: Material.Dark
                    Material.accent: "#ff6b6b"
                    onClicked: {
                        root.actionNote = ""
                        ekvClient.deleteItem(root.tableName, root.keyFor(itemDialog.editingItem))
                        itemDialog.close()
                    }
                }

                BusyIndicator {
                    running: itemDialog.saving
                    visible: itemDialog.saving
                    width: 22
                    height: 22
                    anchors.right: saveItemButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: saveItemButton
                    text: "Save"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !itemDialog.saving && itemEditor.text.trim().length > 0
                    onClicked: {
                        itemDialog.errorText = ""
                        itemDialog.saving = true
                        root.actionNote = ""
                        ekvClient.putItem(root.tableName, itemEditor.text)
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteTableDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 28
        standardButtons: Dialog.NoButton

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: deleteTableDialog.availableWidth
            spacing: 18

            Text { text: "Delete Table"; color: "white"; font.pixelSize: 18; font.bold: true }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#9aa1ac"
                font.pixelSize: 12
                text: "\"" + root.tableName + "\" and the " + root.itemCount + " item(s) in it. There is no undo "
                      + "and no copy: anything reading these items by key starts failing the next time it asks."
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
                    onClicked: deleteTableDialog.close()
                }

                Button {
                    text: "Delete"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#ff6b6b"
                    onClicked: {
                        ekvClient.deleteTable(root.tableName)
                        deleteTableDialog.close()
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
                text: "‹ Back to Tables"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.tableName
                    subtitle: root.detail("ern", "")
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 10

                    Button {
                        text: "+ Add Item"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        enabled: root.partitionKey.length > 0
                        onClicked: itemDialog.openFor(null)
                    }
                    Button {
                        text: "Delete"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        onClicked: deleteTableDialog.open()
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: root.error.length > 0
                text: root.error
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "Items"
                    value: String(root.itemCount)
                    trend: "counted, not kept"
                    trendUp: true
                    accent: "#4f8cff"
                }
                StatCard {
                    title: "Partition key"
                    value: root.partitionKey.length > 0 ? root.partitionKey : "—"
                    trend: root.partitionKeyType
                    trendUp: true
                    accent: "#c56bff"
                }
                StatCard {
                    title: "Sort key"
                    value: root.hasSortKey ? root.sortKey : "none"
                    // A table without one is not lacking anything: its partition key identifies an
                    // item on its own, and a write to that key replaces what was there.
                    trend: root.hasSortKey ? root.sortKeyType : "one item per partition key"
                    trendUp: true
                    accent: root.hasSortKey ? "#4cd97b" : "#9aa1ac"
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Table"; value: root.tableName; copyable: true }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    DetailField { width: identityCol.width; label: "Table ERN"; value: root.detail("ern", "—"); copyable: true }
                }
            }

            // ── Items ────────────────────────────────────────────────────────
            Column {
                width: parent.width
                spacing: 14

                Row {
                    spacing: 10
                    Text {
                        text: root.readMode === "scan" ? "Items" : "Query results"
                        color: "white"
                        font.pixelSize: 15
                        font.bold: true
                    }
                    BusyIndicator {
                        running: root.itemsLoading
                        visible: root.itemsLoading
                        width: 18
                        height: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: root.readMode === "scan"
                          ? "A scan reads every item in the table, a page at a time and in no particular order. It is "
                            + "the way in when the partition is not known, and it is the expensive one."
                          : "A query reads one partition, in sort-key order. It is the cheap read, and the one an "
                            + "application should be making."
                }

                Rectangle {
                    width: parent.width
                    height: queryCol.implicitHeight + 32
                    radius: 14
                    color: "#20242e"
                    border.color: "#2c313c"
                    border.width: 1

                    Column {
                        id: queryCol
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.margins: 16
                        spacing: 12

                        Row {
                            spacing: 10

                            Button {
                                text: "Scan"
                                flat: root.readMode !== "scan"
                                highlighted: root.readMode === "scan"
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                onClicked: {
                                    root.readMode = "scan"
                                    root.itemPageIndex = 0
                                    root.loadItems()
                                }
                            }
                            Button {
                                text: "Query"
                                flat: root.readMode !== "query"
                                highlighted: root.readMode === "query"
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                onClicked: {
                                    root.readMode = "query"
                                    root.itemPageIndex = 0
                                    // Not run yet: a query needs a partition, and the fields below
                                    // are where it is named.
                                    root.items = []
                                    root.returnedCount = 0
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            spacing: 10
                            visible: root.readMode === "query"

                            Column {
                                spacing: 4
                                Text {
                                    text: root.partitionKey.length > 0 ? root.partitionKey : "Partition key"
                                    color: "#9aa1ac"
                                    font.pixelSize: 11
                                }
                                TextField {
                                    id: partitionValueField
                                    width: 180
                                    placeholderText: root.partitionKeyType === "number" ? "a number" : "a value"
                                    Material.accent: "#4f8cff"
                                    selectByMouse: true
                                    Keys.onReturnPressed: if (runQueryButton.enabled) runQueryButton.clicked()
                                }
                            }

                            Column {
                                spacing: 4
                                visible: root.hasSortKey
                                Text { text: "Sort condition"; color: "#9aa1ac"; font.pixelSize: 11 }
                                ComboBox {
                                    id: sortOperatorCombo
                                    width: 170
                                    model: root.sortOperators
                                    Material.theme: Material.Dark
                                    Material.accent: "#4f8cff"
                                }
                            }

                            Column {
                                spacing: 4
                                visible: root.hasSortKey && sortOperatorCombo.currentIndex > 0
                                Text { text: root.sortKey; color: "#9aa1ac"; font.pixelSize: 11 }
                                TextField {
                                    id: sortValueField
                                    width: 150
                                    placeholderText: root.sortKeyType === "number" ? "a number" : "a value"
                                    Material.accent: "#4f8cff"
                                    selectByMouse: true
                                    Keys.onReturnPressed: if (runQueryButton.enabled) runQueryButton.clicked()
                                }
                            }

                            Column {
                                spacing: 4
                                visible: root.hasSortKey && sortOperatorCombo.currentText === "between"
                                Text { text: "and"; color: "#9aa1ac"; font.pixelSize: 11 }
                                TextField {
                                    id: sortUpperField
                                    width: 150
                                    placeholderText: root.sortKeyType === "number" ? "a number" : "a value"
                                    Material.accent: "#4f8cff"
                                    selectByMouse: true
                                    Keys.onReturnPressed: if (runQueryButton.enabled) runQueryButton.clicked()
                                }
                            }

                            Column {
                                spacing: 4
                                visible: root.hasSortKey
                                Text { text: "Order"; color: "#9aa1ac"; font.pixelSize: 11 }
                                ComboBox {
                                    id: forwardCombo
                                    width: 140
                                    model: ["ascending", "descending"]
                                    Material.theme: Material.Dark
                                    Material.accent: "#4f8cff"
                                }
                            }

                            Button {
                                id: runQueryButton
                                text: "Run"
                                highlighted: true
                                anchors.bottom: parent.bottom
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                enabled: !root.itemsLoading
                                         && root.keyTextValid(partitionValueField.text, root.partitionKeyType)
                                         && (sortOperatorCombo.currentIndex === 0
                                             || root.keyTextValid(sortValueField.text, root.sortKeyType))
                                         && (sortOperatorCombo.currentText !== "between"
                                             || root.keyTextValid(sortUpperField.text, root.sortKeyType))
                                onClicked: {
                                    // Copied into the page's own state first: what is on screen is
                                    // the query that ran, not the one being typed.
                                    root.queryPartitionValue = partitionValueField.text
                                    root.querySortOperator = sortOperatorCombo.currentIndex === 0
                                                             ? "" : sortOperatorCombo.currentText
                                    root.querySortValue = sortValueField.text
                                    root.querySortUpper = sortUpperField.text
                                    root.queryForward = forwardCombo.currentIndex === 0
                                    root.itemPageIndex = 0
                                    root.loadItems()
                                }
                            }
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: "#6b7280"
                            font.pixelSize: 11
                            visible: root.readMode === "query" && !root.hasSortKey
                            text: "This table has no sort key, so a partition holds one item and a query answers with "
                                  + "it alone. There is nothing to narrow by."
                        }

                        Text {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            color: "#e0a458"
                            font.pixelSize: 11
                            visible: root.readMode === "query" && sortOperatorCombo.currentText === "begins-with"
                                     && root.sortKeyType !== "string"
                            text: "⚠ \"begins-with\" only applies to a string sort key: a prefix of a number is not a "
                                  + "thing, and the store refuses it rather than answering with nonsense."
                        }
                    }
                }

                DataTable {
                    width: parent.width
                    columns: root.itemColumns
                    rows: root.items
                    totalCount: root.itemTotalCount
                    pageSize: root.itemPageSize
                    pageIndex: root.itemPageIndex
                    loading: root.itemsLoading
                    error: root.itemsError
                    lastUpdatedText: root.itemsUpdatedText
                    // The store has no search over items: a scan takes a page, a query takes a
                    // partition, and neither takes a substring. The two buttons above are the
                    // filter, so a search box here would be one that does nothing.
                    searchable: false
                    emptyText: root.readMode === "query"
                               ? "No item in that partition matches."
                               : "No items in this table."
                    rowsClickable: true

                    onRowClicked: (row) => itemDialog.openFor(row)
                    onRefreshRequested: root.refresh()
                    onPageChanged: (index) => {
                        root.itemPageIndex = index
                        root.loadItems()
                    }
                    onPageSizeRequested: (size) => {
                        root.itemPageSize = size
                        root.itemPageIndex = 0
                        root.loadItems()
                    }

                    contextMenuActions: [
                        {
                            text: "Open…",
                            action: function(row) { itemDialog.openFor(row) }
                        },
                        {
                            text: "Delete",
                            action: function(row) {
                                root.actionNote = ""
                                ekvClient.deleteItem(root.tableName, root.keyFor(row))
                            }
                        }
                    ]
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    visible: root.readMode === "query" && root.returnedCount > 0
                    // A query has no total, so the honest thing to print is what came back rather
                    // than a page count that would be a guess.
                    text: "Found " + root.returnedCount + " item(s) in this partition."
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
}
