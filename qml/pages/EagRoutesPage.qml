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

    // Every method the dialogs offer. Empty selection means "all", which is what the server
    // stores - see Entity::EAG::Route::methods.
    readonly property var httpMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

    // The euclid modules a route may be pointed at, the same set EagServer's kModuleTargets
    // holds. A module the server does not know is refused, so the dialog offers the list.
    readonly property var moduleTargets: ["eam", "eap", "eag", "ees", "ekm", "emm", "emo", "ens", "eqs", "esm", "ets"]

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

    readonly property var columns: [
        { title: "Route", key: "routeId", fill: true },
        { title: "Path", key: "path" },
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

    // Create and edit in one dialog: the fields are the same, and only routeId is fixed once a
    // route exists (it is what update-route addresses it by).
    Dialog {
        id: routeDialog
        modal: true
        anchors.centerIn: parent
        width: 520
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        // The route being edited, or null when creating one.
        property var editing: null
        readonly property bool isEdit: routeDialog.editing !== null
        property bool saving: false
        property string errorText: ""
        // Which methods are ticked, as a map so a delegate can toggle one without rebuilding it.
        property var selectedMethods: ({})
        // Which kind of target the form is filling in: 0 = an application euclid runs, 1 = euclid
        // itself. Only one of the two is ever sent, which is what the server insists on.
        property int targetKind: 0

        function openForCreate() {
            routeDialog.editing = null
            routeDialog.errorText = ""
            routeDialog.saving = false
            routeIdField.text = ""
            pathField.text = "/"
            routeDialog.targetKind = 0
            applicationField.currentIndex = -1
            moduleField.currentIndex = -1
            moduleActionField.text = ""
            authenticationField.currentIndex = 0
            activeSwitch.checked = true
            routeDialog.selectedMethods = ({})
            routeDialog.open()
        }

        function openForEdit(row) {
            routeDialog.editing = row
            routeDialog.errorText = ""
            routeDialog.saving = false
            routeIdField.text = row.routeId
            pathField.text = row.path
            routeDialog.targetKind = root.isModuleRoute(row) ? 1 : 0
            applicationField.currentIndex = root.applicationChoices.indexOf(row.applicationId)
            moduleField.currentIndex = root.moduleTargets.indexOf(String(row.moduleTarget))
            moduleActionField.text = row.moduleAction ? String(row.moduleAction) : ""
            authenticationField.currentIndex = row.authentication === "EUCLID" ? 1 : 0
            activeSwitch.checked = !!row.active
            const picked = ({})
            for (const m of (row.methods || [])) picked[m] = true
            routeDialog.selectedMethods = picked
            routeDialog.open()
        }

        function methodList() {
            return root.httpMethods.filter(m => routeDialog.selectedMethods[m] === true)
        }

        // Refused here rather than by the server, since these are the two it would refuse anyway
        // and the message reads better before the round trip.
        readonly property string problem: {
            if (routeIdField.text.trim().length === 0) return "A route needs a name."
            if (!pathField.text.trim().startsWith("/")) return "The path has to start with \"/\" - it is matched against a request target."
            if (routeDialog.targetKind === 0 && applicationField.currentIndex < 0)
                return "Pick the application that answers this path."
            if (routeDialog.targetKind === 1 && moduleField.currentIndex < 0)
                return "Pick the euclid module this path reaches."
            // The gateway dispatches on the action; without one the route would answer 400 for
            // every request it ever carries, which is why the server refuses it too.
            if (routeDialog.targetKind === 1 && moduleActionField.text.trim().length === 0)
                return "Name the one action this route publishes, e.g. \"login\"."
            return ""
        }

        function submit() {
            routeDialog.saving = true
            routeDialog.errorText = ""
            const methods = routeDialog.methodList()
            const authentication = authenticationField.currentIndex === 1 ? "EUCLID" : "NONE"
            const module = routeDialog.targetKind === 1
            const application = module ? "" : root.applicationChoices[applicationField.currentIndex]
            const moduleTarget = module ? root.moduleTargets[moduleField.currentIndex] : ""
            const moduleAction = module ? moduleActionField.text.trim() : ""

            if (routeDialog.isEdit) {
                // Only the side that applies is sent: applicationId clears the module fields
                // server-side and moduleTarget clears applicationId, so naming both would leave
                // the winner up to the order they happen to be read in.
                const changes = {
                    path: pathField.text.trim(),
                    methods: methods,
                    authentication: authentication,
                    active: activeSwitch.checked
                }
                if (module) {
                    changes.moduleTarget = moduleTarget
                    changes.moduleAction = moduleAction
                } else {
                    changes.applicationId = application
                }
                eagClient.updateRoute(routeIdField.text.trim(), changes)
            } else {
                eagClient.createRoute(routeIdField.text.trim(), pathField.text.trim(), application,
                                      moduleTarget, moduleAction, methods, authentication,
                                      activeSwitch.checked)
            }
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: routeDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: routeDialog.isEdit ? "Edit Route" : "New Route"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "The path is matched as a prefix, so \"/orders\" carries everything beneath it. "
                          + "Where two routes match, the longer path wins."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Route name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: routeIdField
                    width: parent.width
                    // The name addresses the route in every later call, so it cannot move.
                    enabled: !routeDialog.isEdit
                    placeholderText: "orders-api"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
            }

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Path"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: pathField
                    width: parent.width
                    placeholderText: "/orders"
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
            }

            Column {
                width: parent.width
                spacing: 6

                Text { text: "Answered by"; color: "#9aa1ac"; font.pixelSize: 12 }

                // One or the other, never both: that is the server's rule, so the form makes it a
                // choice rather than two fields that can contradict each other.
                Row {
                    spacing: 16
                    RadioButton {
                        text: "An application"
                        checked: routeDialog.targetKind === 0
                        font.pixelSize: 12
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onToggled: if (checked) routeDialog.targetKind = 0
                    }
                    RadioButton {
                        text: "A euclid module"
                        checked: routeDialog.targetKind === 1
                        font.pixelSize: 12
                        Material.theme: Material.Dark
                        Material.accent: "#c56bff"
                        onToggled: if (checked) routeDialog.targetKind = 1
                    }
                }

                ComboBox {
                    id: applicationField
                    width: parent.width
                    visible: routeDialog.targetKind === 0
                    model: root.applicationChoices
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
                Text {
                    visible: routeDialog.targetKind === 0 && root.applicationChoices.length === 0
                    text: "No applications are deployed - a route needs one to answer it."
                    color: "#ffb545"
                    font.pixelSize: 11
                }

                // A module route is how something outside reaches euclid itself - a browser that
                // has to log in before it can call anything, most of all - without a second origin
                // to call and CORS in between.
                Row {
                    width: parent.width
                    spacing: 12
                    visible: routeDialog.targetKind === 1

                    ComboBox {
                        id: moduleField
                        width: (parent.width - 12) / 2
                        model: root.moduleTargets
                        Material.theme: Material.Dark
                        Material.accent: "#c56bff"
                    }
                    TextField {
                        id: moduleActionField
                        width: (parent.width - 12) / 2
                        placeholderText: "action, e.g. login"
                        Material.theme: Material.Dark
                        Material.accent: "#c56bff"
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: routeDialog.targetKind === 1
                    text: "One action per route on purpose: a route that passed the rest of the path through "
                          + "as actions would publish everything the module has, including the ones that delete users."
                    color: "#6b7280"
                    font.pixelSize: 11
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Methods"; color: "#9aa1ac"; font.pixelSize: 12 }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "None ticked means every method, now and in future. Tick some only to carve a "
                          + "resource up between applications."
                    color: "#6b7280"
                    font.pixelSize: 11
                }
                Flow {
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: root.httpMethods
                        delegate: CheckBox {
                            required property string modelData
                            text: modelData
                            checked: routeDialog.selectedMethods[modelData] === true
                            font.pixelSize: 12
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onToggled: {
                                // Reassigned rather than mutated: a JS object property change is
                                // not something QML bindings would see.
                                const picked = Object.assign({}, routeDialog.selectedMethods)
                                picked[modelData] = checked
                                routeDialog.selectedMethods = picked
                            }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: 24

                Column {
                    width: (parent.width - 24) / 2
                    spacing: 4
                    Text { text: "Authentication"; color: "#9aa1ac"; font.pixelSize: 12 }
                    ComboBox {
                        id: authenticationField
                        width: parent.width
                        model: ["NONE", "EUCLID"]
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }

                Column {
                    width: (parent.width - 24) / 2
                    spacing: 8
                    Text { text: "Served"; color: "#9aa1ac"; font.pixelSize: 12 }
                    Row {
                        spacing: 8
                        ToggleSwitch {
                            id: activeSwitch
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: activeSwitch.checked ? "Answering" : "Out of service"
                            color: activeSwitch.checked ? "#4cd97b" : "#9aa1ac"
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            // What "NONE" actually means, said where the choice is made: the gateway forwards the
            // request as it arrives and whatever the application requires, it enforces itself.
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: authenticationField.currentIndex === 0
                text: "⚠ With NONE the gateway forwards requests unauthenticated. Anything this path "
                      + "reaches is as public as the gateway is, unless the application checks for itself."
                color: "#e0a458"
                font.pixelSize: 11
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: routeDialog.errorText.length > 0
                text: routeDialog.errorText
                color: "#ff6b6b"
                font.pixelSize: 12
            }

            Item {
                width: parent.width
                height: 40

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 200
                    wrapMode: Text.WordWrap
                    text: routeDialog.problem
                    color: "#ffb545"
                    font.pixelSize: 11
                    visible: routeDialog.problem.length > 0
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Button {
                        text: "Cancel"
                        flat: true
                        Material.theme: Material.Dark
                        onClicked: routeDialog.close()
                    }
                    Button {
                        text: routeDialog.saving ? "Saving…" : (routeDialog.isEdit ? "Save" : "Create")
                        highlighted: true
                        enabled: !routeDialog.saving && routeDialog.problem.length === 0
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: routeDialog.submit()
                    }
                }
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

            Button {
                text: "‹ Back to EAG Dashboard"
                flat: true
                onClicked: root.back()
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
        }
    }
}
