import QtQuick

// Turns "something changed" notifications into refreshes at a bounded rate.
//
// The event stream reports every change as it happens, which on a busy installation is many per
// second - and a table that reloads on each one reorders itself faster than it can be read, which
// is the behaviour the auto-refresh interval was set to avoid. So events are coalesced: the first
// one refreshes immediately if enough time has passed, and any that arrive inside the interval are
// collapsed into a single refresh at the end of it. Nothing is lost - a refresh re-reads whatever
// the latest state is, so one refresh answers any number of events.
//
// The point of keeping events at all, rather than leaving it to the page's timer, is an idle
// system: one change on a quiet queue shows up at once instead of at the next tick.
Timer {
    id: root

    // No refresh sooner than this after the last one. Callers normally set it from the configured
    // auto-refresh interval, so both paths obey the same number.
    property int minimumIntervalMs: 10000

    // Emitted when a refresh should actually happen.
    signal fired()

    // Milliseconds since the epoch, so the gap survives the component being re-created.
    property double lastFiredAt: 0

    repeat: false

    // Called for every change notification.
    function request() {
        // One is already pending; it will cover this notification too.
        if (root.running)
            return

        const sinceLast = Date.now() - root.lastFiredAt
        if (sinceLast >= root.minimumIntervalMs) {
            root.lastFiredAt = Date.now()
            root.fired()
            return
        }

        // Too soon: wait out the rest of the interval and refresh once for everything that arrives
        // in the meantime.
        root.interval = root.minimumIntervalMs - sinceLast
        root.start()
    }

    onTriggered: {
        root.lastFiredAt = Date.now()
        root.fired()
    }
}
