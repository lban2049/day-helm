import SwiftUI

enum DayHelmColors {
    static let primaryBlue = Color(hex: "#3B82F6")
    static let successEmerald = Color(hex: "#10B981")
    static let warningAmber = Color(hex: "#F59E0B")
    static let destructiveRed = Color(hex: "#EF4444")
    static let violetAccent = Color(hex: "#8B5CF6")

    static let taskPalette: [(hex: String, name: String)] = [
        ("#3B82F6", "推进蓝"),
        ("#10B981", "达标绿"),
        ("#F59E0B", "琥珀橙"),
        ("#8B5CF6", "紫罗兰"),
        ("#EC4899", "玫瑰红"),
        ("#06B6D4", "仪表青")
    ]
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (59, 130, 246)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1.0
        )
    }
}
