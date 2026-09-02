import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// Shows a payload as text - pretty printed when its content type says it is JSON or XML - and
// refuses to show anything that is not text at all.
//
// The refusal is the point. A JAR, a PDF, an image or an "application/octet-stream" put through a
// TextArea is not merely unreadable: it comes back out of the editor as a different sequence of
// bytes than went in, because whatever could not be decoded was already replaced on the way here.
// So the type is checked against what can be displayed, the bytes are checked for the marks of
// binary content in case the type lied, and if either says no the editor is not shown at all.
//
// Pretty printing is a view, not an edit - but an edited pretty printed document saves as it is on
// screen, reformatted. "prettyPrinted" says whether that is what the caller is holding.
Item {
    id: root

    // ── Input ────────────────────────────────────────────────────────────────
    // The payload as text, exactly as it was received.
    property string content: ""
    // MIME type it arrived with, parameters and all ("application/json; charset=utf-8"). Empty
    // means nothing was declared, which is treated as not showable - guessing at a type is how
    // binary content ends up in the editor.
    property string contentType: ""
    property bool readOnly: false
    property bool prettyPrint: true
    // Past this, the payload is refused rather than rendered: a TextArea lays out every line it is
    // given, so a large object freezes the window rather than filling it.
    property int maxLength: 1024 * 1024
    property bool showHeader: true
    property string emptyText: "(empty)"

    // ── Output ───────────────────────────────────────────────────────────────
    // "json", "xml", "text", or "" when nothing here can be displayed.
    readonly property string format: root.formatFor(root.contentType)
    readonly property bool showable: root.rejectReason.length === 0
    // Why the content is not shown, empty when it is. Phrased for a user, not a log.
    readonly property string rejectReason: {
        if (root.content.length === 0) return ""
        if (root.content.length > root.maxLength)
            return "This content is " + SizeFormat.format(root.content.length) + ", past the "
                   + SizeFormat.format(root.maxLength) + " this view will render. Download it instead."
        if (root.format.length === 0)
            return "Cannot display " + root.typeDescription(root.contentType)
                   + ". Only text, JSON and XML content can be shown here."
        if (root.looksBinary(root.content))
            return "This content is declared as " + root.normalizedType(root.contentType)
                   + " but contains binary data, so it is not shown as text."
        return ""
    }
    // One pass over the content, since both the text to show and whether formatting failed come out
    // of the same attempt - and the attempt is the expensive part.
    readonly property var formatted: {
        if (!root.showable || !root.prettyPrint || (root.format !== "json" && root.format !== "xml"))
            return ({ text: root.content, failed: false })
        const pretty = root.format === "json" ? root.prettyJson(root.content) : root.prettyXml(root.content)
        return pretty === null ? ({ text: root.content, failed: true }) : ({ text: pretty, failed: false })
    }
    // What the editor was last loaded with: the pretty printed form when that worked, the content
    // as stored otherwise. This is the baseline "modified" is measured against.
    readonly property string displayText: root.showable ? root.formatted.text : ""
    // Set when the content type promised a format the content could not be reformatted as. Not an
    // error - the content is shown exactly as stored - but the reason it is not indented.
    readonly property string formatWarning: {
        if (!root.formatted.failed) return ""
        return root.format === "json"
               ? "Shown as stored: this is declared as JSON but does not parse."
               : "Shown as stored: this XML was not reformatted - it is either not well-formed, or holds CDATA that must not be rewritten."
    }
    readonly property bool prettyPrinted: root.showable && root.displayText !== root.content
    // What is in the editor right now, which is what a caller should save.
    readonly property string text: editor.text
    readonly property bool modified: root.showable && editor.text !== root.displayText

    // Emitted for edits the user made, not for content loaded into the editor.
    signal edited(string text)

    // Throws away the user's edits and reloads what was last displayed.
    function reset() {
        root.loadIntoEditor()
    }

    implicitHeight: 260
    implicitWidth: 400

    // ── Content type ─────────────────────────────────────────────────────────

    function normalizedType(type) {
        return String(type).split(";")[0].trim().toLowerCase()
    }

    // A whitelist, deliberately: anything not named here is refused, so a type nobody thought about
    // fails closed rather than being fed to the editor.
    function formatFor(type) {
        const base = root.normalizedType(type)
        if (base.length === 0) return ""
        if (base === "application/json" || base === "text/json" || base.endsWith("+json")) return "json"
        if (base === "application/xml" || base === "text/xml" || base.endsWith("+xml")) return "xml"
        if (base.startsWith("text/")) return "text"
        // Text formats that were never given a "text/" type.
        const textTypes = ["application/javascript", "application/x-javascript", "application/ecmascript",
                           "application/yaml", "application/x-yaml", "application/toml", "application/x-toml",
                           "application/sql", "application/graphql", "application/x-ndjson",
                           "application/x-sh", "application/x-shellscript", "application/x-httpd-php",
                           "application/csv", "application/x-www-form-urlencoded"]
        return textTypes.indexOf(base) >= 0 ? "text" : ""
    }

    // Names the type the way the refusal message needs to read, so it says "a JAR archive" rather
    // than repeating a MIME type back at the user.
    function typeDescription(type) {
        const base = root.normalizedType(type)
        if (base.length === 0) return "content that arrived without a content type"
        const named = {
            "application/octet-stream": "raw binary content",
            "application/java-archive": "a JAR archive",
            "application/x-java-archive": "a JAR archive",
            "application/java-vm": "compiled Java bytecode",
            "application/zip": "a ZIP archive",
            "application/gzip": "a gzip archive",
            "application/x-gzip": "a gzip archive",
            "application/x-tar": "a tar archive",
            "application/x-7z-compressed": "a 7z archive",
            "application/x-bzip2": "a bzip2 archive",
            "application/x-rar-compressed": "a RAR archive",
            "application/pdf": "a PDF document",
            "application/x-executable": "an executable",
            "application/x-sharedlib": "a shared library",
            "application/vnd.ms-excel": "an Excel workbook",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "an Excel workbook",
            "application/msword": "a Word document",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "a Word document"
        }
        if (named[base] !== undefined) return named[base]
        if (base.startsWith("image/")) return "an image"
        if (base.startsWith("video/")) return "a video"
        if (base.startsWith("audio/")) return "audio"
        if (base.startsWith("font/") || base.startsWith("application/font")) return "a font"
        return base + " content"
    }

    // The second gate, for content whose type is text but whose bytes are not. Anything that could
    // not be decoded is already U+FFFD by the time it gets here, and a NUL settles it outright.
    function looksBinary(text) {
        const limit = Math.min(text.length, 4000)
        let suspicious = 0
        for (let i = 0; i < limit; ++i) {
            const code = text.charCodeAt(i)
            if (code === 0) return true
            if (code === 0xFFFD) suspicious++
            else if (code < 32 && code !== 9 && code !== 10 && code !== 13) suspicious++
        }
        return limit > 0 && suspicious * 100 > limit * 2
    }

    // ── Pretty printing ──────────────────────────────────────────────────────
    // Both return null rather than throwing or half-formatting: the caller shows the content as
    // stored when that happens, which is always safe and never loses a byte.

    function prettyJson(text) {
        try {
            return JSON.stringify(JSON.parse(text), null, 2)
        } catch (error) {
            return null
        }
    }

    function prettyXml(text) {
        const source = String(text).trim()
        if (!source.startsWith("<")) return null
        // CDATA can hold anything, including the tag boundaries this splits on, so a document with
        // one is left exactly as it is rather than risk rewriting what is inside it.
        if (source.indexOf("<![CDATA[") >= 0) return null

        // Whitespace *between* tags is layout and is replaced; whitespace inside an element's text
        // is content and survives, because "<a>value</a>" never splits.
        const tokens = source.replace(/\r\n?/g, "\n").replace(/>\s+</g, "><").replace(/></g, ">\n<").split("\n")

        const lines = []
        let depth = 0
        for (let i = 0; i < tokens.length; ++i) {
            const token = tokens[i].trim()
            if (token.length === 0) continue

            const isTag = token.startsWith("<")
            const closing = /^<\//.test(token)
            // <?xml ... ?>, <!-- ... -->, <!DOCTYPE ...>: they nest nothing.
            const prologue = /^<[?!]/.test(token)
            const selfClosing = /\/>$/.test(token)
            // Opened and closed within this one token, text and all.
            const complete = /^<([^\s\/>]+)[^>]*>[\s\S]*<\/\1>$/.test(token)

            if (closing) depth = Math.max(0, depth - 1)
            lines.push("  ".repeat(depth) + token)
            if (isTag && !closing && !prologue && !selfClosing && !complete) depth++
        }
        return lines.join("\n")
    }

    // ── Editor state ─────────────────────────────────────────────────────────
    // The editor's text is assigned rather than bound: typing into a TextArea would break a binding
    // on the first keystroke, and then nothing would ever load into it again.
    property bool loading: false

    function loadIntoEditor() {
        root.loading = true
        editor.text = root.displayText
        root.loading = false
    }

    onDisplayTextChanged: root.loadIntoEditor()
    Component.onCompleted: root.loadIntoEditor()

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
                        text: root.format.length > 0 ? root.format.toUpperCase() : "BINARY"
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
                    text: "· edited"
                    color: "#e0a458"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.modified
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12

                Text {
                    text: "Reset"
                    color: resetArea.containsMouse ? "#4f8cff" : "#9aa1ac"
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.modified

                    MouseArea {
                        id: resetArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.reset()
                    }
                }

                CheckBox {
                    text: "Pretty print"
                    // Nothing to indent for plain text, and nothing to indent at all when the
                    // content is not being shown.
                    visible: root.showable && (root.format === "json" || root.format === "xml")
                    checked: root.prettyPrint
                    Material.theme: Material.Dark
                    Material.accent: "#4f8cff"
                    anchors.verticalCenter: parent.verticalCenter
                    // Reformatting reloads the editor, so an edit in progress would be discarded
                    // without this.
                    enabled: !root.modified
                    onToggled: root.prettyPrint = checked
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

            // Shown as stored, with the reason it is not indented.
            Text {
                id: warningLabel
                visible: root.formatWarning.length > 0 && root.showable
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 10
                text: root.formatWarning
                color: "#e0a458"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            ScrollView {
                visible: root.showable && root.content.length > 0
                anchors.fill: parent
                anchors.margins: 10
                anchors.topMargin: warningLabel.visible ? warningLabel.height + 16 : 10
                clip: true

                TextArea {
                    id: editor
                    readOnly: root.readOnly
                    selectByMouse: true
                    wrapMode: TextArea.NoWrap
                    color: "#c4c9d1"
                    font.family: "monospace"
                    font.pixelSize: 12
                    Material.accent: "#4f8cff"
                    // The panel behind it already draws the frame.
                    background: null
                    onTextChanged: if (!root.loading) root.edited(editor.text)
                }
            }

            Text {
                visible: root.content.length === 0
                anchors.centerIn: parent
                text: root.emptyText
                color: "#6b7280"
                font.pixelSize: 12
            }

            // The refusal: what it is and why it is not on screen, in place of an editor that would
            // otherwise be showing mojibake the user could accidentally save.
            Column {
                visible: !root.showable && root.content.length > 0
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
                    text: root.rejectReason
                    color: "#9aa1ac"
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: SizeFormat.format(root.content.length)
                    color: "#6b7280"
                    font.pixelSize: 11
                }
            }
        }
    }
}
