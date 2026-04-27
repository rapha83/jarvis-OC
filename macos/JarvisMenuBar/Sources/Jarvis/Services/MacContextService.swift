import AppKit
import CoreGraphics
import Darwin
import Foundation

enum MacContextService {
    static func currentSummary() -> String {
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName ?? "desconhecido"
        let bundleID = app?.bundleIdentifier ?? "sem bundle id"
        let windowTitle = activeWindowTitle(processID: app?.processIdentifier)
        let screenDescription = NSScreen.main.map { screen in
            "\(Int(screen.frame.width))x\(Int(screen.frame.height))"
        } ?? "tela desconhecida"
        let hostName = Host.current().localizedName ?? "Mac"
        let ipAddress = primaryIPv4Address()

        var parts = [
            "Dispositivo: \(hostName)",
            "App ativo: \(appName)",
            "Bundle: \(bundleID)",
            "Tela principal: \(screenDescription)",
        ]

        if let windowTitle, !windowTitle.isEmpty {
            parts.insert("Janela ativa: \(windowTitle)", at: 2)
        }

        if let ipAddress {
            parts.append("IP local: \(ipAddress)")
        }

        return parts.joined(separator: ". ")
    }

    static func currentSummaryBase64() -> String {
        Data(currentSummary().utf8).base64EncodedString()
    }

    private static func activeWindowTitle(processID: pid_t?) -> String? {
        guard let processID else {
            return nil
        }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard
                let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == processID,
                let layer = window[kCGWindowLayer as String] as? Int,
                layer == 0,
                let title = window[kCGWindowName as String] as? String,
                !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                continue
            }
            return title
        }

        return nil
    }

    private static func primaryIPv4Address() -> String? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let firstInterface = interfaces else {
            return nil
        }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: firstInterface, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = interface.ifa_flags
            guard
                (flags & UInt32(IFF_UP)) != 0,
                (flags & UInt32(IFF_LOOPBACK)) == 0,
                let address = interface.ifa_addr,
                Int32(address.pointee.sa_family) == AF_INET
            else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                return String(cString: host)
            }
        }
        return nil
    }
}
