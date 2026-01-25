import CoreGraphics
import ScreenCaptureKit

enum WindowOrdering {
    static func sortByZOrder(_ windows: [SCWindow]) -> [SCWindow] {
        guard !windows.isEmpty else {
            return windows
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return windows
        }

        var orderIndexByWindowID: [CGWindowID: Int] = [:]
        orderIndexByWindowID.reserveCapacity(infoList.count)

        for (index, info) in infoList.enumerated() {
            if let number = info[kCGWindowNumber as String] as? NSNumber {
                orderIndexByWindowID[CGWindowID(number.uint32Value)] = index
            }
        }

        return windows.enumerated().sorted { lhs, rhs in
            let lhsOrder = orderIndexByWindowID[lhs.element.windowID] ?? Int.max
            let rhsOrder = orderIndexByWindowID[rhs.element.windowID] ?? Int.max
            if lhsOrder != rhsOrder {
                return lhsOrder < rhsOrder
            }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }
}
