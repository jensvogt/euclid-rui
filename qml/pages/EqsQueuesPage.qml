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
    property string sortColumn: "available"
    property bool sortAscending: false

    // euclid's own queues - the bucket queue behind a listener and the like - are left out of
    // list-queues for everyone. An administrator can ask for them, because for them the
    // installation itself is the subject; the switch is not even shown to anyone else, and the
    // server would ignore the request anyway.
    readonly property bool isAdmin: euclidClient.isAdmin
    property bool showInternal: false

    property var queues: []
    // The ERNs some queue names as its dead letter queue. Nothing on a queue says that it is one -
    // the relationship is only ever written by the queues pointing at it - so it is read from the
    // other side, and asked for across every queue rather than only the page on screen.
    property var deadLetterErns: []
    // What the last row action did, kept next to the table: a redrive moves messages between two
    // queues, and neither the row it was started from nor the one they went to says so by itself.
    property string actionNote: ""
    property int totalCount: 0
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    readonly property var columns: {
        let cols = [
            // Internal queues are only ever in this list when an administrator asked for them,
            // and then they are marked: without it euclid's own plumbing sits among the user's
            // queues looking like something somebody created.
            {
                title: "Name",
                key: "name",
                fill: true,
                formatter: function (v, row) { return row && row.internal ? v + "  (internal)" : String(v) },
                colorFor: function (v, row) { return row && row.internal ? "#9aa1ac" : "#c4c9d1" }
            },
            // Approximate: counted periodically rather than maintained per message. Marked once
            // on the first column rather than on all three, which would only add noise.
            { title: "Available (approx.)", key: "available" },
            { title: "Delayed", key: "delayed" },
            { title: "Invisible", key: "invisible" },
            { title: "Size", key: "size", formatter: function (v) { return SizeFormat.format(v) } },
            { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
            { title: "Ern", key: "ern", hidden: true }
        ]
        return cols
    }

    // Whether something feeds this queue, which is the only sense in which a queue "is" a dead
    // letter queue - nothing on the queue itself records it.
    function isDeadLetterQueue(row) {
        return !!row && root.deadLetterErns.indexOf(row.ern) >= 0
    }

    // The queue's name if it is on this page, and the tail of the ERN otherwise - which is the
    // name anyway, since that is what an ERN ends with.
    function queueNameForErn(ern) {
        const row = root.queues.find(q => q.ern === ern)
        if (row) return row.name
        const parts = String(ern).split(":")
        return parts.length > 0 ? parts[parts.length - 1] : ern
    }

    signal back()
    signal openQueue(string queueErn, string queueName)
    signal openQueueDetails(string queueErn, string queueName, var details)

    function refresh() {
        if (!root.loggedIn) {
            error = "Sign in to view queues."
            return
        }
        loading = true
        error = ""
        eqsClient.fetchQueues(root.prefix, root.pageIndex, root.pageSize,
            root.sortColumn, root.sortAscending ? "asc" : "desc",
            root.isAdmin && root.showInternal)
        // Which of them are dead letter queues, for the redrive entry in the row menu.
        eqsClient.fetchDeadLetterTargets()
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
        target: eqsClient
        function onQueuesLoaded(list, total) {
            root.loading = false
            root.error = ""
            root.queues = list
            root.totalCount = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onQueuesFailed(message) {
            root.loading = false
            root.error = message
        }
        function onDeadLetterTargetsLoaded(erns) {
            root.deadLetterErns = erns
        }
        function onDlqRedriven(queueErn, messages, remaining, targets, note) {
            if (messages === 0) {
                root.actionNote = "Nothing to redrive: the dead letter queue held no message with a source queue to go back to."
                    + (remaining > 0 ? " " + remaining + " message(s) remain." : "")
                return
            }
            // Named per target, since a dead letter queue shared by several queues sends each
            // message back to its own - saying only a total would hide that.
            const where = targets.map(t => t.messages + " → " + root.queueNameForErn(t.queueErn)).join(", ")
            root.actionNote = "Redrove " + messages + " message(s): " + where
                             + (note && note.length > 0 ? " " + note : "")
        }
        function onDlqRedriveFailed(message) {
            root.error = message
        }

        function onQueuesReload() {
            refresh()
        }

        function onQueueCreated(name) {
            createQueueDialog.creating = false
            createQueueDialog.close()
        }
        function onQueueCreateFailed(message) {
            createQueueDialog.creating = false
            createQueueDialog.errorText = message
        }
    }

    Dialog {
        id: createQueueDialog
        modal: true
        anchors.centerIn: parent
        width: 380
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

        // Empty unless a dead letter queue was asked for; then it is the name to create it under,
        // which is the field's own text where there is one and "<queue>-dlq" otherwise.
        readonly property string dlqName: {
            if (!dlqCheck.checked) return ""
            const typed = dlqNameField.text.trim()
            return typed.length > 0 ? typed : createQueueDialog.defaultDlqName
        }
        readonly property string defaultDlqName: nameField.text.trim().length > 0 ? nameField.text.trim() + "-dlq" : ""

        onOpened: {
            nameField.text = ""
            dlqCheck.checked = false
            dlqNameField.text = ""
            createQueueDialog.errorText = ""
            createQueueDialog.creating = false
            nameField.forceActiveFocus()
        }

        contentItem: Column {
            width: createQueueDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Queue"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Enter a name for the new queue."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Queue name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: nameField
                    width: parent.width
                    placeholderText: "e.g. orders-in"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createButton.enabled) createButton.clicked()
                }
            }

            // Creating the queue is the one moment EQS attaches a dead letter queue: naming one
            // here creates it and points the new queue at it in the same call. A queue created
            // without one cannot be given one afterwards - there is no action for it - so this is
            // the decision, not a default that can be revisited.
            Column {
                width: parent.width
                spacing: 6

                CheckBox {
                    id: dlqCheck
                    text: "Create a dead letter queue"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }

                TextField {
                    id: dlqNameField
                    width: parent.width
                    visible: dlqCheck.checked
                    placeholderText: createQueueDialog.defaultDlqName.length > 0
                                     ? createQueueDialog.defaultDlqName : "e.g. orders-in-dlq"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createButton.enabled) createButton.clicked()
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: dlqCheck.checked
                          ? "Messages received more than the retry limit are moved into it. It is created with the same "
                            + "settings as this queue. Attach it now or not at all: EQS cannot give an existing queue one."
                          : "Without one, a message that is never processed stays in the queue. It can only be attached "
                            + "while the queue is being created."
                }
            }

            Text {
                text: createQueueDialog.errorText
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
                    onClicked: createQueueDialog.close()
                }

                BusyIndicator {
                    running: createQueueDialog.creating
                    visible: createQueueDialog.creating
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
                    // A dead letter queue by the same name as the queue itself is refused here
                    // rather than by the server: it would be one queue redriving into itself.
                    enabled: !createQueueDialog.creating && nameField.text.trim().length > 0
                             && createQueueDialog.dlqName !== nameField.text.trim()
                    onClicked: {
                        createQueueDialog.errorText = ""
                        createQueueDialog.creating = true
                        eqsClient.createQueue(nameField.text.trim(), createQueueDialog.dlqName)
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
                text: "‹ Back to EQS Dashboard"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Queues (" + root.totalCount + ")"
                    subtitle: "All queues in the " + root.namespaceName + " namespace."
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 16

                    Row {
                        spacing: 8
                        visible: root.isAdmin
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            text: "Internal queues"
                            color: "#9aa1ac"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        ToggleSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.showInternal
                            // Back to the first page: the listing is a different one now, and page
                            // three of the old one is not page three of the new one.
                            onToggled: (checked) => {
                                root.showInternal = checked
                                root.pageIndex = 0
                                root.refresh()
                            }
                        }
                    }

                    Button {
                        text: "+ Add Queue"
                        highlighted: true
                        anchors.verticalCenter: parent.verticalCenter
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: createQueueDialog.open()
                    }
                }
            }

            DataTable {
                width: parent.width
                columns: root.columns
                rows: root.queues
                totalCount: root.totalCount
                pageSize: root.pageSize
                pageIndex: root.pageIndex
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by queue name prefix..."
                emptyText: "No queues found in this namespace."
                rowsClickable: true
                sortKey: root.sortColumn
                sortAscending: root.sortAscending

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
                onRowClicked: (row) => root.openQueue(row.ern, row.name)
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
                            root.openQueueDetails(row.ern, row.name, row)
                        }
                    },
                    {
                        text: "Purge",
                        enabled: function(row) {
                            return !!row && Number(row.available) > 0
                        },
                        action: function(row) {
                            eqsClient.purgeQueue(row.ern)
                        }
                    },
                    {
                        // Only for a queue something else feeds: the server refuses a redrive of
                        // an ordinary queue, and offering it everywhere would make that refusal
                        // the usual outcome of clicking it.
                        text: "Redrive…",
                        enabled: function(row) { return root.isDeadLetterQueue(row) },
                        action: function(row) { redriveDialog.openFor(row) }
                    },
                    {
                        text: "Delete",
                        action: function(row) {
                            eqsClient.deleteQueue(row.ern)
                        }
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

    Dialog {
        id: redriveDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        standardButtons: Dialog.NoButton

        property var queue: null

        function openFor(row) {
            redriveDialog.queue = row
            redriveDialog.open()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: redriveDialog.availableWidth
            spacing: 16

            Text { text: "Redrive Dead Letter Queue"; color: "white"; font.pixelSize: 18; font.bold: true }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: redriveDialog.queue
                      ? "Every message in \"" + redriveDialog.queue.name + "\" goes back to the queue it came from, "
                        + "with its receive count reset so it gets a full set of attempts again."
                      : ""
                color: "#c4c9d1"
                font.pixelSize: 12
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "A message whose source queue was never recorded stays where it is rather than being "
                      + "guessed at. Whatever put them here will do so again if it still fails."
                color: "#9aa1ac"
                font.pixelSize: 11
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: !!redriveDialog.queue && Number(redriveDialog.queue.available) > 0
                text: "⚠ " + (redriveDialog.queue ? redriveDialog.queue.available : 0)
                      + " message(s) will be delivered again as soon as they arrive."
                color: "#e0a458"
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
                        onClicked: redriveDialog.close()
                    }
                    Button {
                        text: "Redrive"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: {
                            root.actionNote = ""
                            eqsClient.redriveDlq(redriveDialog.queue.ern)
                            redriveDialog.close()
                        }
                    }
                }
            }
        }
    }
}
