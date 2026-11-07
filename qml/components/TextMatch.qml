pragma Singleton
import QtQuick

// The four ways a table filter can match, applied in the client - for the tables that filter rows
// they already hold. Server-filtered tables send the same match type with their query instead, and
// the server applies the same rule there (see DataTable.matchType).
QtObject {
    // Whether `value` matches `text` under `matchType` ("prefix", "endsWith", "contains", "regex").
    // Empty text matches everything. A pattern that does not compile matches nothing - see
    // invalidPattern() for saying why. ignoreCase applies to all four, the regex included.
    function matches(value, text, matchType, ignoreCase) {
        if (!text || text.length === 0) return true
        let v = value === undefined || value === null ? "" : String(value)
        if (matchType === "regex") {
            try { return new RegExp(text, ignoreCase ? "i" : "").test(v) } catch (e) { return false }
        }
        let t = text
        if (ignoreCase) {
            v = v.toLowerCase()
            t = t.toLowerCase()
        }
        switch (matchType) {
        case "endsWith": return v.endsWith(t)
        case "contains": return v.indexOf(t) >= 0
        default: return v.startsWith(t)
        }
    }

    // True when any of `values` matches - for a filter that searches several columns at once.
    function matchesAny(values, text, matchType, ignoreCase) {
        if (!text || text.length === 0) return true
        for (let i = 0; i < values.length; i++) {
            if (matches(values[i], text, matchType, ignoreCase)) return true
        }
        return false
    }

    // Why a regular expression does not compile, or empty when it does (or is not a regex at all).
    function invalidPattern(text, matchType) {
        if (matchType !== "regex" || !text) return ""
        try {
            new RegExp(text)
            return ""
        } catch (e) {
            return String(e.message || e)
        }
    }
}
