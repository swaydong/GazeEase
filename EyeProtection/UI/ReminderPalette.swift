import SwiftUI

struct ReminderThemeStyle {
    let backdrop: Color
    let surface: Color
    let accent: Color
    let accentHighlight: Color
    let panelTop: Color
    let panelBottom: Color
    let panelMist: Color
}

extension ReminderTheme {
    var style: ReminderThemeStyle {
        switch self {
        case .quietHorizon:
            ReminderThemeStyle(
                backdrop: Color(red: 0.015, green: 0.080, blue: 0.090),
                surface: Color(red: 0.025, green: 0.120, blue: 0.130),
                accent: Color(red: 0.384, green: 0.722, blue: 0.647),
                accentHighlight: Color(red: 0.480, green: 0.790, blue: 0.720),
                panelTop: Color(red: 0.010, green: 0.085, blue: 0.090),
                panelBottom: Color(red: 0.004, green: 0.050, blue: 0.055),
                panelMist: Color(red: 0.42, green: 0.69, blue: 0.67)
            )
        case .forestLight:
            ReminderThemeStyle(
                backdrop: Color(red: 0.018, green: 0.060, blue: 0.058),
                surface: Color(red: 0.030, green: 0.105, blue: 0.090),
                accent: Color(red: 0.450, green: 0.690, blue: 0.555),
                accentHighlight: Color(red: 0.570, green: 0.780, blue: 0.650),
                panelTop: Color(red: 0.018, green: 0.075, blue: 0.068),
                panelBottom: Color(red: 0.008, green: 0.038, blue: 0.036),
                panelMist: Color(red: 0.48, green: 0.64, blue: 0.55)
            )
        case .alpineMist:
            ReminderThemeStyle(
                backdrop: Color(red: 0.035, green: 0.060, blue: 0.100),
                surface: Color(red: 0.075, green: 0.110, blue: 0.165),
                accent: Color(red: 0.590, green: 0.730, blue: 0.820),
                accentHighlight: Color(red: 0.700, green: 0.820, blue: 0.885),
                panelTop: Color(red: 0.045, green: 0.075, blue: 0.120),
                panelBottom: Color(red: 0.020, green: 0.040, blue: 0.070),
                panelMist: Color(red: 0.64, green: 0.72, blue: 0.80)
            )
        case .twilightDunes:
            ReminderThemeStyle(
                backdrop: Color(red: 0.045, green: 0.050, blue: 0.105),
                surface: Color(red: 0.105, green: 0.080, blue: 0.120),
                accent: Color(red: 0.800, green: 0.655, blue: 0.455),
                accentHighlight: Color(red: 0.890, green: 0.755, blue: 0.565),
                panelTop: Color(red: 0.050, green: 0.055, blue: 0.115),
                panelBottom: Color(red: 0.030, green: 0.025, blue: 0.060),
                panelMist: Color(red: 0.78, green: 0.55, blue: 0.36)
            )
        }
    }
}
