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

    // EQS
    property int eqsQueueCount: -1
    property int eqsTotalMessages: -1
    property string selectedQueueErn: ""
    property string selectedQueueName: ""
    property var selectedQueueDetails: ({})

    // ESM
    property int esmBucketCount: -1
    property int esmTotalObjects: -1
    property string selectedBucketErn: ""
    property string selectedBucketName: ""
    property var selectedBucketDetails: ({})

    // ENS
    property int ensTopicCount: -1
    property int ensTotalMessages: -1
    property string selectedTopicErn: ""
    property string selectedTopicName: ""
    property var selectedTopicDetails: ({})

    // EKM
    property int ekmKeyCount: -1

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
        "ekm": "modules-ekm", "ens": "modules-ens"
    })

    function moduleRouteFor(query) {
        const key = query.trim().toLowerCase()
        return window.moduleRoutes[key] || ""
    }

    function refreshEqsSummary() {
        if (!window.loggedIn)
            return
        eqsClient.fetchQueues("", 0, 100)
    }

    function refreshEsmSummary() {
        if (!window.loggedIn)
            return
        esmClient.fetchBuckets("", 0, 100)
    }

    function refreshEnsSummary() {
        if (!window.loggedIn)
            return
        ensClient.fetchTopics("", 0, 100)
    }

    function refreshEkmSummary() {
        if (!window.loggedIn)
            return
        ekmClient.fetchKeys("", 0, 100)
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

    Component.onCompleted: {
        x = Screen.width / 2 - width / 2
        y = Screen.height / 2 - height / 2
        if (cliUser.length > 0 && cliPassword.length > 0)
            loginDialog.autoLogin(cliUser, cliPassword, cliNamespace)
        else
            loginDialog.open()
    }

    onCurrentRouteChanged: {
        if (currentRoute === "modules-eqs") refreshEqsSummary()
        if (currentRoute === "modules-esm") refreshEsmSummary()
        if (currentRoute === "modules-ens") refreshEnsSummary()
        if (currentRoute === "modules-ekm") refreshEkmSummary()
    }
    onLoggedInChanged: {
        if (loggedIn && currentRoute === "modules-eqs") refreshEqsSummary()
        if (loggedIn && currentRoute === "modules-esm") refreshEsmSummary()
        if (loggedIn && currentRoute === "modules-ens") refreshEnsSummary()
        if (loggedIn && currentRoute === "modules-ekm") refreshEkmSummary()
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
                        Text { text: window.currentNamespace; color: "#9aa1ac"; font.pixelSize: 11 }
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
                }
                AnalyticsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "analytics"
                }
                SettingsPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "settings"
                }
                ModulePage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-eam"
                    moduleName: "EAM"
                    loggedIn: window.loggedIn
                    stats: [
                        { title: "Active Sessions", value: "47", trend: "+5.4% today", trendUp: true, accent: "#4f8cff" },
                        { title: "Logins Today", value: "312", trend: "+2.1% today", trendUp: true, accent: "#4cd97b" },
                        { title: "Failed Logins", value: "6", trend: "-4.0% today", trendUp: false, accent: "#ffb545" },
                        { title: "Namespaces", value: "18", trend: "+1 today", trendUp: true, accent: "#c56bff" }
                    ]
                    activity: [
                        { initials: "EA", avatarColor: "#4f8cff", title: "User \"" + window.currentUser + "\" signed in", subtitle: "namespace · " + window.currentNamespace, time: "1m ago" },
                        { initials: "EA", avatarColor: "#4cd97b", title: "Namespace \"staging\" created", subtitle: "account · 000000000000", time: "34m ago" },
                        { initials: "EA", avatarColor: "#ffb545", title: "Access key rotated", subtitle: "policy · default", time: "2h ago" }
                    ]
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
                        { title: "Encrypt Ops/sec", value: "890", trend: "+3.8% today", trendUp: true, accent: "#4cd97b" },
                        { title: "Decrypt Ops/sec", value: "742", trend: "+1.6% today", trendUp: true, accent: "#ffb545" },
                        { title: "Key Rotations", value: "5", trend: "0 today", trendUp: true, accent: "#c56bff" }
                    ]
                    activity: [
                        { initials: "EK", avatarColor: "#4f8cff", title: "Key \"prod-primary\" rotated", subtitle: "namespace · " + window.currentNamespace, time: "9m ago" },
                        { initials: "EK", avatarColor: "#4cd97b", title: "New key \"backup-2026\" created", subtitle: "usage · encrypt/decrypt", time: "1h ago" },
                        { initials: "EK", avatarColor: "#ffb545", title: "Key policy updated", subtitle: "key · prod-primary", time: "5h ago" }
                    ]
                    onNavigate: (route) => window.currentRoute = route
                }
                EkmKeysPage {
                    anchors.fill: parent
                    visible: window.currentRoute === "modules-ekm-keys"
                    loggedIn: window.loggedIn
                    namespaceName: window.currentNamespace
                    onBack: window.currentRoute = "modules-ekm"
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
                        { title: "Avg. Latency", value: "18ms", trend: "+1.4% today", trendUp: true, accent: "#ffb545" },
                        { title: "Dead Letters", value: "3", trend: "0% today", trendUp: true, accent: "#c56bff" }
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
                        { title: "Failed Deliveries", value: "7", trend: "-1.2% today", trendUp: false, accent: "#ffb545" },
                        { title: "Avg. Delivery", value: "94ms", trend: "+0.5% today", trendUp: true, accent: "#c56bff" }
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
