import QtQuick
import QtQuick.Controls
import "../components"

Item {
    ScrollView {
        id: scrollView
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            width: scrollView.availableWidth
            spacing: 28

            SectionHeader {
                title: "Dashboard"
                subtitle: "Welcome back, here's what's happening today."
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "Active Users"
                    value: "12,483"
                    trend: "+4.3% this week"
                    trendUp: true
                    accent: "#4f8cff"
                }
                StatCard {
                    title: "Revenue"
                    value: "$48,920"
                    trend: "+8.1% this week"
                    trendUp: true
                    accent: "#4cd97b"
                }
                StatCard {
                    title: "Error Rate"
                    value: "0.42%"
                    trend: "-1.2% this week"
                    trendUp: false
                    accent: "#ffb545"
                }
                StatCard {
                    title: "Avg. Session"
                    value: "6m 12s"
                    trend: "+0.8% this week"
                    trendUp: true
                    accent: "#c56bff"
                }
            }

            Row {
                width: parent.width
                spacing: 18

                Rectangle {
                    width: parent.width * 0.42
                    height: 280
                    radius: 14
                    color: "#20242e"
                    border.color: "#2c313c"
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 18

                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "System Load"
                            color: "#9aa1ac"
                            font.pixelSize: 13
                        }

                        Row {
                            spacing: 24
                            Gauge {
                                value: 0.68
                                valueText: "68%"
                                label: "CPU"
                                progressColor: "#4f8cff"
                            }
                            Gauge {
                                value: 0.41
                                valueText: "41%"
                                label: "Memory"
                                progressColor: "#4cd97b"
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width * 0.58 - 18
                    height: 280
                    radius: 14
                    color: "#20242e"
                    border.color: "#2c313c"
                    border.width: 1

                    Column {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 14

                        Text {
                            text: "Weekly Traffic"
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Row {
                            id: barRow
                            width: parent.width
                            height: 180
                            spacing: 18

                            property var values: [0.4, 0.65, 0.5, 0.8, 0.7, 0.95, 0.6]
                            property var labels: ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]

                            Repeater {
                                model: barRow.values.length
                                delegate: Column {
                                    spacing: 8
                                    width: (barRow.width - barRow.spacing * 6) / 7

                                    Item {
                                        width: parent.width
                                        height: 140

                                        Rectangle {
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            radius: 6
                                            color: index === 5 ? "#4f8cff" : "#2c3648"
                                            height: 0
                                            Behavior on height { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                                            Component.onCompleted: height = 140 * barRow.values[index]
                                        }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: barRow.labels[index]
                                        color: "#9aa1ac"
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
                height: 280
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 14

                    Text {
                        text: "Recent Activity"
                        color: "white"
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Column {
                        width: parent.width
                        spacing: 10

                        ActivityRow {
                            width: parent.width
                            initials: "AK"
                            avatarColor: "#4f8cff"
                            title: "Anna Kern deployed build #482"
                            subtitle: "production · euclid-rui"
                            time: "2m ago"
                        }
                        ActivityRow {
                            width: parent.width
                            initials: "TS"
                            avatarColor: "#4cd97b"
                            title: "Tom Sato resolved issue #918"
                            subtitle: "bug · high priority"
                            time: "18m ago"
                        }
                        ActivityRow {
                            width: parent.width
                            initials: "MB"
                            avatarColor: "#ffb545"
                            title: "Maria Bell commented on PR #205"
                            subtitle: "code review"
                            time: "1h ago"
                        }
                        ActivityRow {
                            width: parent.width
                            initials: "JV"
                            avatarColor: "#c56bff"
                            title: "Jens Vogt updated settings"
                            subtitle: "configuration"
                            time: "3h ago"
                        }
                    }
                }
            }
        }
    }
}
