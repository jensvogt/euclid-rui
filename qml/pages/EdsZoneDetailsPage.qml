import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// One EDS zone: what it is, the record sets stored in it, and what the DNS port answers for a name.
// Records are sets - every value of one type at one name - and writing one replaces the whole set,
// which is why "Edit" and "Add" are the same dialog and the same call.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string zoneName: ""
    // The listing's row, until get-zone answers with a fresh one.
    property var details: ({})

    function detail(key, fallback) {
        const v = root.details ? root.details[key] : undefined
        return v === undefined || v === null ? fallback : v
    }

    // The record types EDS stores, with the value format each takes - zone-file presentation
    // format, without the quoting.
    readonly property var recordTypes: ["A", "AAAA", "CNAME", "MX", "NS", "PTR", "SRV", "TXT"]
    readonly property var valueHints: ({
        "A": "192.0.2.1",
        "AAAA": "2001:db8::1",
        "CNAME": "target.example.com",
        "NS": "ns1.example.com",
        "PTR": "host.example.com",
        "MX": "10 mail.example.com  (preference, host)",
        "SRV": "10 5 8080 host.example.com  (priority, weight, port, target)",
        "TXT": "any text, up to 4000 bytes"
    })

    property var records: []
    property int recordTotal: 0
    property int recordPageIndex: 0
    property int recordPageSize: 25
    property string recordNameFilter: ""
    property string recordTypeFilter: ""
    property bool recordsLoading: false
    property string recordsError: ""
    property string recordNote: ""
    property string lastUpdatedText: "—"

    property var answer: null
    property bool answerLoading: false
    property string answerError: ""

    signal back()

    // A stored name as it reads inside the zone: "@" for the apex, the part in front of the zone
    // otherwise. The table shows both, since the full name is what a client asks for.
    function relativeName(name) {
        if (name === root.zoneName) return "@"
        const suffix = "." + root.zoneName
        return name.endsWith(suffix) ? name.substring(0, name.length - suffix.length) : name
    }

    readonly property var recordColumns: [
        {
            title: "Name",
            key: "name",
            sortable: false,
            tooltip: "The owner name within the zone - \"@\" is the zone itself.",
            formatter: function (v) { return root.relativeName(v) }
        },
        { title: "Type", key: "type", sortable: false },
        {
            title: "Values",
            key: "valuesText",
            fill: true,
            sortable: false,
            tooltip: "Every value of this type at this name. They are served together and replaced together."
        },
        {
            title: "TTL",
            key: "ttl",
            sortable: false,
            tooltip: "Seconds a resolver may cache the answer. 0 or empty takes the zone's default.",
            formatter: function (v) { return v > 0 ? v + " s" : "zone default" }
        },
        {
            title: "Fully qualified",
            key: "name",
            sortable: false,
            tooltip: "The name a client asks for."
        },
        {
            title: "Modified",
            key: "modified",
            sortable: false,
            formatter: function (v) { return DateFormat.format(v) }
        }
    ]

    function refresh() {
        if (!root.loggedIn || root.zoneName.length === 0) return
        edsClient.fetchZone(root.zoneName)
        loadRecords()
    }

    function loadRecords() {
        if (!root.loggedIn || root.zoneName.length === 0) return
        root.recordsLoading = true
        root.recordsError = ""
        edsClient.fetchRecords(root.zoneName, root.recordNameFilter, root.recordTypeFilter,
                               root.recordPageIndex, root.recordPageSize)
    }

    function lookup() {
        const name = lookupNameField.text.trim()
        if (name.length === 0) return
        root.answerLoading = true
        root.answerError = ""
        edsClient.fetchAnswer(name, lookupTypeCombo.currentText)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()
    onZoneNameChanged: {
        root.records = []
        root.recordTotal = 0
        root.recordPageIndex = 0
        root.recordNameFilter = ""
        root.recordTypeFilter = ""
        typeFilterCombo.currentIndex = 0
        root.recordNote = ""
        root.answer = null
        root.answerError = ""
        lookupNameField.text = root.zoneName
        if (visible) refresh()
    }

    Connections {
        target: edsClient
        function onZoneLoaded(zone) {
            if (zone.name !== root.zoneName) return
            root.details = zone
        }
        function onZoneFailed(name, message) {
            if (name !== root.zoneName) return
            root.recordsError = message
        }
        function onRecordsLoaded(zone, list, total) {
            if (zone !== root.zoneName) return
            root.recordsLoading = false
            root.recordsError = ""
            root.records = list
            root.recordTotal = total
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onRecordsFailed(zone, message) {
            if (zone !== root.zoneName) return
            root.recordsLoading = false
            root.recordsError = message
        }
        function onRecordPut(zone, record) {
            if (zone !== root.zoneName) return
            recordDialog.saving = false
            recordDialog.close()
            root.recordNote = record.type + " " + root.relativeName(record.name) + " saved with "
                    + record.values.length + " value(s)."
            root.refresh()
        }
        function onRecordPutFailed(message) {
            recordDialog.saving = false
            recordDialog.errorText = message
        }
        function onRecordDeleted(zone, name, type) {
            if (zone !== root.zoneName) return
            deleteRecordDialog.deleting = false
            deleteRecordDialog.close()
            root.recordNote = type + " " + root.relativeName(name) + " deleted."
            root.refresh()
        }
        function onRecordDeleteFailed(message) {
            deleteRecordDialog.deleting = false
            deleteRecordDialog.errorText = message
        }
        function onAnswerLoaded(answer) {
            root.answerLoading = false
            root.answer = answer
        }
        function onAnswerFailed(message) {
            root.answerLoading = false
            root.answer = null
            root.answerError = message
        }
    }

    // Add and edit are one dialog: put-record replaces the set, so editing is writing it again.
    Dialog {
        id: recordDialog
        modal: true
        anchors.centerIn: parent
        width: 500
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property bool editing: false
        property bool saving: false
        property string errorText: ""

        function openForNew() {
            recordDialog.editing = false
            recordNameField.text = ""
            recordTypeCombo.currentIndex = 0
            recordTtlField.text = ""
            recordValuesArea.text = ""
            recordDialog.errorText = ""
            recordDialog.saving = false
            recordDialog.open()
            recordNameField.forceActiveFocus()
        }
        function openForEdit(row) {
            recordDialog.editing = true
            recordNameField.text = root.relativeName(row.name)
            recordTypeCombo.currentIndex = Math.max(0, root.recordTypes.indexOf(row.type))
            recordTtlField.text = row.ttl > 0 ? String(row.ttl) : ""
            recordValuesArea.text = row.values.join("\n")
            recordDialog.errorText = ""
            recordDialog.saving = false
            recordDialog.open()
            recordValuesArea.forceActiveFocus()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: recordDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: recordDialog.editing ? "Edit Record Set" : "Add Record Set"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    text: "In " + root.zoneName + ". Saving replaces every value of this type at this name - "
                          + "a CNAME must be the only record at its name, and the zone itself cannot be one."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Row {
                width: parent.width
                spacing: 12

                Column {
                    width: parent.width - 12 - typeColumn.width
                    spacing: 6
                    Text { text: "Name"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: recordNameField
                        width: parent.width
                        placeholderText: "api, @ for the zone, *.dev for a wildcard"
                        // The set is named by name and type; changing either while editing would
                        // write a different set and leave the old one in place.
                        enabled: !recordDialog.editing
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                    }
                }

                Column {
                    id: typeColumn
                    width: 120
                    spacing: 6
                    Text { text: "Type"; color: "#9aa1ac"; font.pixelSize: 12 }
                    ComboBox {
                        id: recordTypeCombo
                        width: parent.width
                        model: root.recordTypes
                        enabled: !recordDialog.editing
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Values - one per line"; color: "#9aa1ac"; font.pixelSize: 12 }
                Rectangle {
                    width: parent.width
                    height: 110
                    radius: 8
                    color: "#181b21"
                    border.color: recordValuesArea.activeFocus ? "#4f8cff" : "#3a4152"
                    border.width: 1

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 8
                        TextArea {
                            id: recordValuesArea
                            wrapMode: TextEdit.WrapAnywhere
                            font.family: "monospace"
                            font.pixelSize: 13
                            color: "#e6e8ec"
                            selectByMouse: true
                            placeholderText: root.valueHints[recordTypeCombo.currentText] || ""
                            background: null
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "TTL (seconds)"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: recordTtlField
                    width: 160
                    placeholderText: "zone default"
                    inputMethodHints: Qt.ImhDigitsOnly
                    validator: IntValidator { bottom: 1; top: 2147483647 }
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                }
                Text {
                    text: recordDialog.errorText
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
                    onClicked: recordDialog.close()
                }

                BusyIndicator {
                    running: recordDialog.saving
                    visible: recordDialog.saving
                    width: 22
                    height: 22
                    anchors.right: saveRecordButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: saveRecordButton
                    text: "Save"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    readonly property var values: recordValuesArea.text.split("\n").map(v => v.trim()).filter(v => v.length > 0)
                    enabled: !recordDialog.saving && values.length > 0
                             && (recordTtlField.text.length === 0 || recordTtlField.acceptableInput)
                    onClicked: {
                        recordDialog.errorText = ""
                        recordDialog.saving = true
                        const name = recordNameField.text.trim()
                        edsClient.putRecord(root.zoneName, name.length > 0 ? name : "@", recordTypeCombo.currentText,
                                            saveRecordButton.values, recordTtlField.text.length > 0 ? parseInt(recordTtlField.text, 10) : 0)
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteRecordDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property var record: null
        property bool deleting: false
        property string errorText: ""

        function openFor(record) {
            deleteRecordDialog.record = record
            deleteRecordDialog.errorText = ""
            deleteRecordDialog.deleting = false
            deleteRecordDialog.open()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: deleteRecordDialog.availableWidth
            spacing: 16

            Text { text: "Delete Record Set"; color: "white"; font.pixelSize: 18; font.bold: true }
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#c4c9d1"
                font.pixelSize: 13
                text: deleteRecordDialog.record
                      ? "Delete the " + deleteRecordDialog.record.type + " record set at "
                        + deleteRecordDialog.record.name + " (" + deleteRecordDialog.record.values.length
                        + " value(s))? Resolvers may go on answering from their cache for up to its TTL."
                      : ""
            }
            Text {
                text: deleteRecordDialog.errorText
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
                    onClicked: deleteRecordDialog.close()
                }

                BusyIndicator {
                    running: deleteRecordDialog.deleting
                    visible: deleteRecordDialog.deleting
                    width: 22
                    height: 22
                    anchors.right: deleteRecordButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: deleteRecordButton
                    text: "Delete"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#ff6b6b"
                    enabled: !deleteRecordDialog.deleting && deleteRecordDialog.record !== null
                    onClicked: {
                        deleteRecordDialog.errorText = ""
                        deleteRecordDialog.deleting = true
                        edsClient.deleteRecord(root.zoneName, deleteRecordDialog.record.name,
                                               deleteRecordDialog.record.type)
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
                leaf: root.zoneName
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.zoneName
                    subtitle: root.detail("description", "").length > 0 ? root.detail("description", "")
                                                                         : "Hosted zone - answered authoritatively by EDS."
                }

                Button {
                    text: "+ Add Record"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: root.loggedIn
                    onClicked: {
                        root.recordNote = ""
                        recordDialog.openForNew()
                    }
                }
            }

            Grid {
                id: statGrid
                width: parent.width
                spacing: 18
                columns: Math.max(1, Math.min(4, Math.floor((width + spacing) / (200 + spacing))))
                readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

                StatCard {
                    width: statGrid.cellWidth
                    title: "Record Sets"
                    value: String(root.detail("recordCount", 0))
                    trend: "plus SOA and NS"
                    accent: "#4f8cff"
                }
                StatCard {
                    width: statGrid.cellWidth
                    title: "Default TTL"
                    value: root.detail("ttl", 0) + " s"
                    trend: "for records without their own"
                    accent: "#4cd97b"
                }
                StatCard {
                    width: statGrid.cellWidth
                    title: "SOA Serial"
                    value: String(root.detail("serial", "—"))
                    trend: "moves with every change"
                    accent: "#c56bff"
                }
                StatCard {
                    width: statGrid.cellWidth
                    title: "Last Change"
                    value: DateFormat.format(root.detail("modified", ""))
                    trend: "created " + DateFormat.format(root.detail("created", ""))
                    accent: "#ffb545"
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

                    Text { text: "Zone"; color: "white"; font.pixelSize: 15; font.bold: true }
                    DetailField { width: identityCol.width; label: "Zone name"; value: root.zoneName; copyable: true }
                    DetailField { width: identityCol.width; label: "Zone ERN"; value: root.detail("ern", "—"); copyable: true }
                    DetailField { width: identityCol.width; label: "Namespace"; value: root.detail("namespace", "—") }
                }
            }

            // Records
            Item {
                width: parent.width
                height: recordsHeader.implicitHeight

                Text {
                    id: recordsHeader
                    text: "Record Sets (" + root.recordTotal + ")"
                    color: "white"
                    font.pixelSize: 16
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        text: "Type"
                        color: "#9aa1ac"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    ComboBox {
                        id: typeFilterCombo
                        width: 130
                        model: ["All types"].concat(root.recordTypes)
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onActivated: (index) => {
                            root.recordTypeFilter = index === 0 ? "" : root.recordTypes[index - 1]
                            root.recordPageIndex = 0
                            root.loadRecords()
                        }
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#e0a458"
                font.pixelSize: 12
                visible: root.recordNote.length > 0
                text: root.recordNote
            }

            DataTable {
                width: parent.width
                columns: root.recordColumns
                rows: root.records
                totalCount: root.recordTotal
                pageSize: root.recordPageSize
                pageIndex: root.recordPageIndex
                loading: root.recordsLoading
                error: root.recordsError
                lastUpdatedText: root.lastUpdatedText
                // list-records narrows to one owner name, not a prefix of one.
                searchPlaceholder: "Show one name - api, @ for the zone, *.dev..."
                matchTypeSelectable: false
                emptyText: root.recordNameFilter.length > 0 || root.recordTypeFilter.length > 0
                           ? "No record set matches." : "No records yet - add one above."
                rowsClickable: true
                onRowClicked: (row) => {
                    root.recordNote = ""
                    recordDialog.openForEdit(row)
                }

                onSearchChanged: (text) => {
                    root.recordNameFilter = text.trim()
                    root.recordPageIndex = 0
                    root.loadRecords()
                }
                onRefreshRequested: root.refresh()
                onPageChanged: (index) => {
                    root.recordPageIndex = index
                    root.loadRecords()
                }
                onPageSizeRequested: (size) => {
                    root.recordPageSize = size
                    root.recordPageIndex = 0
                    root.loadRecords()
                }

                contextMenuActions: [
                    {
                        text: "Edit",
                        action: function (row) {
                            root.recordNote = ""
                            recordDialog.openForEdit(row)
                        }
                    },
                    {
                        text: "Look up",
                        action: function (row) {
                            lookupNameField.text = row.name
                            lookupTypeCombo.currentIndex = Math.max(0, lookupTypeCombo.model.indexOf(row.type))
                            root.lookup()
                        }
                    },
                    {
                        text: "Delete",
                        action: function (row) {
                            root.recordNote = ""
                            deleteRecordDialog.openFor(row)
                        }
                    }
                ]
            }

            // What the DNS port would answer - the zone's records as a resolver sees them, CNAME
            // chains, wildcards, NXDOMAIN and all - without a DNS client.
            Rectangle {
                width: parent.width
                height: lookupCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: lookupCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Lookup"; color: "white"; font.pixelSize: 15; font.bold: true }
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#9aa1ac"
                        font.pixelSize: 12
                        text: "What EDS answers for a name, as a resolver asking its DNS port would get it. Any name "
                              + "works, not only this zone's - one in none of EDS's zones shows as not authoritative."
                    }

                    Row {
                        width: parent.width
                        spacing: 12

                        TextField {
                            id: lookupNameField
                            width: parent.width - 12 - lookupTypeCombo.width - 12 - lookupButton.width
                            placeholderText: "www." + root.zoneName
                            Material.accent: "#4f8cff"
                            selectByMouse: true
                            Keys.onReturnPressed: root.lookup()
                        }
                        ComboBox {
                            id: lookupTypeCombo
                            width: 120
                            model: ["A", "AAAA", "CNAME", "MX", "NS", "PTR", "SRV", "TXT", "SOA", "ANY"]
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                        }
                        Button {
                            id: lookupButton
                            text: "Look up"
                            highlighted: true
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            enabled: !root.answerLoading && lookupNameField.text.trim().length > 0 && root.loggedIn
                            onClicked: root.lookup()
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.answerError.length > 0
                        text: root.answerError
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }

                    Column {
                        width: parent.width
                        spacing: 8
                        visible: root.answer !== null

                        Row {
                            spacing: 14
                            Text {
                                text: root.answer ? root.answer.rcode : ""
                                font.pixelSize: 14
                                font.bold: true
                                font.family: "monospace"
                                color: !root.answer ? "#9aa1ac"
                                       : root.answer.rcode === "NOERROR" ? "#4cd97b"
                                       : root.answer.rcode === "NXDOMAIN" ? "#ffb545" : "#ff6b6b"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                color: "#9aa1ac"
                                font.pixelSize: 12
                                text: !root.answer ? ""
                                      : root.answer.authoritative
                                        ? "authoritative, from zone " + root.answer.zone
                                        : "not in any EDS zone - the DNS port would forward it to an upstream, or refuse it"
                            }
                        }

                        Text {
                            visible: !!root.answer && root.answer.authoritative && (root.answer.answers || []).length === 0
                            text: root.answer && root.answer.rcode === "NOERROR"
                                  ? "The name exists, but has no " + root.answer.type + " records (NODATA)."
                                  : "No such name."
                            color: "#9aa1ac"
                            font.pixelSize: 12
                        }

                        Repeater {
                            model: root.answer ? (root.answer.answers || []).concat((root.answer.authority || []).map(
                                                     r => Object.assign({ authority: true }, r))) : []
                            Row {
                                required property var modelData
                                spacing: 14
                                Text {
                                    text: modelData.authority ? "authority" : "answer"
                                    width: 70
                                    color: "#6b7280"
                                    font.pixelSize: 11
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                TextEdit {
                                    readOnly: true
                                    selectByMouse: true
                                    font.family: "monospace"
                                    font.pixelSize: 12
                                    color: modelData.authority ? "#9aa1ac" : "#e6e8ec"
                                    text: modelData.name + "  " + modelData.ttl + "  " + modelData.type + "  " + modelData.value
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
