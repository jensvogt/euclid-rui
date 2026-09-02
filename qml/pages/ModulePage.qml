import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property string moduleName: ""
    property bool loggedIn: false
    property var stats: []
    property var activity: []
    signal navigate(string route)

    property int runningInstances: -1
    property int maxInstances: -1
    property real uptimeSeconds: 0
    property bool statusLoading: false
    property string statusError: ""
    property real cpuPercent: -1
    property real memoryPercent: -1

    function formatUptime(seconds) {
        if (seconds <= 0)
            return "—"
        const days = Math.floor(seconds / 86400)
        const hours = Math.floor((seconds % 86400) / 3600)
        const minutes = Math.floor((seconds % 3600) / 60)
        if (days > 0)
            return days + "d " + hours + "h " + minutes + "m"
        if (hours > 0)
            return hours + "h " + minutes + "m"
        return minutes + "m"
    }

    // What F5 calls (see Main.qml's refreshCurrentPage()).
    function refresh() {
        root.refreshStatus()
    }

    function refreshStatus() {
        if (!root.loggedIn) {
            statusError = "Sign in to view live status."
            return
        }
        statusLoading = true
        statusError = ""
        emmClient.fetchModuleStatus(root.moduleName.toLowerCase())
        // Unlike emm's module registry (lowercase, matching x-euclid-target routing), emo's
        // "module" metric label is the module's uppercase display name (e.g. "EQS") - set by
        // each module's own HttpActionServer/UnixSocketServer serviceName, a different naming
        // convention than the gateway routing target.
        emoClient.fetchCpuUsage(root.moduleName)
        emoClient.fetchMemoryUsage(root.moduleName)
    }

    onVisibleChanged: if (visible) refreshStatus()
    onLoggedInChanged: if (loggedIn && visible) refreshStatus()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refreshStatus()
    }

    Connections {
        target: emmClient
        function onModuleStatusLoaded(name, uptime, instances, maxInstances) {
            if (name.toLowerCase() !== root.moduleName.toLowerCase())
                return
            root.statusLoading = false
            root.statusError = ""
            root.uptimeSeconds = uptime
            root.runningInstances = instances
            root.maxInstances = maxInstances
        }
        function onModuleStatusFailed(name, message) {
            if (name.toLowerCase() !== root.moduleName.toLowerCase())
                return
            root.statusLoading = false
            root.statusError = message
        }
    }

    Connections {
        target: emoClient
        function onCpuUsageLoaded(name, percent) {
            if (name.toLowerCase() !== root.moduleName.toLowerCase())
                return
            root.cpuPercent = percent
        }
        function onCpuUsageFailed(name, message) {
            if (name.toLowerCase() !== root.moduleName.toLowerCase())
                return
            root.cpuPercent = -1
        }
        function onMemoryUsageLoaded(name, percent) {
            if (name.toLowerCase() !== root.moduleName.toLowerCase())
                return
            root.memoryPercent = percent
        }
        function onMemoryUsageFailed(name, message) {
            if (name.toLowerCase() !== root.moduleName.toLowerCase())
                return
            root.memoryPercent = -1
        }
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            width: parent.width
            spacing: 28

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: moduleName + " Module"
                    subtitle: "Status and metrics for the " + moduleName + " module."
                }

                // The same dialog the Settings page opens, scoped to this module - which is where
                // you already are when exporting just this one is what you want. Only the modules
                // EMM can dump have it, and only for administrators, who are the only ones it
                // answers.
                Button {
                    text: "Export…"
                    flat: true
                    visible: euclidClient.isAdmin
                             && emmClient.exportableModules().indexOf(root.moduleName.toLowerCase()) >= 0
                    enabled: root.loggedIn
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: {
                        moduleExportDialog.scopeModule = root.moduleName.toLowerCase()
                        moduleExportDialog.open()
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 100
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 20
                    anchors.right: memoryGauge.left
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 24

                    Row {
                        spacing: 8
                        anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: 9
                            height: 9
                            radius: 4.5
                            color: root.runningInstances > 0 ? "#4cd97b" : (root.runningInstances === 0 ? "#ff6b6b" : "#6b7280")
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.runningInstances < 0
                                ? "Unknown"
                                : (root.runningInstances === 1 ? "1 instance running" : root.runningInstances + " instances running")
                            color: root.runningInstances > 0 ? "#4cd97b" : (root.runningInstances === 0 ? "#ff6b6b" : "#9aa1ac")
                            font.pixelSize: 13
                            font.bold: true
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle { width: 1; height: 24; color: "#2c313c"; anchors.verticalCenter: parent.verticalCenter }

                    Column {
                        spacing: 1
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: "Uptime"; color: "#6b7280"; font.pixelSize: 10 }
                        Text { text: root.formatUptime(root.uptimeSeconds); color: "#c4c9d1"; font.pixelSize: 12 }
                    }

                    Text {
                        visible: root.statusError.length > 0
                        text: root.statusError
                        color: "#ff6b6b"
                        font.pixelSize: 11
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                    }

                    BusyIndicator {
                        running: root.statusLoading
                        visible: root.statusLoading
                        width: 20
                        height: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Gauge {
                    id: memoryGauge
                    visible: root.memoryPercent >= 0
                    anchors.right: cpuGauge.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76
                    height: 76
                    value: Math.min(1, Math.max(0, root.memoryPercent) / 100)
                    valueText: root.memoryPercent >= 0 ? Math.round(root.memoryPercent) + "%" : "—"
                    label: "Memory"
                    progressColor: root.memoryPercent >= 80 ? "#ff6b6b" : (root.memoryPercent >= 50 ? "#ffb545" : "#4cd97b")
                }

                Gauge {
                    id: cpuGauge
                    visible: root.cpuPercent >= 0
                    anchors.right: instanceGauge.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76
                    height: 76
                    value: Math.min(1, Math.max(0, root.cpuPercent) / 100)
                    valueText: root.cpuPercent >= 0 ? Math.round(root.cpuPercent) + "%" : "—"
                    label: "CPU"
                    progressColor: root.cpuPercent >= 80 ? "#ff6b6b" : (root.cpuPercent >= 50 ? "#ffb545" : "#4cd97b")
                }

                Gauge {
                    id: instanceGauge
                    visible: root.maxInstances > 0
                    anchors.right: parent.right
                    anchors.rightMargin: 20
                    anchors.verticalCenter: parent.verticalCenter
                    width: 76
                    height: 76
                    value: root.maxInstances > 0 ? Math.min(1, root.runningInstances / root.maxInstances) : 0
                    valueText: root.maxInstances > 0
                        ? Math.round(Math.min(1, root.runningInstances / root.maxInstances) * 100) + "%"
                        : "—"
                    label: "of " + root.maxInstances
                    progressColor: "#4f8cff"
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                Repeater {
                    model: stats
                    delegate: StatCard {
                        title: modelData.title
                        value: modelData.value
                        trend: modelData.trend
                        trendUp: modelData.trendUp
                        accent: modelData.accent
                        clickable: modelData.route !== undefined
                        onClicked: root.navigate(modelData.route)
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: activityCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: activityCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text {
                        text: "Recent Events"
                        color: "white"
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Column {
                        width: parent.width
                        spacing: 10

                        Repeater {
                            model: activity
                            delegate: ActivityRow {
                                width: parent.width
                                initials: modelData.initials
                                avatarColor: modelData.avatarColor
                                title: modelData.title
                                subtitle: modelData.subtitle
                                time: modelData.time
                            }
                        }
                    }
                }
            }
        }
    }

    ImportExportDialog {
        id: moduleExportDialog
        parent: Overlay.overlay
    }
}
