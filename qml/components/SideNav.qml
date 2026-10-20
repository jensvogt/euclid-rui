import QtQuick

Rectangle {
    id: root
    color: "#181b21"
    width: 220

    property string currentRoute: "dashboard"
    property bool modulesExpanded: currentRoute.indexOf("modules-") === 0
    signal navigate(string route)
    // The mark at the top asks for the About box. A signal rather than the dialog itself, for the
    // reason navigate() is one: the dialog belongs to the window, and this is a component that
    // knows nothing about what is in it.
    signal aboutRequested()

    Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 24
        spacing: 26

        // The mark and the name, and the way to the About box. Nothing says so on sight, which is
        // the usual bargain for a logo: it is where people try first, and the version it shows is
        // not something anybody needs to be led to.
        //
        // An Item around the Row, rather than the click handler inside it: a positioner lays its
        // children out and refuses one that anchors itself, so a MouseArea filling the Row made
        // the Row collapse and took the mark off the screen with it. The handler belongs to a
        // plain Item, which is free to be filled, and the Row sizes that Item from its content.
        Item {
            anchors.left: parent.left
            anchors.leftMargin: 20
            width: brand.width
            height: brand.height

            Row {
                id: brand
                spacing: 10

                Image {
                    source: "qrc:/EuclidRui/dist/branding/euclid-icon.svg"
                    width: 30
                    height: 30
                    // An SVG is rasterised once at sourceSize and scaled after, so this is what
                    // keeps the mark crisp on a high-DPI screen rather than blurred up from 30px.
                    sourceSize.width: 60
                    sourceSize.height: 60
                    fillMode: Image.PreserveAspectFit
                    opacity: brandMouse.containsMouse ? 0.8 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                Text {
                    text: "Euclid"
                    color: brandMouse.containsMouse ? "#4f8cff" : "white"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    font.pixelSize: 17
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: brandMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.aboutRequested()
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
                        label: "EAP (Apps)"
                        selected: root.currentRoute.indexOf("modules-eap") === 0
                        onClicked: root.navigate("modules-eap")
                    }
                    SubNavButton {
                        label: "EAM (Access)"
                        selected: root.currentRoute.indexOf("modules-eam") === 0
                        onClicked: root.navigate("modules-eam")
                    }
                    SubNavButton {
                        label: "EKM (Keys)"
                        selected: root.currentRoute.indexOf("modules-ekm") === 0
                        onClicked: root.navigate("modules-ekm")
                    }
                    SubNavButton {
                        label: "EKV (Key/Value)"
                        selected: root.currentRoute.indexOf("modules-ekv") === 0
                        onClicked: root.navigate("modules-ekv")
                    }
                    SubNavButton {
                        label: "ENS (Topics)"
                        selected: root.currentRoute.indexOf("modules-ens") === 0
                        onClicked: root.navigate("modules-ens")
                    }
                    SubNavButton {
                        label: "EQS (Queues)"
                        selected: root.currentRoute.indexOf("modules-eqs") === 0
                        onClicked: root.navigate("modules-eqs")
                    }
                    SubNavButton {
                        label: "ESM (Storage)"
                        selected: root.currentRoute === "modules-esm"
                        onClicked: root.navigate("modules-esm")
                    }
                    SubNavButton {
                        label: "ESS (Secrets)"
                        selected: root.currentRoute.indexOf("modules-ess") === 0
                        onClicked: root.navigate("modules-ess")
                    }
                    SubNavButton {
                        label: "ETS (Transfer)"
                        selected: root.currentRoute.indexOf("modules-ets") === 0
                        onClicked: root.navigate("modules-ets")
                    }
                    SubNavButton {
                        // The gateway in front of the EAP application pools. Administrators only,
                        // and the server agrees: what it publishes is how this installation is
                        // reached from outside.
                        label: "EAG (Gateway)"
                        visible: euclidClient.isAdmin
                        selected: root.currentRoute.indexOf("modules-eag") === 0
                        onClicked: root.navigate("modules-eag")
                    }
                    SubNavButton {
                        // The registry the other entries above are rows of. Administrators only -
                        // how the installation is put together is an operator's business.
                        label: "EMM (Modules)"
                        visible: euclidClient.isAdmin
                        selected: root.currentRoute.indexOf("modules-emm") === 0
                        onClicked: root.navigate("modules-emm")
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
