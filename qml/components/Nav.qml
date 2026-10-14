pragma Singleton

import QtQuick

// Where the window is, and how anything that is not the window asks it to go somewhere else.
//
// The routes themselves stay in Main.qml, which owns `currentRoute` and the state that goes with a
// page - which bucket's objects, which application's details. This is only the two things a page
// cannot otherwise reach: what the current route is, and a way to request another one.
//
// It exists for the breadcrumb. A page knows one step back - that is what its `back` signal is -
// but a trail reaching Home has to offer every step above it, and no page knows the route names of
// its ancestors. Rather than give all forty of them a signal per ancestor, they ask here.
QtObject {
    id: nav

    // Mirrors the window's currentRoute; Main.qml keeps it in step. Read, never written, by
    // anything else: writing it would move the crumb without moving the page.
    property string current: ""

    // Asked for, not done. Main.qml applies it, because going somewhere is more than setting a
    // string - it is the selection state that belongs to the page being left and the one arrived at.
    signal requested(string route)

    function go(route) {
        if (route.length > 0 && route !== nav.current)
            nav.requested(route)
    }
}
