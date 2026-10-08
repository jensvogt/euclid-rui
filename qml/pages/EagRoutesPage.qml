import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// EAG: the paths the API gateway publishes, and what answers behind each of them.
//
// A route is a path *prefix*, so one row usually covers a whole REST resource rather than a single
// operation, and the longest matching route wins. Two routes may share a path as long as their
// methods do not overlap - that is how reads and writes of the same resource can be served by
// different applications without the caller seeing a seam.
//
// What answers is either an application euclid runs or euclid itself - a route may name a module
// and one action on it instead, which is how a browser reaches "login" without a second origin to
// call. Exactly one of the two; the server refuses both and refuses neither.
//
// Administrators only, and this time the server agrees: every EAG action requires it, because
// publishing a path decides what the outside world can reach.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    // Everything "list-routes" returned, and the prefix the table filters it by. The action does
    // take a prefix, so unlike EMM this filter is sent rather than applied here.
    property var routes: []
    property string prefix: ""
    readonly property int totalCount: root.routes.length
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    readonly property bool isAdmin: euclidClient.isAdmin

    // What the last action did. Kept next to the table because a route change takes effect on the
    // gateway's next request rather than visibly here.
    property string actionNote: ""

    signal back()
    signal openRouteDetails(string routeId, var details)

    // The applications a route can point at. EAG refuses a route to an application that does not
    // exist, so the dialogs offer the list rather than a free-text field that fails on save.
    property var applicationChoices: []

    // The gateway's listeners, which is where a route's port and protocol come from: a route has
    // neither of its own. EAG binds one listener per euclid.modules.eag.listeners entry and every
    // listener serves out of the same routing table, so what a route is reachable on is whichever
    // listeners carry it.
    property var listeners: []
    // Kept apart from root.error, the way the instances list is on the application details page: a
    // routing table that reads fine while the listeners cannot be asked for is still worth showing,
    // and putting this in the page's error line would make the whole page look broken.
    property string listenersError: ""

    // Which listeners carry a route, following RouteTable::matchIn: one bound to a namespace serves
    // that namespace's routes and those that name none, and one bound to nothing serves every route
    // there is. Port order, because that is how somebody has them in front of them.
    function listenersFor(row) {
        if (!row) return []
        const routeNamespace = String(row["namespace"] || "")
        return root.listeners.filter(function (listener) {
            const listenerNamespace = String(listener["namespace"] || "")
            return listenerNamespace.length === 0 || routeNamespace.length === 0
                   || listenerNamespace === routeNamespace
        }).sort((a, b) => Number(a.port) - Number(b.port))
    }

    function portText(row) {
        const matched = root.listenersFor(row)
        return matched.length === 0 ? "—" : matched.map(l => l.port).join(", ")
    }

    // One entry per distinct protocol rather than one per listener: two HTTP ports carrying the
    // same route say "HTTP" once, and a route on both an HTTP and an HTTPS port is the case worth
    // seeing spelled out.
    function protocolText(row) {
        const matched = root.listenersFor(row)
        if (matched.length === 0) return "—"
        const distinct = []
        for (const listener of matched) {
            const protocol = String(listener.protocol).toUpperCase()
            if (distinct.indexOf(protocol) < 0) distinct.push(protocol)
        }
        return distinct.join(", ")
    }

    // What a row answers with: an application pool, or one action on a euclid module.
    function targetText(row) {
        if (!row) return "—"
        if (row.moduleTarget && String(row.moduleTarget).length > 0)
            return String(row.moduleTarget).toUpperCase() + " · " + row.moduleAction
        return row.applicationId
    }

    function isModuleRoute(row) {
        return !!row && !!row.moduleTarget && String(row.moduleTarget).length > 0
    }

    function methodsText(methods) {
        return !methods || methods.length === 0 ? "ALL" : methods.join(", ")
    }

    function stateColor(row) {
        return row && row.active ? "#4cd97b" : "#9aa1ac"
    }

    readonly property var columns: {
        // Read so this rebuilds when the listeners arrive. DataTable measures its columns from what
        // the formatters return at the moment "columns" or "rows" changes, and the two below are
        // computed from the listeners rather than from the row - without this they would keep the
        // width of the "—" they were first sized from.
        root.listeners

        return [
        { title: "Route", key: "routeId", fill: true },
        { title: "Path", key: "path" },
        {
            // Derived from the listeners, so there is no field on the row to sort on - and ordering
            // routes by a port most of them share would say nothing anyway.
            title: "Port",
            formatter: function (v, row) { return root.portText(row) },
            colorFor: function (v, row) {
                const matched = root.listenersFor(row)
                if (matched.length === 0) return "#9aa1ac"
                // Configured but not bound - the port was taken, or its certificate would not load.
                // The route is published and still unreachable, which is worth the same red the
                // listeners page gives it.
                return matched.some(l => l.serving) ? "#c4c9d1" : "#ff4f5e"
            }
        },
        {
            title: "Protocol",
            formatter: function (v, row) { return root.protocolText(row) },
            // Same reading as the listeners page: the plain-text port is the one worth noticing.
            colorFor: function (v, row) {
                const matched = root.listenersFor(row)
                if (matched.length === 0) return "#9aa1ac"
                return matched.every(l => l.https) ? "#4cd97b" : "#ffb545"
            }
        },
        {
            // One column for both kinds: an application pool, or "EAM · login" for a route into
            // euclid itself. Which it is matters more than which field it came from.
            title: "Target",
            key: "applicationId",
            sortable: false,
            formatter: function (v, row) { return root.targetText(row) },
            colorFor: function (v, row) { return root.isModuleRoute(row) ? "#c56bff" : "#c4c9d1" }
        },
        {
            title: "Methods",
            key: "methods",
            sortable: false,
            formatter: function (v) { return root.methodsText(v) },
            // "ALL" is a decision not to restrict, so it is not highlighted as though it were a
            // narrower setting than it is.
            colorFor: function (v) { return !v || v.length === 0 ? "#9aa1ac" : "#c4c9d1" }
        },
        {
            title: "Auth",
            key: "authentication",
            // A public path is the one worth noticing in a list of them.
            colorFor: function (v) { return v === "EUCLID" ? "#4cd97b" : "#ffb545" }
        },
        {
            title: "State",
            key: "active",
            formatter: function (v) { return v ? "SERVED" : "DISABLED" },
            colorFor: function (v, row) { return root.stateColor(row) }
        },
        { title: "Created", key: "created", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Modified", key: "modified", formatter: function (v) { return DateFormat.format(v) } },
        { title: "Ern", key: "ern", hidden: true }
        ]
    }

    function refresh() {
        if (!root.loggedIn) {
            root.error = "Sign in to view routes."
            return
        }
        if (!root.isAdmin) {
            root.error = "Listing gateway routes requires administrator access."
            return
        }
        root.loading = true
        root.error = ""
        eagClient.fetchRoutes(root.prefix)
        // Where the Port and Protocol columns come from. A handful of ports at most, and they only
        // change when the module restarts, but they are read with the routes rather than once: this
        // page is open exactly when somebody is asking what is reachable.
        eagClient.fetchListeners()
        // For the dialogs' application picker; harmless while nothing is open, and it means the
        // list is already there when one is.
        eapClient.fetchApplications("")
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Live updates are off by default: a table that reloads while it is being read
        // moves rows out from under the pointer. See AppSettings::liveListUpdates().
        running: appSettings.liveListUpdates && appSettings.autoRefreshSeconds > 0
                 && root.visible && root.loggedIn && root.isAdmin
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: eagClient
        function onRoutesLoaded(list, total) {
            root.loading = false
            root.error = ""
            // Name order: "list-routes" returns them in whatever order they were written, and a
            // routing table is read by name.
            root.routes = list.slice().sort((a, b) => String(a.routeId).localeCompare(String(b.routeId)))
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onRoutesFailed(message) {
            root.loading = false
            root.error = message
        }
        function onRoutesReload() {
            root.refresh()
        }
        function onListenersLoaded(list, total, serving) {
            root.listenersError = ""
            root.listeners = list
        }
        function onListenersFailed(message) {
            // The routing table is still on screen and still correct; only the two columns computed
            // from the listeners are empty, which is said under the table rather than over it.
            root.listeners = []
            root.listenersError = message
        }
        function onRouteCreated(routeId) {
            routeDialog.saving = false
            routeDialog.close()
            root.actionNote = "Route '" + routeId + "' created. The gateway serves it from its next request."
        }
        function onRouteCreateFailed(message) {
            routeDialog.saving = false
            routeDialog.errorText = message
        }
        function onRouteUpdated(routeId, route) {
            routeDialog.saving = false
            if (routeDialog.opened) routeDialog.close()
            root.actionNote = "Route '" + routeId + "' updated"
                              + (route && route.active === false ? " and taken out of service." : ".")
        }
        function onRouteUpdateFailed(message) {
            routeDialog.saving = false
            routeDialog.errorText = message
            root.actionNote = ""
            root.error = message
        }
        function onRouteDeleted(routeId) {
            root.actionNote = "Route '" + routeId + "' deleted. Callers of its path get a 404 from now on."
        }
        function onRouteDeleteFailed(message) {
            root.error = message
        }
    }

    Connections {
        target: eapClient
        function onApplicationsLoaded(list, total) {
            root.applicationChoices = list.map(a => a.applicationId)
        }
    }

    // Create and edit in one dialog, and the same dialog the route details page edits with: the
    // fields are the same, and only routeId is fixed once a route exists (it is what update-route
    // addresses it by). See components/RouteEditDialog.qml.
    RouteEditDialog {
        id: routeDialog
        applicationChoices: root.applicationChoices
    }

    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 440
        padding: 28
        standardButtons: Dialog.NoButton

        property var route: null

        function openFor(row) {
            deleteDialog.route = row
            deleteDialog.open()
        }

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
                text: deleteDialog.route
                      ? "\"" + deleteDialog.route.routeId + "\" serves " + deleteDialog.route.path
                        + ". Deleting it stops the gateway answering that path at all - callers get a 404 "
                        + "rather than a refusal. The application behind it is untouched and keeps running."
                      : ""
                color: "#c4c9d1"
                font.pixelSize: 12
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: "To stop serving it for a while and put it back exactly as it was, disable it instead."
                color: "#9aa1ac"
                font.pixelSize: 11
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
                            eagClient.deleteRoute(deleteDialog.route.routeId)
                            deleteDialog.close()
                        }
                    }
                }
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
            spacing: 20

            Breadcrumb {
                width: parent.width
                segments: [
                    { label: "EAG", action: () => root.back() },
                    { label: "Routes" }
                ]
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: "Routes (" + root.totalCount + ")"
                    subtitle: "Paths the gateway publishes, and the application answering beneath each one."
                }

                Button {
                    text: "+ Add Route"
                    highlighted: true
                    visible: root.isAdmin
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: routeDialog.openForCreate()
                }
            }

            // Shown instead of the table rather than beside it: an empty table under a permission
            // message reads like there are no routes.
            Rectangle {
                width: parent.width
                height: 120
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                visible: !root.isAdmin

                Text {
                    anchors.centerIn: parent
                    width: parent.width - 48
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: "The gateway's routing table is only shown to administrators."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }

            DataTable {
                width: parent.width
                visible: root.isAdmin
                columns: root.columns
                rows: root.routes
                totalCount: root.totalCount
                // One page: "list-routes" returns every route at once, so there is no size to pick.
                pageSizeSelectable: false
                pageSize: root.totalCount > 0 ? root.totalCount : 1
                pageIndex: 0
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by route name prefix..."
                emptyText: root.prefix.length > 0 ? "No route matches that name." : "No routes published."
                rowsClickable: true
                onRowClicked: (row) => root.openRouteDetails(row.routeId, row)
                onSearchChanged: (text) => {
                    root.prefix = text
                    root.refresh()
                }
                onRefreshRequested: root.refresh()

                contextMenuActions: [
                    {
                        text: "Details",
                        action: function(row) { root.openRouteDetails(row.routeId, row) }
                    },
                    {
                        text: "Edit…",
                        action: function(row) { routeDialog.openForEdit(row) }
                    },
                    {
                        text: "Enable",
                        enabled: function(row) { return !!row && !row.active },
                        action: function(row) { eagClient.enableRoute(row.routeId) }
                    },
                    {
                        text: "Disable",
                        enabled: function(row) { return !!row && row.active },
                        action: function(row) { eagClient.disableRoute(row.routeId) }
                    },
                    {
                        text: "Delete…",
                        action: function(row) { deleteDialog.openFor(row) }
                    }
                ]
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#4cd97b"
                font.pixelSize: 12
                visible: root.isAdmin && root.actionNote.length > 0
                text: root.actionNote
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ffb545"
                font.pixelSize: 12
                visible: root.isAdmin && root.listenersError.length > 0
                text: "The gateway's listeners could not be read, so Port and Protocol are empty: "
                      + root.listenersError
            }
        }
    }
}
