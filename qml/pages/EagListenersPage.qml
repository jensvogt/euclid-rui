import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// EAG: the ports the gateway answers on, what each of them speaks, and the certificate an HTTPS
// one terminates TLS with.
//
// Read-only, because they are read-only server-side. A listener comes out of
// euclid.modules.eag.listeners and is fixed until the module restarts, so there is nothing here to
// save - a port that could be moved or switched to HTTPS through this page would be a way to take
// an installation off the network with one click.
//
// What the page is for is the question nothing else answers: which port speaks what, and whether
// the certificate behind an HTTPS one is somebody's or the self-signed stopgap euclid minted when
// the listener first came up. Certificates are EKM's, so replacing one happens on the certificates
// page and this links there.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""

    // Everything "list-listeners" returned, and the text the table filters it by. The action takes
    // no arguments and has no paging - an installation has a handful of ports at most - so the
    // filter is applied here rather than sent.
    property var listeners: []
    property string filter: ""
    // Whether the ports are actually bound. Not the same question as whether any were configured:
    // one whose port was taken, or whose certificate would not load, is still listed.
    property bool serving: false
    property bool loading: false
    property string error: ""
    property string lastUpdatedText: "—"

    // Sorted here rather than by the server: "list-listeners" returns every listener at once and
    // has no sort to ask for, so the alternative would be headers that look clickable and are not.
    property string sortColumn: "port"
    property bool sortAscending: true

    readonly property bool isAdmin: euclidClient.isAdmin

    signal back()
    // Carries the certificate the listener names, so the certificates page can open on it.
    signal openCertificates(string certificateName)

    readonly property var filteredListeners: {
        const needle = root.filter.toLowerCase()
        const matched = needle.length === 0 ? root.listeners.slice() : root.listeners.filter(l =>
            String(l["namespace"]).toLowerCase().indexOf(needle) >= 0
            || String(l.port).indexOf(needle) >= 0
            || String(l.protocol).toLowerCase().indexOf(needle) >= 0
            || String(l.certificate).toLowerCase().indexOf(needle) >= 0)

        const key = root.sortColumn
        const direction = root.sortAscending ? 1 : -1
        return matched.sort((a, b) => {
            const left = a[key]
            const right = b[key]
            // Ports compare as numbers; everything else the table sorts on is a string or a bool,
            // and comparing those as text is what puts them in the order somebody expects.
            if (typeof left === "number" && typeof right === "number") return (left - right) * direction
            return String(left).localeCompare(String(right)) * direction
        })
    }

    readonly property int httpsCount: root.listeners.filter(l => l.https).length

    // A listener naming no namespace carries every route, which is what a single-listener
    // installation gets - said in words rather than left as an empty cell.
    function namespaceText(row) {
        return row && String(row["namespace"]).length > 0 ? String(row["namespace"]) : "all namespaces"
    }

    // Whether this session can look this listener's certificate up. Certificates are scoped to a
    // namespace like every other named resource, and every request carries the one the session is
    // working in - so a listener bound to another namespace, or to none, holds its certificate
    // somewhere this session cannot ask about. The gateway reads them all because it is the
    // process that owns them; a client only ever sees one namespace at a time.
    function certificateReachable(row) {
        return !!row && row.https && String(row["namespace"]) === root.namespaceName
    }

    // Days until the certificate stops being accepted, or NaN when there is nothing to count.
    function daysLeft(row) {
        if (!row || !row.certificateFound || !row.certificateNotAfter) return NaN
        const notAfter = new Date(row.certificateNotAfter)
        if (isNaN(notAfter.getTime())) return NaN
        return Math.floor((notAfter.getTime() - Date.now()) / 86400000)
    }

    // What the certificate column says, which is a different question per listener kind: an HTTP
    // port has no certificate to be missing, and saying "none" for it would read as a fault.
    function certificateText(row) {
        if (!row || !row.https) return "—"
        if (!row.certificateFound) return String(row.certificate) + " (missing)"
        return String(row.certificate)
    }

    function certificateColor(row) {
        if (!row || !row.https) return "#9aa1ac"
        // Missing or expired first: both mean the port is not working for anybody, whoever issued
        // what it was meant to serve.
        if (!row.certificateFound || row.certificateExpired) return "#ff4f5e"
        const days = root.daysLeft(row)
        if (!isNaN(days) && days < 30) return "#ffb545"
        // Self-signed is not broken, but it is refused by every client that has not been told
        // about it - worth a colour of its own rather than the same green as a real one.
        return row.certificateGenerated ? "#ffb545" : "#4cd97b"
    }

    function expiryText(row) {
        if (!row || !row.https) return "—"
        if (!row.certificateFound) return "no certificate"
        const days = root.daysLeft(row)
        if (isNaN(days)) return DateFormat.format(row.certificateNotAfter)
        if (days < 0) return "expired " + (-days) + " d ago"
        return DateFormat.format(row.certificateNotAfter) + " (" + days + " d)"
    }

    readonly property var columns: [
        {
            title: "Namespace",
            key: "namespace",
            fill: true,
            formatter: function (v, row) { return root.namespaceText(row) },
            colorFor: function (v) { return String(v).length > 0 ? "#c4c9d1" : "#9aa1ac" }
        },
        { title: "Port", key: "port" },
        {
            title: "Protocol",
            key: "protocol",
            formatter: function (v) { return String(v).toUpperCase() },
            // The plain-text port is the one worth noticing in a list of them.
            colorFor: function (v) { return v === "https" ? "#4cd97b" : "#ffb545" }
        },
        {
            title: "State",
            key: "serving",
            formatter: function (v) { return v ? "BOUND" : "NOT BOUND" },
            colorFor: function (v) { return v ? "#4cd97b" : "#ff4f5e" }
        },
        {
            title: "Certificate",
            key: "certificate",
            sortable: false,
            formatter: function (v, row) { return root.certificateText(row) },
            colorFor: function (v, row) { return root.certificateColor(row) }
        },
        {
            title: "Issued by",
            key: "certificateGenerated",
            sortable: false,
            formatter: function (v, row) {
                if (!row || !row.https || !row.certificateFound) return "—"
                return v ? "euclid (self-signed)" : String(row.certificateIssuer)
            },
            colorFor: function (v, row) {
                return row && row.https && row.certificateFound && v ? "#ffb545" : "#c4c9d1"
            }
        },
        {
            // Sortable on the raw ISO timestamp, which sorts chronologically as text - and expiry
            // is the one column somebody actually wants ordered.
            title: "Expires",
            key: "certificateNotAfter",
            formatter: function (v, row) { return root.expiryText(row) },
            colorFor: function (v, row) { return root.certificateColor(row) }
        }
    ]

    function refresh() {
        if (!root.loggedIn) {
            root.error = "Sign in to view listeners."
            return
        }
        if (!root.isAdmin) {
            root.error = "Listing the gateway's listeners requires administrator access."
            return
        }
        root.loading = true
        root.error = ""
        eagClient.fetchListeners()
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
        function onListenersLoaded(list, total, serving) {
            root.loading = false
            root.error = ""
            // Kept in the order the gateway read them; filteredListeners puts them in port order,
            // which is how somebody reading a firewall rule has them in front of them.
            root.listeners = list
            root.serving = serving
            root.lastUpdatedText = Qt.formatDateTime(new Date(), "hh:mm:ss")
        }
        function onListenersFailed(message) {
            root.loading = false
            root.error = message
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
                    title: "Listeners (" + root.listeners.length + ")"
                    subtitle: "Ports the gateway answers on, and what each of them speaks."
                }

                Button {
                    text: "Certificates"
                    visible: root.isAdmin
                    flat: true
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: root.openCertificates("")
                }
            }

            // Shown instead of the table rather than beside it: an empty table under a permission
            // message reads like there are no listeners.
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
                    text: "The gateway's listeners are only shown to administrators."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }

            // The gateway is up but nothing is bound: a port was taken, or a certificate would not
            // load. Said above the table, because every row below it is then a description of what
            // is not happening.
            Rectangle {
                width: parent.width
                height: notServingText.implicitHeight + 32
                radius: 14
                color: "#2a1f1f"
                border.color: "#5a3535"
                border.width: 1
                visible: root.isAdmin && !root.loading && root.listeners.length > 0 && !root.serving

                Text {
                    id: notServingText
                    anchors.centerIn: parent
                    width: parent.width - 40
                    wrapMode: Text.WordWrap
                    text: "⚠ None of these ports is bound. The module is running and its routes can still be "
                          + "managed, but nothing is being served - a port was already taken, or an HTTPS "
                          + "listener's certificate could not be loaded. The gateway's log says which."
                    color: "#ff8f8f"
                    font.pixelSize: 12
                }
            }

            DataTable {
                width: parent.width
                visible: root.isAdmin
                columns: root.columns
                rows: root.filteredListeners
                totalCount: root.filteredListeners.length
                // One page: "list-listeners" returns every listener at once, so there is no size
                // to pick.
                pageSizeSelectable: false
                pageSize: root.filteredListeners.length > 0 ? root.filteredListeners.length : 1
                pageIndex: 0
                loading: root.loading
                error: root.error
                lastUpdatedText: root.lastUpdatedText
                searchPlaceholder: "Filter by namespace, port, protocol or certificate..."
                emptyText: root.filter.length > 0
                           ? "No listener matches that."
                           : "The gateway has no usable listener - see its log."
                rowsClickable: false
                sortKey: root.sortColumn
                sortAscending: root.sortAscending
                onSearchChanged: (text) => { root.filter = text }
                onRefreshRequested: root.refresh()
                onSortRequested: (key, ascending) => {
                    root.sortColumn = key
                    root.sortAscending = ascending
                }

                contextMenuActions: [
                    {
                        text: "Open certificate…",
                        // Only for a listener in the namespace this session is working in - see
                        // certificateReachable(). Offering it otherwise would open a details page
                        // that could only answer "not found".
                        enabled: function(row) { return root.certificateReachable(row) },
                        action: function(row) { root.openCertificates(String(row.certificate)) }
                    },
                    {
                        text: "Copy fingerprint",
                        enabled: function(row) { return !!row && row.certificateFound },
                        action: function(row) { fingerprintCopy.text = String(row.certificateFingerprint); fingerprintCopy.selectAll(); fingerprintCopy.copy() }
                    }
                ]
            }

            // Off-screen carrier for "Copy fingerprint": QML has no clipboard API of its own, so a
            // TextEdit is what actually holds the selection being copied.
            TextEdit {
                id: fingerprintCopy
                visible: false
                width: 0
                height: 0
            }

            Rectangle {
                width: parent.width
                height: explainCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                visible: root.isAdmin

                Column {
                    id: explainCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 12

                    Text { text: "Where these come from"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#c4c9d1"
                        font.pixelSize: 12
                        text: "A listener is configuration, not a resource: it is read from "
                              + "euclid.modules.eag.listeners in euclid.json when the module starts, and is fixed "
                              + "until it restarts. That is why nothing here can be edited - moving a port or "
                              + "switching it to HTTPS is a change on the host."
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#9aa1ac"
                        font.pixelSize: 11
                        text: "\"listeners\": { \"development\": { \"port\": 8080, \"protocol\": \"https\", "
                              + "\"certificate\": \"eag-development\" } }"
                        font.family: "monospace"
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#c4c9d1"
                        font.pixelSize: 12
                        text: "An HTTPS listener terminates TLS itself with a certificate EKM holds, named rather "
                              + "than given as file paths - which is what makes it listable, replaceable and "
                              + "watchable for expiry. A listener naming none takes the conventional name for its "
                              + "namespace: eag-<namespace>, or eag for one bound to none."
                    }

                    // Said only when it actually applies, since in a single-namespace installation
                    // every listener's certificate is reachable and the caveat is noise.
                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.listeners.some(l => l.https && String(l["namespace"]) !== root.namespaceName)
                        color: "#9aa1ac"
                        font.pixelSize: 11
                        text: "A certificate belongs to the namespace its listener serves, and this session works "
                              + "in " + root.namespaceName + ". The listeners above are shown whatever namespace "
                              + "they are bound to - the gateway owns them all - but one whose certificate is held "
                              + "elsewhere can only be opened after switching to that namespace. A listener bound "
                              + "to no namespace keeps its certificate in none either."
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.listeners.some(l => l.https && l.certificateGenerated)
                        color: "#e0a458"
                        font.pixelSize: 11
                        text: "⚠ A certificate marked self-signed was generated by euclid because the listener "
                              + "needed something to start with. Nobody has vouched for it, so callers refuse it "
                              + "until they are given it as a trust anchor. Import a real one under the same name "
                              + "on the certificates page; it takes over at the next restart."
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        visible: root.listeners.some(l => !l.https)
                        color: "#e0a458"
                        font.pixelSize: 11
                        text: "⚠ An HTTP listener publishes its port in clear text. That is what a gateway behind "
                              + "a load balancer that has already terminated TLS wants, and it is what a route "
                              + "carrying a login or Basic authentication must not be reached over."
                    }
                }
            }
        }
    }
}
