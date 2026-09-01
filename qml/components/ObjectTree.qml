import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// A directory tree over a flat list of ESM objects. Buckets have no directories of their own -
// the "/" inside a key is the only structure there is, plus zero-byte marker objects whose key
// ends in "/" - so the hierarchy is rebuilt here from the keys themselves.
//
// Only expanded folders contribute rows, which is what keeps a bucket with thousands of objects
// from being laid out all at once.
Item {
    id: root

    // Flat object list, each {key, ern, bucketErn, size, contentType, status, created, modified,
    // isDirectory}. Exactly what EsmClient::fetchObjects() emits.
    property var objects: []
    // Case-insensitive substring filter on the full key. While it is set, every folder that still
    // has a match under it is forced open, so results are visible without hunting for them.
    property string filter: ""

    signal openObject(var object)
    signal deleteObject(var object)
    signal renameObject(var object)
    signal copyObject(var object)
    signal moveObject(var object)

    implicitHeight: rows.implicitHeight

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

    function expandAll() {
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

    Column {
        id: rows
        width: parent.width

        Repeater {
            model: root.visibleRows

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
        MenuItem {
            text: "Delete"
            onTriggered: root.deleteObject(rowMenu.currentObject)
        }
    }
}
