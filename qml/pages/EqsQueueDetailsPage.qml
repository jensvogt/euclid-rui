import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string queueErn: ""
    property string queueName: ""
    property var details: ({})

    signal back()
    signal viewMessages(string queueErn, string queueName)

    // Erns look like ern:eqs:{region}:{accountId}:{namespace}:queue:{name}
    function ernPart(index) {
        const parts = root.queueErn.split(":")
        return index < parts.length ? parts[index] : "—"
    }

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    function tagList() {
        const tags = detail("tags", {})
        return tags ? Object.keys(tags) : []
    }

    // No "get single queue" action exists server-side to re-fetch after a mutation, so apply the
    // now-confirmed change to the local details snapshot instead (reassigned, not mutated in
    // place, so the "var" property change notification actually fires).
    function addTagLocally(key, value) {
        const tags = Object.assign({}, detail("tags", {}))
        tags[key] = value
        root.details = Object.assign({}, root.details, { tags: tags })
    }

    function removeTagLocally(key) {
        const tags = Object.assign({}, detail("tags", {}))
        delete tags[key]
        root.details = Object.assign({}, root.details, { tags: tags })
    }

    function setStatusLocally(status) {
        root.details = Object.assign({}, root.details, { status: status })
    }

    function setDetailLocally(key, value) {
        const patch = ({})
        patch[key] = value
        root.details = Object.assign({}, root.details, patch)
    }

    // ── Configuration ────────────────────────────────────────────────────────

    readonly property int visibility: Number(detail("visibility", 30))
    readonly property int delay: Number(detail("delay", 0))
    readonly property int maxMessageLength: Number(detail("maxMessageLength", 0))
    // Entity::EQS::kDefaultMaxMessageLength: what a send is measured against when the queue carries
    // no limit of its own, which is what a zero here means.
    readonly property int defaultMaxMessageLength: 1024 * 1024

    // Anything that is not "STOPPED" reads as running, including a snapshot from a server old
    // enough not to carry the field: that way round the page offers "Stop", which the server can
    // answer, rather than "Start" on a queue that was never stopped.
    readonly property bool stopped: String(root.detail("status", "AVAILABLE")) === "STOPPED"

    Connections {
        target: eqsClient
        function onQueueTagAdded(queueErn, key, value) {
            if (queueErn !== root.queueErn) return
            addTagDialog.saving = false
            addTagDialog.close()
            root.addTagLocally(key, value)
        }
        function onQueueTagAddFailed(message) {
            addTagDialog.saving = false
            addTagDialog.errorText = message
        }
        function onQueueTagDeleted(queueErn, key) {
            if (queueErn !== root.queueErn) return
            root.removeTagLocally(key)
        }
        function onQueueStatusChanged(queueErn, status) {
            if (queueErn !== root.queueErn) return
            root.setStatusLocally(status)
            // Said in full because "stopped" is narrower than it reads: what stops is consumption,
            // and a queue nobody is draining goes on growing.
            root.statusNote = status === "STOPPED"
                ? "Stopped: receives are refused from now on. Sends still land, and messages already "
                  + "in flight are left to their consumers."
                : "Started: consumers can receive from this queue again."
        }
        function onQueueStatusFailed(message) {
            root.statusNote = message
        }
        function onQueueVisibilityChanged(queueErn, visibility) {
            if (queueErn !== root.queueErn) return
            root.setDetailLocally("visibility", visibility)
            settingsDialog.settled()
        }
        function onQueueDelayChanged(queueErn, delay) {
            if (queueErn !== root.queueErn) return
            root.setDetailLocally("delay", delay)
            settingsDialog.settled()
        }
        function onQueueMaxMessageLengthChanged(queueErn, maxMessageLength, effective) {
            if (queueErn !== root.queueErn) return
            root.setDetailLocally("maxMessageLength", maxMessageLength)
            settingsDialog.settled()
        }
        function onQueueConfigurationFailed(message) {
            // Left open with the message on it: one or two of the three may have gone through, and
            // the dialog is where the ones that did not can be tried again.
            settingsDialog.pending = 0
            settingsDialog.errorText = message
        }
        // "create-queue" is the queues page's signal as much as this dialog's, so only a save
        // started here is acted on.
        function onQueueCreated(name) {
            if (!dlqDialog.saving) return
            dlqDialog.saving = false
            dlqDialog.close()
            root.dlqNote = "Created queue \"" + name + "\". It is not yet the dead letter queue of "
                    + root.queueName + " - EQS attaches one only when a queue is created."
        }
        function onQueueCreateFailed(message) {
            if (!dlqDialog.saving) return
            dlqDialog.saving = false
            dlqDialog.errorText = message
        }
    }

    readonly property int available: Number(detail("available", 0))
    readonly property int delayed: Number(detail("delayed", 0))
    readonly property int invisible: Number(detail("invisible", 0))

    // The queue this one redrives into once a message has been received more than maxReceiveCount
    // times. EQS only ever sets this when a queue is created, so it is read-only here.
    readonly property string deadLetterQueue: detail("deadLetterQueueArn", "")
    // What the last "+ Dead Letter Queue" did, kept on screen because the created queue is not
    // linked to this one and that is the part worth not forgetting.
    property string dlqNote: ""
    // What the last Stop or Start did, and why it may not look like it did anything: the counts on
    // this page do not change when a queue is taken out of service.
    property string statusNote: ""

    onQueueErnChanged: {
        root.dlqNote = ""
        root.statusNote = ""
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
                text: "‹ Back to Queues"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.queueName
                    subtitle: root.queueErn
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    // One button rather than the row menu's pair: here there is one queue and its
                    // state is on the page, so what the button would do is never in question.
                    Button {
                        text: root.stopped ? "Start" : "Stop"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: root.stopped ? "#4cd97b" : "#ffb545"
                        onClicked: {
                            root.statusNote = ""
                            if (root.stopped) eqsClient.startQueue(root.queueErn)
                            else eqsClient.stopQueue(root.queueErn)
                        }
                    }

                    Button {
                        text: "- Purge"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        enabled: root.available > 0
                        onClicked: eqsClient.purgeQueue(root.queueErn)
                    }

                    Button {
                        text: "View Messages"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: root.viewMessages(root.queueErn, root.queueName)
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                // Counted periodically rather than tracked per message, so these are approximate
                // in the sense SQS uses the word - right as of the last count, and self-correcting
                // on the next one.
                StatCard { title: "Available"; value: String(root.available); trend: "messages (approx.)"; trendUp: true; accent: "#4cd97b" }
                StatCard { title: "Delayed"; value: String(root.delayed); trend: "messages (approx.)"; trendUp: root.delayed === 0; accent: "#ffb545" }
                StatCard { title: "Invisible"; value: String(root.invisible); trend: "messages (approx.)"; trendUp: root.invisible === 0; accent: "#4f8cff" }
                StatCard { title: "Size"; value: SizeFormat.format(root.detail("size", 0)); trend: "on disk (approx.)"; trendUp: true; accent: "#c56bff" }
                StatCard {
                    // Not approximate, and not visible in any of the counts beside it: a stopped
                    // queue goes on accepting sends and simply hands nothing out.
                    title: "State"
                    value: root.stopped ? "STOPPED" : "AVAILABLE"
                    trend: root.stopped ? "receives refused" : "consumers can receive"
                    trendUp: !root.stopped
                    accent: root.stopped ? "#ffb545" : "#4cd97b"
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#9aa1ac"
                font.pixelSize: 12
                visible: root.statusNote.length > 0
                text: root.statusNote
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

                        DetailField { width: (identityCol.width - 48) / 3; label: "Owner"; value: root.detail("owner", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.ernPart(2) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.ernPart(3) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Namespace"; value: root.ernPart(4) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    // The name above the ERN it is the tail of: it is what every client API and
                    // every command line asks for, so it is the one worth copying most often.
                    DetailField { width: identityCol.width; label: "Queue name"; value: root.queueName; copyable: true }
                    DetailField { width: identityCol.width; label: "Queue ERN"; value: root.queueErn; copyable: true }
                }
            }

            Rectangle {
                width: parent.width
                height: configCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: configCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: configHeaderRow.implicitHeight

                        Row {
                            id: configHeaderRow
                            Text { text: "Configuration"; color: "white"; font.pixelSize: 15; font.bold: true }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: configHeaderRow.verticalCenter
                            spacing: 8

                            Button {
                                text: "Edit…"
                                flat: true
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                onClicked: settingsDialog.open()
                            }

                            Button {
                                text: "+ Dead Letter Queue"
                                highlighted: true
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                onClicked: dlqDialog.open()
                            }
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField {
                            width: (configCol.width - 48) / 3
                            label: "Delay"
                            // Zero is "none", which reads better than "0 s" for a queue that holds
                            // nothing back.
                            value: root.delay > 0 ? root.delay + " s" : "none"
                        }
                        DetailField { width: (configCol.width - 48) / 3; label: "Visibility Timeout"; value: root.visibility + " s" }
                        DetailField { width: (configCol.width - 48) / 3; label: "Max Receive Count"; value: String(root.detail("maxReceiveCount", 0)) }
                        DetailField {
                            width: (configCol.width - 48) / 3
                            label: "Max Message Length"
                            // A queue carrying no limit of its own is measured against the
                            // installation's default, so that is the figure worth showing - said as
                            // the default rather than as a limit somebody chose.
                            value: root.maxMessageLength > 0
                                   ? SizeFormat.format(root.maxMessageLength)
                                   : SizeFormat.format(root.defaultMaxMessageLength) + " (default)"
                        }
                        DetailField {
                            width: (configCol.width * 2 / 3)
                            label: "Dead Letter Queue"
                            value: root.deadLetterQueue.length > 0 ? root.deadLetterQueue : "None"
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#e0a458"
                        font.pixelSize: 12
                        visible: root.dlqNote.length > 0
                        text: root.dlqNote
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: tagsCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: tagsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: tagsHeaderRow.implicitHeight

                        Row {
                            id: tagsHeaderRow
                            Text { text: "Tags"; color: "white"; font.pixelSize: 15; font.bold: true }
                        }

                        Button {
                            text: "+ Add"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: tagsHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: addTagDialog.open()
                        }
                    }

                    Text {
                        visible: root.tagList().length === 0
                        text: "No tags set for this queue."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Flow {
                        width: parent.width
                        spacing: 8
                        visible: root.tagList().length > 0

                        Repeater {
                            model: root.tagList()
                            delegate: Rectangle {
                                radius: 8
                                color: "#2c3648"
                                height: 26
                                width: chipRow.implicitWidth + 20

                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData + ": " + root.detail("tags", {})[modelData]
                                        color: "#c4c9d1"
                                        font.pixelSize: 11
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "×"
                                        color: removeArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                        font.pixelSize: 13
                                        font.bold: true

                                        MouseArea {
                                            id: removeArea
                                            anchors.fill: parent
                                            anchors.margins: -4
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: eqsClient.deleteQueueTag(root.queueErn, modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // The three settings a queue can be given after it exists. One dialog, because they are one
    // decision about how this queue behaves - and three calls, because that is what the server
    // offers; only what changed is sent.
    Dialog {
        id: settingsDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string errorText: ""
        // How many of the three calls are outstanding: 0 to 3, and the dialog closes on the last.
        property int pending: 0
        readonly property bool saving: settingsDialog.pending > 0

        readonly property var lengthUnits: [
            { label: "bytes", bytes: 1 },
            { label: "KB", bytes: 1024 },
            { label: "MB", bytes: 1024 * 1024 }
        ]

        function number(field, fallback) {
            const value = parseInt(field.text, 10)
            return isNaN(value) ? fallback : value
        }

        function maxLengthBytes() {
            if (defaultLengthSwitch.checked) return 0
            const unit = settingsDialog.lengthUnits[lengthUnitCombo.currentIndex]
            return Math.round(Number(lengthValueField.text) * unit.bytes)
        }

        // The server's own bounds, checked here so a value it would refuse cannot be sent: 0-43200
        // for a visibility timeout and 0-900 for a delay, which are the figures AWS SQS holds both
        // to and which handleSetQueueVisibility/handleSetQueueDelay enforce.
        readonly property bool visibilityValid: settingsDialog.number(visibilityField, -1) >= 0
                                                && settingsDialog.number(visibilityField, -1) <= 43200
        readonly property bool delayValid: settingsDialog.number(delayField, -1) >= 0
                                           && settingsDialog.number(delayField, -1) <= 900
        readonly property bool lengthValid: defaultLengthSwitch.checked || settingsDialog.maxLengthBytes() > 0
        readonly property bool valid: settingsDialog.visibilityValid && settingsDialog.delayValid && settingsDialog.lengthValid

        function settled() {
            if (settingsDialog.pending > 0) settingsDialog.pending--
            if (settingsDialog.pending === 0 && settingsDialog.errorText.length === 0)
                settingsDialog.close()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        // Opened on the values as they are, with the length in the largest unit it divides into
        // evenly - somebody who set one megabyte should be shown one megabyte.
        onOpened: {
            settingsDialog.errorText = ""
            settingsDialog.pending = 0

            visibilityField.text = String(root.visibility)
            delayField.text = String(root.delay)

            defaultLengthSwitch.checked = root.maxMessageLength <= 0

            let unit = 0
            let value = root.maxMessageLength > 0 ? root.maxMessageLength : root.defaultMaxMessageLength
            if (value % (1024 * 1024) === 0) {
                unit = 2
                value = value / (1024 * 1024)
            } else if (value % 1024 === 0) {
                unit = 1
                value = value / 1024
            }
            lengthUnitCombo.currentIndex = unit
            lengthValueField.text = String(value)
            visibilityField.forceActiveFocus()
        }

        contentItem: Column {
            width: settingsDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Queue Settings"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "All three apply from here on. Messages already in the queue keep what they were given "
                          + "when they arrived - a lease in flight, a delay already counted, a size already accepted."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Visibility timeout (seconds)"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: visibilityField
                    width: parent.width
                    validator: IntValidator { bottom: 0; top: 43200 }
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
                Text {
                    text: settingsDialog.visibilityValid
                          ? "How long a received message stays invisible to other consumers. 0 to 43200 seconds."
                          : "Has to be between 0 and 43200 seconds."
                    color: settingsDialog.visibilityValid ? "#6b7280" : "#ffb545"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Delay (seconds)"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: delayField
                    width: parent.width
                    validator: IntValidator { bottom: 0; top: 900 }
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
                Text {
                    text: settingsDialog.delayValid
                          ? "How long a sent message is held back before it can be received. 0 for none, up to 900 seconds."
                          : "Has to be between 0 and 900 seconds."
                    color: settingsDialog.delayValid ? "#6b7280" : "#ffb545"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                id: lengthColumn
                width: parent.width
                spacing: 6
                Text { text: "Max message length"; color: "#9aa1ac"; font.pixelSize: 12 }

                CheckBox {
                    id: defaultLengthSwitch
                    text: "Follow the installation default"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }

                Text {
                    visible: defaultLengthSwitch.checked
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: "The queue carries no limit of its own, and a send is measured against "
                          + SizeFormat.format(root.defaultMaxMessageLength) + " - which is also what a queue "
                          + "created before the limit meant anything is measured against."
                }

                Row {
                    width: parent.width
                    spacing: 8
                    visible: !defaultLengthSwitch.checked

                    TextField {
                        id: lengthValueField
                        width: lengthColumn.width - 132
                        validator: DoubleValidator { bottom: 0; decimals: 3; notation: DoubleValidator.StandardNotation }
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                    }
                    ComboBox {
                        id: lengthUnitCombo
                        width: 124
                        model: settingsDialog.lengthUnits.map(u => u.label)
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }

                Text {
                    visible: !defaultLengthSwitch.checked
                    text: settingsDialog.lengthValid
                          ? "A send larger than " + SizeFormat.format(settingsDialog.maxLengthBytes()) + " is refused."
                          : "Has to be more than nothing. Switch the default back on to carry no limit of your own."
                    color: settingsDialog.lengthValid ? "#6b7280" : "#ffb545"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Text {
                text: settingsDialog.errorText
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
                    onClicked: settingsDialog.close()
                }

                BusyIndicator {
                    running: settingsDialog.saving
                    visible: settingsDialog.saving
                    width: 22
                    height: 22
                    anchors.right: saveSettingsButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: saveSettingsButton
                    text: "Save"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !settingsDialog.saving && settingsDialog.valid
                    onClicked: {
                        settingsDialog.errorText = ""

                        // Only what moved: each is an action of its own server-side, and sending one
                        // that changes nothing would stamp a modification date for a change nobody
                        // made.
                        const wantedVisibility = settingsDialog.number(visibilityField, root.visibility)
                        const wantedDelay = settingsDialog.number(delayField, root.delay)
                        const wantedLength = settingsDialog.maxLengthBytes()

                        const visibilityChanged = wantedVisibility !== root.visibility
                        const delayChanged = wantedDelay !== root.delay
                        const lengthChanged = wantedLength !== root.maxMessageLength

                        if (!visibilityChanged && !delayChanged && !lengthChanged) {
                            settingsDialog.close()
                            return
                        }

                        settingsDialog.pending = (visibilityChanged ? 1 : 0) + (delayChanged ? 1 : 0)
                                                 + (lengthChanged ? 1 : 0)
                        if (visibilityChanged) eqsClient.setQueueVisibility(root.queueErn, wantedVisibility)
                        if (delayChanged) eqsClient.setQueueDelay(root.queueErn, wantedDelay)
                        if (lengthChanged) eqsClient.setQueueMaxMessageLength(root.queueErn, wantedLength)
                    }
                }
            }
        }
    }

    Dialog {
        id: dlqDialog
        modal: true
        anchors.centerIn: parent
        width: 440
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""

        // A dead letter queue is an ordinary queue, so it is created with this queue's settings
        // unless they are changed here - the messages it will hold are this queue's messages.
        readonly property int parentVisibility: Number(root.detail("visibility", 30))
        readonly property int parentMaxReceiveCount: Number(root.detail("maxReceiveCount", 3))
        readonly property int parentMaxMessageLength: Number(root.detail("maxMessageLength", 1048576))

        function number(field, fallback) {
            const value = parseInt(field.text.trim(), 10)
            return isNaN(value) || value < 0 ? fallback : value
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            dlqDialog.errorText = ""
            dlqDialog.saving = false
            dlqNameField.text = root.queueName + "-dlq"
            dlqVisibilityField.text = String(dlqDialog.parentVisibility)
            dlqMaxReceiveField.text = String(dlqDialog.parentMaxReceiveCount)
            dlqMaxLengthField.text = String(dlqDialog.parentMaxMessageLength)
            dlqNameField.forceActiveFocus()
            dlqNameField.selectAll()
        }

        contentItem: Column {
            width: dlqDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Create Dead Letter Queue"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "for " + root.queueName
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            // Said before the queue is created rather than after: EQS takes a dead letter queue
            // only in "create-queue", where naming one creates it and points the new queue at it in
            // the same call. There is no action that attaches one to a queue that already exists, so
            // this creates the queue and nothing more.
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#e0a458"
                font.pixelSize: 12
                text: "⚠  This creates the queue only. " + root.queueName + " will not redrive into it: EQS attaches a "
                      + "dead letter queue when a queue is created, and has no action to attach one afterwards."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#9aa1ac"
                font.pixelSize: 12
                visible: root.deadLetterQueue.length > 0
                text: "This queue already redrives into " + root.deadLetterQueue + "."
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Queue name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: dlqNameField
                    width: parent.width
                    placeholderText: "e.g. orders-dlq"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (createDlqButton.enabled) createDlqButton.clicked()
                }
            }

            Grid {
                width: parent.width
                columns: 3
                columnSpacing: 12
                rowSpacing: 6

                Text { text: "Visibility (s)"; color: "#9aa1ac"; font.pixelSize: 12; width: (dlqDialog.availableWidth - 24) / 3 }
                Text { text: "Max receive count"; color: "#9aa1ac"; font.pixelSize: 12; width: (dlqDialog.availableWidth - 24) / 3 }
                Text { text: "Max length (bytes)"; color: "#9aa1ac"; font.pixelSize: 12; width: (dlqDialog.availableWidth - 24) / 3 }

                TextField {
                    id: dlqVisibilityField
                    width: (dlqDialog.availableWidth - 24) / 3
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    validator: IntValidator { bottom: 0 }
                }
                TextField {
                    id: dlqMaxReceiveField
                    width: (dlqDialog.availableWidth - 24) / 3
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    validator: IntValidator { bottom: 0 }
                }
                TextField {
                    id: dlqMaxLengthField
                    width: (dlqDialog.availableWidth - 24) / 3
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    validator: IntValidator { bottom: 0 }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "Taken from " + root.queueName + ", since a dead letter queue holds that queue's messages."
            }

            Text {
                text: dlqDialog.errorText
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
                    onClicked: dlqDialog.close()
                }

                BusyIndicator {
                    running: dlqDialog.saving
                    visible: dlqDialog.saving
                    width: 22
                    height: 22
                    anchors.right: createDlqButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: createDlqButton
                    text: "Create"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !dlqDialog.saving && dlqNameField.text.trim().length > 0
                             && dlqNameField.text.trim() !== root.queueName
                    onClicked: {
                        dlqDialog.errorText = ""
                        dlqDialog.saving = true
                        // No dlqName of its own: this queue is being created *as* a dead letter
                        // queue, not with one.
                        eqsClient.createQueue(dlqNameField.text.trim(), "",
                                              dlqDialog.number(dlqVisibilityField, dlqDialog.parentVisibility),
                                              dlqDialog.number(dlqMaxReceiveField, dlqDialog.parentMaxReceiveCount),
                                              dlqDialog.number(dlqMaxLengthField, dlqDialog.parentMaxMessageLength))
                    }
                }
            }
        }
    }

    Dialog {
        id: addTagDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool saving: false
        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            tagKeyField.text = ""
            tagValueField.text = ""
            addTagDialog.errorText = ""
            addTagDialog.saving = false
            tagKeyField.forceActiveFocus()
        }

        contentItem: Column {
            width: addTagDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Tag"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Set a key/value tag on this queue."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Key"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: tagKeyField
                    width: parent.width
                    placeholderText: "e.g. environment"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: tagValueField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Value"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: tagValueField
                    width: parent.width
                    placeholderText: "e.g. production"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (saveTagButton.enabled) saveTagButton.clicked()
                }
                Text {
                    text: addTagDialog.errorText
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
                    onClicked: addTagDialog.close()
                }

                BusyIndicator {
                    running: addTagDialog.saving
                    visible: addTagDialog.saving
                    width: 22
                    height: 22
                    anchors.right: saveTagButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: saveTagButton
                    text: "Add"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !addTagDialog.saving && tagKeyField.text.trim().length > 0
                    onClicked: {
                        addTagDialog.errorText = ""
                        addTagDialog.saving = true
                        eqsClient.addQueueTag(root.queueErn, tagKeyField.text.trim(), tagValueField.text)
                    }
                }
            }
        }
    }
}
