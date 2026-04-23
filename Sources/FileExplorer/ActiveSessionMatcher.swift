import Foundation

/// Maps workspaces to folder paths by matching currentDirectory.
struct ActiveSessionMatcher {

    /// Returns workspace info for workspaces whose currentDirectory matches the given folder path.
    static func sessions(for folderPath: String, from workspaces: [WorkspaceDirectoryInfo]) -> [WorkspaceDirectoryInfo] {
        let normalizedFolder = (folderPath as NSString).standardizingPath
        return workspaces.filter { ws in
            let normalizedDir = (ws.directory as NSString).standardizingPath
            return normalizedDir == normalizedFolder
        }
    }

    /// Extracts lightweight directory info from tab manager workspaces.
    /// Called from the sidebar view to avoid passing full Workspace objects into the model.
    @MainActor
    static func workspaceDirectoryInfos(from tabs: [any WorkspaceDirectoryProviding], selectedTabId: UUID? = nil) -> [WorkspaceDirectoryInfo] {
        tabs.map { workspace in
            let latestBody = AppDelegate.shared?.notificationStore?
                .latestNotification(forTabId: workspace.workspaceId)?.body
            return WorkspaceDirectoryInfo(
                id: workspace.workspaceId,
                title: workspace.workspaceTitle,
                directory: workspace.workspaceCurrentDirectory,
                hasUnread: workspace.workspaceHasUnread,
                isSelected: workspace.workspaceId == selectedTabId,
                shellState: workspace.workspaceShellState,
                latestNotificationBody: latestBody,
                changedFileCount: nil
            )
        }
    }
}

/// Protocol to decouple from Workspace type — Workspace will conform to this.
@MainActor
protocol WorkspaceDirectoryProviding {
    var workspaceId: UUID { get }
    var workspaceTitle: String { get }
    var workspaceCurrentDirectory: String { get }
    var workspaceHasUnread: Bool { get }
    var workspaceShellState: String { get }  // "idle", "running", or "unknown"
}
