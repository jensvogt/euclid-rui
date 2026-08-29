import QtQuick

Column {
    property string label: ""
    property string value: ""
    spacing: 1

    Text { text: label; color: "#6b7280"; font.pixelSize: 10 }
    Text { text: value; color: "#c4c9d1"; font.pixelSize: 13; elide: Text.ElideMiddle; width: parent.width }
}
