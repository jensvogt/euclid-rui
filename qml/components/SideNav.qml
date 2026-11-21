import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

Rectangle {
    id: root
    color: "#181b21"

    // Folded down to its icons, or open with their labels. Kept in the settings, so the window
    // opens the way it was left; the toggle at the bottom flips it.
    readonly property bool collapsed: appSettings.sideNavCollapsed
    readonly property int expandedWidth: 220
    readonly property int collapsedWidth: 64
    width: root.collapsed ? root.collapsedWidth : root.expandedWidth
    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    // Labels slide under the edge while it animates rather than spilling over the page.
    clip: true

    property string currentRoute: "dashboard"
    property bool modulesExpanded: currentRoute.indexOf("modules-") === 0

    // The module entries, once: the open panel lists them under "Modules", the folded one pops
    // them out from its icon. `exact` is for ESM, whose objects page is a route of its own that is
    // not the module's page.
    readonly property var moduleEntries: [
        { label: "EAP (Apps)", route: "modules-eap" },
        { label: "EAM (Access)", route: "modules-eam" },
        { label: "EKM (Keys)", route: "modules-ekm" },
        { label: "EKV (Key/Value)", route: "modules-ekv" },
        { label: "ENS (Topics)", route: "modules-ens" },
        { label: "EQS (Queues)", route: "modules-eqs" },
        { label: "ESM (Storage)", route: "modules-esm", exact: true },
        { label: "ESS (Secrets)", route: "modules-ess" },
        { label: "ETS (Transfer)", route: "modules-ets" },
        // Hosted DNS zones and the names euclid gives what it runs.
        { label: "EDS (DNS)", route: "modules-eds" },
        // The gateway in front of the EAP application pools. Administrators only, and the server
        // agrees: what it publishes is how this installation is reached from outside.
        { label: "EAG (Gateway)", route: "modules-eag", adminOnly: true },
        // The registry the other entries are rows of. Administrators only - how the installation
        // is put together is an operator's business.
        { label: "EMM (Modules)", route: "modules-emm", adminOnly: true }
    ]
    function moduleSelected(entry) {
        return entry.exact ? root.currentRoute === entry.route : root.currentRoute.indexOf(entry.route) === 0
    }
    signal navigate(string route)
    // The mark at the top asks for the About box. A signal rather than the dialog itself, for the
    // reason navigate() is one: the dialog belongs to the window, and this is a component that
    // knows nothing about what is in it.
    signal aboutRequested()

    Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 10
        spacing: 16

        // The fold, at the very top: one click in the same place whichever way the panel is - at
        // the right edge when open, centred over the icons when folded.
        Item {
            width: parent.width
            height: 28

            Rectangle {
                id: collapseToggle
                width: 28
                height: 28
                radius: 6
                anchors.verticalCenter: parent.verticalCenter
                x: root.collapsed ? (parent.width - width) / 2 : parent.width - width - 12
                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                color: collapseMouse.containsMouse ? "#22262f" : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: root.collapsed ? "»" : "«"
                    font.pixelSize: 16
                    color: collapseMouse.containsMouse ? "#4f8cff" : "#9aa1ac"
                }

                MouseArea {
                    id: collapseMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: appSettings.sideNavCollapsed = !appSettings.sideNavCollapsed
                }

                ToolTip.visible: collapseMouse.containsMouse
                ToolTip.text: root.collapsed ? "Expand navigation" : "Collapse navigation"
                ToolTip.delay: 400
            }
        }

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
            anchors.leftMargin: 17
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
                    opacity: root.collapsed ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: 120 } }
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
            anchors.leftMargin: root.collapsed ? 8 : 12
            anchors.rightMargin: root.collapsed ? 8 : 12
            spacing: 4

            NavButton {
                collapsed: root.collapsed
                icon: "⌂"
                label: "Dashboard"
                selected: root.currentRoute === "dashboard"
                onClicked: root.navigate("dashboard")
            }
            NavButton {
                collapsed: root.collapsed
                icon: "📈"
                label: "Analytics"
                selected: root.currentRoute === "analytics"
                onClicked: root.navigate("analytics")
            }
            NavButton {
                // EMO's alert states. Administrators only, as the server has it.
                collapsed: root.collapsed
                icon: "🔔"
                label: "Alerts"
                visible: euclidClient.isAdmin
                selected: root.currentRoute.indexOf("alerts") === 0
                onClicked: root.navigate("alerts")
            }

            Rectangle {
                width: parent.width
                height: 44
                radius: 10
                // Folded, there is no list below to show it is open, so the entry itself carries
                // the selection the way the other buttons do.
                color: root.collapsed && root.modulesExpanded ? "#2c3648"
                       : (modulesMouseArea.containsMouse ? "#22262f" : "transparent")
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
                    anchors.leftMargin: root.collapsed ? (parent.width - modulesIcon.width) / 2 : 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 14

                    Text {
                        id: modulesIcon
                        text: "▤"
                        font.pixelSize: 16
                        color: root.modulesExpanded ? "#4f8cff" : "#9aa1ac"
                    }
                    Text {
                        text: "Modules"
                        visible: !root.collapsed
                        font.pixelSize: 14
                        color: root.modulesExpanded ? "white" : "#c4c9d1"
                    }
                }

                Text {
                    visible: !root.collapsed
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
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.collapsed) modulesMenu.popup(parent, parent.width + 6, 0)
                        else root.modulesExpanded = !root.modulesExpanded
                    }
                }

                ToolTip.visible: root.collapsed && modulesMouseArea.containsMouse && !modulesMenu.visible
                ToolTip.text: "Modules"
                ToolTip.delay: 400

                // The folded panel's way to a module: the same entries as the list below, popped
                // out beside the icon. Parented to the window's overlay by Menu itself, so the
                // panel's clip does not cut it off.
                Menu {
                    id: modulesMenu
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"

                    Repeater {
                        model: root.moduleEntries.filter(e => !e.adminOnly || euclidClient.isAdmin)
                        MenuItem {
                            required property var modelData
                            text: modelData.label
                            checkable: true
                            checked: root.moduleSelected(modelData)
                            onTriggered: root.navigate(modelData.route)
                        }
                    }
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
                    height: root.modulesExpanded && !root.collapsed ? implicitHeight : 0

                    Repeater {
                        model: root.moduleEntries
                        SubNavButton {
                            required property var modelData
                            label: modelData.label
                            visible: !modelData.adminOnly || euclidClient.isAdmin
                            selected: root.moduleSelected(modelData)
                            onClicked: root.navigate(modelData.route)
                        }
                    }
                }
            }

            NavButton {
                collapsed: root.collapsed
                icon: "⚙"
                label: "Settings"
                selected: root.currentRoute === "settings"
                onClicked: root.navigate("settings")
            }
        }
    }

    Row {
        id: userRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.collapsed ? 14 : 18
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
            visible: !root.collapsed
            spacing: 1
            Text { text: "Jens Vogt"; color: "white"; font.pixelSize: 13 }
            Text { text: "Administrator"; color: "#9aa1ac"; font.pixelSize: 11 }
        }
    }
}
