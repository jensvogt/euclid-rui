import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// What the app is, and what it is currently talking to. The second half matters as much as the
// first: with the gateway configurable per session, "which build against which backend as whom"
// is exactly what a bug report needs and what nothing else on screen states in one place.
Dialog {
    id: root

    // Filled in by the caller from the window's session state, so this component stays free of
    // context-property lookups and can be shown from anywhere.
    property string currentUser: ""
    property string currentNamespace: ""
    property bool signedIn: false

    modal: true
    anchors.centerIn: parent
    width: 420
    padding: 28
    topPadding: 24
    bottomPadding: 24
    standardButtons: Dialog.NoButton

    background: Rectangle {
        radius: 16
        color: "#1b1e25"
        border.color: "#2c313c"
        border.width: 1
    }

    contentItem: Column {
        width: root.availableWidth
        spacing: 20

        Row {
            spacing: 14

            Image {
                source: "qrc:/EuclidRui/dist/branding/euclid-icon.svg"
                width: 44
                height: 44
                sourceSize.width: 88
                sourceSize.height: 88
                fillMode: Image.PreserveAspectFit
                anchors.verticalCenter: parent.verticalCenter
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text { text: "Euclid RUI"; color: "white"; font.pixelSize: 20; font.bold: true }
                Text {
                    text: "Version " + appVersion + " · built " + buildDate
                    color: "#9aa1ac"
                    font.pixelSize: 12
                }
            }
        }

        Text {
            width: parent.width
            text: "Desktop client for the euclid backend - accounts and access (EAM), storage (ESM), queues "
                  + "(EQS), notifications (ENS), keys (EKM), transfer servers (ETS) and applications (EAP)."
            color: "#c4c9d1"
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            height: sessionColumn.implicitHeight + 24
            radius: 10
            color: "#20242e"
            border.color: "#2c313c"
            border.width: 1

            Column {
                id: sessionColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 6

                Text { text: "This session"; color: "#9aa1ac"; font.pixelSize: 11 }

                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 4

                    Text { text: "Gateway"; color: "#6b7280"; font.pixelSize: 11; width: 90 }
                    Text {
                        text: appSettings.baseUrl
                        color: "#c4c9d1"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        width: sessionColumn.width - 102
                    }

                    Text { text: "Signed in as"; color: "#6b7280"; font.pixelSize: 11; width: 90 }
                    Text {
                        text: root.signedIn ? root.currentUser + " · " + root.currentNamespace : "not signed in"
                        color: "#c4c9d1"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        width: sessionColumn.width - 102
                    }

                    Text { text: "Auth"; color: "#6b7280"; font.pixelSize: 11; width: 90 }
                    Text {
                        // Named the way the settings page names them, so the two never disagree.
                        text: appSettings.authMode === "sigv4" ? "AWS SigV4 (access key)"
                              : appSettings.authMode === "rfc9421" ? "RFC 9421 message signature (access key)"
                              : "Bearer token (login)"
                        color: "#c4c9d1"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        width: sessionColumn.width - 102
                    }

                    Text { text: "Config"; color: "#6b7280"; font.pixelSize: 11; width: 90 }
                    Text {
                        text: appSettings.configFilePath
                        color: "#c4c9d1"
                        font.pixelSize: 11
                        elide: Text.ElideMiddle
                        width: sessionColumn.width - 102
                    }
                }
            }
        }

        // Qt is linked statically here, which is the case where the LGPL's relinking obligation
        // actually bites - so which Qt this was built against is stated rather than implied.
        Text {
            width: parent.width
            text: "Built with Qt " + qtVersion + ", linked statically under the LGPL v3."
            color: "#6b7280"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Item {
            width: parent.width
            height: 40

            Button {
                text: "Close"
                flat: true
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                Material.theme: Material.Dark
                onClicked: root.close()
            }
        }
    }
}
