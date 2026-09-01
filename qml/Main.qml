import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Window
import "components"
import "pages"

ApplicationWindow {
    id: window
    width: 2000
    height: 1200
    minimumWidth: 960
    minimumHeight: 600
    visible: true
    title: "Euclid RUI"

    Material.theme: Material.Dark
    Material.accent: "#4f8cff"
    Material.background: "#14161b"

    color: "#14161b"

    property bool loggedIn: false
    property string currentUser: ""
    property string currentNamespace: ""
    property string currentRoute: "dashboard"

    // EAM
    property int eamAccountCount: -1
    property int eamNamespaceCount: -1
    property int eamUserCount: -1
    property int eamGroupCount: -1
    property double eamServiceCount: -1
    property double eamServiceTime: -1
    property string selectedUserErn: ""
    property string selectedUserId: ""
    property var selectedUserDetails: ({})
    property string selectedGroupErn: ""
    property string selectedGroupName: ""
    property var selectedGroupDetails: ({})
    property string selectedAccountId: ""
    property string selectedAccountName: ""
    property var selectedAccountDetails: ({})
    property string selectedNamespaceAccountId: ""
    property string selectedNamespaceName: ""
    property var selectedNamespaceDetails: ({})
    // Where "‹ Back" on the namespace details page returns to: it is reachable both from the
    // namespaces table and from a namespace row on the account details page.
    property string namespaceDetailsReturnRoute: "modules-eam-namespaces"

    // EQS
    property int eqsQueueCount: -1
    property int eqsTotalMessages: -1
    property double eqsServiceCount: -1
    property double eqsServiceTime: -1
    property string selectedQueueErn: ""
    property string selectedQueueName: ""
    property var selectedQueueDetails: ({})
    property string selectedMessageErn: ""
    property string selectedMessageId: ""
    property string selectedMessageQueueName: ""
    property var selectedMessageDetails: ({})
    // Message and byte volume through the queues, labelled per queue ERN server-side and summed
    // across them here. "Sent" is what went into a queue, "received" what a consumer took back
    // out - a redelivered message counts again, which is what makes the gap between the two
    // visible. -1 means "not loaded yet", as distinct from a genuine zero.
    property double eqsMessagesSent: -1
    property double eqsMessagesReceived: -1
    property double eqsBytesSent: -1
    property double eqsBytesReceived: -1

    // ESM
    property int esmBucketCount: -1
    property int esmTotalObjects: -1
    property double esmServiceCount: -1
    property double esmServiceTime: -1
    property string selectedBucketErn: ""
    property string selectedBucketName: ""
    property var selectedBucketDetails: ({})
    property string selectedObjectErn: ""
    property string selectedObjectKey: ""
    property string selectedObjectBucketName: ""
    property var selectedObjectDetails: ({})

    // ENS
    property int ensTopicCount: -1
    property int ensTotalMessages: -1
    property double ensServiceCount: -1
    property double ensServiceTime: -1
    property string selectedTopicErn: ""
    property string selectedTopicName: ""
    property var selectedTopicDetails: ({})
    property string selectedEnsMessageErn: ""
    property string selectedEnsMessageId: ""
    property string selectedEnsMessageTopicName: ""
    property var selectedEnsMessageDetails: ({})
    // Per-topic volume, summed across topics here. Read like the EQS pair with one difference
    // worth remembering: "received" is what was handed to a topic's subscriptions, so one publish
    // to three subscriptions counts once sent and three times received - the fan-out factor.
    property double ensMessagesSent: -1
    property double ensMessagesReceived: -1
    property double ensBytesSent: -1
    property double ensBytesReceived: -1

    // EAP. Same control-plane shape as ETS: the module owns application definitions and a desired
    // state, and euclid-mgr's reconciler runs the processes.
    property int eapApplicationCount: -1
    property int eapRunningCount: -1
    property int eapInstanceCount: -1
    property double eapServiceCount: -1
    property double eapServiceTime: -1
    property string selectedApplicationId: ""
    property var selectedApplicationDetails: ({})

    // ETS. Two kinds of metric: the per-action service count/time every module records through
    // Core::Monitoring::MonitoringTimer, and the transfer counters recorded by the
    // euclid-ftp/euclid-sftp processes themselves (extern/common/include/TransferMetrics.h),
    // labelled by server. -1 means "not loaded yet", which is what distinguishes it from a
    // genuine zero.
    property int etsServerCount: -1
    property int etsRunningCount: -1
    property double etsServiceCount: -1
    property double etsServiceTime: -1
    property double etsFilesSent: -1
    property double etsFilesReceived: -1
    // Bytes are counted at the protocol rather than at the bucket, so they are what the client
    // actually put on or took off the wire - for SFTP that can differ from the objects' size, a
    // partial re-read or a write into the middle of a file being the usual reasons.
    property double etsBytesSent: -1
    property double etsBytesReceived: -1
    property string selectedTransferServerId: ""
    property var selectedTransferServerDetails: ({})

    // EKM
    property int ekmKeyCount: -1
    property double ekmServiceCount: -1
    property double ekmServiceTime: -1
    property string selectedKeyErn: ""
    property string selectedKeyName: ""
    property var selectedKeyDetails: ({})

    function initialsFor(name) {
        const parts = name.trim().split(/[\s@.]+/).filter(p => p.length > 0)
        if (parts.length === 0)
            return "?"
        if (parts.length === 1)
            return parts[0].substring(0, 2).toUpperCase()
        return (parts[0][0] + parts[1][0]).toUpperCase()
    }

    readonly property var moduleRoutes: ({
        "eam": "modules-eam", "eqs": "modules-eqs", "esm": "modules-esm",
        "ekm": "modules-ekm", "ens": "modules-ens", "ets": "modules-ets", "eap": "modules-eap"
    })

    function moduleRouteFor(query) {
        const key = query.trim().toLowerCase()
        return window.moduleRoutes[key] || ""
    }

    function refreshEamSummary() {
        if (!window.loggedIn)
            return
        eamClient.fetchAccounts("", 0, 100)
        eamClient.fetchNamespaces(euclidClient.accountId, "", 0, 100)
        eamClient.fetchUsers("", 0, 100)
        eamClient.fetchUserGroups("", 0, 100)
        emoClient.fetchAverage("eam-service-count")
        emoClient.fetchAverage("eam-service-time")
    }

    function refreshEqsSummary() {
        if (!window.loggedIn)
            return
        eqsClient.fetchQueues("", 0, 100)
        emoClient.fetchAverage("eqs-service-count")
        emoClient.fetchAverage("eqs-service-time")
        // Aggregated across the "queue" label for a deployment total, then summed over today (see
        // sumToday). The row cap is a day of 5-minute buckets times room for eight queues.
        emoClient.fetchAggregatedSeries("eqs-messages-sent", 288 * 8, "RAW")
        emoClient.fetchAggregatedSeries("eqs-messages-received", 288 * 8, "RAW")
        emoClient.fetchAggregatedSeries("eqs-bytes-sent", 288 * 8, "RAW")
        emoClient.fetchAggregatedSeries("eqs-bytes-received", 288 * 8, "RAW")
    }

    function refreshEsmSummary() {
        if (!window.loggedIn)
            return
        esmClient.fetchBuckets("", 0, 100)
        emoClient.fetchAverage("esm-service-count")
        emoClient.fetchAverage("esm-service-time")
    }

    function refreshEnsSummary() {
        if (!window.loggedIn)
            return
        ensClient.fetchTopics("", 0, 100)
        emoClient.fetchAverage("ens-service-count")
        emoClient.fetchAverage("ens-service-time")
        // Aggregated across the "topic" label, then summed over today (see sumToday). The row cap
        // is a day of 5-minute buckets times room for eight topics.
        emoClient.fetchAggregatedSeries("ens-messages-sent", 288 * 8, "RAW")
        emoClient.fetchAggregatedSeries("ens-messages-received", 288 * 8, "RAW")
        emoClient.fetchAggregatedSeries("ens-bytes-sent", 288 * 8, "RAW")
        emoClient.fetchAggregatedSeries("ens-bytes-received", 288 * 8, "RAW")
    }

    function refreshEkmSummary() {
        if (!window.loggedIn)
            return
        ekmClient.fetchKeys("", 0, 100)
        emoClient.fetchAverage("ekm-service-count")
        emoClient.fetchAverage("ekm-service-time")
    }

    // Total of a RATE series over today's buckets. emo has neither a "sum" action nor a
    // today-to-date query - "average" returns a per-bucket mean over the whole retention - so the
    // buckets are fetched and added up here, the same way the analytics page bounds "Today".
    function sumToday(points) {
        const now = new Date()
        const start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
        let total = 0
        for (const point of points) {
            const t = new Date(point.timestamp).getTime()
            if (!isNaN(t) && t >= start)
                total += point.value
        }
        return total
    }

    function refreshEapSummary() {
        if (!window.loggedIn)
            return
        eapClient.fetchApplications("")
        emoClient.fetchAverage("eap-service-count")
        emoClient.fetchAverage("eap-service-time")
    }

    Connections {
        target: eapClient
        function onApplicationsLoaded(list, total) {
            window.eapApplicationCount = total
            // Counted on `state`, not `desiredState`: the module page should say what is actually
            // up, not what was asked for.
            window.eapRunningCount = list.filter(a => a.state === "RUNNING").length
            let instances = 0
            for (const application of list) instances += application.instances
            window.eapInstanceCount = instances
        }
        function onApplicationsFailed(message) {
            window.eapApplicationCount = -1
            window.eapRunningCount = -1
            window.eapInstanceCount = -1
        }
    }

    function refreshEtsSummary() {
        if (!window.loggedIn)
            return
        etsClient.fetchServers("")
        emoClient.fetchAverage("ets-service-count")
        emoClient.fetchAverage("ets-service-time")
        // Aggregated across the "server" label, so the dashboard shows the deployment's total
        // rather than one server's. The row cap counts rows, and one bucket costs one row per
        // server, so it is a day of 5-minute buckets times room for eight transfer servers.
        emoClient.fetchAggregatedSeries("ets-files-received", 288 * 8, "RAW")
        emoClient.fetchAggregatedSeries("ets-files-sent", 288 * 8, "RAW")
        emoClient.fetchAggregatedSeries("ets-bytes-received", 288 * 8, "RAW")
        emoClient.fetchAggregatedSeries("ets-bytes-sent", 288 * 8, "RAW")
    }

    Connections {
        target: emoClient
        function onSeriesLoaded(name, labelValue, points) {
            if (name === "ets-files-received") window.etsFilesReceived = window.sumToday(points)
            else if (name === "ets-files-sent") window.etsFilesSent = window.sumToday(points)
            else if (name === "ets-bytes-received") window.etsBytesReceived = window.sumToday(points)
            else if (name === "ets-bytes-sent") window.etsBytesSent = window.sumToday(points)
            else if (name === "eqs-messages-received") window.eqsMessagesReceived = window.sumToday(points)
            else if (name === "eqs-messages-sent") window.eqsMessagesSent = window.sumToday(points)
            else if (name === "eqs-bytes-received") window.eqsBytesReceived = window.sumToday(points)
            else if (name === "eqs-bytes-sent") window.eqsBytesSent = window.sumToday(points)
            else if (name === "ens-messages-received") window.ensMessagesReceived = window.sumToday(points)
            else if (name === "ens-messages-sent") window.ensMessagesSent = window.sumToday(points)
            else if (name === "ens-bytes-received") window.ensBytesReceived = window.sumToday(points)
            else if (name === "ens-bytes-sent") window.ensBytesSent = window.sumToday(points)
        }
        function onSeriesFailed(name, labelValue, message) {
            if (name === "ets-files-received") window.etsFilesReceived = -1
            else if (name === "ets-files-sent") window.etsFilesSent = -1
            else if (name === "ets-bytes-received") window.etsBytesReceived = -1
            else if (name === "ets-bytes-sent") window.etsBytesSent = -1
            else if (name === "eqs-messages-received") window.eqsMessagesReceived = -1
            else if (name === "eqs-messages-sent") window.eqsMessagesSent = -1
            else if (name === "eqs-bytes-received") window.eqsBytesReceived = -1
            else if (name === "eqs-bytes-sent") window.eqsBytesSent = -1
            else if (name === "ens-messages-received") window.ensMessagesReceived = -1
            else if (name === "ens-messages-sent") window.ensMessagesSent = -1
            else if (name === "ens-bytes-received") window.ensBytesReceived = -1
            else if (name === "ens-bytes-sent") window.ensBytesSent = -1
        }
    }

    Connections {
        target: etsClient
        function onServersLoaded(list, total) {
            window.etsServerCount = total
            // Counted on `state`, not `desiredState`: the module page should say what is actually
            // up, not what was asked for.
            window.etsRunningCount = list.filter(s => s.state === "RUNNING").length
        }
        function onServersFailed(message) {
            window.etsServerCount = -1
            window.etsRunningCount = -1
        }
    }

    LoginDialog {
        id: loginDialog
        onLoggedIn: (username, namespaceName) => {
            window.loggedIn = true
            window.currentUser = username
            window.currentNamespace = namespaceName
            euclidClient.setNamespace(namespaceName)
        }
    }

    Connections {
        target: euclidClient
        // Pointing the client at another gateway throws the session away (a token is only good on
        // the euclid-mgr that issued it), so the window has to stop claiming someone is signed in
        // - otherwise every page would keep polling with a token that no longer exists.
        function onSessionCleared() {
            window.loggedIn = false
            window.currentUser = ""
            window.currentNamespace = ""
        }
    }

    Component.onCompleted: {
        x = Screen.width / 2 - width / 2
        y = Screen.height / 2 - height / 2
        if (cliUser.length > 0 && cliPassword.length > 0)
            loginDialog.autoLogin(cliUser, cliPassword, cliNamespace)
        else
            loginDialog.open()
    }

    onCurrentRouteChanged: {
        if (currentRoute === "modules-eam") refreshEamSummary()
        if (currentRoute === "modules-eqs") refreshEqsSummary()
        if (currentRoute === "modules-esm") refreshEsmSummary()
        if (currentRoute === "modules-ens") refreshEnsSummary()
        if (currentRoute === "modules-ekm") refreshEkmSummary()
        if (currentRoute === "modules-ets") refreshEtsSummary()
        if (currentRoute === "modules-eap") refreshEapSummary()
    }
    onLoggedInChanged: {
        if (loggedIn && currentRoute === "modules-eam") refreshEamSummary()
        if (loggedIn && currentRoute === "modules-eqs") refreshEqsSummary()
        if (loggedIn && currentRoute === "modules-esm") refreshEsmSummary()
        if (loggedIn && currentRoute === "modules-ens") refreshEnsSummary()
        if (loggedIn && currentRoute === "modules-ekm") refreshEkmSummary()
        if (loggedIn && currentRoute === "modules-ets") refreshEtsSummary()
        if (loggedIn && currentRoute === "modules-eap") refreshEapSummary()
    }

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && window.currentRoute === "modules-eam" && window.loggedIn
        repeat: true
        onTriggered: window.refreshEamSummary()
    }

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && window.currentRoute === "modules-eqs" && window.loggedIn
        repeat: true
        onTriggered: window.refreshEqsSummary()
    }

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && window.currentRoute === "modules-esm" && window.loggedIn
        repeat: true
        onTriggered: window.refreshEsmSummary()
    }

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && window.currentRoute === "modules-ens" && window.loggedIn
        repeat: true
        onTriggered: window.refreshEnsSummary()
    }

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && window.currentRoute === "modules-ekm" && window.loggedIn
        repeat: true
        onTriggered: window.refreshEkmSummary()
    }

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && window.currentRoute === "modules-ets" && window.loggedIn
        repeat: true
        onTriggered: window.refreshEtsSummary()
    }

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        running: appSettings.autoRefreshSeconds > 0 && window.currentRoute === "modules-eap" && window.loggedIn
        repeat: true
        onTriggered: window.refreshEapSummary()
    }

    Connections {
        target: eamClient
        function onAccountsLoaded(list, total) {
            window.eamAccountCount = total
        }
        function onNamespacesLoaded(list, total) {
            window.eamNamespaceCount = total
        }
        function onUsersLoaded(list, total) {
            window.eamUserCount = total
        }
        function onUserGroupsLoaded(list, total) {
            window.eamGroupCount = total
        }
    }

    Connections {
        target: eqsClient
        function onQueuesLoaded(list, total) {
            window.eqsQueueCount = total
            let sum = 0
            for (let i = 0; i < list.length; i++)
                sum += list[i].available + list[i].delayed + list[i].invisible
            window.eqsTotalMessages = sum
        }
    }

    Connections {
        target: esmClient
        function onBucketsLoaded(list, total) {
            window.esmBucketCount = total
            let sum = 0
            for (let i = 0; i < list.length; i++)
                sum += list[i].objects
            window.esmTotalObjects = sum
        }
    }

    Connections {
        target: ensClient
        function onTopicsLoaded(list, total) {
            window.ensTopicCount = total
            let sum = 0
            for (let i = 0; i < list.length; i++)
                sum += list[i].messages
            window.ensTotalMessages = sum
        }
    }

    Connections {
        target: ekmClient
        function onKeysLoaded(list, total) {
            window.ekmKeyCount = total
        }
    }

    Connections {
        target: emoClient
        function onAverageLoaded(name, value) {
            if(name === "esm-service-count")
                window.esmServiceCount = value
            else if(name === "esm-service-time")
                window.esmServiceTime = value
            else if(name === "eqs-service-count")
                window.eqsServiceCount = value
            else if(name === "eqs-service-time")
                window.eqsServiceTime = value
            else if(name === "ens-service-count")
                window.ensServiceCount = value
            else if(name === "ens-service-time")
                window.ensServiceTime = value
            else if(name === "eam-service-count")
                window.eamServiceCount = value
            else if(name === "eam-service-time")
                window.eamServiceTime = value
            else if(name === "ekm-service-count")
                window.ekmServiceCount = value
            else if(name === "ekm-service-time")
                window.ekmServiceTime = value
            else if(name === "ets-service-count")
                window.etsServiceCount = value
            else if(name === "ets-service-time")
                window.etsServiceTime = value
            else if(name === "eap-service-count")
                window.eapServiceCount = value
            else if(name === "eap-service-time")
                window.eapServiceTime = value
        }
    }

    Row {
        anchors.fill: parent

        SideNav {
            id: sideNav
            height: parent.height
            currentRoute: window.currentRoute
            onNavigate: (route) => window.currentRoute = route
        }

        Column {
            width: parent.width - sideNav.width
            height: parent.height

            Rectangle {
                width: parent.width
                height: 64
                color: "#181b21"

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 28
                    anchors.rightMargin: 28
                    spacing: 16

                    TextField {
                        id: searchField
                        width: 320
                        height: 40
                        anchors.verticalCenter: parent.verticalCenter
                        placeholderText: "Search..."
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onAccepted: {
                            const route = window.moduleRouteFor(text)
                            if (route.length > 0) {
                                window.currentRoute = route
                                text = ""
                            }
                        }
                    }

                    Item {
                        width: parent.width - 320 - 16 - 40 - 40 - 150 - 32
                        height: 1
                    }

                    Column {
                        visible: window.loggedIn
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text { text: window.currentUser; color: "#e5e7eb"; font.pixelSize: 12 }
                        // Which gateway, alongside the namespace: with a remote euclid-mgr one
                        // click away, "where am I connected" stops being obvious.
                        Text {
                            text: window.currentNamespace + " · " + appSettings.host + ":" + appSettings.port
                            color: "#9aa1ac"
                            font.pixelSize: 11
                        }
                    }

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 10
                        color: "#20242e"
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: "🔔"
                            font.pixelSize: 16
                        }
                    }

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: "#2c3648"
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: window.loggedIn ? window.initialsFor(window.currentUser) : "?"
                            color: "white"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: loginDialog.open()
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: "#2c313c"
                }
            }

            Item {
                id: pageLoader
                width: parent.width
                height: parent.height - 64

                DashboardPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "dashboard"
                    loggedIn: window.loggedIn
                }
                AnalyticsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "analytics"
                    loggedIn: window.loggedIn
                }
                SettingsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "settings"
                }

                // EAM
                ModulePage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eam"
                    moduleName: "EAM"
                    loggedIn: window.loggedIn
                    stats: [
                        {
                            title: "Accounts", value: window.eamAccountCount < 0 ? "—" : String(window.eamAccountCount),
                            trend: "live", trendUp: true, accent: "#4f8cff", route: "modules-eam-accounts"
                        },
                        {
                            title: "Namespaces", value: window.eamNamespaceCount < 0 ? "—" : String(window.eamNamespaceCount),
                            trend: "live", trendUp: true, accent: "#4f8cff", route: "modules-eam-namespaces"
                        },
                        {
                            title: "Users", value: window.eamUserCount < 0 ? "—" : String(window.eamUserCount),
                            trend: "live", trendUp: true, accent: "#4cd97b", route: "modules-eam-users"
                        },
                        {
                            title: "User Groups", value: window.eamGroupCount < 0 ? "—" : String(window.eamGroupCount),
                            trend: "live", trendUp: true, accent: "#ffb545", route: "modules-eam-user-groups"
                        },
                        {
                            title: "Service Count", value: window.eamServiceCount < 0 ? "—" : window.eamServiceCount.toFixed(1),
                            trend: "-1.2% today", trendUp: false, accent: "#ffb545" },
                        {
                            title: "Service Time", value: window.eamServiceTime < 0 ? "—" : window.eamServiceTime.toFixed(1) + " ms",
                            trend: "+0.5% today", trendUp: true, accent: "#c56bff"
                        }
                    ]
                    activity: [
                        { initials: "EA", avatarColor: "#4f8cff", title: "User \"" + window.currentUser + "\" signed in", subtitle: "namespace · " + window.currentNamespace, time: "1m ago" },
                        { initials: "EA", avatarColor: "#4cd97b", title: "Namespace \"staging\" created", subtitle: "account · 000000000000", time: "34m ago" },
                        { initials: "EA", avatarColor: "#ffb545", title: "Access key rotated", subtitle: "policy · default", time: "2h ago" }
                    ]
                    onNavigate: (route) => window.currentRoute = route
                }
                EamAccountsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eam-accounts"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-eam"
                    onOpenAccountDetails: (accountId, accountName, details) => {
                        window.selectedAccountId = accountId
                        window.selectedAccountName = accountName
                        window.selectedAccountDetails = details
                        window.currentRoute = "modules-eam-account-details"
                    }
                }
                EamAccountDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eam-account-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    accountId: window.selectedAccountId
                    accountName: window.selectedAccountName
                    details: window.selectedAccountDetails
                    onBack: window.currentRoute = "modules-eam-accounts"
                    onOpenNamespaceDetails: (accountId, namespaceName, details) => {
                        window.selectedNamespaceAccountId = accountId
                        window.selectedNamespaceName = namespaceName
                        window.selectedNamespaceDetails = details
                        window.namespaceDetailsReturnRoute = "modules-eam-account-details"
                        window.currentRoute = "modules-eam-namespace-details"
                    }
                }
                EamNamespacesPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eam-namespaces"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-eam"
                    onOpenNamespaceDetails: (accountId, namespaceName, details) => {
                        window.selectedNamespaceAccountId = accountId
                        window.selectedNamespaceName = namespaceName
                        window.selectedNamespaceDetails = details
                        window.namespaceDetailsReturnRoute = "modules-eam-namespaces"
                        window.currentRoute = "modules-eam-namespace-details"
                    }
                }
                EamNamespaceDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eam-namespace-details"
                    loggedIn: window.loggedIn
                    accountId: window.selectedNamespaceAccountId
                    namespaceName: window.selectedNamespaceName
                    details: window.selectedNamespaceDetails
                    onBack: window.currentRoute = window.namespaceDetailsReturnRoute
                }
                EamUsersPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eam-users"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-eam"
                    onOpenUserDetails: (userErn, userId, details) => {
                        window.selectedUserErn = userErn
                        window.selectedUserId = userId
                        window.selectedUserDetails = details
                        window.currentRoute = "modules-eam-user-details"
                    }
                }
                EamUserDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eam-user-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    userErn: window.selectedUserErn
                    userId: window.selectedUserId
                    details: window.selectedUserDetails
                    onBack: window.currentRoute = "modules-eam-users"
                }
                EamUserGroupsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eam-user-groups"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-eam"
                    onOpenGroupDetails: (groupErn, groupName, details) => {
                        window.selectedGroupErn = groupErn
                        window.selectedGroupName = groupName
                        window.selectedGroupDetails = details
                        window.currentRoute = "modules-eam-user-group-details"
                    }
                }
                EamUserGroupDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eam-user-group-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    groupErn: window.selectedGroupErn
                    groupName: window.selectedGroupName
                    details: window.selectedGroupDetails
                    onBack: window.currentRoute = "modules-eam-user-groups"
                }

                ModulePage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ekm"
                    moduleName: "EKM"
                    loggedIn: window.loggedIn
                    stats: [
                        {
                            title: "Managed Keys", value: window.ekmKeyCount < 0 ? "—" : String(window.ekmKeyCount),
                            trend: "live", trendUp: true, accent: "#4f8cff", route: "modules-ekm-keys"
                        },
                        {
                            title: "Service Count", value: window.ekmServiceCount < 0 ? "—" : window.ekmServiceCount.toFixed(1),
                            trend: "-1.2% today", trendUp: false, accent: "#ffb545" },
                        {
                            title: "Service Time", value: window.ekmServiceTime < 0 ? "—" : window.ekmServiceTime.toFixed(1) + " ms",
                            trend: "+0.5% today", trendUp: true, accent: "#c56bff"
                        }
                    ]
                    activity: [
                        { initials: "EK", avatarColor: "#4f8cff", title: "Key \"prod-primary\" rotated", subtitle: "namespace · " + window.currentNamespace, time: "9m ago" },
                        { initials: "EK", avatarColor: "#4cd97b", title: "New key \"backup-2026\" created", subtitle: "usage · encrypt/decrypt", time: "1h ago" },
                        { initials: "EK", avatarColor: "#ffb545", title: "Key policy updated", subtitle: "key · prod-primary", time: "5h ago" }
                    ]
                    onNavigate: (route) => {
                        window.selectedKeyErn = ""
                        window.selectedKeyName = ""
                        window.currentRoute = route
                    }
                }
                EkmKeysPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ekm-keys"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-ekm"
                    onOpenKeyDetails: (keyErn, keyName, details) => {
                        window.selectedKeyErn = keyErn
                        window.selectedKeyName = keyName
                        window.selectedKeyDetails = details
                        window.currentRoute = "modules-ekm-key-details"
                    }
                }
                EkmKeyDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ekm-key-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    keyErn: window.selectedKeyErn
                    keyName: window.selectedKeyName
                    details: window.selectedKeyDetails
                    onBack: window.currentRoute = "modules-ekm-keys"
                }

                // EAP
                ModulePage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eap"
                    moduleName: "EAP"
                    loggedIn: window.loggedIn
                    stats: [
                        {
                            title: "Applications", value: window.eapApplicationCount < 0 ? "—" : String(window.eapApplicationCount),
                            trend: "live", trendUp: true, accent: "#4f8cff", route: "modules-eap-applications"
                        },
                        {
                            title: "Running", value: window.eapRunningCount < 0 ? "—" : String(window.eapRunningCount),
                            trend: window.eapApplicationCount > 0 ? "of " + window.eapApplicationCount + " defined" : "none defined",
                            trendUp: window.eapRunningCount > 0, accent: "#4cd97b", route: "modules-eap-applications"
                        },
                        {
                            title: "Instances", value: window.eapInstanceCount < 0 ? "—" : String(window.eapInstanceCount),
                            trend: "processes up", trendUp: window.eapInstanceCount > 0, accent: "#c56bff"
                        },
                        {
                            title: "Service Count", value: window.eapServiceCount < 0 ? "—" : window.eapServiceCount.toFixed(1),
                            trend: "per flush period", trendUp: true, accent: "#9aa1ac"
                        },
                        {
                            title: "Service Time", value: window.eapServiceTime < 0 ? "—" : window.eapServiceTime.toFixed(1) + " ms",
                            trend: "per action", trendUp: true, accent: "#9aa1ac"
                        }
                    ]
                    activity: [
                        { initials: "AP", avatarColor: "#4f8cff", title: "Applications reconciled", subtitle: "euclid-mgr · desired state", time: "live" },
                        { initials: "AP", avatarColor: "#4cd97b", title: "Artifacts come out of ESM buckets", subtitle: "storage · esm", time: "—" },
                        { initials: "AP", avatarColor: "#ffb545", title: "Each runs as an EAM user's access key", subtitle: "access · eam", time: "—" }
                    ]
                    onNavigate: (route) => {
                        window.selectedApplicationId = ""
                        window.currentRoute = route
                    }
                }
                EapApplicationsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eap-applications"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-eap"
                    onOpenApplicationDetails: (applicationId, details) => {
                        window.selectedApplicationId = applicationId
                        window.selectedApplicationDetails = details
                        window.currentRoute = "modules-eap-application-details"
                    }
                }
                EapApplicationDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eap-application-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    applicationId: window.selectedApplicationId
                    details: window.selectedApplicationDetails
                    onBack: window.currentRoute = "modules-eap-applications"
                }

                // ETS
                ModulePage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ets"
                    moduleName: "ETS"
                    loggedIn: window.loggedIn
                    stats: [
                        {
                            title: "Transfer Servers", value: window.etsServerCount < 0 ? "—" : String(window.etsServerCount),
                            trend: "live", trendUp: true, accent: "#4f8cff", route: "modules-ets-servers"
                        },
                        {
                            title: "Running", value: window.etsRunningCount < 0 ? "—" : String(window.etsRunningCount),
                            trend: window.etsServerCount > 0 ? "of " + window.etsServerCount + " defined" : "none defined",
                            trendUp: window.etsRunningCount > 0, accent: "#4cd97b", route: "modules-ets-servers"
                        },
                        {
                            title: "Stopped",
                            value: window.etsServerCount < 0 ? "—" : String(window.etsServerCount - window.etsRunningCount),
                            trend: "not accepting logins", trendUp: false, accent: "#ffb545"
                        },
                        {
                            title: "Service Count", value: window.etsServiceCount < 0 ? "—" : window.etsServiceCount.toFixed(1),
                            trend: "per flush period", trendUp: true, accent: "#9aa1ac"
                        },
                        {
                            title: "Service Time", value: window.etsServiceTime < 0 ? "—" : window.etsServiceTime.toFixed(1) + " ms",
                            trend: "per action", trendUp: true, accent: "#9aa1ac"
                        },
                        {
                            title: "Files Received",
                            value: window.etsFilesReceived < 0 ? "—" : String(Math.round(window.etsFilesReceived)),
                            trend: "uploaded today", trendUp: window.etsFilesReceived > 0, accent: "#4cd97b"
                        },
                        {
                            title: "Bytes Received",
                            value: window.etsBytesReceived < 0 ? "—" : SizeFormat.format(window.etsBytesReceived),
                            trend: "on the wire today", trendUp: window.etsBytesReceived > 0, accent: "#4cd97b"
                        },
                        {
                            title: "Files Sent",
                            value: window.etsFilesSent < 0 ? "—" : String(Math.round(window.etsFilesSent)),
                            trend: "downloaded today", trendUp: window.etsFilesSent > 0, accent: "#c56bff"
                        },
                        {
                            title: "Bytes Sent",
                            value: window.etsBytesSent < 0 ? "—" : SizeFormat.format(window.etsBytesSent),
                            trend: "on the wire today", trendUp: window.etsBytesSent > 0, accent: "#c56bff"
                        }
                    ]
                    activity: [
                        { initials: "ET", avatarColor: "#4f8cff", title: "Transfer servers reconciled", subtitle: "euclid-mgr · desired state", time: "live" },
                        { initials: "ET", avatarColor: "#4cd97b", title: "FTP and SFTP endpoints front ESM buckets", subtitle: "storage · esm", time: "—" },
                        { initials: "ET", avatarColor: "#ffb545", title: "Logins come from EAM users and groups", subtitle: "access · eam", time: "—" }
                    ]
                    onNavigate: (route) => {
                        window.selectedTransferServerId = ""
                        window.currentRoute = route
                    }
                }
                EtsServersPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ets-servers"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-ets"
                    onOpenServerDetails: (serverId, details) => {
                        window.selectedTransferServerId = serverId
                        window.selectedTransferServerDetails = details
                        window.currentRoute = "modules-ets-server-details"
                    }
                }
                EtsServerDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ets-server-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    serverId: window.selectedTransferServerId
                    details: window.selectedTransferServerDetails
                    onBack: window.currentRoute = "modules-ets-servers"
                }

                ModulePage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eqs"
                    moduleName: "EQS"
                    loggedIn: window.loggedIn
                    stats: [
                        {
                            title: "Queues", value: window.eqsQueueCount < 0 ? "—" : String(window.eqsQueueCount),
                            trend: "live", trendUp: true, accent: "#4f8cff", route: "modules-eqs-queues"
                        },
                        {
                            title: "Total Messages", value: window.eqsTotalMessages < 0 ? "—" : String(window.eqsTotalMessages),
                            trend: "live", trendUp: true, accent: "#4cd97b", route: "modules-eqs-messages"
                        },
                        {
                            title: "Service Count", value: window.eqsServiceCount < 0 ? "—" : window.eqsServiceCount.toFixed(1),
                            trend: "-1.2% today", trendUp: false, accent: "#ffb545" },
                        {
                            title: "Service Time", value: window.eqsServiceTime < 0 ? "—" : window.eqsServiceTime.toFixed(1) + " ms",
                            trend: "+0.5% today", trendUp: true, accent: "#c56bff"
                        },
                        {
                            title: "Messages Sent",
                            value: window.eqsMessagesSent < 0 ? "—" : String(Math.round(window.eqsMessagesSent)),
                            trend: "into queues today", trendUp: window.eqsMessagesSent > 0, accent: "#4f8cff"
                        },
                        {
                            title: "Bytes Sent",
                            value: window.eqsBytesSent < 0 ? "—" : SizeFormat.format(window.eqsBytesSent),
                            trend: "into queues today", trendUp: window.eqsBytesSent > 0, accent: "#4f8cff"
                        },
                        {
                            title: "Messages Received",
                            value: window.eqsMessagesReceived < 0 ? "—" : String(Math.round(window.eqsMessagesReceived)),
                            trend: "consumed today", trendUp: window.eqsMessagesReceived > 0, accent: "#4cd97b"
                        },
                        {
                            title: "Bytes Received",
                            value: window.eqsBytesReceived < 0 ? "—" : SizeFormat.format(window.eqsBytesReceived),
                            trend: "consumed today", trendUp: window.eqsBytesReceived > 0, accent: "#4cd97b"
                        }
                    ]
                    activity: [
                        { initials: "EQ", avatarColor: "#4f8cff", title: "Queue \"orders-in\" created", subtitle: "namespace · " + window.currentNamespace, time: "6m ago" },
                        { initials: "EQ", avatarColor: "#4cd97b", title: "Redrive policy updated", subtitle: "queue · orders-dlq", time: "41m ago" },
                        { initials: "EQ", avatarColor: "#ffb545", title: "Health check passed", subtitle: "liveness probe", time: "1h ago" }
                    ]
                    onNavigate: (route) => {
                        window.selectedQueueErn = ""
                        window.selectedQueueName = ""
                        window.currentRoute = route
                    }
                }

                // EQS
                EqsQueuesPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eqs-queues"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-eqs"
                    onOpenQueue: (queueErn, queueName) => {
                        window.selectedQueueErn = queueErn
                        window.selectedQueueName = queueName
                        window.currentRoute = "modules-eqs-messages"
                    }
                    onOpenQueueDetails: (queueErn, queueName, details) => {
                        window.selectedQueueErn = queueErn
                        window.selectedQueueName = queueName
                        window.selectedQueueDetails = details
                        window.currentRoute = "modules-eqs-queue-details"
                    }
                }
                EqsMessagesPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eqs-messages"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    queueErn: window.selectedQueueErn
                    queueName: window.selectedQueueName
                    onBack: window.currentRoute = window.selectedQueueErn.length > 0 ? "modules-eqs-queues" : "modules-eqs"
                    onOpenMessageDetails: (messageErn, messageId, queueName, details) => {
                        window.selectedMessageErn = messageErn
                        window.selectedMessageId = messageId
                        window.selectedMessageQueueName = queueName
                        window.selectedMessageDetails = details
                        window.currentRoute = "modules-eqs-message-details"
                    }
                }
                EqsMessageDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eqs-message-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    queueName: window.selectedMessageQueueName
                    messageErn: window.selectedMessageErn
                    messageId: window.selectedMessageId
                    details: window.selectedMessageDetails
                    onBack: window.currentRoute = "modules-eqs-messages"
                }
                EqsQueueDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eqs-queue-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    queueErn: window.selectedQueueErn
                    queueName: window.selectedQueueName
                    details: window.selectedQueueDetails
                    onBack: window.currentRoute = "modules-eqs-queues"
                    onViewMessages: (queueErn, queueName) => {
                        window.selectedQueueErn = queueErn
                        window.selectedQueueName = queueName
                        window.currentRoute = "modules-eqs-messages"
                    }
                }

                ModulePage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-esm"
                    moduleName: "ESM"
                    loggedIn: window.loggedIn
                    stats: [
                        {
                            title: "Buckets", value: window.esmBucketCount < 0 ? "—" : String(window.esmBucketCount),
                            trend: "live", trendUp: true, accent: "#4f8cff", route: "modules-esm-buckets"
                        },
                        {
                            title: "Total Objects", value: window.esmTotalObjects < 0 ? "—" : String(window.esmTotalObjects),
                            trend: "live", trendUp: true, accent: "#4cd97b", route: "modules-esm-objects"
                        },
                        {
                            title: "Service Count", value: window.esmServiceCount < 0 ? "—" : window.esmServiceCount.toFixed(1),
                            trend: "-1.2% today", trendUp: false, accent: "#ffb545" },
                        {
                            title: "Service Time", value: window.esmServiceTime < 0 ? "—" : window.esmServiceTime.toFixed(1) + " ms",
                            trend: "+0.5% today", trendUp: true, accent: "#c56bff"
                        }
                    ]
                    activity: [
                        { initials: "ES", avatarColor: "#4f8cff", title: "Service \"eam\" restarted", subtitle: "supervisor · autoheal", time: "12m ago" },
                        { initials: "ES", avatarColor: "#4cd97b", title: "Config reloaded", subtitle: "esm.yaml", time: "2h ago" },
                        { initials: "ES", avatarColor: "#ffb545", title: "Instance registered", subtitle: "region · eu-central-1", time: "5h ago" }
                    ]
                    onNavigate: (route) => {
                        window.selectedBucketErn = ""
                        window.selectedBucketName = ""
                        window.currentRoute = route
                    }
                }

                // ESM
                EsmBucketsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-esm-buckets"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-esm"
                    onOpenBucket: (bucketErn, bucketName) => {
                        window.selectedBucketErn = bucketErn
                        window.selectedBucketName = bucketName
                        window.currentRoute = "modules-esm-objects"
                    }
                    onOpenBucketDetails: (bucketErn, bucketName, details) => {
                        window.selectedBucketErn = bucketErn
                        window.selectedBucketName = bucketName
                        window.selectedBucketDetails = details
                        window.currentRoute = "modules-esm-bucket-details"
                    }
                }

                EsmObjectsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-esm-objects"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    bucketErn: window.selectedBucketErn
                    bucketName: window.selectedBucketName
                    onBack: window.currentRoute = window.selectedBucketErn.length > 0 ? "modules-esm-buckets" : "modules-esm"
                    onOpenObjectDetails: (objectErn, objectKey, bucketName, details) => {
                        window.selectedObjectErn = objectErn
                        window.selectedObjectKey = objectKey
                        window.selectedObjectBucketName = bucketName
                        window.selectedObjectDetails = details
                        window.currentRoute = "modules-esm-object-details"
                    }
                }
                EsmObjectDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-esm-object-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    bucketName: window.selectedObjectBucketName
                    objectErn: window.selectedObjectErn
                    objectKey: window.selectedObjectKey
                    details: window.selectedObjectDetails
                    onBack: window.currentRoute = "modules-esm-objects"
                }

                EsmBucketDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-esm-bucket-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    bucketErn: window.selectedBucketErn
                    bucketName: window.selectedBucketName
                    details: window.selectedBucketDetails
                    onBack: window.currentRoute = "modules-esm-buckets"
                    onViewObjects: (bucketErn, bucketName) => {
                        window.selectedBucketErn = bucketErn
                        window.selectedBucketName = bucketName
                        window.currentRoute = "modules-esm-objects"
                    }
                }

                ModulePage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ens"
                    moduleName: "ENS"
                    loggedIn: window.loggedIn
                    stats: [
                        {
                            title: "Topics", value: window.ensTopicCount < 0 ? "—" : String(window.ensTopicCount),
                            trend: "live", trendUp: true, accent: "#4f8cff", route: "modules-ens-topics"
                        },
                        {
                            title: "Total Messages", value: window.ensTotalMessages < 0 ? "—" : String(window.ensTotalMessages),
                            trend: "live", trendUp: true, accent: "#4cd97b", route: "modules-ens-messages"
                        },
                        {
                            title: "Service Count", value: window.ensServiceCount < 0 ? "—" : window.ensServiceCount.toFixed(1),
                            trend: "-1.2% today", trendUp: false, accent: "#ffb545" },
                        {
                            title: "Service Time", value: window.ensServiceTime < 0 ? "—" : window.ensServiceTime.toFixed(1) + " ms",
                            trend: "+0.5% today", trendUp: true, accent: "#c56bff"
                        },
                        {
                            title: "Messages Published",
                            value: window.ensMessagesSent < 0 ? "—" : String(Math.round(window.ensMessagesSent)),
                            trend: "into topics today", trendUp: window.ensMessagesSent > 0, accent: "#4f8cff"
                        },
                        {
                            title: "Bytes Published",
                            value: window.ensBytesSent < 0 ? "—" : SizeFormat.format(window.ensBytesSent),
                            trend: "into topics today", trendUp: window.ensBytesSent > 0, accent: "#4f8cff"
                        },
                        {
                            title: "Messages Delivered",
                            value: window.ensMessagesReceived < 0 ? "—" : String(Math.round(window.ensMessagesReceived)),
                            trend: "to subscriptions today", trendUp: window.ensMessagesReceived > 0, accent: "#4cd97b"
                        },
                        {
                            title: "Bytes Delivered",
                            value: window.ensBytesReceived < 0 ? "—" : SizeFormat.format(window.ensBytesReceived),
                            trend: "to subscriptions today", trendUp: window.ensBytesReceived > 0, accent: "#4cd97b"
                        }
                    ]
                    activity: [
                        { initials: "EN", avatarColor: "#4f8cff", title: "Topic \"deploy-events\" created", subtitle: "namespace · " + window.currentNamespace, time: "3m ago" },
                        { initials: "EN", avatarColor: "#4cd97b", title: "Subscription confirmed", subtitle: "endpoint · webhook", time: "27m ago" },
                        { initials: "EN", avatarColor: "#ffb545", title: "Retry policy applied", subtitle: "topic · alerts", time: "3h ago" }
                    ]
                    onNavigate: (route) => {
                        window.selectedTopicErn = ""
                        window.selectedTopicName = ""
                        window.currentRoute = route
                    }
                }

                // ENS
                EnsTopicsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ens-topics"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-ens"
                    onOpenTopic: (topicErn, topicName) => {
                        window.selectedTopicErn = topicErn
                        window.selectedTopicName = topicName
                        window.currentRoute = "modules-ens-messages"
                    }
                    onOpenTopicDetails: (topicErn, topicName, details) => {
                        window.selectedTopicErn = topicErn
                        window.selectedTopicName = topicName
                        window.selectedTopicDetails = details
                        window.currentRoute = "modules-ens-topic-details"
                    }
                }
                EnsMessagesPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ens-messages"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    topicErn: window.selectedTopicErn
                    topicName: window.selectedTopicName
                    onBack: window.currentRoute = window.selectedTopicErn.length > 0 ? "modules-ens-topics" : "modules-ens"
                    onOpenMessageDetails: (messageErn, messageId, topicName, details) => {
                        window.selectedEnsMessageErn = messageErn
                        window.selectedEnsMessageId = messageId
                        window.selectedEnsMessageTopicName = topicName
                        window.selectedEnsMessageDetails = details
                        window.currentRoute = "modules-ens-message-details"
                    }
                }
                EnsMessageDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ens-message-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    topicName: window.selectedEnsMessageTopicName
                    messageErn: window.selectedEnsMessageErn
                    messageId: window.selectedEnsMessageId
                    details: window.selectedEnsMessageDetails
                    onBack: window.currentRoute = "modules-ens-messages"
                }
                EnsTopicDetailsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ens-topic-details"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    topicErn: window.selectedTopicErn
                    topicName: window.selectedTopicName
                    details: window.selectedTopicDetails
                    onBack: window.currentRoute = "modules-ens-topics"
                    onViewMessages: (topicErn, topicName) => {
                        window.selectedTopicErn = topicErn
                        window.selectedTopicName = topicName
                        window.currentRoute = "modules-ens-messages"
                    }
                }
            }
        }
    }
}
