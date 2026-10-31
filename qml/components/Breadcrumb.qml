import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// Where you are, and the way back out of it - in place of the "‹ Back to X" button every page used
// to open with.
//
// The whole trail, not one step of it: "Home › EAP › Applications › file-copy". Everything but the
// last segment is a link, and the last is the page you are on - clicking it would reload what is
// already in front of you.
//
// A page supplies only its own name (`leaf`), because that is the only part of the trail it knows:
// an application's id, a bucket's name, a message's id. Everything above comes from the route the
// window is on, through the table below - so every page's trail is built the same way and a page
// cannot drift into describing a path that does not exist.
//
// `segments` is still there for a trail the table cannot express; nothing uses it, and a page that
// reaches for it should ask whether the route table is wrong instead.
Item {
    id: root

    // The page's own name, the last segment. Empty for a page whose name is already in the table -
    // a listing is "Applications" whichever application you came from.
    property string leaf: ""

    // [{ label: string, action: function|undefined }] - in order, outermost first. Overrides the
    // trail the route would have produced.
    property var segments: []

    // Route -> { label, parent }. The label is what a crumb for that route reads; a route with none
    // is a page named by whatever it is showing, which is what `leaf` supplies. The parent is the
    // page above it, which is not always the page you arrived from: a message's trail goes up
    // through its topic's list whether you came from there or from a search.
    readonly property var routeTree: ({
        "dashboard": { label: "Home" },
        "analytics": { label: "Analytics", parent: "dashboard" },
        "alerts": { label: "Alerts", parent: "dashboard" },
        "settings": { label: "Settings", parent: "dashboard" },

        "modules-emm": { label: "Modules", parent: "dashboard" },
        "modules-emm-details": { parent: "modules-emm" },

        "modules-eam": { label: "EAM", parent: "dashboard" },
        "modules-eam-accounts": { label: "Accounts", parent: "modules-eam" },
        "modules-eam-account-details": { parent: "modules-eam-accounts" },
        "modules-eam-namespaces": { label: "Namespaces", parent: "modules-eam" },
        "modules-eam-namespace-details": { parent: "modules-eam-namespaces" },
        "modules-eam-users": { label: "Users", parent: "modules-eam" },
        "modules-eam-user-details": { parent: "modules-eam-users" },
        "modules-eam-user-groups": { label: "User Groups", parent: "modules-eam" },
        "modules-eam-user-group-details": { parent: "modules-eam-user-groups" },
        "modules-eam-roles": { label: "Roles", parent: "modules-eam" },
        "modules-eam-role-details": { parent: "modules-eam-roles" },

        "modules-eap": { label: "EAP", parent: "dashboard" },
        "modules-eap-applications": { label: "Applications", parent: "modules-eap" },
        "modules-eap-application-details": { parent: "modules-eap-applications" },
        "modules-eap-nodes": { label: "Worker Nodes", parent: "modules-eap" },
        "modules-eap-node-details": { parent: "modules-eap-nodes" },

        "modules-eag": { label: "EAG", parent: "dashboard" },
        "modules-eag-routes": { label: "Routes", parent: "modules-eag" },
        "modules-eag-route-details": { parent: "modules-eag-routes" },
        "modules-eag-listeners": { label: "Listeners", parent: "modules-eag" },

        "modules-ekm": { label: "EKM", parent: "dashboard" },
        "modules-ekm-keys": { label: "Keys", parent: "modules-ekm" },
        "modules-ekm-key-details": { parent: "modules-ekm-keys" },
        "modules-ekm-certificates": { label: "Certificates", parent: "modules-ekm" },
        "modules-ekm-certificate-details": { parent: "modules-ekm-certificates" },

        "modules-ekv": { label: "EKV", parent: "dashboard" },
        "modules-ekv-tables": { label: "Tables", parent: "modules-ekv" },
        "modules-ekv-table-details": { parent: "modules-ekv-tables" },

        "modules-ens": { label: "ENS", parent: "dashboard" },
        "modules-ens-topics": { label: "Topics", parent: "modules-ens" },
        "modules-ens-topic-details": { parent: "modules-ens-topics" },
        // Under the topic listing rather than under one topic's details: the messages are reached
        // by opening a topic, and its details page is a sibling of them rather than their parent.
        //
        // The label is only ever read from above - a message's trail says "Messages" where the
        // page itself says which topic's. Clicking it returns to the topic still selected.
        "modules-ens-messages": { label: "Messages", parent: "modules-ens-topics" },
        "modules-ens-message-details": { parent: "modules-ens-messages" },

        "modules-eqs": { label: "EQS", parent: "dashboard" },
        "modules-eqs-queues": { label: "Queues", parent: "modules-eqs" },
        "modules-eqs-queue-details": { parent: "modules-eqs-queues" },
        "modules-eqs-messages": { label: "Messages", parent: "modules-eqs-queues" },
        "modules-eqs-message-details": { parent: "modules-eqs-messages" },

        "modules-esm": { label: "ESM", parent: "dashboard" },
        "modules-esm-buckets": { label: "Buckets", parent: "modules-esm" },
        "modules-esm-bucket-details": { parent: "modules-esm-buckets" },
        "modules-esm-objects": { label: "Objects", parent: "modules-esm-buckets" },
        "modules-esm-object-details": { parent: "modules-esm-objects" },

        "modules-ess": { label: "ESS", parent: "dashboard" },
        "modules-ess-secrets": { label: "Secrets", parent: "modules-ess" },
        "modules-ess-secret-details": { parent: "modules-ess-secrets" },

        "modules-ets": { label: "ETS", parent: "dashboard" },
        "modules-ets-servers": { label: "Transfer Servers", parent: "modules-ets" },
        "modules-ets-server-details": { parent: "modules-ets-servers" }
    })

    // The route's ancestors, outermost first, each as a crumb that navigates to it. An ancestor
    // whose label the table does not carry is skipped rather than drawn empty - that is a route
    // named by what it shows, and from above it there is nothing useful to call it.
    readonly property var routeTrail: {
        const trail = []
        let route = Nav.current
        const entry = root.routeTree[route]
        // A page the table does not know gets whatever it supplied and nothing invented around it.
        if (entry === undefined) return trail

        // Upwards from the parent: the current route is the page itself and is added by `crumbs`.
        let at = entry.parent
        let guard = 0
        while (at !== undefined && root.routeTree[at] !== undefined && guard++ < 10) {
            const node = root.routeTree[at]
            if (node.label !== undefined) {
                // Captured per iteration: the closure below outlives the loop.
                const target = at
                trail.unshift({ label: node.label, action: () => Nav.go(target) })
            }
            at = node.parent
        }
        return trail
    }

    // What is drawn: an explicit trail if one was given, otherwise the route's ancestors plus this
    // page. The page's own crumb is the leaf it supplied, or the name the table has for its route.
    readonly property var crumbs: {
        if (root.segments.length > 0) return root.segments
        const entry = root.routeTree[Nav.current]
        const own = root.leaf.length > 0 ? root.leaf
                    : (entry !== undefined && entry.label !== undefined ? entry.label : "")
        if (own.length === 0) return root.routeTrail
        return root.routeTrail.concat([{ label: own }])
    }

    implicitHeight: Math.max(20, crumbRow.implicitHeight)
    height: implicitHeight

    Row {
        id: crumbRow
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Repeater {
            model: root.crumbs

            delegate: Row {
                id: segment
                required property var modelData
                required property int index

                spacing: 8

                readonly property bool linked: !!segment.modelData.action
                                               && segment.index < root.crumbs.length - 1

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // Only between segments, so the trail does not open with a stray separator.
                    visible: segment.index > 0
                    text: "›"
                    color: "#4a5160"
                    font.pixelSize: 13
                }

                Text {
                    id: segmentLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: segment.modelData.label
                    // The page you are on is stated, not offered: clicking it would reload what is
                    // already in front of you.
                    color: !segment.linked ? "#e5e7eb"
                           : (segmentArea.containsMouse ? "#4f8cff" : "#9aa1ac")
                    font.pixelSize: 13
                    font.bold: segment.index === root.crumbs.length - 1
                    elide: Text.ElideRight
                    // Long enough for an object key or an ERN-ish name without pushing the rest of
                    // the trail off the page.
                    width: Math.min(implicitWidth, 420)

                    MouseArea {
                        id: segmentArea
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: segment.linked
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: segment.modelData.action()
                    }
                }
            }
        }
    }
}
