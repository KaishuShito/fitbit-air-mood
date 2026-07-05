import Foundation

enum PanelActiveRow: Equatable {
    case mood
    case energy
}

enum PanelKeyInput: Equatable {
    case digit(Int)
    case tab
    case up
    case down
    case left
    case right
    case note
    case `return`
    case commandReturn
    case escape
}

enum PanelKeyAction: Equatable {
    case setValue(row: PanelActiveRow, value: Int)
    case changeValue(row: PanelActiveRow, delta: Int)
    case setActiveRow(PanelActiveRow)
    case revealNotes
    case save
    case saveFromNotes
    case leaveNotes
    case dismiss
}

struct PanelKeyRouter {
    static func actions(for input: PanelKeyInput, activeRow: PanelActiveRow, notesFocused: Bool) -> [PanelKeyAction] {
        switch input {
        case .digit(let value):
            guard (1...5).contains(value), !notesFocused else { return [] }
            var actions: [PanelKeyAction] = [.setValue(row: activeRow, value: value)]
            if activeRow == .mood {
                actions.append(.setActiveRow(.energy))
            }
            return actions
        case .tab, .up, .down:
            guard !notesFocused else { return [] }
            return [.setActiveRow(activeRow == .mood ? .energy : .mood)]
        case .left:
            guard !notesFocused else { return [] }
            return [.changeValue(row: activeRow, delta: -1)]
        case .right:
            guard !notesFocused else { return [] }
            return [.changeValue(row: activeRow, delta: 1)]
        case .note:
            guard !notesFocused else { return [] }
            return [.revealNotes]
        case .return:
            guard !notesFocused else { return [] }
            return [.save]
        case .commandReturn:
            return [.saveFromNotes]
        case .escape:
            return notesFocused ? [.leaveNotes] : [.dismiss]
        }
    }
}
