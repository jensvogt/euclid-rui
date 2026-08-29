import QtQuick

Item {
    id: root
    property bool checked: false
    property color onColor: "#4f8cff"
    property color offColor: "#3a3f4b"
    signal toggled(bool checked)

    width: 46
    height: 26

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? root.onColor : root.offColor
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Rectangle {
        id: knob
        width: 20
        height: 20
        radius: 10
        color: "white"
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? root.width - width - 3 : 3
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        layer.enabled: true
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            root.checked = !root.checked
            root.toggled(root.checked)
        }
    }
}
