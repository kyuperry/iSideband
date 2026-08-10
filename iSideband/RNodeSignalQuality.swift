import SwiftUI

enum RNodeSignalQuality {
    static func level(for rssi: Int) -> Int {
        switch rssi {
        case -60...0: 4
        case -70..<(-60): 3
        case -80..<(-70): 2
        default: 1
        }
    }

    static func label(for rssi: Int) -> String {
        switch level(for: rssi) {
        case 4: "Excellent"
        case 3: "Good"
        case 2: "Fair"
        default: "Weak"
        }
    }

    static func color(for rssi: Int) -> Color {
        switch level(for: rssi) {
        case 3...4: .green
        case 2: .yellow
        default: .red
        }
    }
}
