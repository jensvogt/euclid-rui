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
            // Gone from the list: deleted, by this page or from somewhere else.
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
