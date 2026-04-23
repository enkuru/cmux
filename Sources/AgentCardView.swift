import SwiftUI

struct AgentCardView: View {
    let workspace: WorkspaceDirectoryInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onApprove: (() -> Void)?
    let onReject: (() -> Void)?

    private var statusColor: Color {
        switch workspace.agentStatus {
        case .running: return .green
        case .needsAttention: return .red
        case .idle: return .yellow
        case .completed: return .blue
        case .errored: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: status dot + name + project
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .opacity(workspace.agentStatus == .needsAttention ? 1 : 0.8)

                Text(workspace.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)

                Spacer()

                Text((workspace.directory as NSString).lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            // Task summary (from latest notification)
            if let body = workspace.latestNotificationBody {
                Text(body)
                    .font(.system(size: 10))
                    .foregroundColor(workspace.agentStatus == .needsAttention ? .red : .secondary)
                    .lineLimit(2)
            }

            // Progress or action buttons
            if workspace.agentStatus == .needsAttention {
                HStack(spacing: 6) {
                    if let onApprove = onApprove {
                        Button(String(localized: "mission.control.approve", defaultValue: "Approve"), action: onApprove)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.mini)
                            .tint(.green)
                    }
                    if let onReject = onReject {
                        Button(String(localized: "mission.control.reject", defaultValue: "Reject"), action: onReject)
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }
            } else if workspace.agentStatus == .running {
                // Progress indicator
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }

            // Changed files count
            if let count = workspace.changedFileCount, count > 0 {
                Text("\(count) files changed")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(statusColor.opacity(0.5), lineWidth: 2)
                .opacity(workspace.agentStatus == .needsAttention ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
