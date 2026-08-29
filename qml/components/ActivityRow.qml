import QtQuick

Row {
    id: root
    property string initials: ""
    property color avatarColor: "#4f8cff"
    property string title: ""
    property string subtitle: ""
    property string time: ""

    spacing: 14
    width: parent ? parent.width : 300
    height: 48

    Rectangle {
        width: 40
        height: 40
        radius: 20
        color: root.avatarColor
        anchors.verticalCenter: parent.verticalCenter

        Text {
            anchors.centerIn: parent
            text: root.initials
            color: "white"
            font.pixelSize: 13
            font.bold: true
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2
        width: root.width - 40 - 14 - 60

        Text {
            text: root.title
            color: "white"
            font.pixelSize: 13
            elide: Text.ElideRight
            width: parent.width
        }
        Text {
            text: root.subtitle
            color: "#9aa1ac"
            font.pixelSize: 12
            elide: Text.ElideRight
            width: parent.width
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.time
        color: "#6b7280"
        font.pixelSize: 11
    }
}
