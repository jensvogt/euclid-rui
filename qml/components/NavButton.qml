import QtQuick

Rectangle {
    id: root
    property string icon: "●"
    property string label: ""
    property bool selected: false
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
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 14

        Text {
            text: root.icon
            font.pixelSize: 16
            color: root.selected ? "#4f8cff" : "#9aa1ac"
        }
        Text {
            text: root.label
            font.pixelSize: 14
            color: root.selected ? "white" : "#c4c9d1"
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
