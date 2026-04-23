import Foundation
import Combine

/// A panel that displays a side-by-side diff editor with approve/reject actions.
/// Created by the IDE MCP server when Claude Code sends an openDiff tool call.
@MainActor
final class DiffPanel: Panel, ObservableObject {
    let id = UUID()
    let panelType: PanelType = .diff

    let fileName: String
    let originalContent: String
    @Published var proposedContent: String
    let language: String

    @Published private(set) var displayTitle: String
    var displayIcon: String? { "doc.badge.plus" }

    @Published private(set) var focusFlashToken: Int = 0

    /// Called after approve/reject to remove the panel from the workspace.
    var onDismiss: (() -> Void)?

    private let onResult: (IDEMCPServer.DiffResult) -> Void
    private var settled = false

    init(
        fileName: String,
        originalContent: String,
        proposedContent: String,
        language: String,
        onResult: @escaping (IDEMCPServer.DiffResult) -> Void
    ) {
        self.fileName = fileName
        self.originalContent = originalContent
        self.proposedContent = proposedContent
        self.language = language
        self.displayTitle = fileName
        self.onResult = onResult
    }

    func approve() {
        guard !settled else { return }
        settled = true
        onResult(.accepted(content: proposedContent))
        onDismiss?()
    }

    func reject() {
        guard !settled else { return }
        settled = true
        onResult(.rejected)
        onDismiss?()
    }

    func close() {
        if !settled { reject() }
    }

    func focus() {}
    func unfocus() {}

    func triggerFlash() {
        focusFlashToken += 1
    }
}

// MARK: - Diff computation

enum DiffLineKind {
    case unchanged
    case removed
    case added
    case padding
}

struct DiffLine {
    let text: String
    let kind: DiffLineKind
}

enum DiffComputer {
    static func compute(original: String, proposed: String) -> (left: [DiffLine], right: [DiffLine]) {
        let origLines = original.components(separatedBy: "\n")
        let propLines = proposed.components(separatedBy: "\n")

        let diff = propLines.difference(from: origLines)

        var removedOffsets = Set<Int>()
        var insertedOffsets = Set<Int>()

        for change in diff {
            switch change {
            case .remove(let offset, _, _):
                removedOffsets.insert(offset)
            case .insert(let offset, _, _):
                insertedOffsets.insert(offset)
            }
        }

        // Build aligned side-by-side output
        var left: [DiffLine] = []
        var right: [DiffLine] = []
        var origIdx = 0
        var propIdx = 0

        while origIdx < origLines.count || propIdx < propLines.count {
            let isRemoved = origIdx < origLines.count && removedOffsets.contains(origIdx)
            let isInserted = propIdx < propLines.count && insertedOffsets.contains(propIdx)

            if isRemoved && isInserted {
                left.append(DiffLine(text: origLines[origIdx], kind: .removed))
                right.append(DiffLine(text: propLines[propIdx], kind: .added))
                origIdx += 1
                propIdx += 1
            } else if isRemoved {
                left.append(DiffLine(text: origLines[origIdx], kind: .removed))
                right.append(DiffLine(text: "", kind: .padding))
                origIdx += 1
            } else if isInserted {
                left.append(DiffLine(text: "", kind: .padding))
                right.append(DiffLine(text: propLines[propIdx], kind: .added))
                propIdx += 1
            } else {
                if origIdx < origLines.count && propIdx < propLines.count {
                    left.append(DiffLine(text: origLines[origIdx], kind: .unchanged))
                    right.append(DiffLine(text: propLines[propIdx], kind: .unchanged))
                    origIdx += 1
                    propIdx += 1
                } else if origIdx < origLines.count {
                    left.append(DiffLine(text: origLines[origIdx], kind: .unchanged))
                    right.append(DiffLine(text: "", kind: .padding))
                    origIdx += 1
                } else {
                    left.append(DiffLine(text: "", kind: .padding))
                    right.append(DiffLine(text: propLines[propIdx], kind: .unchanged))
                    propIdx += 1
                }
            }
        }

        return (left, right)
    }
}
