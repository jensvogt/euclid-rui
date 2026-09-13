import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// Where you are, and the way back out of it - in place of the "‹ Back to X" button every page used
// to open with.
//
// A crumb says two things a back button cannot: what this page is, and what it sits under. The last
// segment is the page itself and is never a link; everything before it carries an action and is.
//
// Each page supplies its own trail, because only the page knows what it is showing - a queue's name,
// an application's id - and only the window knows the routes. So a segment carries a callback rather
// than a route, and a page that can only go one step up says exactly that rather than pretending to
// a deeper path it cannot navigate.
Item {
    id: root

    // [{ label: string, action: function|undefined }] - in order, outermost first.
    property var segments: []

    implicitHeight: Math.max(20, crumbs.implicitHeight)
    height: implicitHeight

    Row {
        id: crumbs
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Repeater {
            model: root.segments

            delegate: Row {
                id: segment
                required property var modelData
                required property int index

                spacing: 8

                readonly property bool linked: !!segment.modelData.action
                                               && segment.index < root.segments.length - 1

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // Only between segments, so the trail does not open with a stray separator.
                    visible: segment.index > 0
                    text: "›"
                    color: "#4a5160"
                    font.pixelSize: 13
                }

                Text {
                    id: segmentLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: segment.modelData.label
                    // The page you are on is stated, not offered: clicking it would reload what is
                    // already in front of you.
                    color: !segment.linked ? "#e5e7eb"
                           : (segmentArea.containsMouse ? "#4f8cff" : "#9aa1ac")
                    font.pixelSize: 13
                    font.bold: segment.index === root.segments.length - 1
                    elide: Text.ElideRight
                    // Long enough for an object key or an ERN-ish name without pushing the rest of
                    // the trail off the page.
                    width: Math.min(implicitWidth, 420)

                    MouseArea {
                        id: segmentArea
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: segment.linked
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: segment.modelData.action()
                    }
                }
            }
        }
    }
}
