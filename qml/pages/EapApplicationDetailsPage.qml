import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// One application definition. The two states are shown side by side on purpose: start and stop
// only write `desiredState`, and euclid-mgr's reconciler is what eventually makes `state` match -
// an application stuck disagreeing is the module saying it could not start the process.
Item {
    id: root
    property bool loggedIn: false
    property string namespaceName: ""
    property string applicationId: ""
    property var details: ({})

    property string error: ""
    property bool deleting: false
    property bool savingEnvironment: false
    property bool savingRuntime: false
    property bool savingNodeLabels: false

    // ── Command line ─────────────────────────────────────────────────────────
    // What the process is actually started with. The rule is in Core::Launch::CommandLine(): a
    // command the application names is the executable and the artifact becomes its first argument,
    // overriding the runtime; otherwise it is the runtime's interpreter and its own leading
    // arguments ("java -jar") and then the artifact. The application's arguments follow in every
    // case, which is what makes them the thing worth editing here.
    property bool savingArguments: false

    readonly property var arguments: root.detail("arguments", [])

    // The interpreter the runtime brings, for showing what the arguments will follow. Mirrors
    // Core::Launch::InterpreterPrefix(); BINARY and anything unknown is the artifact itself.
    function interpreterPrefix(runtime) {
        if (runtime === "JAVA" || runtime === "JAVA21" || runtime === "JAVA25")
            return (runtime === "JAVA" ? "java" : runtime.toLowerCase()) + " -jar"
        if (runtime === "PYTHON") return "python3"
        if (runtime === "NODEJS") return "node"
        return ""
    }

    // The whole line, as the worker would assemble it. Shown rather than described: an argument
    // list means little without the executable and the artifact it comes after.
    function commandLineText(args) {
        const command = String(root.detail("command", ""))
        const artifact = String(root.detail("artifactKey", ""))
        const head = command.length > 0
                     ? command + " " + artifact
                     : (root.interpreterPrefix(String(root.detail("runtime", ""))).length > 0
                        ? root.interpreterPrefix(String(root.detail("runtime", ""))) + " " + artifact
                        : artifact)
        const tail = (args || []).join(" ")
        return tail.length > 0 ? head + " " + tail : head
    }

    // Sent whole: update-application replaces the field it is given, and an argument list has no
    // per-entry call - which is right, since what matters about these is their order.
    function setArguments(args) {
        root.error = ""
        root.savingArguments = true
        eapClient.updateApplication(root.applicationId, { arguments: args })
    }

    // ── Egress rate limits ───────────────────────────────────────────────────
    // This application's: how fast it may call each outside site, and how many requests to one it
    // may have in flight. Per application rather than per instance - the autoscaler would multiply
    // a limit each instance kept, and the site on the other end counts requests per source, not
    // per process. See EapClient::fetchEgressSites().
    property var egressSites: []
    property var egressDefaults: ({})
    property bool egressLoading: false
    property string egressError: ""

    function limitText(requestsPerSecond, burst, concurrent) {
        // Zero is a setting, not an absence: it is what says a site has no rate limit or no
        // concurrency limit at all, so it is spelled out rather than shown as a bare 0.
        const rate = Number(requestsPerSecond) > 0 ? Number(requestsPerSecond).toFixed(2) + "/s" : "unlimited"
        const slots = Number(concurrent) > 0 ? Number(concurrent) + " at once" : "unlimited"
        return rate + ", burst " + Number(burst).toFixed(0) + ", " + slots
    }

    readonly property string egressDefaultText: root.egressDefaults
            && root.egressDefaults.requestsPerSecond !== undefined
        ? root.limitText(root.egressDefaults.requestsPerSecond, root.egressDefaults.burst,
                         root.egressDefaults.concurrent)
        : "—"

    readonly property var egressColumns: [
        {
            title: "Site",
            key: "site",
            fill: true,
            // "*" is not a host: it is what this application is held to everywhere it has no
            // limit of its own, so it is said rather than printed.
            formatter: function (v) { return String(v) === root.allSites ? "All sites (this application's default)" : String(v) },
            colorFor: function (v) { return String(v) === root.allSites ? "#9aa1ac" : "#c4c9d1" }
        },
        {
            title: "Rate",
            key: "requestsPerSecond",
            formatter: function (v) { return Number(v) > 0 ? Number(v).toFixed(2) + "/s" : "unlimited" }
        },
        { title: "Burst", key: "burst", formatter: function (v) { return Number(v).toFixed(0) } },
        {
            title: "Concurrent",
            key: "concurrent",
            formatter: function (v) { return Number(v) > 0 ? String(v) : "unlimited" }
        },
        {
            // Whose decision these limits are: the site's own, or nobody's yet.
            title: "Limits",
            key: "limitsSet",
            formatter: function (v) { return v ? "set" : "default" },
            colorFor: function (v) { return v ? "#4f8cff" : "#6b7280" }
        },
        {
            // What is left of the bucket right now, which is what decides whether the next request
            // waits. Blank for the "*" row: nothing acquires a permit for it, so it has no bucket.
            title: "Tokens",
            key: "tokens",
            formatter: function (v, row) { return row && row.allSites ? "—" : Number(v).toFixed(1) }
        },
        {
            title: "In flight",
            key: "inFlight",
            formatter: function (v, row) { return row && row.allSites ? "—" : String(v) }
        },
        {
            // Only ever set when the site itself asked to be left alone - a 429 or 503 an
            // application reported - and nothing is granted for it until then.
            title: "Blocked until",
            key: "blockedUntil",
            formatter: function (v) { return String(v).length > 0 ? DateFormat.format(v) : "—" },
            colorFor: function (v) { return String(v).length > 0 ? "#ff6b6b" : "#6b7280" }
        },
        {
            title: "Last used",
            key: "lastUsed",
            formatter: function (v, row) { return row && row.allSites ? "—" : DateFormat.format(v) }
        }
    ]

    function refreshEgress() {
        if (!root.loggedIn || root.applicationId.length === 0) return
        root.egressLoading = true
        // Scoped to this application: the call answers for every application the account can see
        // when asked for none, and this page is about one of them.
        eapClient.fetchEgressSites(root.applicationId)
    }

    // The site an application's own default is stored under - Egress::kAllSites. It is a row like
    // any other to the server and a setting rather than a site here, which is why it is named in
    // the table instead of being shown as a host called "*".
    readonly property string allSites: "*"

    // What this application falls back to for a site it has no limit of its own for: its "*" row
    // if it has one, and otherwise the installation's default.
    readonly property var egressFallback: {
        const all = root.egressSites.find(s => s.site === root.allSites)
        return all ? all : root.egressDefaults
    }
    readonly property bool egressHasOwnDefault: root.egressSites.some(s => s.site === root.allSites
                                                                      && s.limitsSet === true)

    // The processes actually running this application, from EMM rather than EAP: the manager runs
    // an application as a module pool named after its *runtime* name, and only that pool knows
    // which processes exist, what pids they have and which port each was given. EAP's own
    // "instances" is a count and nothing more.
    property var instances: []
    // Kept apart from root.error: a definition that reads fine while its pool cannot be listed is
    // still worth showing, and putting this in the page's error line would make the whole page
    // look broken.
    property string instancesError: ""

    // How big the deployed artifact is, as EAP recorded it when it was deployed. Zero means it was
    // never recorded rather than that the file is empty - see applicationToMap() - so it cannot be
    // shown as "0 B".
    readonly property real recordedArtifactSize: Number(root.detail("artifactSize", 0))

    // The fallback for exactly those definitions: ESM still knows how big the object is, so an
    // application deployed before EAP recorded the size is measured rather than left blank.
    // Negative means not known yet, which is also where it stays if the lookup fails.
    property real measuredArtifactSize: -1
    // Shown in place of the size rather than in the page's error line: an artifact that cannot be
    // measured says nothing about whether the definition is fine, and most of the reasons are
    // ordinary - the bucket is in another namespace, or the caller may not read it.
    property string artifactSizeError: ""
    // Which artifact the measurement belongs to, so the ten-second poll behind this page does not
    // ask ESM again every time it re-reads a definition that has not changed. The checksum is part
    // of it because a redeploy keeps the key and changes the contents.
    property string artifactSizeFor: ""

    // EAP's own figure wins where there is one, and not only because it costs nothing to read: it
    // is the size of the build that was actually deployed, where ESM reports whatever is in the
    // bucket now - and an object can be overwritten without the application being redeployed.
    readonly property real artifactSize: root.recordedArtifactSize > 0
                                         ? root.recordedArtifactSize
                                         : root.measuredArtifactSize

    signal back()

    function detail(key, fallback) {
        return root.details && root.details[key] !== undefined ? root.details[key] : fallback
    }

    // Not "state": QQuickItem already has one (the Item state machine), and shadowing it silently
    // changes what every state-related binding on this page means.
    readonly property int minInstances: Number(detail("minInstances", 1))
    readonly property int maxInstances: Number(detail("maxInstances", 1))

    readonly property string applicationState: detail("state", "")
    readonly property string desiredState: detail("desiredState", "")

    // PROCESS when the definition carries no type, which is what every application written before
    // the field existed has - and what the server itself falls back to, so the two agree.
    readonly property string applicationType: detail("type", "PROCESS")

    // One width for every stat on this page. They are read across rather than one at a time, and a
    // row of cards at three different sizes reads as three kinds of thing. Wide enough for the
    // longest line any of them shows - the principal of an application running under its own
    // identity - and StatCard elides anything past that, so a long value cannot change the layout.
    readonly property int statWidth: 300

    // What the manager knows this application as, and what everything outside the definition is
    // named after: the process pool and its EMM module row, the data directory, the socket, the log
    // channel and the technical principal. Issued once by EAP and held from then on, so it is not
    // derivable from anything on this page - it has to come off the definition.
    //
    // The applicationId is the fallback for an application deployed before the field existed, which
    // is exactly what those are still running as.
    readonly property string runtimeName: String(detail("runtimeName", "")).length > 0
        ? String(detail("runtimeName", "")) : root.applicationId

    // An application left unnamed at creation gets a principal of its own, called after the name it
    // runs under - EAM user ids are installation-wide, so two namespaces each deploying a "billing"
    // cannot both be "app-billing".
    readonly property bool ownPrincipal: root.detail("userId", "") === "app-" + root.runtimeName

    function resourceList() {
        return root.detail("resources", [])
    }

    // The application's own state now carries the pool's, so it has the same values an instance row
    // below can have - and is coloured the same way, bar STOPPED, which here is also what the
    // Requested state beside it can say and is not a fault.
    function applicationStateColor(value) {
        if (value === "RUNNING") return "#4cd97b"
        if (value === "CRASHED") return "#ff6b6b"
        if (value === "STARTING" || value === "STOPPING") return "#ffb545"
        if (value === "STOPPED") return "#ffb545"
        return "#9aa1ac"
    }

    // Same reading the applications list gives it: a job is a different kind of thing rather than
    // a worse one, and UNKNOWN is the only value that says something is wrong - a type this build
    // has no word for, which it runs as a process because that is all it knows how to do.
    function applicationTypeColor(value) {
        if (value === "JOB") return "#c56bff"
        if (value === "UNKNOWN") return "#ffb545"
        return "#4f8cff"
    }

    function instanceStateColor(value) {
        if (value === "RUNNING") return "#4cd97b"
        if (value === "STARTING") return "#ffb545"
        if (value === "STOPPED") return "#9aa1ac"
        return "#ff6b6b"
    }

    // How long the process has been up, as a person would say it. The exact start time is in the
    // column beside it; what an operator reads off a pool is whether an instance is minutes or
    // days old - a young one among old ones is one that has been restarting.
    //
    // From the instance's "started", the running process's own start. It used to be "created",
    // which is the slot's and outlives every process in it, so a pool replaced three hours earlier
    // read as up for eleven. Empty, and shown as "—", for a slot with no process running.
    function uptimeText(startedAt) {
        if (!startedAt) return "—"
        const started = new Date(startedAt)
        if (isNaN(started.getTime())) return "—"
        const seconds = Math.floor((Date.now() - started.getTime()) / 1000)
        if (seconds < 0) return "—"
        if (seconds < 60) return seconds + "s"
        if (seconds < 3600) return Math.floor(seconds / 60) + "m"
        if (seconds < 86400) return Math.floor(seconds / 3600) + "h " + Math.floor((seconds % 3600) / 60) + "m"
        return Math.floor(seconds / 86400) + "d " + Math.floor((seconds % 86400) / 3600) + "h"
    }

    readonly property int runningInstances: root.instances.filter(i => i.state === "RUNNING").length
    // A slot the manager is holding rather than a process that is running - stopped, restarting,
    // or one it could not start. Worth counting separately: the pool looks full either way.
    readonly property int heldSlots: root.instances.length - root.runningInstances

    // Filtered, sorted and paged here rather than by the server: "list-modules" hands over every
    // module with every instance in one answer and has no paging to ask for, so the table is given
    // one page's worth out of what is already in hand.
    property string instanceFilter: ""
    property int instancePageIndex: 0
    property int instancePageSize: 10
    property string instanceSortColumn: "started"
    property bool instanceSortAscending: true

    readonly property var filteredInstances: {
        const needle = root.instanceFilter.toLowerCase()
        const matched = needle.length === 0 ? root.instances.slice() : root.instances.filter(i =>
            String(i.instanceId).toLowerCase().indexOf(needle) >= 0
            || String(i.pid).indexOf(needle) >= 0
            || String(i.httpPort).indexOf(needle) >= 0
            // By the reported host rather than what the column shows for an empty one: "manager" is
            // a word this page chose, and filtering by it would match hosts nobody can name.
            || String(i.host).toLowerCase().indexOf(needle) >= 0
            || String(i.state).toLowerCase().indexOf(needle) >= 0)

        const key = root.instanceSortColumn
        const direction = root.instanceSortAscending ? 1 : -1
        return matched.sort((a, b) => {
            const left = a[key]
            const right = b[key]
            // pid, port and restart count are numbers and have to compare as such - as text, port
            // 9100 sorts before 921. Everything else here is a string or a timestamp, and both of
            // those order correctly compared as text.
            if (typeof left === "number" && typeof right === "number") return (left - right) * direction
            return String(left).localeCompare(String(right)) * direction
        })
    }

    // Clamped rather than left where it was: a pool that shrank while the last page was on screen
    // would otherwise leave the table showing nothing with no way to tell why.
    readonly property int instancePageCount: Math.max(1, Math.ceil(root.filteredInstances.length / root.instancePageSize))
    readonly property int clampedInstancePage: Math.min(root.instancePageIndex, root.instancePageCount - 1)
    readonly property var instancePage: root.filteredInstances.slice(
        root.clampedInstancePage * root.instancePageSize,
        root.clampedInstancePage * root.instancePageSize + root.instancePageSize)

    // The clamp above keeps the wrong page from being shown; this keeps the stored index from
    // staying out of range behind it. Without it a pool that shrank to one page and then grew
    // again would jump back to page two on its own, because the index was never actually moved.
    onFilteredInstancesChanged: {
        if (root.instancePageIndex > root.instancePageCount - 1)
            root.instancePageIndex = root.instancePageCount - 1
    }

    readonly property var instanceColumns: [
        { title: "Instance", key: "instanceId", fill: true },
        {
            title: "PID",
            key: "pid",
            // -1 is the manager's "no process", not a pid.
            formatter: function (v) { return Number(v) > 0 ? String(v) : "—" }
        },
        {
            // Beside the pid, because a pid on its own does not identify a process here: every host
            // runs the same installation path and pids collide across machines as a matter of
            // course. This is the machine the worker running the instance reported itself as.
            title: "Host",
            key: "host",
            // Empty is the manager's own host and not an unknown one - it is what every instance on
            // an installation with no workers carries. Named rather than left blank, so a column of
            // them reads as "all here" instead of "nobody knows".
            formatter: function (v) { return String(v).length > 0 ? String(v) : "manager" },
            colorFor: function (v) { return String(v).length > 0 ? "#c4c9d1" : "#6b7280" }
        },
        {
            title: "Port",
            key: "httpPort",
            // 0 means none was handed out. An instance without one is not reachable through the
            // gateway, whatever its state says, so it is marked rather than left blank.
            formatter: function (v) { return Number(v) > 0 ? String(v) : "—" },
            colorFor: function (v) { return Number(v) > 0 ? "#4f8cff" : "#6b7280" }
        },
        {
            // Not "State", though that is what the field is called: this is one process's state out
            // of EMM - STARTING, CRASHED, RESTARTING and the rest of the module lifecycle - and the
            // application's own State above it is EAP's answer to "is any instance running", which
            // has only two values. Naming both "State" reads as one of them being wrong.
            title: "Instance state",
            key: "state",
            colorFor: function (v) { return root.instanceStateColor(v) }
        },
        {
            title: "Restarts",
            key: "restartCount",
            // A pool that keeps its count only by restarting is one that looks healthy from the
            // outside, so the number is coloured.
            colorFor: function (v) { return Number(v) > 0 ? "#ffb545" : "#c4c9d1" }
        },
        {
            // Same underlying value as "Started", read the other way round: this is the one an
            // operator scans, and a young instance among old ones is one that has been restarting.
            // Not sortable - it would order identically to "Started", which is.
            title: "Up",
            key: "started",
            sortable: false,
            formatter: function (v) { return root.uptimeText(v) }
        },
        { title: "Started", key: "started", formatter: function (v) { return DateFormat.format(v) } }
    ]

    // What EAP accepts, in the order its own error message lists them. Java is the only one that
    // is versioned, and deliberately: a host runs several JDKs, a class file built for 25 will not
    // start on 21 at all, and leaving it to whichever "java" comes first on the manager's PATH
    // made the version an accident of the host. JAVA still means exactly that - whichever java
    // this machine calls java - and is what every application deployed before the versioned ones
    // existed still runs under, so it stays on the list rather than being quietly replaced.
    readonly property var runtimeOptions: ["JAVA", "JAVA21", "JAVA25", "PYTHON", "NODEJS", "BINARY"]

    // Changed through update-application, which touches only the field it is given. The manager
    // reads the changed definition as a new revision and restarts the pool onto it within a few
    // seconds - so this is a restart, not just a note about one.
    function setRuntime(runtime) {
        root.error = ""
        root.savingRuntime = true
        eapClient.updateApplication(root.applicationId, { runtime: runtime })
    }

    // "update-application" replaces each field it is given, so adding or removing one variable
    // means sending the resulting map - EAP has no per-variable call.
    function setEnvironment(environment) {
        root.error = ""
        root.savingEnvironment = true
        eapClient.updateApplication(root.applicationId, { environment: environment })
    }

    // Adding and changing are the same write: the map is sent whole either way, and a name that is
    // already in it takes the new value.
    function setEnvironmentVariable(name, value) {
        const environment = Object.assign({}, root.detail("environment", ({})))
        environment[name] = value
        root.setEnvironment(environment)
    }

    function removeEnvironmentVariable(name) {
        const environment = Object.assign({}, root.detail("environment", ({})))
        delete environment[name]
        root.setEnvironment(environment)
    }

    function environmentNames() {
        const environment = root.detail("environment", ({}))
        return environment ? Object.keys(environment).sort() : []
    }

    // Placement constraints, written the same way the environment is and for the same reason:
    // "update-application" replaces each field it is given, so adding or removing one label means
    // sending the resulting map.
    function setNodeLabels(labels) {
        root.error = ""
        root.savingNodeLabels = true
        eapClient.updateApplication(root.applicationId, { nodeLabels: labels })
    }

    function setNodeLabel(name, value) {
        const labels = Object.assign({}, root.detail("nodeLabels", ({})))
        labels[name] = value
        root.setNodeLabels(labels)
    }

    function removeNodeLabel(name) {
        const labels = Object.assign({}, root.detail("nodeLabels", ({})))
        delete labels[name]
        root.setNodeLabels(labels)
    }

    function nodeLabelNames() {
        const labels = root.detail("nodeLabels", ({}))
        return labels ? Object.keys(labels).sort() : []
    }

    function refresh() {
        if (!root.loggedIn || root.applicationId.length === 0)
            return
        root.error = ""
        // The list carries the same fields "get-application" would, and is what keeps every other
        // view in sync, so there is no separate per-application read here.
        eapClient.fetchApplications("")
        // The pool behind it. "list-modules" has no per-module read, so this asks for all of them
        // and picks its own out below - the same call the modules page makes.
        emmClient.fetchModules()
        // Nothing to do with this application, and asked for with it all the same: it is the
        // answer to "why is my application waiting on that site", which is asked here.
        root.refreshEgress()
    }

    // Measures the artifact through ESM, for the one case that still needs it: a definition from
    // before EAP recorded the size. Asks only when it is a different artifact from the one already
    // measured - see artifactSizeFor. Called after every definition read rather than from
    // refresh(), because the bucket and key it needs arrive with the definition.
    function refreshArtifactSize() {
        // EAP has answered; there is nothing to ask ESM, and nothing left over from a definition
        // that had to be measured before.
        if (root.recordedArtifactSize > 0) {
            root.artifactSizeFor = ""
            root.measuredArtifactSize = -1
            root.artifactSizeError = ""
            return
        }

        const bucketErn = String(root.detail("bucketErn", ""))
        const key = String(root.detail("artifactKey", ""))

        if (bucketErn.length === 0 || key.length === 0) {
            root.artifactSizeFor = ""
            root.measuredArtifactSize = -1
            root.artifactSizeError = ""
            return
        }

        const token = bucketErn + "\n" + key + "\n" + String(root.detail("md5Sum", ""))
        if (token === root.artifactSizeFor)
            return

        root.artifactSizeFor = token
        root.measuredArtifactSize = -1
        root.artifactSizeError = ""
        esmClient.fetchObjectSize(bucketErn, key)
    }

    onVisibleChanged: if (visible) refresh()
    onLoggedInChanged: if (loggedIn && visible) refresh()

    Connections {
        target: esmClient

        // Matched against the definition on screen rather than against what was asked for: these
        // signals reach every page, and the object browser asks about objects too.
        function onObjectSizeLoaded(bucketErn, key, size) {
            if (bucketErn !== String(root.detail("bucketErn", "")) || key !== String(root.detail("artifactKey", "")))
                return
            root.measuredArtifactSize = size
            root.artifactSizeError = ""
        }

        function onObjectSizeFailed(bucketErn, key, message) {
            if (bucketErn !== String(root.detail("bucketErn", "")) || key !== String(root.detail("artifactKey", "")))
                return
            root.measuredArtifactSize = -1
            root.artifactSizeError = message
        }
    }

    Timer {
        interval: appSettings.autoRefreshSeconds * 1000
        // Worth polling here specifically: after a start or stop this page is where the user is
        // watching for `state` and `instances` to catch up with `desiredState`.
        running: appSettings.autoRefreshSeconds > 0 && root.visible && root.loggedIn
        repeat: true
        onTriggered: root.refresh()
    }

    Connections {
        target: eapClient

        function onApplicationsLoaded(list, total) {
            for (const application of list) {
                if (application.applicationId !== root.applicationId) continue
                root.details = application
                root.error = ""
                root.refreshArtifactSize()
                return
            }
            // Gone from the list: deleted, by this page or from somewhere else. Its pool goes with
            // it rather than being left on screen describing processes of an application that no
            // longer exists.
            root.instances = []
            if (root.deleting) {
                root.deleting = false
                root.back()
            }
        }
        function onApplicationsFailed(message) {
            root.error = message
        }
        function onApplicationStateFailed(message) {
            root.deleting = false
            root.savingEnvironment = false
            root.savingRuntime = false
            root.savingNodeLabels = false
            root.savingArguments = false
            if (environmentDialog.opened) environmentDialog.errorText = message
            else if (runtimeDialog.opened) runtimeDialog.errorText = message
            else if (nodeLabelDialog.opened) nodeLabelDialog.errorText = message
            else if (argumentsDialog.opened) argumentsDialog.errorText = message
            else root.error = message
        }
        function onApplicationStateChanged(applicationId, desiredState) {
            if (applicationId !== root.applicationId) return
            root.savingEnvironment = false
            root.savingRuntime = false
            root.savingNodeLabels = false
            root.savingArguments = false
            // All of them are modal, so only the one that was open can have sent this.
            environmentDialog.close()
            runtimeDialog.close()
            nodeLabelDialog.close()
            argumentsDialog.close()
            // Stored already; re-reading is what puts the new map on screen.
            root.refresh()
        }
        function onApplicationScaled(applicationId, minInstances, maxInstances) {
            if (applicationId !== root.applicationId) return
            scaleDialog.scaling = false
            scaleDialog.close()
            // The bounds on this page come from the definition, so it is re-read rather than
            // patched: the pool below it has not moved yet either way, and will not until the
            // manager's next pass.
            root.refresh()
        }
        function onApplicationScaleFailed(message) {
            scaleDialog.scaling = false
            if (scaleDialog.opened) scaleDialog.errorText = message
            else root.error = message
        }

        function onEgressSitesLoaded(sites, defaults) {
            root.egressLoading = false
            root.egressError = ""
            // Filtered even though the request was scoped: the same signal answers an unscoped
            // listing of every application's sites, and one application's page shows one
            // application's. It is also what stops the previous application's rows standing here
            // for a moment after this page is pointed at another one.
            root.egressSites = sites.filter(entry => entry.applicationId === root.applicationId)
            root.egressDefaults = defaults
        }
        function onEgressSitesFailed(message) {
            root.egressLoading = false
            root.egressSites = []
            // Kept out of the page's own error line: the application reads fine whether or not the
            // installation's egress state can be asked for, and this belongs beside the table it
            // is about. The call is administrator-only, so this is also what everyone else sees.
            root.egressError = message
        }
        function onEgressSitesReload() {
            root.refreshEgress()
        }
        function onEgressLimitChanged(applicationId, site, limits) {
            if (applicationId !== root.applicationId) return
            egressDialog.saving = false
            egressDialog.close()
        }
        function onEgressLimitFailed(message) {
            egressDialog.saving = false
            if (egressDialog.opened) egressDialog.errorText = message
            else root.egressError = message
        }
    }

    Connections {
        target: emmClient

        function onModulesLoaded(list, total) {
            root.instancesError = ""
            for (const module of list) {
                // By the runtime name, which is what the manager registers the pool as. Module
                // names are installation-wide and an applicationId is not, so matching on the
                // applicationId would find nothing for any application deployed since EAP started
                // issuing runtime names - and would find the *wrong* namespace's pool for one
                // deployed before, if two namespaces have since come to share an id.
                if (module.name !== root.runtimeName) continue
                root.instances = module.instances || []
                return
            }
            // No pool at all, which is not an error: an application that has never been started,
            // or one stopped long enough for the manager to have let its slots go, simply has none.
            root.instances = []
        }
        function onModulesFailed(message) {
            root.instancesError = message
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
                leaf: root.applicationId
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.applicationId
                    subtitle: root.detail("ern", "")
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    Button {
                        text: "Runtime…"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: runtimeDialog.open()
                    }

                    Button {
                        text: "Scale…"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                        onClicked: scaleDialog.open()
                    }

                    Button {
                        text: "Start"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#4cd97b"
                        enabled: root.desiredState !== "RUNNING"
                        onClicked: {
                            root.error = ""
                            eapClient.startApplication(root.applicationId)
                        }
                    }

                    Button {
                        text: "Stop"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: "#ffb545"
                        enabled: root.desiredState === "RUNNING"
                        onClicked: {
                            root.error = ""
                            eapClient.stopApplication(root.applicationId)
                        }
                    }

                    Button {
                        text: "Delete"
                        highlighted: true
                        Material.theme: Material.Dark
                        Material.accent: "#ff6b6b"
                        enabled: !root.deleting
                        onClicked: deleteDialog.open()
                    }
                }
            }

            Text {
                visible: root.error.length > 0
                width: parent.width
                text: root.error
                color: "#ff6b6b"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            Flow {
                width: parent.width
                spacing: 18

                StatCard {
                    title: "State"
                    value: root.applicationState.length > 0 ? root.applicationState : "—"
                    // "Reconciling" is what a state on its way to the requested one is doing, and a
                    // crashed pool is not doing it: the manager restarts it or it stays where it
                    // is, and either way the word to read is the one EMM used.
                    trend: root.applicationState === root.desiredState
                           ? "as requested"
                           : root.applicationState === "CRASHED"
                             ? "crashed, asked for " + root.desiredState
                             : "reconciling to " + root.desiredState
                    trendUp: root.applicationState === "RUNNING"
                    accent: root.applicationStateColor(root.applicationState)
                    width: root.statWidth
                }
                StatCard {
                    title: "Type"
                    value: root.applicationType
                    // Said here because it decides what the card beside it means: for a PROCESS,
                    // STOPPED is a fault to look into, and for a JOB it is the ordinary end.
                    trend: root.applicationType === "JOB"
                           ? "runs once, then it is done"
                           : root.applicationType === "UNKNOWN"
                             ? "not a type this build knows"
                             : "kept up, an exit is a fault"
                    // Down for UNKNOWN alone: a definition written by a newer euclid, which this
                    // one runs as a process because that is the only behaviour it has.
                    trendUp: root.applicationType !== "UNKNOWN"
                    accent: root.applicationTypeColor(root.applicationType)
                    width: root.statWidth
                }
                StatCard {
                    title: "Instances"
                    value: String(root.detail("instances", 0))
                    trend: "scales " + root.detail("minInstances", 1) + " to " + root.detail("maxInstances", 1)
                    trendUp: root.detail("instances", 0) > 0
                    accent: "#4f8cff"
                    width: root.statWidth
                }
                StatCard {
                    title: "Runtime"
                    value: root.detail("runtime", "—")
                    trend: "starts the artifact"
                    trendUp: true
                    accent: "#c56bff"
                    width: root.statWidth
                }
                StatCard {
                    title: "Runs as"
                    value: root.detail("userId", "—")
                    // "app-<id>" is the technical principal EAP creates with the application and
                    // deletes with it; anything else is an EAM user somebody named on purpose.
                    trend: root.ownPrincipal ? "its own principal, signs with its key" : "an existing user's identity"
                    trendUp: true
                    accent: "#ffb545"
                    width: root.statWidth
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

                    Text { text: "Definition"; color: "white"; font.pixelSize: 15; font.bold: true }

                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 24
                        rowSpacing: 16

                        DetailField { width: (identityCol.width - 48) / 3; label: "Application ID"; value: root.applicationId }
                        DetailField {
                            width: (identityCol.width - 48) / 3
                            // The one field on this page that an operator takes to a host: the
                            // module row, the data directory, the socket, the log channel and the
                            // principal are all called this, and none of them is called the
                            // applicationId. Copyable for exactly that reason.
                            label: "Runs as"
                            value: root.runtimeName
                            copyable: true
                        }
                        DetailField {
                            width: (identityCol.width - 48) / 3
                            // Part of what identifies the application, not just where it works: an
                            // applicationId is unique within a namespace, so the id alone does not
                            // say which application this is.
                            label: "Namespace"
                            value: String(root.detail("namespace", "")).length > 0
                                   ? root.detail("namespace", "") : "— (account root)"
                        }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Runtime"; value: root.detail("runtime", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Artifact"; value: root.detail("artifactKey", "—") }
                        DetailField {
                            width: (identityCol.width - 48) / 3
                            label: "Artifact size"
                            // Three states, and they are worth telling apart: the size, the reason
                            // there is none, and the ellipsis of an answer still on its way. A bare
                            // "—" while the request is in flight would say the file is missing when
                            // nobody has looked yet; a bare "—" afterwards would hide why, and the
                            // reasons are ordinary enough to act on - the bucket is in another
                            // namespace, or the artifact was deleted out from under the definition.
                            // DetailField elides, so a long message cannot widen the column.
                            value: root.artifactSize >= 0
                                   ? SizeFormat.format(root.artifactSize)
                                   : (root.artifactSizeError.length > 0 ? "— " + root.artifactSizeError : "…")
                        }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Version"; value: root.detail("version", "—") }
                        DetailField {
                            width: (identityCol.width - 48) / 3
                            label: "MD5 sum"
                            // EAP records the checksum of the artifact it deployed. Copyable
                            // because the thing you do with it is compare it against the build you
                            // have in your hand - md5sum on the jar you think is running.
                            value: root.detail("md5Sum", "—")
                            copyable: root.detail("md5Sum", "").length > 0
                        }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Account ID"; value: root.detail("accountId", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Region"; value: root.detail("region", "—") }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Requested state"; value: root.desiredState.length > 0 ? root.desiredState : "—" }
                        DetailField {
                            width: (identityCol.width - 48) / 3
                            label: "Ready timeout"
                            value: root.detail("readyTimeoutMs", 0) + " ms"
                        }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Created"; value: DateFormat.format(root.detail("created", "")) }
                        DetailField { width: (identityCol.width - 48) / 3; label: "Modified"; value: DateFormat.format(root.detail("modified", "")) }
                    }

                    DetailField {
                        width: identityCol.width
                        label: "Command"
                        // The whole line rather than the command field alone: what starts the
                        // process is the executable, the artifact and the arguments together, and
                        // an application that names no command still has the first two.
                        value: root.commandLineText(root.arguments)
                        copyable: true
                    }
                    DetailField { width: identityCol.width; label: "Bucket ERN"; value: root.detail("bucketErn", "—"); copyable: true }
                    DetailField { width: identityCol.width; label: "Application ERN"; value: root.detail("ern", "—"); copyable: true }
                }
            }

            // The arguments the process is started with, after the executable and the artifact.
            // Their own tile rather than a field in the identity grid: they are a list, they are
            // ordered, and they are the one part of the command line an operator sets.
            Rectangle {
                width: parent.width
                height: argumentsCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: argumentsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: argumentsHeader.implicitHeight

                        Text {
                            id: argumentsHeader
                            text: "Command Line Arguments"
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Button {
                            text: "Edit…"
                            flat: true
                            anchors.right: parent.right
                            anchors.verticalCenter: argumentsHeader.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: argumentsDialog.open()
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 11
                        text: "Passed to the application after the artifact, in this order. What comes before "
                              + "them is the runtime's interpreter - or the command this application names, which "
                              + "replaces it - and the artifact itself."
                    }

                    // One per line, so an argument that contains a space is still one argument.
                    Column {
                        width: parent.width
                        spacing: 4
                        visible: root.arguments.length > 0

                        Repeater {
                            model: root.arguments
                            Text {
                                width: argumentsCol.width
                                text: (index + 1) + ".  " + modelData
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                font.family: "monospace"
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 12
                        visible: root.arguments.length === 0
                        text: "None. The application is started with nothing after the artifact."
                    }

                    DetailField {
                        width: argumentsCol.width
                        label: "Started as"
                        value: root.commandLineText(root.arguments)
                        copyable: true
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: environmentCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: environmentCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: environmentHeaderRow.implicitHeight

                        Row {
                            id: environmentHeaderRow
                            spacing: 10
                            Text { text: "Environment"; color: "white"; font.pixelSize: 15; font.bold: true }
                            BusyIndicator {
                                running: root.savingEnvironment
                                visible: root.savingEnvironment
                                width: 18
                                height: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Button {
                            text: "+ Add variable"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: environmentHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            enabled: !root.savingEnvironment
                            onClicked: environmentDialog.openFor("", "")
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Passed to the process on start, on top of the socket path and credentials euclid-mgr "
                              + "supplies itself. A running application keeps its current environment until the "
                              + "reconciler next restarts it."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.environmentNames().length === 0
                        text: "No environment variables set."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.environmentNames()
                        delegate: Row {
                            id: environmentRow
                            required property string modelData

                            width: environmentCol.width
                            height: 26
                            spacing: 12

                            Text {
                                text: environmentRow.modelData
                                color: "#e5e7eb"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                width: Math.min(260, environmentRow.width * 0.35)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.detail("environment", ({}))[environmentRow.modelData]
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: environmentRow.width - Math.min(260, environmentRow.width * 0.35) - 140
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Edit"
                                color: editVariableArea.containsMouse ? "#4f8cff" : "#9aa1ac"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    id: editVariableArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.savingEnvironment
                                    onClicked: environmentDialog.openFor(environmentRow.modelData,
                                        String(root.detail("environment", ({}))[environmentRow.modelData]))
                                }
                            }
                            Text {
                                text: "Remove"
                                color: removeVariableArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    id: removeVariableArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.savingEnvironment
                                    onClicked: root.removeEnvironmentVariable(environmentRow.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // How fast this application may call the outside. It asks EAP for a permit before
            // each request - a token from the site's bucket and a slot among its requests to that
            // site in flight - so these are the numbers that decide whether it is made to wait.
            //
            // Per application and per site: another application calling the same site has its own
            // bucket and is not slowed by this one. Per application rather than per instance,
            // because the autoscaler would multiply a limit each instance kept.
            Rectangle {
                width: parent.width
                height: egressCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: egressCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: egressHeader.implicitHeight

                        Text {
                            id: egressHeader
                            text: "Egress Rate Limits"
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: egressHeader.verticalCenter
                            spacing: 8

                            BusyIndicator {
                                running: root.egressLoading
                                visible: root.egressLoading
                                width: 18; height: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Button {
                                // The application's own default, in between one site's limit and
                                // the installation's. Offered as a button because it is a setting
                                // rather than a site, and nothing will ever create its row by
                                // being called.
                                text: root.egressHasOwnDefault ? "Default for all sites…" : "Set a default…"
                                flat: true
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                onClicked: egressDialog.openFor(root.allSites, root.egressFallback)
                            }
                            Button {
                                text: "Add site…"
                                flat: true
                                Material.theme: Material.Dark
                                Material.accent: "#4f8cff"
                                onClicked: egressDialog.openFor("")
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 11
                        text: "A site appears here the first time this application asks for a permit to call it. "
                              + "What one is held to: its own limits, or this application's default for all sites, "
                              + "or the installation's - "
                              + (root.egressHasOwnDefault
                                 ? "this application sets its own default, and the installation's is "
                                 : "this application sets no default of its own, so the installation's applies: ")
                              + root.egressDefaultText + "."
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#ff6b6b"
                        font.pixelSize: 12
                        visible: root.egressError.length > 0
                        text: root.egressError
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 12
                        visible: root.egressError.length === 0 && !root.egressLoading && root.egressSites.length === 0
                        text: "This application has not called an outside site yet. One appears here the first "
                              + "time it asks for a permit to reach one."
                    }

                    DataTable {
                        width: parent.width
                        visible: root.egressSites.length > 0
                        columns: root.egressColumns
                        rows: root.egressSites
                        totalCount: root.egressSites.length
                        // Everything at once: list-egress-sites answers with every site there is,
                        // and there is no page to ask for.
                        pageSize: Math.max(1, root.egressSites.length)
                        pageIndex: 0
                        pageSizeSelectable: false
                        searchable: false
                        emptyText: "This application has not called an outside site yet."
                        onRefreshRequested: root.refreshEgress()

                        contextMenuActions: [
                            {
                                text: "Set limits…",
                                action: function(row) { egressDialog.openFor(row.site, row) }
                            },
                            {
                                // Back to what it would be held to without a limit of its own -
                                // this application's default for all sites, or the installation's.
                                // Not "no limits", and refused by the server for a site that has
                                // none of its own, which is why it is greyed out for those.
                                text: "Use the inherited limits",
                                enabled: function(row) { return !!row && row.limitsSet === true },
                                action: function(row) {
                                    eapClient.deleteEgressLimit(root.applicationId, row.site)
                                }
                            }
                        ]
                    }
                }
            }

            // Where this application may run, as opposed to what it runs with. Under the
            // environment because the two are edited the same way and read the same way - a map of
            // names to values, replaced whole on every change - but they are answering different
            // questions, which is why this is a tile of its own rather than another section of that
            // one.
            Rectangle {
                width: parent.width
                height: nodeLabelsCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: nodeLabelsCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: nodeLabelsHeaderRow.implicitHeight

                        Row {
                            id: nodeLabelsHeaderRow
                            spacing: 10
                            Text { text: "Node Labels"; color: "white"; font.pixelSize: 15; font.bold: true }
                            BusyIndicator {
                                running: root.savingNodeLabels
                                visible: root.savingNodeLabels
                                width: 18
                                height: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Button {
                            text: "+ Add label"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: nodeLabelsHeaderRow.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            enabled: !root.savingNodeLabels
                            onClicked: nodeLabelDialog.openFor("", "")
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Labels a worker node must carry - all of them - for this application to be placed there. "
                              + "The scalable half of a placement constraint: naming nodes means editing every "
                              + "application when a machine is replaced, where a label follows whichever machine "
                              + "carries it."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.nodeLabelNames().length === 0
                        // Not a restriction waiting to be filled in: no constraint is the permissive
                        // case, and it is what every application on an installation without workers
                        // has and must go on having.
                        text: "No constraints: this application may run on any node, including the manager's own host."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: root.nodeLabelNames()
                        delegate: Row {
                            id: nodeLabelRow
                            required property string modelData

                            width: nodeLabelsCol.width
                            height: 26
                            spacing: 12

                            Text {
                                text: nodeLabelRow.modelData
                                color: "#e5e7eb"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                width: Math.min(260, nodeLabelRow.width * 0.35)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: root.detail("nodeLabels", ({}))[nodeLabelRow.modelData]
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: nodeLabelRow.width - Math.min(260, nodeLabelRow.width * 0.35) - 140
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Edit"
                                color: editLabelArea.containsMouse ? "#4f8cff" : "#9aa1ac"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    id: editLabelArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.savingNodeLabels
                                    onClicked: nodeLabelDialog.openFor(nodeLabelRow.modelData,
                                        String(root.detail("nodeLabels", ({}))[nodeLabelRow.modelData]))
                                }
                            }
                            Text {
                                text: "Remove"
                                color: removeLabelArea.containsMouse ? "#ff6b6b" : "#9aa1ac"
                                font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    id: removeLabelArea
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    enabled: !root.savingNodeLabels
                                    onClicked: root.removeNodeLabel(nodeLabelRow.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // The processes, as opposed to the definition above them. Everything on this page so
            // far is what was asked for; this is what is actually running - which pid, on which
            // port, since when, and how many times it has had to be restarted to stay that way.
            //
            // Laid out as a heading over a DataTable rather than inside a tile of its own: the
            // table draws its own card, and nesting that in another one puts an identical border
            // a few pixels inside itself.
            Column {
                width: parent.width
                spacing: 14

                Row {
                    spacing: 10
                    Text {
                        text: "Instances (" + root.runningInstances + ")"
                        color: "white"
                        font.pixelSize: 15
                        font.bold: true
                    }
                    Text {
                        // Only when the two differ: on a healthy pool every slot is a running
                        // process and saying so twice is noise.
                        visible: root.heldSlots > 0
                        text: "+ " + root.heldSlots + " not running"
                        color: "#ffb545"
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: "The processes euclid-mgr is running for this application. Each is given a TCP port of "
                          + "its own at start, which is what the API gateway routes to - a port written into the "
                          + "application's own configuration would be bound by the first instance and refused to "
                          + "every other. The ports change as the pool is scaled or restarted."
                }

                DataTable {
                    width: parent.width
                    columns: root.instanceColumns
                    rows: root.instancePage
                    totalCount: root.filteredInstances.length
                    pageSize: root.instancePageSize
                    pageIndex: root.clampedInstancePage
                    // Never true: the pool arrives with the application, and a spinner here would
                    // only report that the page as a whole is reloading, which it already shows.
                    loading: false
                    error: root.instancesError
                    searchPlaceholder: "Filter by instance, pid, host, port or state..."
                    emptyText: root.instanceFilter.length > 0
                               ? "No instance matches that."
                               : (root.desiredState === "RUNNING"
                                  ? "No instances yet - the manager has been asked for this application and has not started it."
                                  : "No instances. The application is not running.")
                    rowsClickable: false
                    sortKey: root.instanceSortColumn
                    sortAscending: root.instanceSortAscending

                    onSearchChanged: (text) => {
                        root.instanceFilter = text
                        root.instancePageIndex = 0
                    }
                    onRefreshRequested: root.refresh()
                    onPageChanged: (index) => { root.instancePageIndex = index }
                    // Back to the first page: page four of fifty-row pages is not page four of
                    // ten-row pages.
                    onPageSizeRequested: (size) => {
                        root.instancePageSize = size
                        root.instancePageIndex = 0
                    }
                    onSortRequested: (key, ascending) => {
                        root.instanceSortColumn = key
                        root.instanceSortAscending = ascending
                        root.instancePageIndex = 0
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: resourcesCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1

                Column {
                    id: resourcesCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 14

                    Item {
                        width: parent.width
                        height: resourcesHeader.implicitHeight

                        Text {
                            id: resourcesHeader
                            text: "Resources"
                            color: "white"
                            font.pixelSize: 15
                            font.bold: true
                        }

                        // The other half of the same subject, and the reason it sits here: this
                        // tile lists what may be reached, and the declaration behind the button
                        // says which of it the application owns and which belongs to somebody else.
                        Button {
                            text: "Connections…"
                            flat: true
                            anchors.right: parent.right
                            anchors.verticalCenter: resourcesHeader.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            onClicked: connectionsDialog.open()
                        }
                    }

                    Text {
                        width: parent.width
                        text: "Buckets and queues this application may act on, mirrored onto its principal's grants - "
                              + "ESM and EQS are what enforce them."
                        color: "#6b7280"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.resourceList().length === 0
                        // Not "none": an empty list is the permissive case, and reading it as a
                        // restriction would be exactly backwards.
                        text: "Unrestricted within account " + root.detail("accountId", "—") + "."
                        color: "#6b7280"
                        font.pixelSize: 12
                    }

                    Flow {
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.resourceList()
                            delegate: Rectangle {
                                id: resourceChip
                                required property string modelData

                                radius: 8
                                color: "#2c3648"
                                height: 26
                                width: resourceChipText.implicitWidth + 20
                                Text {
                                    id: resourceChipText
                                    anchors.centerIn: parent
                                    text: resourceChip.modelData
                                    color: "#c4c9d1"
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Reads the declaration itself when it is opened, rather than on every visit to the page: most
    // of them are never looked at, and it is a second round trip - to ESM rather than to EAP.
    ApplicationConnectionsDialog {
        id: connectionsDialog
        applicationId: root.applicationId
        bucketErn: root.detail("bucketErn", "")
    }

    // One site's limits. The three are read and written together even though the server takes them
    // one at a time: a dialog about a single number would be a dialog about a number rather than
    // about what the site is allowed.
    Dialog {
        id: egressDialog
        modal: true
        anchors.centerIn: parent
        width: 460
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string site: ""
        property bool known: false
        property bool saving: false
        property string errorText: ""

        // The application's default for all its sites, rather than one site. Named rather than
        // typed: "*" is what the server stores it under, not something to ask anybody to spell.
        readonly property bool allSitesRow: egressDialog.site === root.allSites

        readonly property string wantedSite: siteField.text.trim()
        readonly property real wantedRate: parseFloat(rateField.text)
        readonly property real wantedBurst: parseFloat(burstField.text)
        readonly property int wantedConcurrent: parseInt(concurrentField.text, 10)

        // What the server would refuse, and one thing it would not: a burst below 1 is raised to 1
        // rather than refused, which is worth saying before it happens rather than afterwards.
        readonly property string problem: {
            if (!egressDialog.allSitesRow && egressDialog.wantedSite.length === 0)
                return "Name the site, e.g. downloads.example.com"
            if (isNaN(egressDialog.wantedRate) || egressDialog.wantedRate < 0)
                return "Requests per second cannot be negative - 0 is what says \"no rate limit\"."
            if (isNaN(egressDialog.wantedBurst) || egressDialog.wantedBurst < 1)
                return "The burst has to be at least 1: a bucket that cannot hold one token never grants a request."
            if (isNaN(egressDialog.wantedConcurrent) || egressDialog.wantedConcurrent < 0)
                return "Concurrent requests cannot be negative - 0 is what says \"no limit\"."
            return ""
        }

        // Opened on the row's limits, or on the installation's default for a site that has none:
        // a change is made against what is in force, not from an empty form.
        function openFor(site, row) {
            egressDialog.site = site === root.allSites ? root.allSites : site
            egressDialog.known = site.length > 0
            egressDialog.saving = false
            egressDialog.errorText = ""
            const limits = row ? row : root.egressDefaults
            siteField.text = site
            rateField.text = String(limits && limits.requestsPerSecond !== undefined ? limits.requestsPerSecond : 2)
            burstField.text = String(limits && limits.burst !== undefined ? limits.burst : 2)
            concurrentField.text = String(limits && limits.concurrent !== undefined ? limits.concurrent : 4)
            egressDialog.open()
            if (egressDialog.known || egressDialog.allSitesRow) rateField.forceActiveFocus()
            else siteField.forceActiveFocus()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: egressDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: egressDialog.allSitesRow ? "Default Egress Limits" : "Egress Limits"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: egressDialog.allSitesRow
                          ? "What " + root.applicationId + " may do to any site it has no limits of its own for. "
                            + "Between one site's limits and the installation's."
                          : "What " + root.applicationId + " may do to this one site. Its own bucket and its own "
                            + "slots - another application calling the same site is not slowed by it."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }

            Column {
                width: parent.width
                spacing: 6
                visible: !egressDialog.allSitesRow
                Text { text: "Site"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: siteField
                    width: parent.width
                    placeholderText: "downloads.example.com"
                    // Fixed once the site exists: it is what the limits are keyed by, so editing it
                    // would set limits on a different site rather than move these.
                    enabled: !egressDialog.known
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                }
            }

            Row {
                width: parent.width
                spacing: 12

                Column {
                    width: (parent.width - 24) / 3
                    spacing: 6
                    Text { text: "Requests/s"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: rateField
                        width: parent.width
                        validator: DoubleValidator { bottom: 0; top: 100000; decimals: 2; notation: DoubleValidator.StandardNotation }
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }
                Column {
                    width: (parent.width - 24) / 3
                    spacing: 6
                    Text { text: "Burst"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: burstField
                        width: parent.width
                        validator: DoubleValidator { bottom: 1; top: 100000; decimals: 0; notation: DoubleValidator.StandardNotation }
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }
                Column {
                    width: (parent.width - 24) / 3
                    spacing: 6
                    Text { text: "Concurrent"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: concurrentField
                        width: parent.width
                        validator: IntValidator { bottom: 0; top: 10000 }
                        Material.theme: Material.Dark
                        Material.accent: "#4f8cff"
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "The rate is averaged; the burst is how many requests may go before it applies. "
                      + "Concurrent is how many may be in flight at once, each holding a leased slot - so an "
                      + "instance killed mid-download gives its slot back when the lease runs out rather than "
                      + "never. Zero means no limit, for the rate and the concurrency alike."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: egressDialog.problem.length > 0 || egressDialog.errorText.length > 0
                text: egressDialog.errorText.length > 0 ? egressDialog.errorText : egressDialog.problem
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Cancel"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    enabled: !egressDialog.saving
                    onClicked: egressDialog.close()
                }

                Button {
                    text: egressDialog.saving ? "Saving…" : "Apply"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !egressDialog.saving && egressDialog.problem.length === 0
                    onClicked: {
                        egressDialog.saving = true
                        egressDialog.errorText = ""
                        root.egressError = ""
                        eapClient.setEgressLimit(root.applicationId,
                                                 egressDialog.allSitesRow ? root.allSites : egressDialog.wantedSite,
                                                 egressDialog.wantedRate, egressDialog.wantedBurst,
                                                 egressDialog.wantedConcurrent)
                    }
                }
            }
        }
    }

    // One argument per line. A list editor with rows and arrows would be more ceremony than the
    // thing deserves, and lines keep what matters: the order, and the fact that an argument may
    // contain spaces - "--opt=a b" is one argument, and splitting the whole line on whitespace
    // would quietly make it two.
    Dialog {
        id: argumentsDialog
        modal: true
        anchors.centerIn: parent
        width: 560
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string errorText: ""

        // Blank lines dropped, each line trimmed: a trailing newline is how a text area ends, not
        // an empty argument somebody meant to pass.
        readonly property var wanted: {
            const out = []
            for (const line of argumentsField.text.split("\n")) {
                const argument = line.trim()
                if (argument.length > 0) out.push(argument)
            }
            return out
        }

        readonly property bool changed: argumentsDialog.wanted.join("\u0000") !== root.arguments.join("\u0000")

        onOpened: {
            argumentsDialog.errorText = ""
            // Assigned rather than bound, so the page's own refresh cannot rewrite what is being
            // typed underneath the cursor.
            argumentsField.text = root.arguments.join("\n")
            argumentsField.forceActiveFocus()
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        contentItem: Column {
            width: argumentsDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Command Line Arguments"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: "One per line, in the order they are passed. They follow the artifact, so this is "
                          + "where an application's own options go - not the interpreter's."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }

            Rectangle {
                width: parent.width
                height: 180
                radius: 10
                color: "#14161b"
                border.color: "#2c313c"
                border.width: 1

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 8
                    clip: true

                    TextArea {
                        id: argumentsField
                        placeholderText: "--config\n/etc/orders.json\n--verbose"
                        color: "#e5e7eb"
                        font.pixelSize: 12
                        font.family: "monospace"
                        selectByMouse: true
                        wrapMode: TextEdit.NoWrap
                        background: null
                    }
                }
            }

            // What it will actually be started with, rebuilt as the lines are typed: an argument
            // list is hard to read against an executable nobody restated.
            Column {
                width: parent.width
                spacing: 4
                Text { text: "Started as"; color: "#9aa1ac"; font.pixelSize: 12 }
                Text {
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    text: root.commandLineText(argumentsDialog.wanted)
                    color: "#c4c9d1"
                    font.pixelSize: 11
                    font.family: "monospace"
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#e0a458"
                font.pixelSize: 12
                // The part that is not visible from the dialog: this is a change to the definition
                // like any other, and the manager restarts the pool onto a changed definition.
                visible: argumentsDialog.changed
                text: "⚠  Saving restarts the application's instances: an argument list is read when a "
                      + "process starts, so the running ones are replaced to pick it up."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: argumentsDialog.errorText.length > 0
                text: argumentsDialog.errorText
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Cancel"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    enabled: !root.savingArguments
                    onClicked: argumentsDialog.close()
                }

                Button {
                    text: root.savingArguments ? "Saving…" : "Save"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !root.savingArguments && argumentsDialog.changed
                    onClicked: root.setArguments(argumentsDialog.wanted)
                }
            }
        }
    }

    // Which interpreter the manager starts the artifact with. A change here is a change to the
    // definition like any other, so the pool restarts onto it - which is the point when the
    // version is what is being changed, and worth saying before it happens.
    Dialog {
        id: runtimeDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string errorText: ""
        readonly property string currentRuntime: root.detail("runtime", "")
        readonly property string wantedRuntime: runtimeCombo.currentText

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            runtimeDialog.errorText = ""
            // Assigned rather than bound, so the page's own refresh cannot move the selection
            // while it is being chosen. An application whose runtime is not on the list - one
            // stored as UNKNOWN, or a value from a newer server - leaves the box on the first
            // entry rather than on nothing, and the line below still says what it is now.
            runtimeCombo.currentIndex = Math.max(0, root.runtimeOptions.indexOf(runtimeDialog.currentRuntime))
        }

        contentItem: Column {
            width: runtimeDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Runtime"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: root.applicationId + "  ·  currently "
                          + (runtimeDialog.currentRuntime.length > 0 ? runtimeDialog.currentRuntime : "—")
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            ComboBox {
                id: runtimeCombo
                width: parent.width
                model: root.runtimeOptions
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                // Said here because the difference is invisible in the row: all three run jars.
                text: "JAVA is whichever java the host calls java. JAVA21 and JAVA25 ask for that version by "
                      + "name, which is what a jar built for one of them needs - a class file built for 25 does "
                      + "not start under 21 at all. The installation has to have that runtime configured, or the "
                      + "application fails to start with the name it was looking for."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ffb545"
                font.pixelSize: 12
                // Only when it is about to do nothing, which is not obvious from this dialog: the
                // runtime decides the interpreter, and an application that spells out its own
                // command is not started through one.
                visible: String(root.detail("command", "")).length > 0
                text: "⚠  This application starts with its own command (" + root.detail("command", "")
                      + "), which the runtime does not decide. Changing it here still restarts the pool."
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: runtimeDialog.errorText.length > 0
                text: runtimeDialog.errorText
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Cancel"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    enabled: !root.savingRuntime
                    onClicked: runtimeDialog.close()
                }

                Button {
                    text: root.savingRuntime ? "Saving…" : "Apply"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !root.savingRuntime && runtimeDialog.wantedRuntime !== runtimeDialog.currentRuntime
                    onClicked: root.setRuntime(runtimeDialog.wantedRuntime)
                }
            }
        }
    }

    // The same shape as the environment dialog next door, because a label is the same kind of
    // thing - a name and a value in a map that is replaced whole. What differs is what it means,
    // which is what the wording carries.
    Dialog {
        id: nodeLabelDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string errorText: ""
        // Non-empty while an existing label is being changed: its name is then fixed. A rename is a
        // remove plus an add, which is two different maps and not what "edit" means here.
        property string editingName: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        function openFor(name, value) {
            nodeLabelDialog.editingName = name
            nodeLabelDialog.errorText = ""
            nodeLabelDialog.open()
            // Assigned rather than bound, so the page's own refresh cannot overwrite what is being
            // typed.
            labelNameField.text = name
            labelValueField.text = value
            if (name.length === 0) labelNameField.forceActiveFocus()
            else labelValueField.forceActiveFocus()
        }

        contentItem: Column {
            width: nodeLabelDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: nodeLabelDialog.editingName.length > 0 ? "Edit Node Label" : "Add Node Label"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    text: "Matched against the labels a worker registered itself with. Every label here has to "
                          + "match for a node to be a candidate, so each one added narrows where this application "
                          + "can run."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: labelNameField
                    width: parent.width
                    placeholderText: "e.g. gpu"
                    enabled: nodeLabelDialog.editingName.length === 0
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: labelValueField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Value"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: labelValueField
                    width: parent.width
                    placeholderText: "e.g. true"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (addLabelButton.enabled) addLabelButton.clicked()
                }
                Text {
                    // The map is replaced wholesale, so re-using a name overwrites rather than
                    // duplicating - worth saying, since that is not obvious from a form called "add".
                    visible: nodeLabelDialog.editingName.length === 0
                             && labelNameField.text.trim().length > 0
                             && root.nodeLabelNames().indexOf(labelNameField.text.trim()) >= 0
                    text: "\"" + labelNameField.text.trim() + "\" is already required; this replaces its value."
                    color: "#ffb545"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Text {
                    // The consequence of getting it wrong, which is quiet rather than loud: a
                    // constraint no node satisfies is not refused, it simply leaves the application
                    // unplaced.
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: "#6b7280"
                    font.pixelSize: 11
                    text: "A constraint no node carries is not an error - the application is placed nowhere and "
                          + "waits. Check the worker nodes list for what is actually labelled."
                }
                Text {
                    text: nodeLabelDialog.errorText
                    color: "#ff6b6b"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                    visible: text.length > 0
                }
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Cancel"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    enabled: !root.savingNodeLabels
                    onClicked: nodeLabelDialog.close()
                }

                Button {
                    id: addLabelButton
                    text: root.savingNodeLabels ? "Saving…"
                          : (nodeLabelDialog.editingName.length > 0 ? "Apply" : "Add")
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    // A value is required, not optional as it is for an environment variable: the
                    // server refuses a label with an empty one ("label 'x' needs a non-empty string
                    // value"), and a form that lets it be sent only to have it come back refused is
                    // a round trip spent learning a rule the button could have held.
                    enabled: !root.savingNodeLabels && labelNameField.text.trim().length > 0
                             && labelValueField.text.trim().length > 0
                    onClicked: {
                        nodeLabelDialog.errorText = ""
                        root.setNodeLabel(labelNameField.text.trim(), labelValueField.text)
                    }
                }
            }
        }
    }

    Dialog {
        id: environmentDialog
        modal: true
        anchors.centerIn: parent
        width: 380
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        property string errorText: ""
        // Non-empty while an existing variable is being changed: its name is then fixed. A rename
        // is a remove plus an add, which is two different maps and not what "edit" means here.
        property string editingName: ""

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        // Both ways in, the way the attribute dialog on the object page does it: the fields are
        // assigned rather than bound, so the page's own refresh cannot overwrite what is being
        // typed. Adding is the same call with an empty name.
        function openFor(name, value) {
            environmentDialog.editingName = name
            environmentDialog.errorText = ""
            environmentDialog.open()
            variableNameField.text = name
            variableValueField.text = value
            if (name.length === 0) variableNameField.forceActiveFocus()
            else variableValueField.forceActiveFocus()
        }

        contentItem: Column {
            width: environmentDialog.availableWidth
            spacing: 16

            Column {
                width: parent.width
                spacing: 4
                Text {
                    text: environmentDialog.editingName.length > 0 ? "Edit Environment Variable"
                                                                   : "Add Environment Variable"
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    text: "Handed to the process on start. Names beginning with EUCLID_ are set by euclid-mgr "
                          + "itself, so one set here under the same name is the one that loses."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Name"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: variableNameField
                    width: parent.width
                    placeholderText: "e.g. LOG_LEVEL"
                    enabled: environmentDialog.editingName.length === 0
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: variableValueField.forceActiveFocus()
                }
            }

            Column {
                width: parent.width
                spacing: 6
                Text { text: "Value"; color: "#9aa1ac"; font.pixelSize: 12 }
                TextField {
                    id: variableValueField
                    width: parent.width
                    placeholderText: "e.g. debug"
                    Material.accent: "#4f8cff"
                    selectByMouse: true
                    Keys.onReturnPressed: if (addVariableButton.enabled) addVariableButton.clicked()
                }
                Text {
                    // The map is replaced wholesale, so re-using a name overwrites rather than
                    // duplicating - worth saying, since that is not obvious from a form called "add".
                    // Nothing to warn about when editing: overwriting that one value is the point.
                    visible: environmentDialog.editingName.length === 0
                             && variableNameField.text.trim().length > 0
                             && root.environmentNames().indexOf(variableNameField.text.trim()) >= 0
                    text: "\"" + variableNameField.text.trim() + "\" is already set; this replaces its value."
                    color: "#ffb545"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
                Text {
                    text: environmentDialog.errorText
                    color: "#ff6b6b"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                    visible: text.length > 0
                }
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Cancel"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    onClicked: environmentDialog.close()
                }

                BusyIndicator {
                    running: root.savingEnvironment
                    visible: root.savingEnvironment
                    width: 22
                    height: 22
                    anchors.right: addVariableButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Button {
                    id: addVariableButton
                    text: environmentDialog.editingName.length > 0 ? "Save" : "Add"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: !root.savingEnvironment && variableNameField.text.trim().length > 0
                    onClicked: {
                        environmentDialog.errorText = ""
                        root.setEnvironmentVariable(variableNameField.text.trim(), variableValueField.text)
                    }
                }
            }
        }
    }

    // The autoscaler's bounds, sent through "scale-application" - the one call that changes them,
    // and the only one that will refuse a pair it cannot write instead of correcting it. Nothing
    // else about the definition is touched, and the manager reconciles the pool against the new
    // bounds on its next pass rather than here.
    Dialog {
        id: scaleDialog
        modal: true
        anchors.centerIn: parent
        width: 420
        padding: 28
        topPadding: 24
        bottomPadding: 24
        standardButtons: Dialog.NoButton

        // Held open until the server answers, so a refusal lands beside the fields it is about.
        property bool scaling: false
        property string errorText: ""

        readonly property int wantedMin: parseInt(minField.text, 10)
        readonly property int wantedMax: parseInt(maxField.text, 10)
        readonly property bool valid: !isNaN(scaleDialog.wantedMin) && !isNaN(scaleDialog.wantedMax)
                                      && scaleDialog.wantedMin >= 1 && scaleDialog.wantedMax >= 1
                                      && scaleDialog.wantedMin <= scaleDialog.wantedMax

        // The same three EAP checks before it writes, said here first so they are read before the
        // request rather than after it.
        readonly property string problem: {
            if (isNaN(scaleDialog.wantedMin) || isNaN(scaleDialog.wantedMax)) return ""
            if (scaleDialog.wantedMin < 1) return "An application's floor is at least 1 - stop it to take it off the air."
            if (scaleDialog.wantedMax < 1) return "The ceiling has to be at least 1."
            if (scaleDialog.wantedMin > scaleDialog.wantedMax)
                return "The floor (" + scaleDialog.wantedMin + ") cannot be above the ceiling (" + scaleDialog.wantedMax + ")."
            return ""
        }

        background: Rectangle {
            radius: 16
            color: "#1b1e25"
            border.color: "#2c313c"
            border.width: 1
        }

        onOpened: {
            scaleDialog.scaling = false
            scaleDialog.errorText = ""
            minField.text = String(root.minInstances)
            maxField.text = String(root.maxInstances)
            minField.forceActiveFocus()
            minField.selectAll()
        }

        contentItem: Column {
            width: scaleDialog.availableWidth
            spacing: 18

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Scale Application"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: root.applicationId + "  ·  " + root.detail("instances", 0) + " running, currently "
                          + root.minInstances + "–" + root.maxInstances
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    width: parent.width
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#6b7280"
                font.pixelSize: 11
                text: "The floor is what the manager keeps running; the ceiling is as far as the autoscaler may go "
                      + "under load. Raising the floor starts instances, raising the ceiling only permits them."
            }

            Row {
                width: parent.width
                spacing: 12

                Column {
                    width: (scaleDialog.availableWidth - 12) / 2
                    spacing: 6
                    Text { text: "Min instances"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: minField
                        width: parent.width
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        // Bottom of 1: EAP refuses a floor of zero outright and names the way to
                        // take an application out of service, which is stopping it. This field
                        // used to accept 0 and update-application quietly stored 1 instead - so
                        // the pool that was meant to drain when idle never did, and nothing said
                        // so. Scaling to nothing is not a thing an application does here.
                        validator: IntValidator { bottom: 1; top: 999 }
                        Keys.onReturnPressed: maxField.forceActiveFocus()
                    }
                }

                Column {
                    width: (scaleDialog.availableWidth - 12) / 2
                    spacing: 6
                    Text { text: "Max instances"; color: "#9aa1ac"; font.pixelSize: 12 }
                    TextField {
                        id: maxField
                        width: parent.width
                        Material.accent: "#4f8cff"
                        selectByMouse: true
                        validator: IntValidator { bottom: 1; top: 999 }
                        Keys.onReturnPressed: if (applyScaleButton.enabled) applyScaleButton.clicked()
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                // What this page worked out, or - once it has been sent - what EAP answered. The
                // server's wording wins: it is the side that decides, and the two only ever
                // disagree about a case this dialog did not think of.
                visible: scaleDialog.problem.length > 0 || scaleDialog.errorText.length > 0
                text: scaleDialog.errorText.length > 0 ? scaleDialog.errorText : scaleDialog.problem
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Cancel"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    onClicked: scaleDialog.close()
                }

                Button {
                    id: applyScaleButton
                    text: scaleDialog.scaling ? "Scaling…" : "Apply"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    enabled: scaleDialog.valid && !scaleDialog.scaling
                             && (scaleDialog.wantedMin !== root.minInstances
                                 || scaleDialog.wantedMax !== root.maxInstances)
                    onClicked: {
                        root.error = ""
                        scaleDialog.scaling = true
                        scaleDialog.errorText = ""
                        eapClient.scaleApplication(root.applicationId,
                                                   scaleDialog.wantedMin, scaleDialog.wantedMax)
                    }
                }
            }
        }
    }

    Dialog {
        id: deleteDialog
        modal: true
        anchors.centerIn: parent
        width: 380
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
            width: deleteDialog.availableWidth
            spacing: 20

            Column {
                width: parent.width
                spacing: 4
                Text { text: "Delete Application"; color: "white"; font.pixelSize: 18; font.bold: true }
                Text {
                    text: "Permanently deletes the definition of \"" + root.applicationId + "\". The reconciler stops its "
                          + "processes on the next tick; the artifact in the bucket is untouched."
                          + (root.ownPrincipal ? " Its principal \"" + root.detail("userId", "") + "\" and that principal's "
                                                 + "access key go with it." : "")
                          + " This cannot be undone."
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    width: parent.width
                }
            }

            Item {
                width: parent.width
                height: 40

                Button {
                    text: "Cancel"
                    flat: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    onClicked: deleteDialog.close()
                }

                Button {
                    text: "Delete"
                    highlighted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#ff6b6b"
                    onClicked: {
                        root.deleting = true
                        deleteDialog.close()
                        eapClient.deleteApplication(root.applicationId)
                    }
                }
            }
        }
    }
}
