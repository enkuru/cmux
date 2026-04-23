import SwiftUI

struct MissionControlView: View {
    let workspaceInfos: [WorkspaceDirectoryInfo]
    let selectedTabId: UUID?
    let onSelectWorkspace: (UUID) -> Void

    /// Space at top for traffic light buttons (matches other sidebar views)
    private let trafficLightPadding: CGFloat = 28

    private var needsAttentionCount: Int {
        workspaceInfos.filter { $0.agentStatus == .needsAttention }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
                .frame(height: trafficLightPadding)

            // Agent cards grid
            if workspaceInfos.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "rectangle.stack.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(String(localized: "mission.control.empty", defaultValue: "No agents running"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 180, maximum: 280), spacing: 8)
                    ], spacing: 8) {
                        ForEach(workspaceInfos, id: \.id) { info in
                            AgentCardView(
                                workspace: info,
                                isSelected: info.id == selectedTabId,
                                onSelect: { onSelectWorkspace(info.id) },
                                onApprove: nil,  // TODO: Wire up to diff approval if active
                                onReject: nil
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
