import Foundation

// Line-level markdown classification for the Tasks editor. The editor keeps
// the raw markdown characters visible and only decorates them, so every kind
// carries ranges expressed in UTF-16 units relative to the line start.
enum TaskLineKind: Equatable {
    case heading(level: Int)
    case checkbox(checked: Bool, markerLength: Int)
    case bullet(markerLength: Int)
    case separator
    case body
}

enum TaskLineClassifier {
    static func classify(_ line: String) -> TaskLineKind {
        let ns = line as NSString
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed == "---" || trimmed == "***" {
            return .separator
        }

        if trimmed.hasPrefix("#") {
            let level = trimmed.prefix(while: { $0 == "#" }).count
            if level <= 6, trimmed.dropFirst(level).first == " " {
                return .heading(level: level)
            }
        }

        if let match = Self.checkboxRegex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: ns.length)
        ) {
            let stateRange = match.range(at: 1)
            let state = ns.substring(with: stateRange).lowercased()
            return .checkbox(checked: state == "x", markerLength: match.range.length)
        }

        if let match = Self.bulletRegex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: ns.length)
        ) {
            return .bullet(markerLength: match.range.length)
        }

        return .body
    }

    private static let checkboxRegex = try! NSRegularExpression(pattern: "^\\s*[-*] \\[( |x|X)\\] ")
    private static let bulletRegex = try! NSRegularExpression(pattern: "^\\s*[-*] ")
}

// ⌘L behaviour, matching Obsidian's "toggle checkbox status" plus a promotion
// step so any line can become a task: `- [ ]` ↔ `- [x]`, `- text` → `- [ ] text`,
// plain text → `- [ ] text`. Headings and separators are left untouched.
enum TaskCheckboxToggler {
    struct Result: Equatable {
        let text: String
        let selectionLocation: Int
    }

    // A single-line replacement, so NSTextView callers can route it through
    // shouldChangeText/didChangeText and keep undo working per toggle.
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
        let selectionLocation: Int
    }

    static func edit(text: String, selectionLocation: Int) -> Edit? {
        let ns = text as NSString
        guard selectionLocation >= 0, selectionLocation <= ns.length else { return nil }

        let lineRange = ns.lineRange(for: NSRange(location: selectionLocation, length: 0))
        var line = ns.substring(with: lineRange)
        var lineContentRange = lineRange
        if line.hasSuffix("\n") {
            lineContentRange.length -= 1
            line = String(line.dropLast())
        }

        guard let newLine = toggledLine(line) else { return nil }

        let delta = (newLine as NSString).length - lineContentRange.length
        let lineEnd = lineContentRange.location + (newLine as NSString).length
        let newSelection = min(max(selectionLocation + delta, lineContentRange.location), lineEnd)
        return Edit(range: lineContentRange, replacement: newLine, selectionLocation: newSelection)
    }

    static func toggle(text: String, selectionLocation: Int) -> Result? {
        guard let edit = edit(text: text, selectionLocation: selectionLocation) else { return nil }
        let newText = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return Result(text: newText, selectionLocation: edit.selectionLocation)
    }

    static func toggledLine(_ line: String) -> String? {
        switch TaskLineClassifier.classify(line) {
        case .heading, .separator:
            return nil
        case .checkbox(let checked, _):
            let ns = line as NSString
            let bracketRange = ns.range(of: checked ? "[x] " : "[ ] ", options: [.caseInsensitive])
            guard bracketRange.location != NSNotFound else { return nil }
            return ns.replacingCharacters(in: bracketRange, with: checked ? "[ ] " : "[x] ")
        case .bullet(let markerLength):
            let ns = line as NSString
            let marker = ns.substring(to: markerLength)
            let rest = ns.substring(from: markerLength)
            return marker + "[ ] " + rest
        case .body:
            let indent = line.prefix(while: { $0 == " " || $0 == "\t" })
            let rest = line.dropFirst(indent.count)
            return indent + "- [ ] " + rest
        }
    }
}
