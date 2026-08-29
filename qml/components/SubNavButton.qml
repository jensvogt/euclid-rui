import QtQuick

Rectangle {
    id: root
    property string label: ""
    property bool selected: false
    signal clicked()

    width: parent ? parent.width : 200
    height: 36
    radius: 8
    color: selected ? "#2c3648" : (mouseArea.containsMouse ? "#22262f" : "transparent")

    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        width: 5
        height: 5
        radius: 2.5
        color: root.selected ? "#4f8cff" : "#4b5160"
        anchors.left: parent.left
        anchors.leftMargin: 34
        anchors.verticalCenter: parent.verticalCenter
    }

    Text {
        text: root.label
        font.pixelSize: 13
        color: root.selected ? "white" : "#9aa1ac"
        anchors.left: parent.left
        anchors.leftMargin: 48
        anchors.verticalCenter: parent.verticalCenter
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.clicked()
    }
}
