import QtQuick

Column {
    id: root
    property string label: ""
    property string value: ""
    // Shows a small clipboard icon that copies "value" on click - opt-in since most callers
    // (names, dates, regions) have no reason to be copied.
    property bool copyable: false
    spacing: 1

    Text { text: root.label; color: "#6b7280"; font.pixelSize: 10 }

    Row {
        id: valueRow
        width: root.width
        spacing: 6

        Text {
            id: valueText
            // Hugs the text's natural width so the icon sits right next to it; only capped down
            // (triggering elide) if the value is too long to fit the field's allotted width.
            width: Math.min(implicitWidth, root.width - (root.copyable ? copyIcon.implicitWidth + valueRow.spacing : 0))
            text: root.value
            color: "#c4c9d1"
            font.pixelSize: 13
            elide: Text.ElideMiddle
        }

        Text {
            id: copyIcon
            visible: root.copyable
            text: copyArea.containsMouse ? "✓" : "⧉"
            color: copyArea.containsMouse ? "#4cd97b" : "#6b7280"
            font.pixelSize: 13
            anchors.verticalCenter: valueText.verticalCenter

            MouseArea {
                id: copyArea
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    clipboardHelper.text = root.value
                    clipboardHelper.selectAll()
                    clipboardHelper.copy()
                }
            }
        }
    }

    // Hidden TextEdit is the standard QML idiom for clipboard access - TextEdit.copy() reaches
    // the system clipboard directly, with no extra import needed beyond plain QtQuick.
    TextEdit {
        id: clipboardHelper
        visible: false
        text: ""
    }
}
