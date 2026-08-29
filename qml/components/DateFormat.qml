pragma Singleton
import QtQuick

QtObject {
    property string pattern: "dd-MM-yyyy HH:mm:ss"
    function format(isoString) {
        if (!isoString || isoString.length === 0)
            return "—"
        const date = new Date(isoString)
        if (isNaN(date.getTime()))
            return isoString
        return Qt.formatDateTime(date, pattern)
    }
}
