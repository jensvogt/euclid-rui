import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root

    // Public Properties
    property string title: "Tile Header"
    property bool expanded: false
    property alias contentData: contentArea.data // Allows placing any QML elements inside

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

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16

                Text {
                    text: root.title
                    color: "#ffffff"
                    font.pixelSize: 15
                    font.bold: true
                    Layout.fillWidth: true
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

            MouseArea {
                id: headerMouseArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.expanded = !root.expanded
            }
        }

        // 2. Expandable Content Container
        Item {
            id: contentContainer
            Layout.fillWidth: true
            Layout.preferredHeight: root.expanded ? contentArea.implicitHeight : 0
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