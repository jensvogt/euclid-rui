import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

Item {
    id: root
    property bool loggedIn: false

    // "gateway-service-count"/"gateway-service-time" are recorded once per request in the
    // gateway's router, labelled by HTTP method (GET/POST/PUT/DELETE) - the closest thing emo
    // exposes to overall traffic across every module. One point per method per emo flush period
    // (5 minutes by default server-side).
    readonly property var httpMethods: [
        { name: "GET", color: "#4f8cff" },
        { name: "POST", color: "#4cd97b" },
        { name: "PUT", color: "#ffb545" },
        { name: "DELETE", color: "#ff6b6b" }
    ]
    property var requestCountByMethod: ({})
    property var requestTimeByMethod: ({})
    property string gatewayMetricsUpdatedText: "—"

    // User-configurable via the chart settings dialog (gear icon). enabledMethods is a
    // {methodName: bool} map - all four methods are always fetched (cheap, and switching one
    // back on shouldn't need a refetch), visibility is purely a client-side display filter.
    property int gatewayHistoryLimit: 50
    property var enabledMethods: ({ GET: true, POST: true, PUT: true, DELETE: true })

    // Builds LineChart's `series` list from a {method: points} map, always in the same
    // GET/POST/PUT/DELETE order regardless of which responses have come back yet.
    function seriesFor(byMethod) {
        const result = []
        for (const m of root.httpMethods) {
            if (!root.enabledMethods[m.name]) continue
            result.push({ name: m.name, color: m.color, points: byMethod[m.name] || [] })
        }
        return result
    }

    function refreshGatewayMetrics() {
        if (!root.loggedIn)
            return
        for (const m of root.httpMethods) {
            emoClient.fetchSeries("gateway-service-count", "method", m.name, root.gatewayHistoryLimit)
            emoClient.fetchSeries("gateway-service-time", "method", m.name, root.gatewayHistoryLimit)
        }
    }

    onVisibleChanged: if (visible) refreshGatewayMetrics()
    onLoggedInChanged: if (loggedIn && visible) refreshGatewayMetrics()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refreshGatewayMetrics()
    }

    Connections {
        target: emoClient
        function onSeriesLoaded(name, labelValue, points) {
            if (name === "gateway-service-count") {
                const byMethod = Object.assign({}, root.requestCountByMethod)
                byMethod[labelValue] = points
                root.requestCountByMethod = byMethod
            } else if (name === "gateway-service-time") {
                const byMethod = Object.assign({}, root.requestTimeByMethod)
                byMethod[labelValue] = points
                root.requestTimeByMethod = byMethod
            } else return
            root.gatewayMetricsUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onSeriesFailed(name, labelValue, message) {
            if (name === "gateway-service-count") {
                const byMethod = Object.assign({}, root.requestCountByMethod)
                byMethod[labelValue] = []
                root.requestCountByMethod = byMethod
            } else if (name === "gateway-service-time") {
                const byMethod = Object.assign({}, root.requestTimeByMethod)
                byMethod[labelValue] = []
                root.requestTimeByMethod = byMethod
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
            spacing: 28

            SectionHeader {
                title: "Analytics"
                subtitle: "Traffic sources and conversion breakdown."
            }

            FoldableTile {
                id: gatewayTile
                width: parent.width
                title: "Gateway Traffic"
                expanded: true

                headerContent: [
                    Button {
                        text: "⚙"
                        font.pixelSize: 16
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        Material.theme: Material.Dark
                        onClicked: chartSettingsDialog.open()
                    },
                    Button {
                        text: "⟳"
                        font.pixelSize: 16
                        flat: true
                        implicitWidth: 32
                        implicitHeight: 32
                        Material.theme: Material.Dark
                        onClicked: root.refreshGatewayMetrics()
                    }
                ]

                contentData: [
                    Column {
                        width: gatewayTile.width - 32
                        spacing: 20

                        Column {
                            width: parent.width
                            spacing: 8
                            Text { text: "Request Count"; color: "#c4c9d1"; font.pixelSize: 12; font.bold: true }
                            LineChart {
                                width: parent.width
                                height: 160
                                series: root.seriesFor(root.requestCountByMethod)
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 8
                            Text { text: "Request Time"; color: "#c4c9d1"; font.pixelSize: 12; font.bold: true }
                            LineChart {
                                width: parent.width
                                height: 160
                                valueSuffix: " ms"
                                decimals: 1
                                series: root.seriesFor(root.requestTimeByMethod)
                            }
                        }

                        Text {
                            text: "Updated " + root.gatewayMetricsUpdatedText
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                    }
                ]
            }

            Rectangle {
                width: parent.width
                height: 260
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 30

                    Column {
                        spacing: 16
                        width: 220
                        anchors.verticalCenter: parent.verticalCenter

                        Text { text: "Traffic Sources"; color: "white"; font.pixelSize: 15; font.bold: true }

                        Repeater {
                            model: [
                                { label: "Organic Search", pct: 42, color: "#4f8cff" },
                                { label: "Direct", pct: 27, color: "#4cd97b" },
                                { label: "Referral", pct: 18, color: "#ffb545" },
                                { label: "Social", pct: 13, color: "#c56bff" }
                            ]
                            delegate: Column {
                                spacing: 4
                                width: 220

                                Row {
                                    width: parent.width
                                    Text {
                                        text: modelData.label
                                        color: "#c4c9d1"
                                        font.pixelSize: 12
                                        width: parent.width - 34
                                    }
                                    Text {
                                        text: modelData.pct + "%"
                                        color: "white"
                                        font.pixelSize: 12
                                        width: 34
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                                Rectangle {
                                    width: parent.width
                                    height: 6
                                    radius: 3
                                    color: "#2c313c"

                                    Rectangle {
                                        height: parent.height
                                        radius: 3
                                        color: modelData.color
                                        width: 0
                                        Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                                        Component.onCompleted: width = parent.width * modelData.pct / 100
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: 1
                        height: parent.height
                        Rectangle { anchors.fill: parent; color: "#2c313c" }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 18

                        Text { text: "Conversion Funnel"; color: "white"; font.pixelSize: 15; font.bold: true }

                        Repeater {
                            model: [
                                { label: "Visitors", value: 1.0 },
                                { label: "Signups", value: 0.62 },
                                { label: "Trials", value: 0.34 },
                                { label: "Paid", value: 0.15 }
                            ]
                            delegate: Row {
                                spacing: 12
                                Text {
                                    text: modelData.label
                                    color: "#9aa1ac"
                                    font.pixelSize: 12
                                    width: 70
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Rectangle {
                                    height: 22
                                    radius: 6
                                    color: "#4f8cff"
                                    opacity: 0.35 + 0.65 * modelData.value
                                    width: 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    Behavior on width { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                                    Component.onCompleted: width = 260 * modelData.value

                                    Text {
                                        anchors.right: parent.right
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Math.round(modelData.value * 100) + "%"
                                        color: "white"
                                        font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 200
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 12

                    Text { text: "Top Pages"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Repeater {
                        model: [
                            { page: "/dashboard", views: "8,204" },
                            { page: "/pricing", views: "5,912" },
                            { page: "/docs/getting-started", views: "4,330" }
                        ]
                        delegate: Row {
                            width: parent.width
                            height: 28
                            Text { text: modelData.page; color: "#c4c9d1"; font.pixelSize: 13; width: parent.width - 100 }
                            Text { text: modelData.views; color: "#9aa1ac"; font.pixelSize: 13; width: 100; horizontalAlignment: Text.AlignRight }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: chartSettingsDialog
        modal: true
        anchors.centerIn: parent
        width: 360
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        // ComboBox's currentIndex binding gets clobbered by its own internal model-populate
        // logic, same as every other dialog's combo/spinbox in this app - set it imperatively
        // on open instead (see createKeyDialog's onOpened in EkmKeysPage.qml for the same idiom).
        onOpened: historyCombo.currentIndex = Math.max(0, historyCombo.limits.indexOf(root.gatewayHistoryLimit))

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: chartSettingsDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Chart Settings"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Controls what the Gateway Traffic charts show."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                id: historyColumn
                width: parent.width
                spacing: 6
                Text { text: "History length"; color: "#9aa1ac"; font.pixelSize: 12 }
                ComboBox {
                    id: historyCombo
                    width: historyColumn.width
                    property var limits: [10, 25, 50, 100]
                    model: [ "Last 10 points", "Last 25 points", "Last 50 points", "Last 100 points" ]
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onActivated: {
                        root.gatewayHistoryLimit = limits[currentIndex]
                        root.refreshGatewayMetrics()
                    }
                }
            }

            Column {
                id: methodsColumn
                width: parent.width
                spacing: 10
                Text { text: "HTTP Methods"; color: "#9aa1ac"; font.pixelSize: 12 }

                Repeater {
                    model: root.httpMethods
                    delegate: Row {
                        width: methodsColumn.width
                        height: 28
                        spacing: 10

                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: modelData.color
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: modelData.name
                            color: "#e5e7eb"
                            font.pixelSize: 13
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 66
                        }
                        ToggleSwitch {
                            anchors.verticalCenter: parent.verticalCenter
                            checked: root.enabledMethods[modelData.name]
                            onToggled: (checked) => {
                                const updated = Object.assign({}, root.enabledMethods)
                                updated[modelData.name] = checked
                                root.enabledMethods = updated
                            }
                        }
                    }
                }
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Close"
                    flat: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    onClicked: chartSettingsDialog.close()
                }
            }
        }
    }
}
