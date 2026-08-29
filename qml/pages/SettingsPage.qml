import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
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
                title: "Settings"
                subtitle: "Manage your preferences and account options."
            }

            Rectangle {
                width: parent.width
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                height: content1.implicitHeight + 40

                Column {
                    id: content1
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 18

                    Text { text: "Notifications"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Repeater {
                        model: [
                            { label: "Email notifications", desc: "Get notified about important updates via email" },
                            { label: "Push notifications", desc: "Receive push alerts on your devices" },
                            { label: "Weekly digest", desc: "A summary of activity sent every Monday" }
                        ]
                        delegate: Row {
                            width: content1.width
                            height: 40

                            Column {
                                width: parent.width - 60
                                anchors.verticalCenter: parent.verticalCenter
                                Text { text: modelData.label; color: "#e5e7eb"; font.pixelSize: 13 }
                                Text { text: modelData.desc; color: "#9aa1ac"; font.pixelSize: 11 }
                            }
                            ToggleSwitch {
                                anchors.verticalCenter: parent.verticalCenter
                                checked: index !== 1
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                height: content2.implicitHeight + 40

                Column {
                    id: content2
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 18

                    Text { text: "Profile"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Row {
                        spacing: 20
                        width: content2.width

                        Column {
                            width: (content2.width - 20) / 2
                            spacing: 6
                            Text { text: "Display name"; color: "#9aa1ac"; font.pixelSize: 12 }
                            TextField {
                                width: parent.width
                                text: "Jens Vogt"
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                            }
                        }
                        Column {
                            width: (content2.width - 20) / 2
                            spacing: 6
                            Text { text: "Time zone"; color: "#9aa1ac"; font.pixelSize: 12 }
                            ComboBox {
                                width: parent.width
                                model: ["UTC", "Europe/Zurich", "America/New_York", "Asia/Tokyo"]
                                currentIndex: 1
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                            }
                        }
                    }

                    Column {
                        width: content2.width
                        spacing: 6

                        Row {
                            width: parent.width
                            Text { text: "UI density"; color: "#9aa1ac"; font.pixelSize: 12; width: parent.width - 40 }
                            Text { text: Math.round(densitySlider.value * 100) + "%"; color: "#c4c9d1"; font.pixelSize: 12; width: 40; horizontalAlignment: Text.AlignRight }
                        }
                        Slider {
                            id: densitySlider
                            width: parent.width
                            from: 0.5
                            to: 1.5
                            value: 1.0
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                        }
                    }

                    Row {
                        spacing: 12
                        Button {
                            text: "Save changes"
                            highlighted: true
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                        }
                        Button {
                            text: "Reset"
                            flat: true
                            Material.theme: Material.Dark
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                height: content3.implicitHeight + 40

                Column {
                    id: content3
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 18

                    Text { text: "Display"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Column {
                        width: content3.width
                        spacing: 6

                        Text { text: "Date & time format"; color: "#9aa1ac"; font.pixelSize: 12 }
                        TextField {
                            id: dateFormatField
                            width: parent.width
                            text: DateFormat.pattern
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onEditingFinished: DateFormat.pattern = text.length > 0 ? text : "dd-MM-yyyy HH:mm:ss"
                        }
                        Text {
                            text: "Example: " + DateFormat.format(new Date().toISOString())
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                        Text {
                            text: "Tokens: dd, MM, yyyy, HH, mm, ss — applies to every date/time shown in the app."
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                height: content4.implicitHeight + 40

                Column {
                    id: content4
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 18

                    Text { text: "Data Refresh"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Column {
                        width: content4.width
                        spacing: 6

                        Text { text: "Auto-refresh interval (seconds)"; color: "#9aa1ac"; font.pixelSize: 12 }
                        SpinBox {
                            id: autoRefreshSpinBox
                            width: 160
                            from: 0
                            to: 3600
                            stepSize: 5
                            value: appSettings.autoRefreshSeconds
                            editable: true
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onValueModified: appSettings.autoRefreshSeconds = value
                        }
                        Text {
                            text: autoRefreshSpinBox.value === 0
                                ? "Auto-refresh is off — pages only update on manual refresh or navigation."
                                : "Dashboards, queues, buckets and objects refresh themselves every " + autoRefreshSpinBox.value + " seconds."
                            color: "#6b7280"
                            font.pixelSize: 11
                        }
                    }
                }
            }
        }
    }
}
