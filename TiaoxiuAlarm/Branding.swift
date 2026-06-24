import SwiftUI

struct AppBranding {
    static let accent = Color(red: 255/255, green: 110/255, blue: 64/255) // 高雅珊瑚橙
    
    static func gradient(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 12/255, green: 14/255, blue: 26/255),    // 深邃暗夜蓝
                    Color(red: 18/255, green: 19/255, blue: 26/255),    //  obsidian
                    Color(red: 10/255, green: 10/255, blue: 14/255)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 236/255, green: 243/255, blue: 250/255), // 冰川蓝
                    Color(red: 245/255, green: 246/255, blue: 249/255), // 极客灰白
                    Color.white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
    
    static func cardGradient(for colorScheme: ColorScheme) -> LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 255/255, green: 110/255, blue: 64/255).opacity(0.20),
                    Color(red: 255/255, green: 45/255, blue: 85/255).opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 255/255, green: 110/255, blue: 64/255).opacity(0.12),
                    Color(red: 255/255, green: 180/255, blue: 185/255).opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}
