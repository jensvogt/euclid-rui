import QtQuick

Rectangle {
    id: root
    property string title: ""
    property string value: ""
    property string trend: ""
    property bool trendUp: true
    property color accent: "#4f8cff"
    property bool clickable: false
    signal clicked()

    radius: 14
    color: "#20242e"
    border.color: "#2c313c"
    border.width: 1

    implicitWidth: 220
    implicitHeight: 120

    Rectangle {
        width: 4
        height: parent.height * 0.6
        radius: 2
        color: root.accent
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
    }

    Column {
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            text: root.title
            color: "#9aa1ac"
            font.pixelSize: 13
        }
        // Both of these are cut off rather than allowed to run on. A Text with no width is as wide
        // as its content, and a card is not: without this, one long principal name or one wordy
        // trend line paints across whatever card sits to the right of it, which is also what
        // forced callers to size cards by their longest sentence instead of by how they should
        // look in a row.
        Text {
            text: root.value
            color: "white"
            font.pixelSize: 28
            font.bold: true
            width: parent.width
            elide: Text.ElideRight
        }
        Row {
            spacing: 4
            width: parent.width

            Text {
                id: trendArrow
                text: root.trendUp ? "▲" : "▼"
                color: root.trendUp ? "#4cd97b" : "#ff6b6b"
                font.pixelSize: 11
            }
            Text {
                text: root.trend
                color: root.trendUp ? "#4cd97b" : "#ff6b6b"
                font.pixelSize: 12
                width: parent.width - trendArrow.width - parent.spacing
                elide: Text.ElideRight
            }
        }
    }

    Text {
        visible: root.clickable
        text: "›"
        color: "#6b7280"
        font.pixelSize: 16
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.top: parent.top
        anchors.topMargin: 10
    }

    scale: hoverArea.containsMouse ? 1.02 : 1.0
    Behavior on scale { NumberAnimation { duration: 120 } }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.clickable) root.clicked()
    }
}
