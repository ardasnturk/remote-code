import SwiftUI
import UIKit

/// Promo Studio's colors, as on the Mac (PromoStudio/Views/Design/Design.swift): the indigo → violet → pink
/// end of the family gradient, on the same glass look as the Vitrin tab (`VitrinDesign.swift`).
enum PromoStudioBrand {
    static let indigo = Color(red: 0.30, green: 0.36, blue: 0.93)
    static let violet = Color(red: 0.62, green: 0.32, blue: 0.92)
    static let pink = Color(red: 0.93, green: 0.36, blue: 0.62)

    /// The Mac app's accent color, lighter in dark mode so it stays readable.
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.70, green: 0.48, blue: 0.98, alpha: 1)
            : UIColor(red: 0.49, green: 0.24, blue: 0.80, alpha: 1)
    })

    /// Icon badges
    static let gradient = LinearGradient(colors: [indigo, violet, pink], startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Primary action buttons
    static let buttonGradient = LinearGradient(colors: [violet, pink], startPoint: .leading, endPoint: .trailing)
}

extension View {
    /// A Promo Studio screen: its color blobs behind the content and its accent on the controls.
    func promoStudioScreen() -> some View {
        // Stronger than Vitrin's: these cool colors read much fainter than its warm ones on the same background
        brandWindowBackground(intensity: 0.8, blobs: [PromoStudioBrand.indigo, PromoStudioBrand.violet, PromoStudioBrand.pink])
            .tint(PromoStudioBrand.accent)
    }
}

extension ButtonStyle where Self == VitrinGradientButtonStyle {
    /// Promo Studio's primary action: the gradient button at the width of its label.
    static var promoStudioPrimary: VitrinGradientButtonStyle {
        VitrinGradientButtonStyle(fullWidth: false, gradient: PromoStudioBrand.buttonGradient)
    }
}
