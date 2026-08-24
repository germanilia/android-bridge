import AppKit
import SwiftUI

/// A meeting note rendered into a real AppKit text view.
///
/// SwiftUI's `Text` only allows a drag-selection *inside* one Text view and has
/// no select-all at all, so a note split into headings and bullet groups could
/// never be selected or copied as a whole. One `NSTextView` over one text
/// storage gives the native behaviour for free: drag across everything, ⌘A,
/// ⌘C, and the standard right-click menu.
struct SelectableNoteText: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> AutoSizingTextView {
        let view = AutoSizingTextView()
        view.apply(text)
        return view
    }

    func updateNSView(_ view: AutoSizingTextView, context: Context) {
        view.apply(text)
    }

    /// SwiftUI proposes the width; we answer with the height the text needs, so
    /// the enclosing SwiftUI ScrollView does all the scrolling.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AutoSizingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width < .infinity else { return nil }
        return CGSize(width: width, height: nsView.height(for: width))
    }
}

/// Read-only NSTextView that reports the height its text needs at a given width
/// instead of scrolling internally.
final class AutoSizingTextView: NSTextView {
    private var source: String?

    init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true   // re-wrap when SwiftUI resizes us
        container.heightTracksTextView = false // …but never clamp height to the frame
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        super.init(frame: .zero, textContainer: container)

        isEditable = false
        isSelectable = true
        isRichText = true
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainerInset = .zero
        focusRingType = .none
        autoresizingMask = [.width]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    /// Re-renders only when the note text actually changed — SwiftUI calls
    /// `updateNSView` on every layout pass and markdown parsing is not free.
    func apply(_ text: String) {
        guard text != source else { return }
        source = text
        textStorage?.setAttributedString(NoteAttributedString.make(text))
        invalidateIntrinsicContentSize()
    }

    func height(for width: CGFloat) -> CGFloat {
        guard let container = textContainer, let layout = layoutManager else { return 0 }
        // The frame may still hold the previous width during measurement, so
        // drive the container directly rather than trusting `widthTracksTextView`.
        container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layout.ensureLayout(for: container) // TextKit lays out lazily
        return ceil(layout.usedRect(for: container).height)
    }

    override var intrinsicContentSize: NSSize {
        guard bounds.width > 0 else { return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
        return NSSize(width: NSView.noIntrinsicMetric, height: height(for: bounds.width))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = frame.width != newSize.width
        super.setFrameSize(newSize)
        if widthChanged { invalidateIntrinsicContentSize() }
    }

    /// A short right-click menu. The stock NSTextView menu carries editing and
    /// substitution items that mean nothing for a read-only note.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        return menu
    }
}

/// Turns a note's Markdown into an `NSAttributedString`. Mirrors the rendering
/// rules of `FormattedNoteText` (headings, bullets, tables, inline emphasis)
/// but produces AppKit attributes so one text view can hold the whole note.
enum NoteAttributedString {
    static func make(_ text: String) -> NSAttributedString {
        let rtl = text.isMostlyHebrew
        let result = NSMutableAttributedString()
        var lastWasBlank = true // suppresses a leading blank line

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let lowered = line.lowercased()
            if lowered == "```" || lowered == "```markdown" { continue }
            if isTableSeparator(line) { continue }

            if line.isEmpty {
                if lastWasBlank { continue } // collapse runs of blank lines
                lastWasBlank = true
            } else {
                lastWasBlank = false
            }

            if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(attributedLine(line))
        }

        let style = NSMutableParagraphStyle()
        style.lineSpacing = 5
        style.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
        style.alignment = rtl ? .right : .left
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: result.length))
        return result
    }

    private static func attributedLine(_ line: String) -> NSAttributedString {
        if let heading = heading(for: line) {
            let font: NSFont = switch heading.level {
            case 1: .preferredFont(forTextStyle: .title2)
            case 2: .preferredFont(forTextStyle: .title3)
            default: .preferredFont(forTextStyle: .headline)
            }
            return inline(heading.text, font: font.bolded())
        }
        if let cells = tableRow(line) {
            return inline(cells.joined(separator: "   |   "), font: .preferredFont(forTextStyle: .body))
        }
        if let bullet = bullet(line) {
            let body = NSFont.preferredFont(forTextStyle: .body)
            let result = NSMutableAttributedString(string: "•  ", attributes: [.font: body, .foregroundColor: NSColor.labelColor])
            result.append(inline(bullet, font: body))
            return result
        }
        return inline(line, font: .preferredFont(forTextStyle: .body))
    }

    /// `## Decisions`, or a bare/numbered section title the model emitted
    /// without any Markdown ("Decisions", "2) Action Items").
    private static func heading(for line: String) -> (level: Int, text: String)? {
        let sections = ["Summary", "Decisions", "Action Items", "Open Questions/Risks"]
        for section in sections {
            if line == section { return (2, section) }
            for n in 1...4 where line == "\(n)) \(section)" || line == "\(n). \(section)" { return (2, section) }
        }
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes > 0 else { return nil }
        let text = line.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (hashes, String(text))
    }

    private static func bullet(_ line: String) -> String? {
        guard line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") else { return nil }
        return String(line.dropFirst(2))
    }

    private static func tableRow(_ line: String) -> [String]? {
        guard line.hasPrefix("|"), line.hasSuffix("|") else { return nil }
        let cells = line.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        return cells.isEmpty ? nil : cells
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        guard line.hasPrefix("|"), line.hasSuffix("|") else { return false }
        let body = line.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
        return !body.isEmpty && body.allSatisfy { $0 == "-" || $0.isWhitespace }
    }

    /// Applies `**bold**`, `*italic*` and `` `code` `` on top of a base font.
    private static func inline(_ text: String, font: NSFont) -> NSAttributedString {
        let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        guard let parsed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: text, attributes: plain)
        }
        let result = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = font
            if intent.contains(.code) { runFont = .monospacedSystemFont(ofSize: font.pointSize, weight: .regular) }
            if intent.contains(.stronglyEmphasized) { runFont = runFont.bolded() }
            if intent.contains(.emphasized) { runFont = runFont.italicised() }
            result.append(NSAttributedString(string: String(parsed[run.range].characters),
                                             attributes: [.font: runFont, .foregroundColor: NSColor.labelColor]))
        }
        return result
    }
}

private extension NSFont {
    func bolded() -> NSFont { withTraits(.bold) }
    func italicised() -> NSFont { withTraits(.italic) }

    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
