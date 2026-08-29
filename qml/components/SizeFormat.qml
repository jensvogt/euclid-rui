pragma Singleton
import QtQuick

QtObject {
    function format(bytes) {
        if (bytes === null || bytes === undefined || isNaN(bytes))
            return "—"

        const num = Number(bytes)
        if (num === 0)
            return "0 B"
        if (num < 0)
            return "—"

        // Use base 1024 (KiB/MiB/GiB style sizing)
        const units = ["B", "kB", "MB", "GB", "TB", "PB"]
        const i = Math.min(Math.floor(Math.log(num) / Math.log(1024)), units.length - 1)

        // Bytes don't need decimal places
        if (i === 0)
            return num + " B"

        const value = num / Math.pow(1024, i)

        // Formats number to 1 decimal place using the current system/QML locale
        return value.toLocaleString(Qt.locale(), "f", 1) + " " + units[i]
    }
}