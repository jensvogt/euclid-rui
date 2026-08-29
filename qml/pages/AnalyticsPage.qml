import QtQuick
import QtQuick.Controls
import "../components"

Item {
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
}
