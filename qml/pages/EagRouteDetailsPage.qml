import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// One published path: what it answers for, and what answers it.
//
// The route carries no address for the application - the gateway looks its instances up in the
// module registry when a request arrives, because the pool's ports are handed out at spawn time and
// change as it scales. So this page says which application, not where it is.
//
// A route may name a euclid module and one action on it instead of an application, which is the way
// in for something outside that needs euclid itself - a browser signing in, most of all. The two
// are mutually exclusive, so the tile below shows whichever one this route is.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string routeId: ""
    property var details: ({})

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    readonly property bool active: !!detail("active", false)
    readonly property string path: String(detail("path", "—"))
    readonly property string applicationId: String(detail("applicationId", "—"))
    readonly property string moduleTarget: String(detail("moduleTarget", ""))
    readonly property string moduleAction: String(detail("moduleAction", ""))
    // Which of the two kinds this is. Exactly one is ever set - see Entity::EAG::Route.
    readonly property bool moduleRoute: root.moduleTarget.length > 0
    readonly property string targetText: root.moduleRoute
        ? root.moduleTarget.toUpperCase() + " · " + root.moduleAction : root.applicationId
    readonly property string authentication: String(detail("authentication", "NONE"))
    readonly property var methods: detail("methods", [])
    readonly property string methodsText: !root.methods || root.methods.length === 0 ? "ALL" : root.methods.join(", ")

    property string actionNote: ""
    property string error: ""

    function refresh() {
        if (!root.loggedIn || root.routeId.length === 0)
            return
        eagClient.fetchRoute(root.routeId)
    }

    onVisibleChanged: if (visible) refresh()
    onRouteIdChanged: if (visible) refresh()

    Connections {
        target: eagClient
        function onRouteLoaded(routeId, route) {
            if (routeId !== root.routeId) return
            root.details = route
            root.error = ""
        }
        function onRouteUpdated(routeId, route) {
            if (routeId !== root.routeId) return
            root.details = route
            root.actionNote = route.active ? "Route is being served again." : "Route taken out of service."
        }
        function onRouteUpdateFailed(message) {
            root.error = message
        }
        function onRoutesFailed(message) {
            root.error = message
        }
        function onRouteDeleteFailed(message) {
            root.error = message
        }
        function onRouteDeleted(routeId) {
            // Nothing left to show; the list is where a deleted route's absence makes sense.
            if (routeId === root.routeId) root.back()
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
                text: "‹ Back to Routes"
                flat: true
                onClicked: root.back()
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.routeId
                    subtitle: "Published by the API gateway in the " + root.namespaceName + " namespace."
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: root.active ? "Disable" : "Enable"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: root.active ? "#ffb545" : "#4cd97b"
                        onClicked: root.active ? eagClient.disableRoute(root.routeId)
                                               : eagClient.enableRoute(root.routeId)
                    }
                    Button {
                        text: "Delete"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        onClicked: deleteDialog.open()
                    }
                }
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "State"
                    value: root.active ? "SERVED" : "DISABLED"
                    trend: root.active ? "answering requests" : "out of service, definition kept"
                    trendUp: root.active
                    accent: root.active ? "#4cd97b" : "#9aa1ac"
                }
                StatCard {
                    title: root.moduleRoute ? "Module" : "Application"
                    value: root.moduleRoute ? root.moduleTarget.toUpperCase() : root.applicationId
                    trend: root.moduleRoute ? "action: " + root.moduleAction : "application pool"
                    trendUp: true
                    accent: root.moduleRoute ? "#c56bff" : "#4f8cff"
                }
                StatCard {
                    title: "Methods"
                    value: root.methodsText
                    trend: !root.methods || root.methods.length === 0 ? "every method, now and later" : "only these"
                    trendUp: true
                    accent: "#4f8cff"
                }
                StatCard {
                    title: "Authentication"
                    value: root.authentication
                    // The public case is the one worth a second look, so it is the one coloured.
                    trend: root.authentication === "EUCLID" ? "checked by the gateway" : "forwarded as it arrives"
                    trendUp: root.authentication === "EUCLID"
                    accent: root.authentication === "EUCLID" ? "#4cd97b" : "#ffb545"
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

                    Text { text: "Identity"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.detail("accountId", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.detail("region", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Namespace"; value: root.detail("namespace", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    DetailField { width: identityCol.width; label: "Route name"; value: root.routeId; copyable: true }
                    DetailField { width: identityCol.width; label: "Route ERN"; value: root.detail("ern", "—"); copyable: true }
                }
            }

            Rectangle {
                width: parent.width
                height: routingCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: routingCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Text { text: "Routing"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 11
                        text: "The path is matched as a prefix, so everything beneath it is carried by this route. "
                              + "Where another route also matches, the longer path wins - which is how a narrower "
                              + "path can be carved out of this one later without either being rewritten."
                    }

                    DetailField { width: routingCol.width; label: "Path"; value: root.path; copyable: true }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField {
                            width: (routingCol.width - 48) / 3
                            // Named for what it actually is, rather than "Target" for both: an
                            // application pool and a module action are reached in different ways.
                            label: root.moduleRoute ? "Euclid module" : "Application"
                            value: root.targetText
                            copyable: true
                        }
                        DetailField { width: (routingCol.width - 48) / 3; label: "Methods"; value: root.methodsText }
                        DetailField { width: (routingCol.width - 48) / 3; label: "Authentication"; value: root.authentication }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.moduleRoute
                        text: "This route reaches euclid itself rather than an application: the request is forwarded "
                              + "to euclid's own gateway as \"" + root.moduleAction + "\" on the " + root.moduleTarget.toUpperCase()
                              + " module. One action per route, so nothing else that module can do is published here."
                        color: "#9aa1ac"
                        font.pixelSize: 11
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.authentication === "NONE"
                        text: "⚠ NONE means the gateway forwards requests as they arrive. Whatever this path reaches "
                              + "is as public as the gateway is, unless the application checks credentials itself."
                        color: "#e0a458"
                        font.pixelSize: 11
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#4cd97b"
                font.pixelSize: 12
                visible: root.actionNote.length > 0 && root.error.length === 0
                text: root.actionNote
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: root.error.length > 0
                text: root.error
            }
        }
    }

    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 440
        padding: 28
        standardButtons: Dialog.NoButton

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: deleteDialog.availableWidth
            spacing: 16

            Text { text: "Delete Route"; color: "white"; font.pixelSize: 18; font.bold: true }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "\"" + root.routeId + "\" serves " + root.path + ". Deleting it stops the gateway "
                      + "answering that path at all - callers get a 404. The application behind it keeps running. "
                      + "To stop serving it for a while and put it back exactly as it was, disable it instead."
                color: "#c4c9d1"
                font.pixelSize: 12
            }

            Item {
                width: parent.width
                height: 40

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Button {
                        text: "Cancel"
                        flat: true
                        Material.theme: Material.Dark
                        onClicked: deleteDialog.close()
                    }
                    Button {
                        text: "Delete"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        onClicked: {
                            eagClient.deleteRoute(root.routeId)
                            deleteDialog.close()
                        }
                    }
                }
            }
        }
    }
}
