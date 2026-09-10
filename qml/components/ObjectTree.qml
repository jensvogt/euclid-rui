import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// A directory tree over a flat list of ESM objects. Buckets have no directories of their own -
// the "/" inside a key is the only structure there is, plus zero-byte marker objects whose key
// ends in "/" - so the hierarchy is rebuilt here from the keys themselves.
//
// Only expanded folders contribute rows, which is what keeps a bucket with thousands of objects
// from being laid out all at once - and the rows that are left are paged, so "Expand all" over a
// full bucket is a page of rows rather than every one of them at once.
Item {
    id: root

    // Flat object list, each {key, ern, bucketErn, size, contentType, status, created, modified,
    // isDirectory}. Exactly what EsmClient::fetchObjects() emits.
    property var objects: []
    // Case-insensitive substring filter on the full key. While it is set, every folder that still
    // has a match under it is forced open, so results are visible without hunting for them.
    property string filter: ""

    // Rows per page, and the page being shown. Both are the tree's own: the objects are all in hand
    // already, so a page is a slice of what would be drawn rather than a query, and there is no
    // owner to ask - unlike DataTable, whose pages come from the server.
    property int pageSize: 50
    property int pageIndex: 0
    property bool pageSizeSelectable: true

    // The current size is always among the choices, even when the owner set one that is not a round
    // number - otherwise the field would show empty for it. Same arrangement DataTable uses.
    readonly property var pageSizeOptions: {
        const sizes = [25, 50, 100, 250, 500]
        return sizes.indexOf(root.pageSize) >= 0
            ? sizes : sizes.concat([root.pageSize]).sort(function (a, b) { return a - b })
    }

    signal openObject(var object)
    signal deleteObject(var object)
    signal renameObject(var object)
    signal copyObject(var object)
    signal moveObject(var object)
    signal touchObject(var object)

    implicitHeight: layout.implicitHeight

    // {path: true} for folders the user has opened. Paths carry their trailing "/", so they are
    // exactly the keys a directory marker object would have.
    property var expandedPaths: ({})

    readonly property bool filtering: root.filter.trim().length > 0

    function isExpanded(path) {
        return root.filtering || root.expandedPaths[path] === true
    }

    function toggle(path) {
        // A filter forces everything open; collapsing under it would just be undone on the next
        // keystroke, so leave the stored state alone until the filter is cleared.
        if (root.filtering)
            return
        const updated = Object.assign({}, root.expandedPaths)
        if (updated[path]) delete updated[path]
        else updated[path] = true
        root.expandedPaths = updated
    }

    // A new filter is a new listing, and its results are read from the top. Expanding or collapsing
    // everything restructures the whole tree the same way; toggling one folder does not, and holds
    // the page it happened on.
    onFilterChanged: root.pageIndex = 0

    function expandAll() {
        root.pageIndex = 0
        const updated = {}
        for (const object of root.objects) {
            const parts = object.key.split("/")
            let path = ""
            // Every element but the last names a folder; a key ending in "/" splits to a trailing
            // empty string, so its own folder is covered too.
            for (let i = 0; i < parts.length - 1; i++) {
                path += parts[i] + "/"
                updated[path] = true
            }
        }
        root.expandedPaths = updated
    }

    function collapseAll() {
        root.pageIndex = 0
        root.expandedPaths = ({})
    }

    // Nested {name, path, isDirectory, object, children, fileCount, totalSize} nodes, built from
    // the keys. A file and a folder can share a name only if one of them ends in "/", so the node
    // map is keyed by name plus that distinction.
    readonly property var tree: {
        const needle = root.filter.trim().toLowerCase()
        const rootNode = { name: "", path: "", isDirectory: true, object: null, children: ({}), fileCount: 0, totalSize: 0 }

        for (const object of root.objects) {
            if (needle.length > 0 && object.key.toLowerCase().indexOf(needle) < 0)
                continue

            const directoryKey = object.key.charAt(object.key.length - 1) === "/"
            const parts = object.key.split("/").filter(p => p.length > 0)
            let node = rootNode
            let path = ""

            for (let i = 0; i < parts.length; i++) {
                const last = i === parts.length - 1
                const isDirectory = !last || directoryKey
                path += parts[i] + (isDirectory ? "/" : "")
                const id = parts[i] + (isDirectory ? "/" : "")

                if (!node.children[id]) {
                    node.children[id] = {
                        name: parts[i], path: path, isDirectory: isDirectory,
                        object: null, children: ({}), fileCount: 0, totalSize: 0
                    }
                }
                node = node.children[id]
                if (last)
                    node.object = object
                // Roll the file up through every folder above it, so a collapsed folder can still
                // say how much is inside.
                if (!directoryKey) {
                    node.fileCount += last ? 0 : 1
                    node.totalSize += last ? 0 : object.size
                }
            }
        }
        return rootNode
    }

    // The tree flattened to just the rows that are currently visible, each with its depth.
    readonly property var visibleRows: {
        const out = []

        function walk(node, depth) {
            const ids = Object.keys(node.children).sort((a, b) => {
                const left = node.children[a]
                const right = node.children[b]
                // Folders first, then case-insensitive by name - the order a file manager uses.
                if (left.isDirectory !== right.isDirectory) return left.isDirectory ? -1 : 1
                const ln = left.name.toLowerCase()
                const rn = right.name.toLowerCase()
                return ln === rn ? 0 : (ln < rn ? -1 : 1)
            })

            for (const id of ids) {
                const child = node.children[id]
                const childIds = Object.keys(child.children)
                out.push({
                    name: child.name, path: child.path, depth: depth,
                    isDirectory: child.isDirectory, object: child.object,
                    childCount: childIds.length, fileCount: child.fileCount, totalSize: child.totalSize,
                    expanded: root.isExpanded(child.path)
                })
                if (child.isDirectory && root.isExpanded(child.path))
                    walk(child, depth + 1)
            }
        }

        walk(root.tree, 0)
        return out
    }

    // ── Paging ───────────────────────────────────────────────────────────────
    // Over the visible rows, which is the tree as it is actually drawn. Paging the objects instead
    // would give pages of wildly different lengths - a page whose objects are all inside collapsed
    // folders would be a handful of rows, or none.

    readonly property int pageCount: Math.max(1, Math.ceil(root.visibleRows.length / root.pageSize))
    // Clamped rather than left where it was: collapsing a folder or typing into the filter shortens
    // the tree, and an index past the end would leave a blank page with nothing saying why.
    readonly property int clampedPageIndex: Math.min(Math.max(0, root.pageIndex), root.pageCount - 1)
    readonly property var pagedRows: root.visibleRows.slice(
        root.clampedPageIndex * root.pageSize,
        root.clampedPageIndex * root.pageSize + root.pageSize)

    // The size field stays even when everything fits on one page - that is exactly when someone
    // wants to make the page larger. An empty tree has nothing to size, and says so above instead.
    readonly property bool pagerVisible: root.visibleRows.length > 0
                                         && (root.pageSizeSelectable || root.visibleRows.length > root.pageSize)

    // The clamp above keeps the wrong page from being shown; this keeps the stored index from
    // staying out of range behind it, so a tree that shrank and grew again does not jump back to a
    // page nobody asked for.
    onVisibleRowsChanged: {
        if (root.pageIndex > root.pageCount - 1)
            root.pageIndex = root.pageCount - 1
    }

    // The folders the first row of this page sits inside, as a path. Every page after the first can
    // begin in the middle of a folder whose own row is on the page before it, and the indentation
    // of these rows says nothing without it - so the structure is repeated at the top of the page.
    // Empty on a page that starts at the top level, where there is nothing to repeat.
    readonly property string pageParentPath: {
        const first = root.pagedRows.length > 0 ? root.pagedRows[0] : null
        if (!first || first.depth === 0) return ""
        // The last part is the row itself, whether it is a file or a folder; everything above it is
        // the context this page is missing.
        const parts = String(first.path).split("/").filter(p => p.length > 0)
        let path = ""
        for (let i = 0; i < parts.length - 1; i++)
            path += parts[i] + "/"
        return path
    }

    Column {
        id: layout
        width: parent.width

        // Where this page picks up. Deliberately not a row of the tree: it is not something to
        // expand or act on, it is the answer to "inside what?" for everything below it.
        Item {
            width: parent.width
            height: root.pageParentPath.length > 0 ? 28 : 0
            visible: root.pageParentPath.length > 0

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    text: "🗀"
                    font.pixelSize: 12
                    color: "#ffb545"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.pageParentPath
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "continued"
                    color: "#6b7280"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: "#2c313c"
            }
        }

        Column {
            id: rows
            width: parent.width

            Repeater {
                model: root.pagedRows

                delegate: Rectangle {
                    id: rowItem
                    required property var modelData

                    width: rows.width
                    height: 30
                    color: rowMouse.containsMouse ? "#262b35" : "transparent"

                    readonly property bool isDirectory: rowItem.modelData.isDirectory
                    // A directory marker object can be deleted like any other; a folder that exists
                    // only because some key contains a "/" has no object of its own to delete.
                    readonly property bool hasObject: !!rowItem.modelData.object

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: rowItem.isDirectory || rowItem.hasObject ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (rowItem.isDirectory) root.toggle(rowItem.modelData.path)
                            else if (rowItem.hasObject) root.openObject(rowItem.modelData.object)
                        }
                    }

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        // 18px per level, past a fixed inset so the first level isn't flush left.
                        anchors.leftMargin: 8 + rowItem.modelData.depth * 18
                        spacing: 6

                        Text {
                            width: 12
                            text: rowItem.isDirectory ? (rowItem.modelData.expanded ? "⌄" : "›") : ""
                            color: "#6b7280"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: rowItem.isDirectory ? "🗀" : "🗎"
                            font.pixelSize: 12
                            color: rowItem.isDirectory ? "#ffb545" : "#6b7280"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: rowItem.modelData.name + (rowItem.isDirectory ? "/" : "")
                            color: "#e5e7eb"
                            font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 14

                        Text {
                            text: rowItem.isDirectory
                                  ? (rowItem.modelData.fileCount > 0
                                     ? rowItem.modelData.fileCount + " file(s) · " + SizeFormat.format(rowItem.modelData.totalSize)
                                     : (rowItem.modelData.childCount === 0 ? "empty" : ""))
                                  : SizeFormat.format(rowItem.modelData.object.size)
                            color: "#6b7280"
                            font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: !rowItem.isDirectory
                            text: rowItem.hasObject ? DateFormat.format(rowItem.modelData.object.modified) : ""
                            color: "#6b7280"
                            font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        // Same actions button every other list in the app uses (see DataTable), so a
                        // row's actions are found in the same place here as anywhere else. Only rows
                        // that have an object of their own get one: a folder that exists merely
                        // because some key contains a "/" is not something the server can act on.
                        Rectangle {
                            visible: rowItem.hasObject
                            width: 24
                            height: 24
                            radius: 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: kebabArea.containsMouse ? "#333a48" : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }

                            Text {
                                anchors.centerIn: parent
                                text: "⋮"
                                // Dimmed until the row is under the cursor, so a long listing is not a
                                // column of icons competing with the keys themselves.
                                color: rowMouse.containsMouse || kebabArea.containsMouse ? "#c4c9d1" : "#4a5160"
                                font.pixelSize: 16
                                font.bold: true
                            }

                            MouseArea {
                                id: kebabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    rowMenu.currentObject = rowItem.modelData.object
                                    rowMenu.popup()
                                }
                            }
                        }
                    }

                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: "#232830"
                    }
                }
            }
        }

        // Counted in rows, not in objects: a folder is a row here too, and the number that matches
        // what is on screen is the one worth printing. Laid out like DataTable's footer, so moving
        // through a tree works the way moving through a table does.
        Item {
            width: parent.width
            // Both from the same property rather than from the row below: QQuickItem::visible reads
            // back as *effective* visibility, so sizing this off a child that this then hides would
            // latch the footer away and never bring it back.
            height: root.pagerVisible ? 44 : 0
            visible: root.pagerVisible

            Text {
                id: rowRangeText
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: root.visibleRows.length > root.pageSize
                text: "Rows " + (root.clampedPageIndex * root.pageSize + 1)
                      + "–" + Math.min((root.clampedPageIndex + 1) * root.pageSize, root.visibleRows.length)
                      + " of " + root.visibleRows.length
                color: "#6b7280"
                font.pixelSize: 11
            }

            Row {
                id: pagingRow
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Row {
                    spacing: 8
                    visible: root.pageSizeSelectable
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: "Rows"
                        color: "#6b7280"
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    ComboBox {
                        id: pageSizeField
                        // Editable so a size that is not on the list can simply be typed; the
                        // validator keeps that from becoming a page of a million rows.
                        editable: true
                        width: 96
                        height: 30
                        anchors.verticalCenter: parent.verticalCenter
                        model: root.pageSizeOptions
                        currentIndex: root.pageSizeOptions.indexOf(root.pageSize)
                        validator: IntValidator { bottom: 1; top: 1000 }
                        font.pixelSize: 12
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"

                        // Back to the first page: the row that was at the top of page four is
                        // somewhere else entirely once the pages are twice the size.
                        onActivated: (index) => {
                            root.pageSize = Number(root.pageSizeOptions[index])
                            root.pageIndex = 0
                        }
                        // Enter in the text part. Clamped rather than refused, so a typed 5000
                        // becomes the largest page this offers instead of nothing happening.
                        onAccepted: {
                            const wanted = parseInt(pageSizeField.editText, 10)
                            if (isNaN(wanted)) return
                            const clamped = Math.max(1, Math.min(1000, wanted))
                            if (clamped === root.pageSize) return
                            root.pageSize = clamped
                            root.pageIndex = 0
                        }
                    }
                }

                Button {
                    text: "« First"
                    flat: true
                    visible: root.visibleRows.length > root.pageSize
                    enabled: root.clampedPageIndex > 0
                    Material.theme: Material.Dark
                    onClicked: root.pageIndex = 0
                }
                Button {
                    text: "‹ Prev"
                    flat: true
                    visible: root.visibleRows.length > root.pageSize
                    enabled: root.clampedPageIndex > 0
                    Material.theme: Material.Dark
                    onClicked: root.pageIndex = root.clampedPageIndex - 1
                }
                Text {
                    text: "Page " + (root.clampedPageIndex + 1) + " of " + root.pageCount
                    visible: root.visibleRows.length > root.pageSize
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
                Button {
                    text: "Next ›"
                    flat: true
                    visible: root.visibleRows.length > root.pageSize
                    enabled: root.clampedPageIndex < root.pageCount - 1
                    Material.theme: Material.Dark
                    onClicked: root.pageIndex = root.clampedPageIndex + 1
                }
                Button {
                    text: "Last »"
                    flat: true
                    visible: root.visibleRows.length > root.pageSize
                    enabled: root.clampedPageIndex < root.pageCount - 1
                    Material.theme: Material.Dark
                    onClicked: root.pageIndex = root.pageCount - 1
                }
            }
        }
    }

    // One menu for the whole tree rather than one per row: a bucket can put hundreds of rows on
    // screen, and only ever one of their menus is open. Same arrangement DataTable uses.
    Menu {
        id: rowMenu

        property var currentObject: null

        MenuItem {
            text: "Rename…"
            onTriggered: root.renameObject(rowMenu.currentObject)
        }
        MenuItem {
            text: "Copy…"
            onTriggered: root.copyObject(rowMenu.currentObject)
        }
        MenuItem {
            text: "Move…"
            onTriggered: root.moveObject(rowMenu.currentObject)
        }
        // No ellipsis and no confirmation: touching one object announces one object, which is
        // both undoable-by-irrelevance - nothing about it changes - and small enough that a
        // consumer hearing about it twice is the ordinary case a retry already covers. The whole
        // bucket is the one that gets asked about, on the bucket list.
        MenuItem {
            text: "Touch"
            onTriggered: root.touchObject(rowMenu.currentObject)
        }
        MenuItem {
            text: "Delete"
            onTriggered: root.deleteObject(rowMenu.currentObject)
        }
    }
}
