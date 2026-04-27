import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let isDefault: Bool

    var title: String {
        isDefault ? "\(name) (padrao)" : name
    }
}
