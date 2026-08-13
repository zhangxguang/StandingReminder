import SwiftUI

enum WorkState: String, CaseIterable, Codable, Identifiable, Sendable {
    case sitting
    case standing
    case resting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sitting: "坐姿办公"
        case .standing: "站立办公"
        case .resting: "休息"
        }
    }

    var shortTitle: String {
        switch self {
        case .sitting: "坐姿"
        case .standing: "站立"
        case .resting: "休息"
        }
    }

    var symbolName: String {
        switch self {
        case .sitting: "chair.lounge.fill"
        case .standing: "figure.stand"
        case .resting: "cup.and.saucer.fill"
        }
    }

    var color: Color {
        switch self {
        case .sitting: .blue
        case .standing: .green
        case .resting: .orange
        }
    }
}
