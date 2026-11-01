import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// The fields of an EMO alert rule, shared by the rule's details page (editing) and the Alerts
// page's Add dialog (creating), so the two cannot drift apart in what they accept.
//
// Checked against the same rules ValidateAlertRule() applies server-side, so a caller only offers
// Save for a rule the server would store. The form knows nothing about saving: it says what is
// wrong (validationError), what moved since `rule` (changes) or the whole rule (values()), and
// the caller sends it.
Column {
    id: root
    spacing: 16

    // The rule as stored - the baseline `changes` is measured against. Ignored in create mode.
    property var rule: null
    // Adds the rule id field and the enabled switch, and measures nothing: everything is new.
    property bool createMode: false
    // What "list-metrics" returned: [{name, type, series, labelNames, lastSeen}]. Offered in the
    // metric picker; any other name can still be typed, since a metric may not have reported yet.
    property var metrics: []
    // Rule ids already taken, so a clash is reported before the server refuses it.
    property var existingRuleIds: []

    readonly property var statistics: ["value", "max", "min"]
    readonly property var comparisons: ["above", "below"]

    // ── Formatting between a rule and the fields ─────────────────────────────

    function labelsText(labels) {
        const keys = Object.keys(labels || {})
        return keys.sort().map(k => k + "=" + labels[k]).join(", ")
    }

    // "host=a, env=b" back into an object; null when it does not parse, which the form reports.
    function parseLabels(text) {
        const result = {}
        const trimmed = String(text).trim()
        if (trimmed.length === 0) return result
        for (const part of trimmed.split(",")) {
            const pair = part.trim()
            const eq = pair.indexOf("=")
            if (eq <= 0) return null
            const key = pair.substring(0, eq).trim()
            const value = pair.substring(eq + 1).trim()
            if (key.length === 0 || result[key] !== undefined) return null
            result[key] = value
        }
        return result
    }

    function thresholdText(v) {
        return v === undefined || v === null ? "" : String(v)
    }

    // A threshold field: null when empty (no line), NaN when it is not a number.
    function thresholdValue(text) {
        const t = String(text).trim()
        if (t.length === 0) return null
        const n = Number(t)
        return isFinite(n) ? n : NaN
    }

    function intValue(text) {
        const t = String(text).trim()
        return /^\d+$/.test(t) ? parseInt(t, 10) : NaN
    }

    // Puts `r` into the fields - the stored rule when editing, defaults when creating.
    function load(r) {
        r = r || {}
        ruleIdField.text = r.ruleId || ""
        metricField.text = r.name || ""
        labelsField.text = root.labelsText(r.labels)
        statisticCombo.currentIndex = Math.max(0, root.statistics.indexOf(r.statistic))
        comparisonCombo.currentIndex = Math.max(0, root.comparisons.indexOf(r.comparison))
        warningField.text = root.thresholdText(r.warning)
        criticalField.text = root.thresholdText(r.critical)
        forField.text = String(r.forPeriods !== undefined ? r.forPeriods : 1)
        clearField.text = String(r.clearPeriods !== undefined ? r.clearPeriods : 1)
        noDataField.text = String(r.noDataAfterPeriods !== undefined ? r.noDataAfterPeriods : 0)
        descriptionField.text = r.description || ""
        enabledSwitch.checked = r.enabled !== false
    }

    // ── What the form holds, and whether the server would take it ────────────

    readonly property string formRuleId: ruleIdField.text.trim()
    readonly property string formName: metricField.text.trim()
    readonly property var formLabels: root.parseLabels(labelsField.text)
    readonly property var formWarning: root.thresholdValue(warningField.text)
    readonly property var formCritical: root.thresholdValue(criticalField.text)
    readonly property var formFor: root.intValue(forField.text)
    readonly property var formClear: root.intValue(clearField.text)
    readonly property var formNoData: root.intValue(noDataField.text)
    readonly property string formComparison: root.comparisons[comparisonCombo.currentIndex] || "above"
    readonly property string formStatistic: root.statistics[statisticCombo.currentIndex] || "value"

    // The first thing wrong, in ValidateAlertRule()'s order and close to its words; empty if none.
    readonly property string validationError: {
        if (root.createMode) {
            if (root.formRuleId.length === 0) return "A rule id is required."
            if (root.formRuleId.length > 128) return "The rule id is longer than 128 characters."
            if (!/^[A-Za-z0-9._-]+$/.test(root.formRuleId)) return "The rule id may hold letters, digits, '-', '_' and '.'."
            if (root.existingRuleIds.indexOf(root.formRuleId) >= 0) return "A rule '" + root.formRuleId + "' already exists."
        }
        if (root.formName.length === 0) return "The metric is required."
        if (root.formLabels === null) return "Labels have to be key=value pairs separated by commas, each key once."
        if (Number.isNaN(root.formWarning)) return "The warning line has to be a number, or empty for none."
        if (Number.isNaN(root.formCritical)) return "The critical line has to be a number, or empty for none."
        if (root.formWarning === null && root.formCritical === null) return "At least one of warning and critical is required."
        if (root.formWarning !== null && root.formCritical !== null) {
            if (root.formComparison === "above" && !(root.formWarning < root.formCritical))
                return "Warning has to be below critical for a rule alerting above them."
            if (root.formComparison === "below" && !(root.formWarning > root.formCritical))
                return "Warning has to be above critical for a rule alerting below them."
        }
        if (Number.isNaN(root.formFor) || root.formFor < 1 || root.formFor > 1000) return "Periods to raise has to be between 1 and 1000."
        if (Number.isNaN(root.formClear) || root.formClear < 1 || root.formClear > 1000) return "Periods to clear has to be between 1 and 1000."
        if (Number.isNaN(root.formNoData) || root.formNoData > 1000) return "No-data periods has to be between 0 and 1000."
        return ""
    }
    readonly property bool valid: root.validationError.length === 0

    // The whole rule, as "create-alert-rule" takes it. Only meaningful when valid.
    function values() {
        const v = {
            ruleId: root.formRuleId,
            name: root.formName,
            labels: root.formLabels || {},
            statistic: root.formStatistic,
            comparison: root.formComparison,
            forPeriods: root.formFor,
            clearPeriods: root.formClear,
            noDataAfterPeriods: root.formNoData,
            enabled: enabledSwitch.checked,
            description: descriptionField.text
        }
        // Left out rather than sent as null: a rule with one line has no other line.
        if (root.formWarning !== null) v.warning = root.formWarning
        if (root.formCritical !== null) v.critical = root.formCritical
        return v
    }

    // Only the fields that moved since `rule`, as "update-alert-rule" takes them. Empty when
    // nothing did, which is what a caller disables Save on.
    readonly property var changes: {
        const c = {}
        const r = root.rule
        if (root.createMode || !r) return c
        if (root.formName !== (r.name || "")) c.name = root.formName
        if (root.formLabels !== null && root.labelsText(root.formLabels) !== root.labelsText(r.labels)) c.labels = root.formLabels
        if (root.formStatistic !== r.statistic) c.statistic = root.formStatistic
        if (root.formComparison !== r.comparison) c.comparison = root.formComparison
        const w = r.warning === undefined ? null : r.warning
        const k = r.critical === undefined ? null : r.critical
        if (!Number.isNaN(root.formWarning) && root.formWarning !== w) c.warning = root.formWarning
        if (!Number.isNaN(root.formCritical) && root.formCritical !== k) c.critical = root.formCritical
        if (!Number.isNaN(root.formFor) && root.formFor !== r.forPeriods) c.forPeriods = root.formFor
        if (!Number.isNaN(root.formClear) && root.formClear !== r.clearPeriods) c.clearPeriods = root.formClear
        if (!Number.isNaN(root.formNoData) && root.formNoData !== r.noDataAfterPeriods) c.noDataAfterPeriods = root.formNoData
        if (descriptionField.text !== (r.description || "")) c.description = descriptionField.text
        return c
    }
    readonly property bool dirty: Object.keys(root.changes).length > 0
    // Changing what the rule judges ends what it said about the series it judged before.
    readonly property bool retargets: root.changes.name !== undefined || root.changes.labels !== undefined

    // The picked metric's entry from `metrics`, for the hint under the labels field.
    readonly property var selectedMetric: root.metrics.find(m => m.name === root.formName) || null

    // ── Layout ───────────────────────────────────────────────────────────────

    readonly property real half: (width - 24) / 2
    readonly property real third: (width - 48) / 3

    component FieldLabel: Text { color: "#9aa1ac"; font.pixelSize: 12 }
    component Hint: Text { color: "#6b7280"; font.pixelSize: 11; wrapMode: Text.WordWrap }

    Row {
        spacing: 24
        visible: root.createMode
        Column {
            width: root.half
            spacing: 6
            FieldLabel { text: "Rule id" }
            TextField {
                id: ruleIdField
                width: parent.width
                selectByMouse: true
                Material.accent: "#4f8cff"
                placeholderText: "disk-usage-per-host"
            }
            Hint {
                width: parent.width
                text: "Letters, digits, '-', '_' and '.'. Fixed once the rule exists."
            }
        }
        Column {
            width: root.half
            spacing: 6
            FieldLabel { text: "Enabled" }
            CheckBox {
                id: enabledSwitch
                checked: true
                text: "Judge from the next period"
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
            }
        }
    }

    Row {
        spacing: 24
        Column {
            width: root.half
            spacing: 6
            FieldLabel { text: "Metric" }
            // A text field and a picker rather than an editable ComboBox: that one rewrites its text
            // whenever its model changes, and the metric list arrives after the rule is loaded.
            // The picker is euclid-amo's dialog rather than a menu - a menu of three hundred
            // underscore-joined names, elided, is one nobody can find anything in.
            Row {
                width: parent.width
                spacing: 8
                TextField {
                    id: metricField
                    width: parent.width - pickButton.width - parent.spacing
                    selectByMouse: true
                    Material.accent: "#4f8cff"
                    placeholderText: "system-cpu-usage"
                }
                Button {
                    id: pickButton
                    text: "Choose…"
                    flat: true
                    anchors.verticalCenter: metricField.verticalCenter
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    onClicked: metricPicker.openFor(root.formName, root.metrics)
                }
            }
            MetricPicker {
                id: metricPicker
                onMetricChosen: name => metricField.text = name
            }
            Hint {
                width: parent.width
                text: root.selectedMetric
                      ? root.selectedMetric.type + ", " + root.selectedMetric.series + " series"
                      : (root.metrics.length > 0 && root.formName.length > 0
                         ? "Not reported in the last 24 hours - fine if it has not started yet."
                         : "Pick one, or type the name of one that has not reported yet.")
            }
        }
        Column {
            width: root.half
            spacing: 6
            FieldLabel { text: "Labels" }
            TextField {
                id: labelsField
                width: parent.width
                selectByMouse: true
                Material.accent: "#4f8cff"
                placeholderText: "host=my-host, module=eqs"
            }
            Hint {
                width: parent.width
                text: "Empty judges every series of the metric, each on its own."
                      + (root.selectedMetric && (root.selectedMetric.labelNames || []).length > 0
                         ? " This metric's labels: " + root.selectedMetric.labelNames.join(", ") + "." : "")
            }
        }
    }

    Text {
        width: root.width
        wrapMode: Text.WordWrap
        color: "#ffb545"
        font.pixelSize: 11
        visible: root.retargets
        text: "Saving a different metric or labels retires every series the rule judges now - the "
              + "firing ones are announced as cleared - and starts on the new ones from the next period."
    }

    Row {
        spacing: 24
        Column {
            width: root.third
            spacing: 6
            FieldLabel { text: "Statistic" }
            ComboBox {
                id: statisticCombo
                width: parent.width
                implicitHeight: 36
                model: root.statistics
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
            }
            Hint {
                width: parent.width
                text: "Which figure of a period it judges: the mean (sum for a rate), the peak or the low."
            }
        }
        Column {
            width: root.third
            spacing: 6
            FieldLabel { text: "Alert when" }
            ComboBox {
                id: comparisonCombo
                width: parent.width
                implicitHeight: 36
                model: root.comparisons
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
            }
        }
        Column {
            width: root.third
            spacing: 6
            FieldLabel { text: "Resolution" }
            Text {
                height: 36
                verticalAlignment: Text.AlignVCenter
                text: root.rule && !root.createMode ? root.rule.resolution || "RAW" : "RAW"
                color: "#c4c9d1"
                font.pixelSize: 13
            }
            Hint {
                width: parent.width
                text: "Always RAW: a rule on an hourly or daily tier would be a report."
            }
        }
    }

    Row {
        spacing: 24
        Column {
            width: root.half
            spacing: 6
            FieldLabel { text: "Warning" }
            TextField {
                id: warningField
                width: parent.width
                selectByMouse: true
                Material.accent: "#ffb545"
                placeholderText: "none"
            }
        }
        Column {
            width: root.half
            spacing: 6
            FieldLabel { text: "Critical" }
            TextField {
                id: criticalField
                width: parent.width
                selectByMouse: true
                Material.accent: "#ff6b6b"
                placeholderText: "none"
            }
        }
    }

    Row {
        spacing: 24
        Column {
            width: root.third
            spacing: 6
            FieldLabel { text: "Periods to raise" }
            TextField {
                id: forField
                width: parent.width
                selectByMouse: true
                validator: IntValidator { bottom: 1; top: 1000 }
                Material.accent: "#4f8cff"
            }
            Hint {
                width: parent.width
                text: "Consecutive periods past a line before the state is entered."
            }
        }
        Column {
            width: root.third
            spacing: 6
            FieldLabel { text: "Periods to clear" }
            TextField {
                id: clearField
                width: parent.width
                selectByMouse: true
                validator: IntValidator { bottom: 1; top: 1000 }
                Material.accent: "#4f8cff"
            }
            Hint {
                width: parent.width
                text: "Consecutive periods back inside before it is left."
            }
        }
        Column {
            width: root.third
            spacing: 6
            FieldLabel { text: "No-data after periods" }
            TextField {
                id: noDataField
                width: parent.width
                selectByMouse: true
                validator: IntValidator { bottom: 0; top: 1000 }
                Material.accent: "#4f8cff"
            }
            Hint {
                width: parent.width
                text: "Periods without a row before a series goes NO DATA; 0 never."
            }
        }
    }

    Column {
        width: root.width
        spacing: 6
        FieldLabel { text: "Description" }
        TextField {
            id: descriptionField
            width: parent.width
            selectByMouse: true
            Material.accent: "#4f8cff"
            placeholderText: "What the rule is for, in words"
        }
    }
}
