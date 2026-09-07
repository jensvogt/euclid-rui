import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// One application definition. The two states are shown side by side on purpose: start and stop
// only write `desiredState`, and euclid-mgr's reconciler is what eventually makes `state` match -
// an application stuck disagreeing is the module saying it could not start the process.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string applicationId: ""
    property var details: ({})

    property string error: ""
    property bool deleting: false
    property bool savingEnvironment: false

    // The processes actually running this application, from EMM rather than EAP: the manager runs
    // an application as a module pool named after its applicationId, and only that pool knows
    // which processes exist, what pids they have and which port each was given. EAP's own
    // "instances" is a count and nothing more.
    property var instances: []
    // Kept apart from root.error: a definition that reads fine while its pool cannot be listed is
    // still worth showing, and putting this in the page's error line would make the whole page
    // look broken.
    property string instancesError: ""

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    // Not "state": QQuickItem already has one (the Item state machine), and shadowing it silently
    // changes what every state-related binding on this page means.
    readonly property int minInstances: Number(detail("minInstances", 1))
    readonly property int maxInstances: Number(detail("maxInstances", 1))

    readonly property string applicationState: detail("state", "")
    readonly property string desiredState: detail("desiredState", "")

    // An application left unnamed at creation gets a principal of its own, called after it.
    readonly property bool ownPrincipal: root.detail("userId", "") === "app-" + root.applicationId

    function resourceList() {
        return root.detail("resources", [])
    }

    function applicationStateColor(value) {
        if (value === "RUNNING") return "#4cd97b"
        if (value === "STOPPED") return "#ffb545"
        return "#9aa1ac"
    }

    function instanceStateColor(value) {
        if (value === "RUNNING") return "#4cd97b"
        if (value === "STARTING") return "#ffb545"
        if (value === "STOPPED") return "#9aa1ac"
        return "#ff6b6b"
    }

    // How long the process has been up, as a person would say it. The exact start time is in the
    // column beside it; what an operator reads off a pool is whether an instance is minutes or
    // days old - a young one among old ones is one that has been restarting.
    function uptimeText(created) {
        if (!created) return "—"
        const started = new Date(created)
        if (isNaN(started.getTime())) return "—"
        const seconds = Math.floor((Date.now() - started.getTime()) / 1000)
        if (seconds < 0) return "—"
        if (seconds < 60) return seconds + "s"
        if (seconds < 3600) return Math.floor(seconds / 60) + "m"
        if (seconds < 86400) return Math.floor(seconds / 3600) + "h " + Math.floor((seconds % 3600) / 60) + "m"
        return Math.floor(seconds / 86400) + "d " + Math.floor((seconds % 86400) / 3600) + "h"
    }

    readonly property int runningInstances: root.instances.filter(i => i.state === "RUNNING").length
    // A slot the manager is holding rather than a process that is running - stopped, restarting,
    // or one it could not start. Worth counting separately: the pool looks full either way.
    readonly property int heldSlots: root.instances.length - root.runningInstances

    // Filtered, sorted and paged here rather than by the server: "list-modules" hands over every
    // module with every instance in one answer and has no paging to ask for, so the table is given
    // one page's worth out of what is already in hand.
    property string instanceFilter: ""
    property int instancePageIndex: 0
    property int instancePageSize: 10
    property string instanceSortColumn: "created"
    property bool instanceSortAscending: true

    readonly property var filteredInstances: {
        const needle = root.instanceFilter.toLowerCase()
        const matched = needle.length === 0 ? root.instances.slice() : root.instances.filter(i =>
            String(i.instanceId).toLowerCase().indexOf(needle) >= 0
            || String(i.pid).indexOf(needle) >= 0
            || String(i.httpPort).indexOf(needle) >= 0
            || String(i.state).toLowerCase().indexOf(needle) >= 0)

        const key = root.instanceSortColumn
        const direction = root.instanceSortAscending ? 1 : -1
        return matched.sort((a, b) => {
            const left = a[key]
            const right = b[key]
            // pid, port and restart count are numbers and have to compare as such - as text, port
            // 9100 sorts before 921. Everything else here is a string or a timestamp, and both of
            // those order correctly compared as text.
            if (typeof left === "number" && typeof right === "number") return (left - right) * direction
            return String(left).localeCompare(String(right)) * direction
        })
    }

    // Clamped rather than left where it was: a pool that shrank while the last page was on screen
    // would otherwise leave the table showing nothing with no way to tell why.
    readonly property int instancePageCount: Math.max(1, Math.ceil(root.filteredInstances.length / root.instancePageSize))
    readonly property int clampedInstancePage: Math.min(root.instancePageIndex, root.instancePageCount - 1)
    readonly property var instancePage: root.filteredInstances.slice(
        root.clampedInstancePage * root.instancePageSize,
        root.clampedInstancePage * root.instancePageSize + root.instancePageSize)

    // The clamp above keeps the wrong page from being shown; this keeps the stored index from
    // staying out of range behind it. Without it a pool that shrank to one page and then grew
    // again would jump back to page two on its own, because the index was never actually moved.
    onFilteredInstancesChanged: {
        if (root.instancePageIndex > root.instancePageCount - 1)
            root.instancePageIndex = root.instancePageCount - 1
    }

    readonly property var instanceColumns: [
        { title: "Instance", key: "instanceId", fill: true },
        {
            title: "PID",
            key: "pid",
            // -1 is the manager's "no process", not a pid.
            formatter: function (v) { return Number(v) > 0 ? String(v) : "—" }
        },
        {
            title: "Port",
            key: "httpPort",
            // 0 means none was handed out. An instance without one is not reachable through the
            // gateway, whatever its state says, so it is marked rather than left blank.
            formatter: function (v) { return Number(v) > 0 ? String(v) : "—" },
            colorFor: function (v) { return Number(v) > 0 ? "#4f8cff" : "#6b7280" }
        },
        {
            title: "State",
            key: "state",
            colorFor: function (v) { return root.instanceStateColor(v) }
        },
        {
            title: "Restarts",
            key: "restartCount",
            // A pool that keeps its count only by restarting is one that looks healthy from the
            // outside, so the number is coloured.
            colorFor: function (v) { return Number(v) > 0 ? "#ffb545" : "#c4c9d1" }
        },
        {
            // Same underlying value as "Started", read the other way round: this is the one an
            // operator scans, and a young instance among old ones is one that has been restarting.
            // Not sortable - it would order identically to "Started", which is.
            title: "Up",
            key: "created",
            sortable: false,
            formatter: function (v) { return root.uptimeText(v) }
        },
        { title: "Started", key: "created", formatter: function (v) { return DateFormat.format(v) } }
    ]

    // "update-application" replaces each field it is given, so adding or removing one variable
    // means sending the resulting map - EAP has no per-variable call.
    function setEnvironment(environment) {
        root.error = ""
        root.savingEnvironment = true
        eapClient.updateApplication(root.applicationId, { environment: environment })
    }

    function addEnvironmentVariable(name, value) {
        const environment = Object.assign({}, root.detail("environment", ({})))
        environment[name] = value
        root.setEnvironment(environment)
    }

    function removeEnvironmentVariable(name) {
        const environment = Object.assign({}, root.detail("environment", ({})))
        delete environment[name]
        root.setEnvironment(environment)
    }

    function environmentNames() {
        const environment = root.detail("environment", ({}))
        return environment ? Object.keys(environment).sort() : []
    }

    function refresh() {
        if (!root.loggedIn || root.applicationId.length === 0)
            return
        root.error = ""
        // The list carries the same fields "get-application" would, and is what keeps every other
        // view in sync, so there is no separate per-application read here.
        eapClient.fetchApplications("")
        // The pool behind it. "list-modules" has no per-module read, so this asks for all of them
        // and picks its own out below - the same call the modules page makes.
        emmClient.fetchModules()
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Worth polling here specifically: after a start or stop this page is where the user is
        // watching for `state` and `instances` to catch up with `desiredState`.
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: eapClient

        function onApplicationsLoaded(list, total) {
            for (const application of list) {
                if (application.applicationId !== root.applicationId) continue
                root.details = application
                root.error = ""
                return
            }
            // Gone from the list: deleted, by this page or from somewhere else. Its pool goes with
            // it rather than being left on screen describing processes of an application that no
            // longer exists.
            root.instances = []
            if (root.deleting) {
                root.deleting = false
                root.back()
            }
        }
        function onApplicationsFailed(message) {
            root.error = message
        }
        function onApplicationStateFailed(message) {
            root.deleting = false
            root.savingEnvironment = false
            if (environmentDialog.opened) environmentDialog.errorText = message
            else root.error = message
        }
        function onApplicationStateChanged(applicationId, desiredState) {
            if (applicationId !== root.applicationId) return
            root.savingEnvironment = false
            environmentDialog.close()
            // Stored already; re-reading is what puts the new map on screen.
            root.refresh()
        }
    }

    Connections {
        target: emmClient

        function onModulesLoaded(list, total) {
            root.instancesError = ""
            for (const module of list) {
                // The pool is named after the application, which is how EAP and the manager refer
                // to the same thing - see the EAG route comment on applicationId.
                if (module.name !== root.applicationId) continue
                root.instances = module.instances || []
                return
            }
            // No pool at all, which is not an error: an application that has never been started,
            // or one stopped long enough for the manager to have let its slots go, simply has none.
            root.instances = []
        }
        function onModulesFailed(message) {
            root.instancesError = message
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
                text: "‹ Back to Applications"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.applicationId
                    subtitle: root.detail("ern", "")
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: "Scale…"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: scaleDialog.open()
                    }

                    Button {
                        text: "Start"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4cd97b"
                        enabled: root.desiredState !== "RUNNING"
                        onClicked: {
                            root.error = ""
                            eapClient.startApplication(root.applicationId)
                        }
                    }

                    Button {
                        text: "Stop"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ffb545"
                        enabled: root.desiredState === "RUNNING"
                        onClicked: {
                            root.error = ""
                            eapClient.stopApplication(root.applicationId)
                        }
                    }

                    Button {
                        text: "Delete"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        enabled: !root.deleting
                        onClicked: deleteDialog.open()
                    }
                }
            }

            Text {
                visible: root.error.length > 0
                width: parent.width
                text: root.error
                color: "#ff6b6b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "State"
                    value: root.applicationState.length > 0 ? root.applicationState : "—"
                    trend: root.applicationState === root.desiredState ? "as requested" : "reconciling to " + root.desiredState
                    trendUp: root.applicationState === "RUNNING"
                    accent: root.applicationStateColor(root.applicationState)
                    width: 440
                }
                StatCard {
                    title: "Instances"
                    value: String(root.detail("instances", 0))
                    trend: "scales " + root.detail("minInstances", 1) + " to " + root.detail("maxInstances", 1)
                    trendUp: root.detail("instances", 0) > 0
                    accent: "#4f8cff"
                }
                StatCard {
                    title: "Runtime"
                    value: root.detail("runtime", "—")
                    trend: "starts the artifact"
                    trendUp: true
                    accent: "#c56bff"
                }
                StatCard {
                    title: "Runs as"
                    value: root.detail("userId", "—")
                    // "app-<id>" is the technical principal EAP creates with the application and
                    // deletes with it; anything else is an EAM user somebody named on purpose.
                    trend: root.ownPrincipal ? "its own principal, signs with its key" : "an existing user's identity"
                    trendUp: true
                    accent: "#ffb545"
                    width: 440
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

                    Text { text: "Definition"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (identityCol.width - 48) / 3; label: "Application ID"; value: root.applicationId }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Runtime"; value: root.detail("runtime", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Artifact"; value: root.detail("artifactKey", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Version"; value: root.detail("version", "—") }
                        DetailField {
                            width: (identityCol.width - 48) / 3
                            label: "MD5 sum"
                            // EAP records the checksum of the artifact it deployed. Copyable
                            // because the thing you do with it is compare it against the build you
                            // have in your hand - md5sum on the jar you think is running.
                            value: root.detail("md5Sum", "—")
                            copyable: root.detail("md5Sum", "").length > 0
                        }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.detail("accountId", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.detail("region", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Requested state"; value: root.desiredState.length > 0 ? root.desiredState : "—" }
                        DetailField {
                            width: (identityCol.width - 48) / 3
                            label: "Ready timeout"
                            value: root.detail("readyTimeoutMs", 0) + " ms"
                        }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    DetailField {
                        width: identityCol.width
                        label: "Command"
                        value: root.detail("command", "").length > 0
                               ? root.detail("command", "") + " " + root.detail("arguments", []).join(" ")
                               : "— (the runtime decides how to start the artifact)"
                    }
                    DetailField { width: identityCol.width; label: "Bucket ERN"; value: root.detail("bucketErn", "—"); copyable: true }
                    DetailField { width: identityCol.width; label: "Application ERN"; value: root.detail("ern", "—"); copyable: true }
                }
            }

            Rectangle {
                width: parent.width
                height: environmentCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: environmentCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: environmentHeaderRow.implicitHeight

                        Row {
                            id: environmentHeaderRow
                            spacing: 10
                            Text { text: "Environment"; color: "white"; font.pixelSize: 15; font.bold: true }
                            BusyIndicator {
                                running: root.savingEnvironment
                                visible: root.savingEnvironment
                                width: 18
                                height: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Button {
                            text: "+ Add variable"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: environmentHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            enabled: !root.savingEnvironment
                            onClicked: environmentDialog.open()
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Passed to the process on start, on top of the socket path and credentials euclid-mgr "
                              + "supplies itself. A running application keeps its current environment until the "
                              + "reconciler next restarts it."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.environmentNames().length === 0
                        text: "No environment variables set."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.environmentNames()
                        delegate: Row {
                            id: environmentRow
                            required property string modelData

                            width: environmentCol.width
                            height: 26
                            spacing: 12

                            Text {
                                text: environmentRow.modelData
                                color: "#e5e7eb"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                width: Math.min(260, environmentRow.width * 0.35)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.detail("environment", ({}))[environmentRow.modelData]
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: environmentRow.width - Math.min(260, environmentRow.width * 0.35) - 90
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Remove"
                                color: removeVariableArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    id: removeVariableArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.savingEnvironment
                                    onClicked: root.removeEnvironmentVariable(environmentRow.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // The processes, as opposed to the definition above them. Everything on this page so
            // far is what was asked for; this is what is actually running - which pid, on which
            // port, since when, and how many times it has had to be restarted to stay that way.
            //
            // Laid out as a heading over a DataTable rather than inside a tile of its own: the
            // table draws its own card, and nesting that in another one puts an identical border
            // a few pixels inside itself.
            Column {
                width: parent.width
                spacing: 14

                Row {
                    spacing: 10
                    Text {
                        text: "Instances (" + root.runningInstances + ")"
                        color: "white"
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        // Only when the two differ: on a healthy pool every slot is a running
                        // process and saying so twice is noise.
                        visible: root.heldSlots > 0
                        text: "+ " + root.heldSlots + " not running"
                        color: "#ffb545"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: "The processes euclid-mgr is running for this application. Each is given a TCP port of "
                          + "its own at start, which is what the API gateway routes to - a port written into the "
                          + "application's own configuration would be bound by the first instance and refused to "
                          + "every other. The ports change as the pool is scaled or restarted."
                }

                DataTable {
                    width: parent.width
                    columns: root.instanceColumns
                    rows: root.instancePage
                    totalCount: root.filteredInstances.length
                    pageSize: root.instancePageSize
                    pageIndex: root.clampedInstancePage
                    // Never true: the pool arrives with the application, and a spinner here would
                    // only report that the page as a whole is reloading, which it already shows.
                    loading: false
                    error: root.instancesError
                    searchPlaceholder: "Filter by instance, pid, port or state..."
                    emptyText: root.instanceFilter.length > 0
                               ? "No instance matches that."
                               : (root.desiredState === "RUNNING"
                                  ? "No instances yet - the manager has been asked for this application and has not started it."
                                  : "No instances. The application is not running.")
                    rowsClickable: false
                    sortKey: root.instanceSortColumn
                    sortAscending: root.instanceSortAscending

                    onSearchChanged: (text) => {
                        root.instanceFilter = text
                        root.instancePageIndex = 0
                    }
                    onRefreshRequested: root.refresh()
                    onPageChanged: (index) => { root.instancePageIndex = index }
                    // Back to the first page: page four of fifty-row pages is not page four of
                    // ten-row pages.
                    onPageSizeRequested: (size) => {
                        root.instancePageSize = size
                        root.instancePageIndex = 0
                    }
                    onSortRequested: (key, ascending) => {
                        root.instanceSortColumn = key
                        root.instanceSortAscending = ascending
                        root.instancePageIndex = 0
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: resourcesCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: resourcesCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Resources"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        text: "Buckets and queues this application may act on, mirrored onto its principal's grants - "
                              + "ESM and EQS are what enforce them."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.resourceList().length === 0
                        // Not "none": an empty list is the permissive case, and reading it as a
                        // restriction would be exactly backwards.
                        text: "Unrestricted within account " + root.detail("accountId", "—") + "."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Flow {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.resourceList()
                            delegate: Rectangle {
                                id: resourceChip
                                required property string modelData

                                radius: 8
                                color: "#2c3648"
                                height: 26
                                width: resourceChipText.implicitWidth + 20
                                Text {
                                    id: resourceChipText
                                    anchors.centerIn: parent
                                    text: resourceChip.modelData
                                    color: "#c4c9d1"
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: environmentDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string errorText: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            variableNameField.text = ""
            variableValueField.text = ""
            environmentDialog.errorText = ""
            variableNameField.forceActiveFocus()
        }

        contentItem: Column {
            width: environmentDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Add Environment Variable"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Handed to the process on start. Names beginning with EUCLID_ are set by euclid-mgr "
                          + "itself, so one set here under the same name is the one that loses."
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
                    id: variableNameField
                    width: parent.width
                    placeholderText: "e.g. LOG_LEVEL"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: variableValueField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Value"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: variableValueField
                    width: parent.width
                    placeholderText: "e.g. debug"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (addVariableButton.enabled) addVariableButton.clicked()
                }
                Text {
                    // The map is replaced wholesale, so re-using a name overwrites rather than
                    // duplicating - worth saying, since that is not obvious from a form called "add".
                    visible: variableNameField.text.trim().length > 0
                             && root.environmentNames().indexOf(variableNameField.text.trim()) >= 0
                    text: "\"" + variableNameField.text.trim() + "\" is already set; this replaces its value."
                    color: "#ffb545"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Text {
                    text: environmentDialog.errorText
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
                    onClicked: environmentDialog.close()
                }

                BusyIndicator {
                    running: root.savingEnvironment
                    visible: root.savingEnvironment
                    width: 22
                    height: 22
                    anchors.right: addVariableButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: addVariableButton
                    text: "Add"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !root.savingEnvironment && variableNameField.text.trim().length > 0
                    onClicked: {
                        environmentDialog.errorText = ""
                        root.addEnvironmentVariable(variableNameField.text.trim(), variableValueField.text)
                    }
                }
            }
        }
    }

    // The autoscaler's bounds. Sent through update-application, which changes only the fields it is
    // given, so the rest of the definition is untouched - and like every other change to a
    // definition, the manager restarts the pool onto it within a few seconds.
    Dialog {
        id: scaleDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        readonly property int wantedMin: parseInt(minField.text, 10)
        readonly property int wantedMax: parseInt(maxField.text, 10)
        readonly property bool valid: !isNaN(scaleDialog.wantedMin) && !isNaN(scaleDialog.wantedMax)
                                      && scaleDialog.wantedMin >= 0 && scaleDialog.wantedMax >= 1
                                      && scaleDialog.wantedMin <= scaleDialog.wantedMax

        readonly property string problem: {
            if (isNaN(scaleDialog.wantedMin) || isNaN(scaleDialog.wantedMax)) return ""
            if (scaleDialog.wantedMax < 1) return "The ceiling has to be at least 1."
            if (scaleDialog.wantedMin > scaleDialog.wantedMax)
                return "The floor (" + scaleDialog.wantedMin + ") cannot be above the ceiling (" + scaleDialog.wantedMax + ")."
            return ""
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            minField.text = String(root.minInstances)
            maxField.text = String(root.maxInstances)
            minField.forceActiveFocus()
            minField.selectAll()
        }

        contentItem: Column {
            width: scaleDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Scale Application"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: root.applicationId + "  ·  " + root.detail("instances", 0) + " running, currently "
                          + root.minInstances + "–" + root.maxInstances
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "The floor is what the manager keeps running; the ceiling is as far as the autoscaler may go "
                      + "under load. Raising the floor starts instances, raising the ceiling only permits them."
            }

            Row {
                width: parent.width
                spacing: 12

                Column {
                    width: (scaleDialog.availableWidth - 12) / 2
                    spacing: 6
                    Text { text: "Min instances"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: minField
                        width: parent.width
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        validator: IntValidator { bottom: 0; top: 999 }
                        Keys.onReturnPressed: maxField.forceActiveFocus()
                    }
                }

                Column {
                    width: (scaleDialog.availableWidth - 12) / 2
                    spacing: 6
                    Text { text: "Max instances"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: maxField
                        width: parent.width
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        validator: IntValidator { bottom: 1; top: 999 }
                        Keys.onReturnPressed: if (applyScaleButton.enabled) applyScaleButton.clicked()
                    }
                }
            }

            // A floor of zero is accepted here, unlike the module page's: an application pool that
            // scales away when idle is reached through EAP rather than the gateway's module
            // routing, so nothing about it depends on an instance being up to bring it back.
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ffb545"
                font.pixelSize: 12
                visible: scaleDialog.wantedMin === 0
                text: "⚠  With a floor of 0 the pool drains to nothing when idle. Whatever the application does on "
                      + "its own - polling a queue, watching a bucket - stops while it has no instances."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: scaleDialog.problem.length > 0
                text: scaleDialog.problem
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
                    onClicked: scaleDialog.close()
                }

                Button {
                    id: applyScaleButton
                    text: "Apply"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: scaleDialog.valid
                             && (scaleDialog.wantedMin !== root.minInstances
                                 || scaleDialog.wantedMax !== root.maxInstances)
                    onClicked: {
                        root.error = ""
                        eapClient.updateApplication(root.applicationId, {
                            minInstances: scaleDialog.wantedMin,
                            maxInstances: scaleDialog.wantedMax
                        })
                        scaleDialog.close()
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: deleteDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Delete Application"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Permanently deletes the definition of \"" + root.applicationId + "\". The reconciler stops its "
                          + "processes on the next tick; the artifact in the bucket is untouched."
                          + (root.ownPrincipal ? " Its principal \"" + root.detail("userId", "") + "\" and that principal's "
                                                 + "access key go with it." : "")
                          + " This cannot be undone."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
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
                        root.deleting = true
                        deleteDialog.close()
                        eapClient.deleteApplication(root.applicationId)
                    }
                }
            }
        }
    }
}
