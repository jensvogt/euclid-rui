import QtQuick
import QtQuick.Templates as T

// The "×" that empties a filter field, sitting inside the field's right edge.
//
// Inside rather than beside: the row a filter shares with a refresh button has room for one more
// control, and a third button on it would read as a third thing done to the table. This is done to
// the text, so it belongs in the text.
//
// Given the field rather than the string, because clearing is the whole of what it does and a
// caller that assigns the empty string itself is one `onTextChanged` away from a field that looks
// cleared while the table still shows a filtered page. Whatever else has to happen - firing a
// search straight away instead of waiting out a debounce - is what `cleared` is for.
Item {
    id: control

    // The field this empties. Typed rather than left as an Item, so that `text` - the only thing
    // read or written here - is checked at build time rather than found missing at runtime.
    //
    // The template type rather than QtQuick.Controls': every style's TextField derives from it, so
    // this accepts the Material ones the application actually builds while a plain
    // "property TextField" would be a different type from each of them.
    property T.TextField field: null

    // After the field is empty, for a caller that has more to do than let the field's own handlers
    // run - see DataTable, which answers the now-empty filter immediately rather than 350ms later.
    signal cleared()

    // The whole of what pressing it does, exposed because a MouseArea's clicked() is not reachable
    // from outside it and the keyboard path has to end up in the same place - see DataTable's
    // Escape handler.
    function clear() {
        if (!control.field) return
        control.field.text = ""
        control.cleared()
    }

    // No field, or nothing in it: there is nothing to clear, and an × on an empty box is a button
    // that does nothing to press.
    visible: !!control.field && control.field.text.length > 0

    width: 22
    height: 22

    Text {
        id: glyph
        anchors.centerIn: parent
        text: "✕"
        font.pixelSize: 13
        // Dim until pointed at: it sits on top of what somebody is reading, and the one time it
        // matters is when they have gone looking for it.
        color: clearArea.containsMouse ? "#e6e9ef" : "#6b7280"

        Behavior on color { ColorAnimation { duration: 120 } }
    }

    MouseArea {
        id: clearArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.clear()
    }
}
