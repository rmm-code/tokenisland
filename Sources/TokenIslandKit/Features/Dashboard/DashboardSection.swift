import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case providers
    case recent
    case trends
    case projects

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .providers: "Provider Breakdown"
        case .recent: "Recent Requests"
        case .trends: "Trends"
        case .projects: "Projects"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .providers: "rectangle.3.group"
        case .recent: "clock.arrow.circlepath"
        case .trends: "chart.bar.xaxis"
        case .projects: "folder"
        }
    }
}
