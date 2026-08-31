import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root

    // Public Properties
    property string title: "Tile Header"
    property bool expanded: false
    property alias contentData: contentArea.data // Allows placing any QML elements inside
    // Extra header content (e.g. a refresh button, a "last updated" label), placed between the
    // title and the expand/collapse arrow.
    property alias headerContent: headerExtra.data

    // Automatic height calculation based on state
    implicitWidth: 300
    implicitHeight: mainLayout.implicitHeight

    Rectangle {
        anchors.fill: parent
        color: "#2b2b2b"
        radius: 8
        border.color: "#3f3f3f"
        border.width: 1
    }

    ColumnLayout {
        id: mainLayout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // 1. Header (Clickable Bar)
        Rectangle {
            id: header
            Layout.fillWidth: true
            implicitHeight: 48
            color: headerMouseArea.containsMouse ? "#383838" : "transparent"
            radius: 8

            // Declared before the RowLayout below so it sits underneath in paint/hit-test order -
            // any interactive item placed via headerContent (e.g. a refresh Button) then wins hit
            // testing over this MouseArea for its own bounds, instead of the MouseArea (being on
            // top) swallowing every click on the header including ones meant for that button.
            MouseArea {
                id: headerMouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.expanded = !root.expanded
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Text {
                    text: root.title
                    color: "#ffffff"
                    font.pixelSize: 15
                    font.bold: true
                    Layout.fillWidth: true
                }

                Row {
                    id: headerExtra
                    spacing: 12
                }

                // Expand/Collapse Arrow Indicator
                Text {
                    text: "▼"
                    color: "#888888"
                    font.pixelSize: 12
                    rotation: root.expanded ? 180 : 0

                    Behavior on rotation {
                        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
                    }
                }
            }
        }

        // 2. Expandable Content Container
        Item {
            id: contentContainer
            Layout.fillWidth: true
            // +32 accounts for contentArea's own top+bottom anchors.margins (16 each), which
            // aren't part of its implicitHeight - without this, the last ~16-32px of content
            // (e.g. a trailing label) gets clipped instead of pushing the tile taller.
            Layout.preferredHeight: root.expanded ? contentArea.implicitHeight + 32 : 0
            clip: true // Prevents child components from rendering outside while collapsed

            // Smooth expansion/collapse animation
            Behavior on Layout.preferredHeight {
                NumberAnimation {
                    duration: 250
                    easing.type: Easing.InOutQuad
                }
            }

            ColumnLayout {
                id: contentArea
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 10
            }
        }
    }
}