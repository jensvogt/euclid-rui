import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import "../components"

// One EMO alert rule: what it judges and against which lines, editable, and where each series it
// judges stands right now.
//
// The form is checked against the same rules ValidateAlertRule() applies server-side, so Save is
// only offered for a rule the server would store; whatever it refuses anyway comes back as the
// error under the form. Only the fields that moved are sent, so saving a new description does not
// re-send - and re-judge - the thresholds.
//
// The rule's id is not editable: it is the rule's identity, and what every series and every history
// entry is filed under.
Item {
    id: root
    property bool loggedIn: false
    property string ruleId: ""

    signal back()

    // The rule as last read or saved, and the series it judges ("list-alerts" filtered to it).
    property var rule: null
    property var series: []

    property int pending: 0
    readonly property bool loading: pending > 0
    property bool saving: false
    property string error: ""
    property string saveError: ""
    property string actionNote: ""

    readonly property bool ruleEnabled: !!root.rule && root.rule.enabled !== false

    function labelsText(labels) {
        const keys = Object.keys(labels || {})
        return keys.sort().map(k => k + "=" + labels[k]).join(", ")
    }

    // What "list-metrics" returned, for the form's metric picker.
    property var metrics: []

    // The form's state, under the names the rest of the page uses.
    readonly property bool dirty: form.dirty
    readonly property var changes: form.changes
    readonly property string validationError: form.validationError

    function loadForm() {
        if (!root.rule) return
        form.load(root.rule)
        root.saveError = ""
    }

    // ── Loading ──────────────────────────────────────────────────────────────

    function refresh() {
        if (!root.loggedIn || root.ruleId.length === 0) return
        pending = 2
        error = ""
        emoClient.fetchAlertRules()
        emoClient.fetchAlerts()
    }

    function settle() {
        root.pending = Math.max(0, root.pending - 1)
    }

    onVisibleChanged: {
        if (visible) {
            root.rule = null
            root.series = []
            root.actionNote = ""
            root.saveError = ""
            refresh()
            if (root.metrics.length === 0) emoClient.fetchMetrics()
        }
    }
    onRuleIdChanged: if (visible) refresh()

    Connections {
        target: emoClient
        function onAlertRulesLoaded(list) {
            if (!root.visible) return
            const found = list.find(r => r.ruleId === root.ruleId)
            // A refresh while somebody is half-way through an edit leaves the form alone: the
            // rule shown above it moves, the typing does not.
            const wasDirty = root.rule !== null && root.dirty
            root.rule = found || null
            if (!found) root.error = "No alert rule '" + root.ruleId + "'. It may have been deleted."
            else if (!wasDirty) root.loadForm()
            root.settle()
        }
        function onAlertRulesFailed(message) {
            if (!root.visible) return
            root.error = message
            root.settle()
        }
        function onAlertsLoaded(list) {
            if (!root.visible) return
            root.series = list.filter(s => s.ruleId === root.ruleId)
            root.settle()
        }
        function onAlertsFailed(message) {
            if (!root.visible) return
            root.error = message
            root.settle()
        }
        function onMetricsLoaded(list) {
            root.metrics = list
        }
        function onAlertRuleUpdated(ruleId, updated) {
            if (!root.visible || ruleId !== root.ruleId) return
            root.saving = false
            root.rule = updated
            root.loadForm()
            root.actionNote = "Saved. The next period is judged against the rule as it is now."
            // The series: a retargeted rule has just retired its old ones.
            emoClient.fetchAlerts()
            root.pending = 1
        }
        function onAlertRuleUpdateFailed(ruleId, message) {
            if (!root.visible || ruleId !== root.ruleId) return
            root.saving = false
            root.saveError = message
        }
        function onAlertRuleEnabledChanged(ruleId, enabled) {
            if (!root.visible || ruleId !== root.ruleId) return
            root.actionNote = enabled
                ? "Rule activated. Its series are judged again from the next period."
                : "Rule deactivated. None of its series are judged any more, and any that were firing have been cleared."
            root.refresh()
        }
        function onAlertRuleEnabledFailed(ruleId, message) {
            if (!root.visible || ruleId !== root.ruleId) return
            root.error = message
        }
    }

    function stateColor(state) {
        if (state === "CRITICAL") return "#ff6b6b"
        if (state === "WARNING") return "#ffb545"
        if (state === "OK") return "#4cd97b"
        return "#9aa1ac"
    }

    function numberText(v) {
        if (v === undefined || v === null || v === "") return "—"
        const n = Number(v)
        if (isNaN(n)) return String(v)
        return Math.abs(n) >= 100 ? n.toFixed(0) : n.toFixed(2)
    }

    readonly property int firingCount: root.series.filter(s => s.state !== "OK").length

    // ── Layout ───────────────────────────────────────────────────────────────


    ScrollView {
        anchors.fill: parent
        anchors.margins: 28
        contentWidth: availableWidth
        clip: true

        Column {
            id: page
            width: parent.width
            spacing: 20

            Breadcrumb {
                width: parent.width
                leaf: root.ruleId
            }

            Item {
                width: parent.width
                height: sectionHeader.implicitHeight

                SectionHeader {
                    id: sectionHeader
                    title: root.ruleId
                    subtitle: root.rule ? (root.rule.description || root.rule.name || "") : ""
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: sectionHeader.verticalCenter
                    spacing: 8

                    BusyIndicator {
                        running: root.loading
                        visible: root.loading
                        width: 22
                        height: 22
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Button {
                        text: "Refresh"
                        flat: true
                        Material.theme: Material.Dark
                        onClicked: root.refresh()
                    }

                    Button {
                        visible: !!root.rule
                        text: root.ruleEnabled ? "Deactivate" : "Activate"
                        flat: true
                        Material.theme: Material.Dark
                        Material.accent: root.ruleEnabled ? "#ffb545" : "#4cd97b"
                        onClicked: {
                            root.actionNote = ""
                            root.error = ""
                            emoClient.setAlertRuleEnabled(root.ruleId, !root.ruleEnabled)
                        }
                    }
                }
            }

            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                color: "#ff6b6b"
                font.pixelSize: 12
                visible: root.error.length > 0
                text: root.error
            }

            Flow {
                width: parent.width
                spacing: 18
                visible: !!root.rule

                StatCard {
                    title: "Rule"
                    value: root.ruleEnabled ? "ENABLED" : "DISABLED"
                    trend: root.ruleEnabled ? "judged every period" : "not judged"
                    trendUp: root.ruleEnabled
                    accent: root.ruleEnabled ? "#4cd97b" : "#9aa1ac"
                }
                StatCard {
                    title: "Series"
                    value: String(root.series.length)
                    trend: root.firingCount === 0 ? "all OK" : root.firingCount + " firing"
                    trendUp: root.firingCount === 0
                    accent: root.firingCount === 0 ? "#4f8cff" : "#ff6b6b"
                }
                StatCard {
                    title: "Modified"
                    value: root.rule ? DateFormat.format(root.rule.modified) : "—"
                    trend: root.rule ? "created " + DateFormat.format(root.rule.created) : ""
                    trendUp: true
                    accent: "#c56bff"
                }
            }

            // ── The rule ─────────────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: formCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                visible: !!root.rule

                Column {
                    id: formCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 16

                    AlertRuleForm {
                        id: form
                        width: parent.width
                        rule: root.rule
                        metrics: root.metrics
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        font.pixelSize: 12
                        color: root.saveError.length > 0 ? "#ff6b6b" : "#ffb545"
                        visible: text.length > 0
                        text: root.saveError.length > 0 ? root.saveError : root.validationError
                    }

                    Text {
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#4cd97b"
                        font.pixelSize: 12
                        visible: root.actionNote.length > 0 && !root.dirty
                        text: root.actionNote
                    }

                    Item {
                        width: parent.width
                        height: 40

                        Button {
                            text: "Revert"
                            flat: true
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            Material.theme: Material.Dark
                            enabled: root.dirty && !root.saving
                            onClicked: root.loadForm()
                        }

                        BusyIndicator {
                            running: root.saving
                            visible: root.saving
                            width: 22
                            height: 22
                            anchors.right: saveButton.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Button {
                            id: saveButton
                            text: "Save"
                            highlighted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            Material.theme: Material.Dark
                            Material.accent: "#4f8cff"
                            enabled: root.dirty && !root.saving && root.validationError.length === 0
                            onClicked: {
                                root.saveError = ""
                                root.actionNote = ""
                                root.saving = true
                                emoClient.updateAlertRule(root.ruleId, root.changes)
                            }
                        }
                    }
                }
            }

            // ── Its series ───────────────────────────────────────────────────
            Rectangle {
                width: parent.width
                height: seriesCol.implicitHeight + 40
                radius: 14
                color: "#20242e"
                border.color: "#2c313c"
                border.width: 1
                visible: !!root.rule

                Column {
                    id: seriesCol
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 20
                    spacing: 12

                    Text {
                        text: "Series (" + root.series.length + ")"
                        color: "white"
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Text {
                        visible: root.series.length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        color: "#6b7280"
                        font.pixelSize: 12
                        text: root.ruleEnabled
                              ? "None yet. A series appears once the rule has judged a row of it - at the next period's flush."
                              : "None: a disabled rule judges nothing."
                    }

                    Row {
                        width: parent.width
                        spacing: 16
                        visible: root.series.length > 0
                        Text { width: seriesCol.width * 0.12; text: "State"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                        Text { width: seriesCol.width * 0.36; text: "Series"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                        Text { width: seriesCol.width * 0.12; text: "Value"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                        Text { width: seriesCol.width * 0.17; text: "Since"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                        Text { width: seriesCol.width * 0.17; text: "Last seen"; color: "#6b7280"; font.pixelSize: 11; font.bold: true }
                    }

                    Repeater {
                        model: root.series
                        delegate: Row {
                            id: seriesRow
                            required property var modelData
                            width: seriesCol.width
                            height: 24
                            spacing: 16

                            Text {
                                width: seriesCol.width * 0.12
                                text: seriesRow.modelData.state === "NO_DATA" ? "NO DATA" : seriesRow.modelData.state
                                color: root.stateColor(seriesRow.modelData.state)
                                font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: seriesCol.width * 0.36
                                text: root.labelsText(seriesRow.modelData.labels) || "—"
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: seriesCol.width * 0.12
                                text: seriesRow.modelData.state === "NO_DATA" ? "—" : root.numberText(seriesRow.modelData.value)
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: seriesCol.width * 0.17
                                text: DateFormat.format(seriesRow.modelData.since)
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: seriesCol.width * 0.17
                                text: DateFormat.format(seriesRow.modelData.lastSeen)
                                color: "#c4c9d1"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }
    }
}
