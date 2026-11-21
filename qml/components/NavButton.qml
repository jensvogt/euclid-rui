import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    property string icon: "●"
    property string label: ""
    property bool selected: false
    // Folded side panel: the icon alone, centred, and the label as a tooltip instead.
    property bool collapsed: false
    // What the tooltip says when folded, if not the label - the fold toggle's label is the action
    // it does when open, and the opposite one is what it does when folded.
    property string tooltip: ""
    signal clicked()

    width: parent ? parent.width : 200
    height: 44
    radius: 10
    color: selected ? "#2c3648" : (mouseArea.containsMouse ? "#22262f" : "transparent")

    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        visible: root.selected
        width: 3
        height: 22
        radius: 2
        color: "#4f8cff"
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: root.collapsed ? (root.width - iconText.width) / 2 : 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Text {
            id: iconText
            text: root.icon
            font.pixelSize: 16
            color: root.selected ? "#4f8cff" : "#9aa1ac"
        }
        Text {
            text: root.label
            visible: !root.collapsed
            font.pixelSize: 14
            color: root.selected ? "white" : "#c4c9d1"
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    ToolTip.visible: root.collapsed && mouseArea.containsMouse
    ToolTip.text: root.tooltip.length > 0 ? root.tooltip : root.label
    ToolTip.delay: 400
}
