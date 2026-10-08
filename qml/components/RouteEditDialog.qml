import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// The form that defines an EAG route, for creating one and for changing one - the fields are the
// same, and only the route name is fixed once a route exists, since that is what update-route
// addresses it by.
//
// One component rather than a copy per page: the route list creates and edits, the route details
// page edits, and a second copy of this form is a second set of rules about what a route may be.
// The caller supplies the applications to choose from and handles the answer; everything about
// the shape of a route is here.
//
// Note what is deliberately absent: a port. A route has none - it is published on whichever of the
// gateway's listeners carry its namespace, and those come from the installation's configuration,
// which the API only reads (list-listeners). Changing the port a path answers on is a change to
// the gateway, not to the route; see the note beside "Served".
Dialog {
    id: control

    // The applications a route may name, as ids. Supplied by the page, which is the one that knows
    // whether it has them - EAP's listing is a separate call from anything about routes.
    property var applicationChoices: []

    readonly property var httpMethods: ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]
    readonly property var moduleTargets: ["eam", "eap", "eag", "ees", "ekm", "emm", "emo", "ens", "eqs", "esm", "ets"]

    // The route being edited, or null when creating one.
    property var editing: null
    readonly property bool isEdit: control.editing !== null
    property bool saving: false
    property string errorText: ""
    // Which methods are ticked, as a map so a delegate can toggle one without rebuilding it.
    property var selectedMethods: ({})
    // Which kind of target the form is filling in: 0 = an application euclid runs, 1 = euclid
    // itself. Only one of the two is ever sent, which is what the server insists on.
    property int targetKind: 0

    function isModuleRoute(row) {
        return !!row && !!row.moduleTarget && String(row.moduleTarget).length > 0
    }

    function openForCreate() {
        control.editing = null
        control.errorText = ""
        control.saving = false
        routeIdField.text = ""
        pathField.text = "/"
        control.targetKind = 0
        applicationField.currentIndex = -1
        moduleField.currentIndex = -1
        moduleActionField.text = ""
        authenticationField.currentIndex = 0
        activeSwitch.checked = true
        control.selectedMethods = ({})
        control.open()
    }

    function openForEdit(row) {
        control.editing = row
        control.errorText = ""
        control.saving = false
        routeIdField.text = row.routeId
        pathField.text = row.path
        control.targetKind = control.isModuleRoute(row) ? 1 : 0
        applicationField.currentIndex = control.applicationChoices.indexOf(row.applicationId)
        moduleField.currentIndex = control.moduleTargets.indexOf(String(row.moduleTarget))
        moduleActionField.text = row.moduleAction ? String(row.moduleAction) : ""
        authenticationField.currentIndex = row.authentication === "EUCLID" ? 1 : 0
        activeSwitch.checked = !!row.active
        const picked = ({})
        for (const m of (row.methods || [])) picked[m] = true
        control.selectedMethods = picked
        control.open()
    }

    function methodList() {
        return control.httpMethods.filter(m => control.selectedMethods[m] === true)
    }

    // Refused here rather than by the server, since these are the ones it would refuse anyway and
    // the message reads better before the round trip.
    readonly property string problem: {
        if (routeIdField.text.trim().length === 0) return "A route needs a name."
        if (!pathField.text.trim().startsWith("/")) return "The path has to start with \"/\" - it is matched against a request target."
        if (control.targetKind === 0 && applicationField.currentIndex < 0)
            return "Pick the application that answers this path."
        if (control.targetKind === 1 && moduleField.currentIndex < 0)
            return "Pick the euclid module this path reaches."
        // The gateway dispatches on the action; without one the route would answer 400 for every
        // request it ever carries, which is why the server refuses it too.
        if (control.targetKind === 1 && moduleActionField.text.trim().length === 0)
            return "Name the one action this route publishes, e.g. \"login\"."
        return ""
    }

    function submit() {
        control.saving = true
        control.errorText = ""
        const methods = control.methodList()
        const authentication = authenticationField.currentIndex === 1 ? "EUCLID" : "NONE"
        const module = control.targetKind === 1
        const application = module ? "" : control.applicationChoices[applicationField.currentIndex]
        const moduleTarget = module ? control.moduleTargets[moduleField.currentIndex] : ""
        const moduleAction = module ? moduleActionField.text.trim() : ""

        if (control.isEdit) {
            // Only the side that applies is sent: applicationId clears the module fields
            // server-side and moduleTarget clears applicationId, so naming both would leave the
            // winner up to the order they happen to be read in.
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

    modal: true
    anchors.centerIn: parent
    width: 520
    padding: 28
    topPadding: 24
    bottomPadding: 24
    standardButtons: Dialog.NoButton

    background: Rectangle {
        radius: 16
        color: "#1b1e25"
        border.color: "#2c313c"
        border.width: 1
    }

    contentItem: Column {
        width: control.availableWidth
        spacing: 16

        Column {
            width: parent.width
            spacing: 4
            Text {
                text: control.isEdit ? "Edit Route" : "New Route"
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
                enabled: !control.isEdit
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
            // Only while editing: changing the path of a route that is already published is the
            // one change here that breaks callers, and nothing else on the form says so.
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: control.isEdit && control.editing
                         && pathField.text.trim() !== String(control.editing.path)
                text: "⚠ " + (control.editing ? String(control.editing.path) : "") + " stops being answered - "
                      + "callers still asking for it get a 404. The gateway re-reads its routes every few "
                      + "seconds, so neither the old path nor the new one changes the instant this is saved."
                color: "#e0a458"
                font.pixelSize: 11
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
                    checked: control.targetKind === 0
                    font.pixelSize: 12
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onToggled: if (checked) control.targetKind = 0
                }
                RadioButton {
                    text: "A euclid module"
                    checked: control.targetKind === 1
                    font.pixelSize: 12
                    Material.theme: Material.Dark
                    Material.accent: "#c56bff"
                    onToggled: if (checked) control.targetKind = 1
                }
            }

            ComboBox {
                id: applicationField
                width: parent.width
                visible: control.targetKind === 0
                model: control.applicationChoices
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
            }
            Text {
                visible: control.targetKind === 0 && control.applicationChoices.length === 0
                text: "No applications are deployed - a route needs one to answer it."
                color: "#ffb545"
                font.pixelSize: 11
            }

            // A module route is how something outside reaches euclid itself - a browser that has to
            // log in before it can call anything, most of all - without a second origin to call and
            // CORS in between.
            Row {
                width: parent.width
                spacing: 12
                visible: control.targetKind === 1

                ComboBox {
                    id: moduleField
                    width: (parent.width - 12) / 2
                    model: control.moduleTargets
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
                visible: control.targetKind === 1
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
                    model: control.httpMethods
                    delegate: CheckBox {
                        required property string modelData
                        text: modelData
                        checked: control.selectedMethods[modelData] === true
                        font.pixelSize: 12
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onToggled: {
                            // Reassigned rather than mutated: a JS object property change is not
                            // something QML bindings would see.
                            const picked = Object.assign({}, control.selectedMethods)
                            picked[modelData] = checked
                            control.selectedMethods = picked
                        }
                    }
                }
            }
            // The method set is half of what makes a route unique: the server refuses a path that
            // another route already carries for the same methods, so narrowing these is also how
            // two routes come to share one path.
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                visible: control.methodList().length > 0
                text: "Only " + control.methodList().join(", ") + " reach this route. Anything else on this path "
                      + "falls through to whatever other route matches, or 404s."
                color: "#6b7280"
                font.pixelSize: 11
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

        // Asked for often enough to be worth answering here: the port is not a property of the
        // route and cannot be set from this form. A route is carried by every listener whose
        // namespace matches, and the listeners are the gateway's own configuration - the API only
        // lists them. The route details page shows which ports a route is actually answered on.
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "A route has no port. It is published on whichever of the gateway's listeners carry its "
                  + "namespace; which ports those are is set in the installation's EAG configuration and "
                  + "takes a restart of the module, not an edit here."
            color: "#6b7280"
            font.pixelSize: 11
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
            visible: control.errorText.length > 0
            text: control.errorText
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
                text: control.problem
                color: "#ffb545"
                font.pixelSize: 11
                visible: control.problem.length > 0
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Button {
                    text: "Cancel"
                    flat: true
                    Material.theme: Material.Dark
                    onClicked: control.close()
                }
                Button {
                    text: control.saving ? "Saving…" : (control.isEdit ? "Save" : "Create")
                    highlighted: true
                    enabled: !control.saving && control.problem.length === 0
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: control.submit()
                }
            }
        }
    }
}
