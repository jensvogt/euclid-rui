import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// One module of the registry: what euclid-mgr was told to run, what it is running, and the
// processes themselves.
//
// The instance list is the part the table cannot show - which pid, in what state, restarted how
// often - and it arrives in the same "list-modules" answer the table is built from, so this page
// needs no call of its own beyond the refresh it shares.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string moduleName: ""
    property var details: ({})

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    readonly property bool active: !!detail("active", false)
    readonly property bool core: !!detail("core", true)
    readonly property bool desiredStopped: !!detail("desiredStopped", false)
    readonly property int runningInstances: Number(detail("runningInstances", 0))
    readonly property int minInstances: Number(detail("minInstances", 0))
    readonly property int maxInstances: Number(detail("maxInstances", 1))
    readonly property int desiredMinInstances: Number(detail("desiredMinInstances", -1))
    readonly property int desiredMaxInstances: Number(detail("desiredMaxInstances", -1))
    readonly property int desiredThreads: Number(detail("desiredThreads", -1))
    readonly property var instances: detail("instances", [])

    // The same three states the table shows, by the same rule: a module nobody asked to run is not
    // a problem, so it reads grey rather than red.
    readonly property string state: !root.active ? "DISABLED"
                                                 : (root.runningInstances > 0 ? "RUNNING" : "STOPPED")
    readonly property color stateColor: !root.active ? "#9aa1ac"
                                                     : (root.runningInstances > 0 ? "#4cd97b" : "#ff6b6b")

    function instanceStateColor(state) {
        if (state === "RUNNING") return "#4cd97b"
        if (state === "STARTING") return "#ffb545"
        if (state === "STOPPED") return "#9aa1ac"
        return "#ff6b6b"
    }

    // A limit that has been asked for but not yet reconciled is shown as "1 → 3" rather than
    // silently as the old value, since that gap is exactly what an operator is waiting on.
    function pending(current, desired) {
        return desired >= 0 && desired !== current ? current + " → " + desired : String(current)
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
                text: "‹ Back to Modules"
                flat: true
                onClicked: root.back()
            }

            SectionHeader {
                title: root.moduleName
                subtitle: root.core ? "A module of this installation, declared in euclid.json."
                                    : "Run by the manager but not a module: its desired state belongs to EAP or ETS."
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "State"
                    value: root.state
                    trend: root.desiredStopped ? "stopped through EMM" : (root.active ? "enabled" : "disabled in the registry")
                    trendUp: root.state === "RUNNING"
                    accent: root.stateColor
                }
                StatCard {
                    title: "Instances"
                    value: String(root.runningInstances)
                    trend: "of " + root.minInstances + "–" + root.maxInstances + " allowed"
                    trendUp: root.runningInstances >= root.minInstances
                    accent: "#4f8cff"
                }
                StatCard {
                    title: "Auto-restart"
                    value: root.detail("autoRestart", false) ? "Yes" : "No"
                    // -1 is the server's "no limit", which is not a number worth printing.
                    trend: Number(root.detail("maxRestarts", -1)) >= 0
                           ? "up to " + root.detail("maxRestarts", -1) + " times" : "no limit"
                    trendUp: true
                    accent: "#c56bff"
                }
            }

            Rectangle {
                width: parent.width
                height: definitionCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: definitionCol
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

                        DetailField { width: (definitionCol.width - 48) / 3; label: "Min instances"; value: root.pending(root.minInstances, root.desiredMinInstances) }
                        DetailField { width: (definitionCol.width - 48) / 3; label: "Max instances"; value: root.pending(root.maxInstances, root.desiredMaxInstances) }
                        DetailField {
                            width: (definitionCol.width - 48) / 3
                            label: "Worker threads"
                            // Only ever known here when a change is pending: what a running process
                            // was started with is not in the registry.
                            value: root.desiredThreads >= 0 ? root.desiredThreads + " (pending)" : "—"
                        }
                        DetailField { width: (definitionCol.width - 48) / 3; label: "Enabled"; value: root.active ? "Yes" : "No" }
                        DetailField { width: (definitionCol.width - 48) / 3; label: "Stopped through EMM"; value: root.desiredStopped ? "Yes" : "No" }
                        DetailField { width: (definitionCol.width - 48) / 3; label: "Core module"; value: root.core ? "Yes" : "No" }
                        DetailField { width: (definitionCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (definitionCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                        DetailField {
                            width: (definitionCol.width - 48) / 3
                            label: "Last started"
                            // Null for a module that has never run, which is worth saying rather
                            // than rendering as an epoch date.
                            value: String(root.detail("lastStartTime", "")).length > 0
                                   ? DateFormat.format(root.detail("lastStartTime", "")) : "never"
                        }
                    }

                    DetailField { width: definitionCol.width; label: "Executable"; value: root.detail("executable", "—"); copyable: true }
                    DetailField { width: definitionCol.width; label: "Socket"; value: root.detail("socketPath", "—"); copyable: true }
                }
            }

            Rectangle {
                width: parent.width
                height: instancesCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: instancesCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text {
                        text: "Instances (" + root.instances.length + ")"
                        color: "white"
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 11
                        text: "The processes euclid-mgr has for this module. A slot with no pid is one it is holding - "
                              + "stopped, or waiting to be restarted - rather than one that is running."
                    }

                    Text {
                        visible: root.instances.length === 0
                        text: "No instances."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    // Column headers, so the rows below are readable without guessing.
                    Row {
                        width: parent.width
                        spacing: 16
                        visible: root.instances.length > 0

                        Text { width: instancesCol.width * 0.32; text: "Instance"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                        Text { width: instancesCol.width * 0.10; text: "PID"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                        Text { width: instancesCol.width * 0.14; text: "State"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                        Text { width: instancesCol.width * 0.10; text: "Restarts"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                        Text { width: instancesCol.width * 0.24; text: "Started"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                    }

                    Repeater {
                        model: root.instances
                        delegate: Row {
                            id: instanceRow
                            required property var modelData

                            width: instancesCol.width
                            height: 26
                            spacing: 16

                            Text {
                                width: instancesCol.width * 0.32
                                text: instanceRow.modelData.instanceId
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                elide: Text.ElideMiddle
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: instancesCol.width * 0.10
                                // -1 is the manager's "no process", not a pid.
                                text: Number(instanceRow.modelData.pid) > 0 ? instanceRow.modelData.pid : "—"
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: instancesCol.width * 0.14
                                text: instanceRow.modelData.state
                                color: root.instanceStateColor(instanceRow.modelData.state)
                                font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: instancesCol.width * 0.10
                                text: String(instanceRow.modelData.restartCount)
                                color: Number(instanceRow.modelData.restartCount) > 0 ? "#ffb545" : "#c4c9d1"
                                font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: instancesCol.width * 0.24
                                text: DateFormat.format(instanceRow.modelData.created)
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
