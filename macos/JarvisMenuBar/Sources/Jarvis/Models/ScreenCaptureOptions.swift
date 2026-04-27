import Foundation

struct ScreenCaptureOptions: Hashable {
    let displayIndex: Int
    let maxWidth: Int
    let showsCursor: Bool
}

struct ScreenDisplayOption: Identifiable, Hashable {
    let id: Int
    let title: String
    let size: String
}
