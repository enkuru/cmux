import SwiftUI
import AppKit
import Highlightr

struct DiffPanelView: View {
    @ObservedObject var panel: DiffPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let portalPriority: Int
    let onRequestPanelFocus: () -> Void

    @State private var diffResult: (left: [DiffLine], right: [DiffLine]) = ([], [])

    var body: some View {
        VStack(spacing: 0) {
            diffToolbar
            Divider()
            HSplitView {
                DiffTextNSView(
                    lines: diffResult.left,
                    isEditable: false,
                    language: panel.language,
                    label: String(localized: "diff.original.label", defaultValue: "Original")
                )
                .frame(minWidth: 200)

                DiffTextNSView(
                    lines: diffResult.right,
                    isEditable: true,
                    language: panel.language,
                    onTextChange: { newText in
                        panel.proposedContent = newText
                    },
                    label: String(localized: "diff.proposed.label", defaultValue: "Proposed")
                )
                .frame(minWidth: 200)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            diffResult = DiffComputer.compute(original: panel.originalContent, proposed: panel.proposedContent)
        }
    }

    private var diffToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)

            Text(panel.fileName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .lineLimit(1)

            Spacer()

            diffStats

            Button(action: { panel.reject() }) {
                HStack(spacing: 4) {
                    Text(String(localized: "diff.reject", defaultValue: "Reject"))
                    Text("esc")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(3)
                }
            }
            .buttonStyle(DiffButtonStyle(color: .red))
            .keyboardShortcut(.escape, modifiers: [])

            Button(action: { panel.approve() }) {
                HStack(spacing: 4) {
                    Text(String(localized: "diff.approve", defaultValue: "Approve"))
                    Text("\u{2318}S")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(3)
                }
            }
            .buttonStyle(DiffButtonStyle(color: .green))
            .keyboardShortcut("s", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
    }

    private var diffStats: some View {
        let added = diffResult.right.filter { $0.kind == .added }.count
        let removed = diffResult.left.filter { $0.kind == .removed }.count
        return HStack(spacing: 8) {
            if added > 0 {
                Text("+\(added)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.green)
            }
            if removed > 0 {
                Text("-\(removed)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.red)
            }
        }
    }
}

// MARK: - Button style

private struct DiffButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1.0))
            .cornerRadius(5)
    }
}

// MARK: - Native NSTextView wrapper

private struct DiffTextNSView: NSViewRepresentable {
    let lines: [DiffLine]
    let isEditable: Bool
    let language: String
    var onTextChange: ((String) -> Void)?
    var label: String = ""

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        // Header label
        let header = NSTextField(labelWithString: label)
        header.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        header.textColor = .secondaryLabelColor
        header.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(header)

        // Scroll view + text view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.13, alpha: 1.0)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        if let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            _ = layoutManager // keep reference
        }

        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.documentView = textView

        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        // Only update if not currently being edited
        if !context.coordinator.isEditing {
            applyDiffContent(to: textView)
        }
    }

    private func applyDiffContent(to textView: NSTextView) {
        let fullText = lines.map(\.text).joined(separator: "\n")
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // Try syntax highlighting first
        let highlightr = Highlightr()
        highlightr?.setTheme(to: "atom-one-dark")
        let attributed: NSMutableAttributedString
        if let highlighted = highlightr?.highlight(fullText, as: language) {
            attributed = NSMutableAttributedString(attributedString: highlighted)
        } else {
            attributed = NSMutableAttributedString(string: fullText, attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ])
        }

        // Ensure consistent font
        attributed.addAttribute(.font, value: font, range: NSRange(location: 0, length: attributed.length))

        // Overlay diff backgrounds per line
        var charIndex = 0
        for (index, line) in lines.enumerated() {
            let lineLength = line.text.utf16.count + (index < lines.count - 1 ? 1 : 0) // +1 for \n
            let range = NSRange(location: charIndex, length: min(lineLength, attributed.length - charIndex))
            guard range.location + range.length <= attributed.length else { break }

            switch line.kind {
            case .removed:
                attributed.addAttribute(.backgroundColor, value: NSColor(red: 0.5, green: 0.1, blue: 0.1, alpha: 0.3), range: range)
            case .added:
                attributed.addAttribute(.backgroundColor, value: NSColor(red: 0.1, green: 0.4, blue: 0.1, alpha: 0.3), range: range)
            case .padding:
                attributed.addAttribute(.backgroundColor, value: NSColor(white: 0.15, alpha: 1.0), range: range)
                attributed.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: range)
            case .unchanged:
                break
            }

            charIndex += lineLength
        }

        textView.textStorage?.setAttributedString(attributed)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var onTextChange: ((String) -> Void)?
        var isEditing = false

        init(onTextChange: ((String) -> Void)?) {
            self.onTextChange = onTextChange
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = textView else { return }
            onTextChange?(textView.string)
        }
    }
}
