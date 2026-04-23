import Combine
import SwiftUI

@MainActor
final class SidebarSelectionState: ObservableObject {
    static let selectionKey = "sidebarSelectionActive"

    @Published var selection: SidebarSelection {
        didSet {
            UserDefaults.standard.set(selection == .files, forKey: Self.selectionKey)
        }
    }

    init(selection: SidebarSelection = .tabs) {
        self.selection = selection
        UserDefaults.standard.set(selection == .files, forKey: Self.selectionKey)
    }
}
