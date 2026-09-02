import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// Shows a payload as an image when its content type says it is one, and says why not when it is
// not - the counterpart to EditableText, which does the same for text.
//
// The check is on the content type first, because that is what decides whether these bytes are
// worth handing to a decoder at all, and on the decoder's own verdict second: an image format Qt
// was built without a plugin for, or a file whose type is right and whose bytes are damaged, both
// fail at load time and neither can be predicted from the type alone. A viewer that showed an
// empty frame in either case would be indistinguishable from one showing a blank image.
//
// The bytes arrive base64 encoded rather than as a string, since an image is not text and anything
// that decoded it as text would already have replaced whatever was not valid UTF-8. Alternatively
// "source" points at an image that is already somewhere addressable, e.g. a file on disk.
Item {
    id: root

    // ── Input ────────────────────────────────────────────────────────────────
    // The image's bytes, base64 encoded. Turned into the data: URI the loader reads.
    property string base64Data: ""
    // MIME type they arrived with, parameters and all ("image/png; charset=binary").
    property string contentType: ""
    // Used when base64Data is empty: an image that already has an address (a local file, say).
    // The content type still decides whether it is shown.
    property url source: ""
    // Past this many decoded bytes the image is refused rather than loaded. Decoding is not
    // proportional to file size - a compressed image can expand into far more memory than it
    // occupies - so this is a bound on the work, not just on the transfer.
    property int maxBytes: 16 * 1024 * 1024
    property bool showHeader: true
    // Fit shrinks an image too large for the frame but never enlarges a small one, so "1:1" always
    // means what it says and fit never invents detail that is not there.
    property bool fitToView: true
    property string emptyText: "(no image)"

    // ── Output ───────────────────────────────────────────────────────────────
    // The image format the content type names ("png", "jpeg", "svg", ...), empty when it names
    // something that is not an image this build can show.
    readonly property string format: root.formatFor(root.contentType)
    readonly property bool showable: root.rejectReason.length === 0
    readonly property string rejectReason: {
        if (!root.hasData) return ""
        if (root.format.length === 0) {
            // Two different refusals: a format nothing here can decode, and something that was
            // never an image to begin with.
            const base = root.normalizedType(root.contentType)
            return base.startsWith("image/")
                   ? "Cannot display " + base + ": this build has no decoder for that format."
                   : "Cannot display " + root.typeDescription(root.contentType) + " here - this view shows images."
        }
        if (root.decodedLength > root.maxBytes)
            return "This image is " + SizeFormat.format(root.decodedLength) + ", past the "
                   + SizeFormat.format(root.maxBytes) + " this view will decode."
        return ""
    }
    // The decoder's verdict, which only exists after it has tried. Kept apart from rejectReason:
    // one is a refusal to load, the other is a load that failed.
    readonly property bool decodeFailed: root.showable && root.hasData && root.view.status === Image.Error
    readonly property bool loading: root.showable && root.hasData && root.view.status === Image.Loading
    readonly property int naturalWidth: root.view.sourceSize.width
    readonly property int naturalHeight: root.view.sourceSize.height

    implicitWidth: 400
    implicitHeight: 320

    readonly property bool hasData: root.base64Data.length > 0 || root.source.toString().length > 0
    // Base64 carries three bytes in every four characters, padding included.
    readonly property int decodedLength: Math.floor(root.base64Data.length * 3 / 4)
    // A GIF is the one format worth animating, and animating it needs a different element - so the
    // pair below exists, and everything else reads whichever of them is in use.
    readonly property bool animated: root.format === "gif"
    readonly property Image view: root.animated ? animatedView : staticView

    readonly property url effectiveSource: {
        if (!root.showable) return ""
        if (root.base64Data.length > 0)
            return "data:" + root.normalizedType(root.contentType) + ";base64," + root.base64Data
        return root.source
    }

    function normalizedType(type) {
        return String(type).split(";")[0].trim().toLowerCase()
    }

    // A whitelist of what Qt can actually decode - png, bmp, ppm/xbm/xpm are built in, the rest
    // come from the imageformats plugins shipped alongside. A type that is genuinely an image but
    // is not here is refused rather than handed over, which is a clearer answer than a frame that
    // silently stays empty.
    function formatFor(type) {
        const base = root.normalizedType(type)
        const formats = {
            "image/png": "png",
            "image/apng": "png",
            "image/jpeg": "jpeg",
            "image/jpg": "jpeg",
            "image/pjpeg": "jpeg",
            "image/gif": "gif",
            "image/bmp": "bmp",
            "image/x-ms-bmp": "bmp",
            "image/webp": "webp",
            "image/svg+xml": "svg",
            "image/tiff": "tiff",
            "image/x-icon": "ico",
            "image/vnd.microsoft.icon": "ico",
            "image/x-icns": "icns",
            "image/x-tga": "tga",
            "image/x-targa": "tga",
            "image/x-portable-pixmap": "ppm",
            "image/x-portable-graymap": "pgm",
            "image/x-portable-bitmap": "pbm",
            "image/x-xbitmap": "xbm",
            "image/x-xpixmap": "xpm",
            "image/vnd.wap.wbmp": "wbmp"
        }
        return formats[base] !== undefined ? formats[base] : ""
    }

    // A noun phrase, so a caller can put it in whatever sentence it is building.
    function typeDescription(type) {
        const base = root.normalizedType(type)
        if (base.length === 0) return "content that arrived without a content type"
        // An image type that is not in the table above: worth saying so, since "not an image" would
        // be wrong and unhelpful at once.
        if (base.startsWith("image/")) return base + ", a format this build cannot decode"
        return base + " content"
    }

    // How much the image has to shrink to fit the frame. Never above 1: an image smaller than the
    // frame is shown at its own size rather than blown up.
    readonly property real fitScale: {
        if (root.naturalWidth <= 0 || root.naturalHeight <= 0) return 1
        return Math.min(1, Math.min(frameArea.width / root.naturalWidth, frameArea.height / root.naturalHeight))
    }
    readonly property real displayScale: root.fitToView ? root.fitScale : 1

    Column {
        anchors.fill: parent
        spacing: 8

        Item {
            width: parent.width
            height: root.showHeader ? headerRow.implicitHeight : 0
            visible: root.showHeader

            Row {
                id: headerRow
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    radius: 6
                    color: "#2c3648"
                    height: 20
                    width: formatLabel.implicitWidth + 14
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        id: formatLabel
                        anchors.centerIn: parent
                        text: root.format.length > 0 ? root.format.toUpperCase() : "NOT AN IMAGE"
                        color: "#9aa1ac"
                        font.pixelSize: 10
                    }
                }

                Text {
                    text: root.normalizedType(root.contentType)
                    color: "#6b7280"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text.length > 0
                }

                Text {
                    // Only meaningful once the decoder has read the header.
                    visible: root.naturalWidth > 0 && root.naturalHeight > 0
                    text: "· " + root.naturalWidth + " × " + root.naturalHeight
                          + (root.displayScale < 1 ? "  (" + Math.round(root.displayScale * 100) + "%)" : "")
                    color: "#6b7280"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                BusyIndicator {
                    running: root.loading
                    visible: root.loading
                    width: 18
                    height: 18
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    // Offered only when it would change anything: an image that already fits is
                    // shown at 1:1 whatever this says.
                    visible: root.showable && root.fitScale < 1
                    text: root.fitToView ? "Actual size" : "Fit"
                    color: zoomArea.containsMouse ? "#4f8cff" : "#9aa1ac"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        id: zoomArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.fitToView = !root.fitToView
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: parent.height - (root.showHeader ? headerRow.implicitHeight + 8 : 0)
            radius: 8
            color: "#14161b"
            border.color: "#2c313c"
            border.width: 1
            clip: true

            Flickable {
                id: frameArea
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                visible: root.showable && root.hasData && !root.decodeFailed
                // The scrollable area is the image when it overflows and the frame when it does
                // not, which is what keeps a fitted image centred rather than pinned to a corner.
                contentWidth: Math.max(width, frame.width)
                contentHeight: Math.max(height, frame.height)
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                Item {
                    id: frame
                    width: root.naturalWidth > 0 ? root.naturalWidth * root.displayScale : frameArea.width
                    height: root.naturalHeight > 0 ? root.naturalHeight * root.displayScale : frameArea.height
                    x: Math.max(0, (frameArea.contentWidth - width) / 2)
                    y: Math.max(0, (frameArea.contentHeight - height) / 2)

                    // Only one of the two ever has a source: loading both would decode the image
                    // twice, and an AnimatedImage holds every frame of it.
                    Image {
                        id: staticView
                        anchors.fill: parent
                        visible: !root.animated
                        source: root.animated ? "" : root.effectiveSource
                        fillMode: Image.PreserveAspectFit
                        // Decoded off the UI thread: a large image otherwise freezes the window for
                        // as long as it takes to read.
                        asynchronous: true
                        // sourceSize is deliberately left alone. Assigning it - even a zero, even
                        // to render an SVG at its displayed size - makes it read back as what was
                        // assigned rather than as the image's own dimensions, and those dimensions
                        // are what the size label and the fit scale are computed from.
                        smooth: true
                        mipmap: true
                    }

                    AnimatedImage {
                        id: animatedView
                        anchors.fill: parent
                        visible: root.animated
                        source: root.animated ? root.effectiveSource : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        playing: true
                    }
                }
            }

            Text {
                visible: !root.hasData
                anchors.centerIn: parent
                text: root.emptyText
                color: "#6b7280"
                font.pixelSize: 12
            }

            // Refused before loading, or failed while loading - two different things, said
            // separately, in place of a frame that would otherwise just sit there empty.
            Column {
                visible: root.hasData && (!root.showable || root.decodeFailed)
                anchors.centerIn: parent
                width: parent.width - 48
                spacing: 8

                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: "⛔"
                    color: "#6b7280"
                    font.pixelSize: 22
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: root.decodeFailed
                          ? "This image could not be decoded. It is declared as "
                            + root.normalizedType(root.contentType) + ", so either the bytes are damaged or they are not that format."
                          : root.rejectReason
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    visible: root.decodedLength > 0
                    text: SizeFormat.format(root.decodedLength)
                    color: "#6b7280"
                    font.pixelSize: 11
                }
            }
        }
    }
}
