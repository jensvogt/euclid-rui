import QtQuick

Column {
    property string title: ""
    property string subtitle: ""
    spacing: 2

    Text {
        text: title
        color: "white"
        font.pixelSize: 20
        font.bold: true
    }
    Text {
        visible: subtitle.length > 0
        text: subtitle
        color: "#9aa1ac"
        font.pixelSize: 13
    }
}
