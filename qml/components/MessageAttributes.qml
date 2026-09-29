import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// A message's attributes as a scrollable name/type/value list. One component for both maps a
// message carries - the sender's own and euclid's - because they are the same shape and only differ
// in who wrote them, which is the calling tab's business rather than this list's.
//
// The type is shown beside every value rather than left implicit: an attribute is stored with the
// type it was sent as (see Dto::COM::Variant), so "1" sent as a string and 1 sent as a long are two
// different attributes, and a consumer reading them with a typed client can tell the difference
// even when this column cannot.
Item {
    id: root

    // [{name, type, value}], already in key order - EqsClient flattens the map the server sends.
    property var attributes: []
    property string emptyText: "No attributes."

    Text {
        anchors.centerIn: parent
        width: parent.width - 48
        horizontalAlignment: Text.AlignHCenter
        visible: root.attributes.length === 0
        text: root.emptyText
        color: "#6b7280"
        font.pixelSize: 12
        wrapMode: Text.WordWrap
    }

    ScrollView {
        anchors.fill: parent
        visible: root.attributes.length > 0
        contentWidth: availableWidth
        clip: true

        Column {
            id: rows
            width: parent.width
            spacing: 1

            Repeater {
                model: root.attributes

                delegate: Rectangle {
                    id: attributeRow
                    required property var modelData
                    required property int index

                    width: rows.width
                    height: Math.max(38, valueText.implicitHeight + 16)
                    // Banded rather than ruled: an attribute value wraps to as many lines as it
                    // needs, and a rule between rows of uneven height reads as a table with a
                    // broken grid where alternating fills just read as rows.
                    color: attributeRow.index % 2 === 0 ? "#1b1e25" : "transparent"
                    radius: 6

                    Column {
                        id: nameColumn
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        width: Math.max(120, attributeRow.width * 0.3)
                        spacing: 2

                        Text {
                            width: parent.width
                            text: attributeRow.modelData.name
                            color: "#e5e7eb"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: attributeRow.modelData.type
                            color: "#6b7280"
                            font.pixelSize: 10
                            visible: text.length > 0
                        }
                    }

                    // Selectable rather than a plain Text: an attribute value is a thing people
                    // paste into a query or a ticket, and a label cannot be copied out of.
                    TextEdit {
                        id: valueText
                        anchors.left: nameColumn.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        readOnly: true
                        selectByMouse: true
                        text: String(attributeRow.modelData.value)
                        color: "#c4c9d1"
                        font.family: "monospace"
                        font.pixelSize: 12
                        wrapMode: TextEdit.Wrap
                        selectionColor: "#2c3648"
                    }
                }
            }
        }
    }
}
