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

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    // Not "state": QQuickItem already has one (the Item state machine), and shadowing it silently
    // changes what every state-related binding on this page means.
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
            root.error = message
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

                    Text { text: "Environment"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        text: "Passed to the process on start, on top of the socket path and credentials euclid-mgr "
                              + "supplies itself. Edited through the EAP API; this page shows the current definition."
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
                                width: environmentRow.width - Math.min(260, environmentRow.width * 0.35) - 12
                                anchors.verticalCenter: parent.verticalCenter
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
