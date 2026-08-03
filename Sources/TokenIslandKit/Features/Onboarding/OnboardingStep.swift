import SwiftUI

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case jump
    case allSet
    case tour
    case boardingPass

    var id: Int { rawValue }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var buttonTitle: String {
        switch self {
        case .welcome: "Get Started"
        case .jump, .allSet, .tour: "Next"
        case .boardingPass: "Start Vibing"
        }
    }
}
