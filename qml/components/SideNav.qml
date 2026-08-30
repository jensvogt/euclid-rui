import QtQuick

Rectangle {
    id: root
    color: "#181b21"
    width: 220

    property string currentRoute: "dashboard"
    property bool modulesExpanded: currentRoute.indexOf("modules-") === 0
    signal navigate(string route)

    Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 24
        spacing: 26

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 20
            spacing: 10

            Rectangle {
                width: 30
                height: 30
                radius: 8
                color: "#4f8cff"
                Text {
                    anchors.centerIn: parent
                    text: "E"
                    color: "white"
                    font.bold: true
                    font.pixelSize: 15
                }
            }
            Text {
                text: "Euclid"
                color: "white"
                font.pixelSize: 17
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 4

            NavButton {
                icon: "⌂"
                label: "Dashboard"
                selected: root.currentRoute === "dashboard"
                onClicked: root.navigate("dashboard")
            }
            NavButton {
                icon: "📈"
                label: "Analytics"
                selected: root.currentRoute === "analytics"
                onClicked: root.navigate("analytics")
            }

            Rectangle {
                width: parent.width
                height: 44
                radius: 10
                color: modulesMouseArea.containsMouse ? "#22262f" : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Rectangle {
                    visible: root.modulesExpanded
                    width: 3
                    height: 22
                    radius: 2
                    color: "#4f8cff"
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        text: "▤"
                        font.pixelSize: 16
                        color: root.modulesExpanded ? "#4f8cff" : "#9aa1ac"
                    }
                    Text {
                        text: "Modules"
                        font.pixelSize: 14
                        color: root.modulesExpanded ? "white" : "#c4c9d1"
                    }
                }

                Text {
                    text: root.modulesExpanded ? "⌄" : "›"
                    color: "#6b7280"
                    font.pixelSize: 12
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                }

                MouseArea {
                    id: modulesMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.modulesExpanded = !root.modulesExpanded
                }
            }

            Item {
                width: parent.width
                height: modulesColumn.height
                clip: true
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                Column {
                    id: modulesColumn
                    width: parent.width
                    spacing: 2
                    height: root.modulesExpanded ? implicitHeight : 0

                    SubNavButton {
                        label: "EAM"
                        selected: root.currentRoute.indexOf("modules-eam") === 0
                        onClicked: root.navigate("modules-eam")
                    }
                    SubNavButton {
                        label: "EKM"
                        selected: root.currentRoute.indexOf("modules-ekm") === 0
                        onClicked: root.navigate("modules-ekm")
                    }
                    SubNavButton {
                        label: "ENS"
                        selected: root.currentRoute.indexOf("modules-ens") === 0
                        onClicked: root.navigate("modules-ens")
                    }
                    SubNavButton {
                        label: "EQS"
                        selected: root.currentRoute.indexOf("modules-eqs") === 0
                        onClicked: root.navigate("modules-eqs")
                    }
                    SubNavButton {
                        label: "ESM"
                        selected: root.currentRoute === "modules-esm"
                        onClicked: root.navigate("modules-esm")
                    }
                }
            }

            NavButton {
                icon: "⚙"
                label: "Settings"
                selected: root.currentRoute === "settings"
                onClicked: root.navigate("settings")
            }
        }
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        spacing: 12

        Rectangle {
            width: 36
            height: 36
            radius: 18
            color: "#2c3648"
            Text {
                anchors.centerIn: parent
                text: "JV"
                color: "white"
                font.pixelSize: 12
                font.bold: true
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            Text { text: "Jens Vogt"; color: "white"; font.pixelSize: 13 }
            Text { text: "Administrator"; color: "#9aa1ac"; font.pixelSize: 11 }
        }
    }
}
