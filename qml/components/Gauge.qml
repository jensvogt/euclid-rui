import QtQuick

Item {
    id: root
    property real value: 0.0        // 0..1
    property color trackColor: "#2c313c"
    property color progressColor: "#4f8cff"
    property string label: ""
    property string valueText: ""

    implicitWidth: 160
    implicitHeight: 160

    property real animatedValue: 0.0
    Behavior on animatedValue { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
    onValueChanged: animatedValue = value
    Component.onCompleted: animatedValue = value

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var cx = width / 2
            var cy = height / 2
            var lineWidth = Math.max(4, Math.min(width, height) * 0.075)
            var radius = Math.min(width, height) / 2 - lineWidth
            var startAngle = Math.PI * 0.75
            var endAngle = Math.PI * 2.25

            ctx.lineWidth = lineWidth
            ctx.lineCap = "round"

            ctx.beginPath()
            ctx.arc(cx, cy, radius, startAngle, endAngle, false)
            ctx.strokeStyle = root.trackColor
            ctx.stroke()

            var valueAngle = startAngle + (endAngle - startAngle) * root.animatedValue
            ctx.beginPath()
            ctx.arc(cx, cy, radius, startAngle, valueAngle, false)
            ctx.strokeStyle = root.progressColor
            ctx.stroke()
        }

        Connections {
            target: root
            function onAnimatedValueChanged() { canvas.requestPaint() }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 2
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.valueText
            color: "white"
            font.pixelSize: Math.max(10, root.width * 0.1625)
            font.bold: true
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: "#9aa1ac"
            font.pixelSize: Math.max(8, root.width * 0.075)
        }
    }
}
