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
    // Whether Ctrl+F opens a find bar over the editor. A caller showing a two-line value has
    // nothing to search and can turn it off; everything holding a document leaves it on.
    property bool searchEnabled: true
    // Shown centred when there is nothing to display, and as the editor's prompt when there is
    // nothing yet but something can be typed.
    property string emptyText: "(empty)"
    // Code and data are read line by line and should scroll sideways rather than be reflowed to
    // whatever width the panel happens to have; prose is the opposite. The default suits the
    // former, which is what a stored payload usually is.
    property int wrapMode: TextArea.NoWrap

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
    // What this would need to show everything without scrolling, for a caller that sizes the
    // component to its content instead of giving it a fixed height. Safe to bind height to: the
    // editor's implicit height follows from its width and its text, never from the height it is
    // given.
    readonly property real implicitContentHeight:
        editor.implicitHeight + 20 + (root.showHeader ? headerRow.implicitHeight + 8 : 0)
        + (root.searchVisible ? root.searchBarHeight + 8 : 0)
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
        // Assigning the same string still moves the cursor back to the start, which is what saving
        // an edit would otherwise do: the saved text comes back as the new baseline and lands here.
        if (editor.text === root.displayText) return
        root.loading = true
        editor.text = root.displayText
        root.loading = false
    }

    onDisplayTextChanged: root.loadIntoEditor()
    Component.onCompleted: root.loadIntoEditor()

    // ── Find ─────────────────────────────────────────────────────────────────
    // Searches what is in the editor rather than "content": with pretty printing on, those are two
    // different documents, and the one the user is looking at is the one they mean.

    property bool searchVisible: false
    property string searchTerm: ""
    property int searchIndex: 0
    readonly property int searchBarHeight: 34
    // Offsets of every match, found once per term rather than per navigation step.
    property var matches: []
    readonly property int matchCount: root.matches.length
    // A single character against a megabyte of JSON is hundreds of thousands of hits, none of which
    // anybody steps through. The search stops counting here and says so with a "+".
    readonly property int matchLimit: 2000
    readonly property bool matchesCapped: root.matches.length >= root.matchLimit

    function findAll(haystack, needle) {
        const hay = haystack.toLowerCase()
        const term = needle.toLowerCase()
        const found = []
        let from = 0
        while (found.length < root.matchLimit) {
            const at = hay.indexOf(term, from)
            if (at < 0) break
            found.push(at)
            // Advanced past the match, not past its first character: overlapping hits of "aa" in
            // "aaa" are one match to a reader, not two.
            from = at + term.length
        }
        return found
    }

    // Recount without disturbing the selection - for an edit made while the bar is open.
    function recount() {
        root.matches = root.searchVisible && root.searchTerm.length > 0
                       ? root.findAll(editor.text, root.searchTerm) : []
        if (root.searchIndex >= root.matchCount) root.searchIndex = 0
    }

    function searchAgain() {
        root.recount()
        if (root.matchCount > 0) root.selectMatch(0)
        else editor.deselect()
    }

    function selectMatch(index) {
        if (root.matchCount === 0) return
        // Wrapping in both directions, so "next" past the last match returns to the first rather
        // than stopping at an end the user cannot see.
        const wrapped = ((index % root.matchCount) + root.matchCount) % root.matchCount
        root.searchIndex = wrapped
        const at = root.matches[wrapped]
        editor.select(at, at + root.searchTerm.length)
        root.revealPosition(at)
    }

    function findNext() { root.selectMatch(root.searchIndex + 1) }
    function findPrevious() { root.selectMatch(root.searchIndex - 1) }

    // A TextArea inside a ScrollView does not scroll itself to a selection made in code, so a match
    // below the fold would be highlighted where nobody can see it. Both axes: with wrapping off, a
    // match can just as easily be off to the right.
    function revealPosition(position) {
        // ScrollView declares its content item as an Item and makes it a Flickable at runtime, so
        // this asks the object rather than trusting the type.
        const flick = scroll.contentItem
        if (!flick || flick.contentHeight === undefined) return
        const box = editor.positionToRectangle(position)
        const margin = 24
        if (box.y < flick.contentY)
            flick.contentY = Math.max(0, box.y - margin)
        else if (box.y + box.height > flick.contentY + flick.height)
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height),
                                      box.y + box.height - flick.height + margin)
        if (box.x < flick.contentX)
            flick.contentX = Math.max(0, box.x - margin)
        else if (box.x + box.width > flick.contentX + flick.width)
            flick.contentX = Math.min(Math.max(0, flick.contentWidth - flick.width),
                                      box.x + box.width - flick.width + margin)
    }

    function openSearch() {
        if (!root.searchEnabled || !root.showable) return
        root.searchVisible = true
        searchField.forceActiveFocus()
        // Ctrl+F on an already open bar means "search for something else", so the old term goes on
        // being shown but the first keystroke replaces it.
        searchField.selectAll()
        root.searchAgain()
    }

    function closeSearch() {
        root.searchVisible = false
        root.matches = []
        root.searchIndex = 0
        editor.deselect()
        editor.forceActiveFocus()
    }

    onSearchTermChanged: root.searchAgain()

    // Ctrl+F belongs to whichever editor the user is in: these come two to a page - the body in the
    // panel and the same body in the full-view dialog - and a shortcut enabled on both at once is
    // ambiguous, which Qt answers by activating neither. Focus decides it, with hover standing in
    // for the reader who is looking at the text but has not clicked into it.
    HoverHandler { id: findHover }

    Shortcut {
        sequences: [StandardKey.Find]
        context: Qt.WindowShortcut
        enabled: root.searchEnabled && root.visible && root.showable
                 && (editor.activeFocus || searchField.activeFocus || findHover.hovered)
        onActivated: root.openSearch()
        onActivatedAmbiguously: root.openSearch()
    }

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

                // Ctrl+F nobody was told about is a feature nobody has. Same wording as the bar it
                // opens, and it closes it again.
                Text {
                    text: "Find"
                    color: findArea.containsMouse ? "#4f8cff" : (root.searchVisible ? "#4f8cff" : "#9aa1ac")
                    font.pixelSize: 11
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.searchEnabled && root.showable

                    MouseArea {
                        id: findArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.searchVisible ? root.closeSearch() : root.openSearch()
                    }
                }

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

        // Hidden until Ctrl+F asks for it, so the component looks exactly as it always did to
        // everyone who never presses it. Height and visibility both read root.searchVisible rather
        // than each other: "visible" answers with the effective value, which latches an item whose
        // height is what makes it visible in the first place.
        Rectangle {
            width: parent.width
            height: root.searchVisible ? root.searchBarHeight : 0
            visible: root.searchVisible
            radius: 8
            color: "#14161b"
            border.color: searchField.activeFocus ? "#3d5473" : "#2c313c"
            border.width: 1

            Text {
                id: findLabel
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "Find"
                color: "#6b7280"
                font.pixelSize: 11
            }

            Row {
                id: findControls
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 11
                    text: {
                        if (root.searchTerm.length === 0) return ""
                        if (root.matchCount === 0) return "No matches"
                        return (root.searchIndex + 1) + " of " + root.matchCount + (root.matchesCapped ? "+" : "")
                    }
                    color: root.searchTerm.length > 0 && root.matchCount === 0 ? "#e0a458" : "#6b7280"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "‹"
                    font.pixelSize: 16
                    color: root.matchCount === 0 ? "#3a4150" : (previousArea.containsMouse ? "#4f8cff" : "#9aa1ac")

                    MouseArea {
                        id: previousArea
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: root.matchCount > 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.findPrevious()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "›"
                    font.pixelSize: 16
                    color: root.matchCount === 0 ? "#3a4150" : (nextArea.containsMouse ? "#4f8cff" : "#9aa1ac")

                    MouseArea {
                        id: nextArea
                        anchors.fill: parent
                        anchors.margins: -4
                        enabled: root.matchCount > 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.findNext()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "✕"
                    font.pixelSize: 11
                    color: closeArea.containsMouse ? "#4f8cff" : "#9aa1ac"

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeSearch()
                    }
                }
            }

            TextField {
                id: searchField
                anchors.left: findLabel.right
                anchors.leftMargin: 8
                anchors.right: findControls.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height - 8
                placeholderText: "Search this content"
                color: "#c4c9d1"
                font.pixelSize: 12
                topPadding: 0
                bottomPadding: 0
                leftPadding: 0
                rightPadding: 0
                Material.theme: Material.Dark
                Material.accent: "#4f8cff"
                // The bar behind it already draws the frame, and an underline inside one reads as a
                // second, narrower field.
                background: null
                onTextChanged: root.searchTerm = searchField.text
                // Enter walks the matches rather than doing nothing, which is what every other find
                // bar does; Shift+Enter walks them backwards.
                Keys.onReturnPressed: event => {
                    if (event.modifiers & Qt.ShiftModifier) root.findPrevious()
                    else root.findNext()
                }
                Keys.onEnterPressed: event => {
                    if (event.modifiers & Qt.ShiftModifier) root.findPrevious()
                    else root.findNext()
                }
                Keys.onEscapePressed: root.closeSearch()
            }
        }

        Rectangle {
            width: parent.width
            height: parent.height - (root.showHeader ? headerRow.implicitHeight + 8 : 0)
                    - (root.searchVisible ? root.searchBarHeight + 8 : 0)
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
                id: scroll
                // Empty content is still an editor when it can be typed into - otherwise there
                // would be no way to write the first version of something that has none yet. Only
                // a read-only view of nothing falls back to the placeholder below.
                visible: root.showable && (root.content.length > 0 || !root.readOnly)
                anchors.fill: parent
                anchors.margins: 10
                anchors.topMargin: warningLabel.visible ? warningLabel.height + 16 : 10
                clip: true

                TextArea {
                    id: editor
                    readOnly: root.readOnly
                    selectByMouse: true
                    // Doubles as the empty-editor prompt, since the placeholder Text below is only
                    // reached by a read-only view.
                    placeholderText: root.readOnly ? "" : root.emptyText
                    wrapMode: root.wrapMode
                    color: "#c4c9d1"
                    font.family: "monospace"
                    font.pixelSize: 12
                    Material.accent: "#4f8cff"
                    // The panel behind it already draws the frame.
                    background: null
                    onTextChanged: {
                        if (!root.loading) root.edited(editor.text)
                        // The document moved under the search: the offsets found before the edit
                        // point at the wrong characters now. Counted again, but without jumping the
                        // cursor - the user is typing, not searching.
                        if (root.searchVisible) root.recount()
                    }
                    // Escape closes the bar from the text as well, which is where the cursor lands
                    // after a match is found.
                    Keys.onEscapePressed: event => {
                        if (root.searchVisible) root.closeSearch()
                        else event.accepted = false
                    }
                }
            }

            Text {
                visible: root.content.length === 0 && root.readOnly
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
