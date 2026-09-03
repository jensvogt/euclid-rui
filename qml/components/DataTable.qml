import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

Item {
    id: root

    // Columns: [{ title, key, width?, fill?, color, formatter(value, row), colorFor(value, row) }]
    // - width: fixed pixel width
    // - fill: true -> takes all remaining space (at most one such column)
    // - neither -> "as needed": sized to fit the widest header/cell content
    property var columns: []
    property var rows: []
    property int totalCount: 0
    property int pageSize: 10
    property int pageIndex: 0
    property bool loading: false
    property string error: ""
    property string searchPlaceholder: "Filter by prefix..."
    property string lastUpdatedText: "—"
    property bool rowsClickable: false
    property string emptyText: "No results found."
    property int columnSpacing: 20

    // Context menu
    property var contextMenuActions: []

    // Sorting: column is sortable unless it sets "sortable: false" or has no "key"
    property string sortKey: ""
    property bool sortAscending: true

    signal searchChanged(string prefix)
    signal refreshRequested()
    signal pageChanged(int pageIndex)
    signal rowClicked(var row)
    signal contextMenuActionTriggered(var action, var row)
    signal sortRequested(string key, bool ascending)

    readonly property int pageCount: totalCount > 0 ? Math.max(1, Math.ceil(totalCount / pageSize)) : 1

    property var columnWidths: []

    readonly property var visibleColumns:
        root.columns.filter(function(column) {
            return !column.hidden
        })

    // Reserves room so the trailing drill-in chevron / actions button don't collide with the
    // last column's text (fill-column sizing otherwise has no idea they're there).
    readonly property int trailingIconsWidth: root.contextMenuActions.length > 0 ? (root.columnSpacing + 26) : 0

    function recomputeColumnWidths() {
        let widths = []
        let usedWidth = 0
        let fillIndex = -1

        for (let i = 0; i < root.visibleColumns.length; i++) {
            const col = root.visibleColumns[i]
            if (col.fill) {
                widths.push(0)
                fillIndex = i
                continue
            }
            if (typeof col.width === "number") {
                widths.push(col.width)
                usedWidth += col.width
                continue
            }

            headerMetrics.text = col.title
            let maxW = headerMetrics.width
            for (let r = 0; r < root.rows.length; r++) {
                const v = root.rows[r][col.key]
                cellMetrics.text = col.formatter
                    ? String(col.formatter(v, root.rows[r]))
                    : (v === undefined || v === null ? "" : String(v))
                if (cellMetrics.width > maxW)
                    maxW = cellMetrics.width
            }
            const w = Math.ceil(maxW) + 20
            widths.push(w)
            usedWidth += w
        }

        if (fillIndex >= 0) {
            const spacingTotal = Math.max(0, root.visibleColumns.length - 1) * root.columnSpacing
            const availableWidth = root.width - 24 - root.trailingIconsWidth
            widths[fillIndex] = Math.max(140, availableWidth - usedWidth - spacingTotal)
        }

        columnWidths = widths
    }

    onColumnsChanged: recomputeColumnWidths()
    onRowsChanged: recomputeColumnWidths()
    onWidthChanged: recomputeColumnWidths()
    Component.onCompleted: recomputeColumnWidths()

    TextMetrics {
        id: headerMetrics
        font.pixelSize: 11
        font.bold: true
    }
    TextMetrics {
        id: cellMetrics
        font.pixelSize: 12
    }

    implicitWidth: contentCol.implicitWidth
    implicitHeight: contentCol.implicitHeight

    Column {
        id: contentCol
        width: parent.width
        spacing: 14

        Column {
            width: parent.width
            spacing: 10

            Row {
                width: parent.width
                height: 40
                spacing: 10

                TextField {
                    id: searchField
                    width: parent.width - refreshButton.width - 10
                    height: parent.height
                    anchors.verticalCenter: parent.verticalCenter
                    placeholderText: root.searchPlaceholder
                    Material.accent: "#4f8cff"
                    onTextChanged: searchDebounce.restart()

                    Timer {
                        id: searchDebounce
                        interval: 350
                        onTriggered: root.searchChanged(searchField.text)
                    }
                }

                Button {
                    id: refreshButton
                    text: "⟳"
                    font.pixelSize: 20
                    flat: true
                    width: parent.height
                    height: parent.height
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    onClicked: root.refreshRequested()
                }
            }

            Rectangle {
                width: parent.width
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                height: tableCol.implicitHeight + 24
                visible: root.rows.length > 0

                Column {
                    id: tableCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 12
                    spacing: 6

                    Row {
                        width: parent.width
                        spacing: root.columnSpacing
                        Repeater {
                            model: root.visibleColumns
                            delegate: Item {
                                id: headerCell
                                width: root.columnWidths[index]
                                height: headerLabel.implicitHeight
                                readonly property bool sortable: modelData.key !== undefined && modelData.sortable !== false

                                Row {
                                    spacing: 4
                                    Text {
                                        id: headerLabel
                                        text: modelData.title
                                        color: headerArea.containsMouse && headerCell.sortable ? "#c4c9d1" : "#6b7280"
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                    Text {
                                        visible: root.sortKey === modelData.key
                                        text: root.sortAscending ? "▲" : "▼"
                                        color: "#4f8cff"
                                        font.pixelSize: 9
                                        anchors.verticalCenter: headerLabel.verticalCenter
                                    }
                                }

                                MouseArea {
                                    id: headerArea
                                    anchors.fill: parent
                                    hoverEnabled: headerCell.sortable
                                    cursorShape: headerCell.sortable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: {
                                        if (!headerCell.sortable)
                                            return
                                        const ascending = root.sortKey === modelData.key ? !root.sortAscending : true
                                        root.sortRequested(modelData.key, ascending)
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { width: parent.width; height: 1; color: "#2c313c" }

                    Repeater {
                        model: root.rows
                        delegate: Rectangle {
                            id: rowItem
                            property var rowData: modelData
                            width: tableCol.width
                            height: 44
                            radius: 8
                            color: rowArea.containsMouse && root.rowsClickable ? "#262b35" : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: root.rowsClickable
                                cursorShape: root.rowsClickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (root.rowsClickable) root.rowClicked(rowItem.rowData)
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: root.columnSpacing
                                Repeater {
                                    model: root.visibleColumns
                                    delegate: Text {
                                        width: root.columnWidths[index]
                                        property var cellValue: rowItem.rowData[modelData.key]
                                        text: modelData.formatter
                                            ? modelData.formatter(cellValue, rowItem.rowData)
                                            : (cellValue === undefined || cellValue === null ? "" : String(cellValue))
                                        color: modelData.colorFor
                                            ? modelData.colorFor(cellValue, rowItem.rowData)
                                            : (modelData.color !== undefined ? modelData.color : "#c4c9d1")
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                }

                                // Trailing "column": actions button, laid out in the same flow as the
                                // data columns (same root.columnSpacing gap) instead of overlaid/
                                // absolutely positioned. Row left-click already drills in, so no
                                // separate chevron indicator is needed here.
                                Rectangle {
                                    visible: root.contextMenuActions.length > 0
                                    width: 26
                                    height: 26
                                    radius: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: kebabArea.containsMouse ? "#333a48" : "transparent"
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "⋮"
                                        color: "#c4c9d1"
                                        font.pixelSize: 18
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: kebabArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            contextMenu.currentRow = rowItem.rowData
                                            contextMenu.popup()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            visible: !root.loading && root.error.length === 0 && root.rows.length === 0
            text: root.emptyText
            color: "#9aa1ac"
            font.pixelSize: 13
        }

        // One footer row: what the table is showing on the left, how to move through it on the
        // right. Its height follows the buttons when they are there and the status line when they
        // are not, so a single-page table keeps a footer the size of its own contents.
        Item {
            width: parent.width
            height: Math.max(statusRow.implicitHeight, pagingRow.visible ? pagingRow.implicitHeight : 0)

            Row {
                id: statusRow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                BusyIndicator { running: root.loading; visible: root.loading; width: 16; height: 16 }
                Text {
                    text: root.error.length > 0 ? root.error : ("Last updated " + root.lastUpdatedText)
                    color: root.error.length > 0 ? "#ff6b6b" : "#6b7280"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                id: pagingRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                visible: root.totalCount > root.pageSize

                Button {
                    text: "« First"
                    flat: true
                    enabled: root.pageIndex > 0
                    Material.theme: Material.Dark
                    onClicked: root.pageChanged(0)
                }
                Button {
                    text: "‹ Prev"
                    flat: true
                    enabled: root.pageIndex > 0
                    Material.theme: Material.Dark
                    onClicked: root.pageChanged(root.pageIndex - 1)
                }
                Text {
                    text: "Page " + (root.pageIndex + 1) + " of " + root.pageCount
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
                Button {
                    text: "Next ›"
                    flat: true
                    enabled: root.pageIndex < root.pageCount - 1
                    Material.theme: Material.Dark
                    onClicked: root.pageChanged(root.pageIndex + 1)
                }
                Button {
                    text: "Last »"
                    flat: true
                    enabled: root.pageIndex < root.pageCount - 1
                    Material.theme: Material.Dark
                    onClicked: root.pageChanged(root.pageCount - 1)
                }
            }
        }

        Menu {
            id: contextMenu

            property var currentRow: null

            Repeater {
                model: root.contextMenuActions

                delegate: MenuItem {
                    required property var modelData

                    text: modelData.text
                    enabled: modelData.enabled ? modelData.enabled(contextMenu.currentRow) : true

                    onTriggered: {
                        if (modelData.action)
                            modelData.action(contextMenu.currentRow)
                    }
                }
            }
        }
    }
}
