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
        case .mossGardenRain:
            ReminderThemeStyle(
                backdrop: Color(red: 12.0 / 255.0, green: 32.0 / 255.0, blue: 26.0 / 255.0),
                surface: Color(red: 26.0 / 255.0, green: 53.0 / 255.0, blue: 40.0 / 255.0),
                accent: Color(red: 128.0 / 255.0, green: 154.0 / 255.0, blue: 105.0 / 255.0),
                accentHighlight: Color(red: 177.0 / 255.0, green: 199.0 / 255.0, blue: 150.0 / 255.0),
                panelTop: Color(red: 17.0 / 255.0, green: 42.0 / 255.0, blue: 34.0 / 255.0),
                panelBottom: Color(red: 7.0 / 255.0, green: 21.0 / 255.0, blue: 16.0 / 255.0),
                panelMist: Color(red: 131.0 / 255.0, green: 155.0 / 255.0, blue: 121.0 / 255.0)
            )
        case .polarNightGlow:
            ReminderThemeStyle(
                backdrop: Color(red: 9.0 / 255.0, green: 19.0 / 255.0, blue: 39.0 / 255.0),
                surface: Color(red: 20.0 / 255.0, green: 36.0 / 255.0, blue: 64.0 / 255.0),
                accent: Color(red: 112.0 / 255.0, green: 143.0 / 255.0, blue: 196.0 / 255.0),
                accentHighlight: Color(red: 160.0 / 255.0, green: 184.0 / 255.0, blue: 223.0 / 255.0),
                panelTop: Color(red: 12.0 / 255.0, green: 25.0 / 255.0, blue: 50.0 / 255.0),
                panelBottom: Color(red: 4.0 / 255.0, green: 9.0 / 255.0, blue: 20.0 / 255.0),
                panelMist: Color(red: 123.0 / 255.0, green: 148.0 / 255.0, blue: 194.0 / 255.0)
            )
        case .moonlitBamboo:
            ReminderThemeStyle(
                backdrop: Color(red: 7.0 / 255.0, green: 31.0 / 255.0, blue: 32.0 / 255.0),
                surface: Color(red: 18.0 / 255.0, green: 53.0 / 255.0, blue: 52.0 / 255.0),
                accent: Color(red: 104.0 / 255.0, green: 164.0 / 255.0, blue: 149.0 / 255.0),
                accentHighlight: Color(red: 151.0 / 255.0, green: 200.0 / 255.0, blue: 187.0 / 255.0),
                panelTop: Color(red: 11.0 / 255.0, green: 41.0 / 255.0, blue: 40.0 / 255.0),
                panelBottom: Color(red: 4.0 / 255.0, green: 21.0 / 255.0, blue: 21.0 / 255.0),
                panelMist: Color(red: 118.0 / 255.0, green: 167.0 / 255.0, blue: 156.0 / 255.0)
            )
        case .rainwashedSeaCliff:
            ReminderThemeStyle(
                backdrop: Color(red: 10.0 / 255.0, green: 28.0 / 255.0, blue: 40.0 / 255.0),
                surface: Color(red: 23.0 / 255.0, green: 54.0 / 255.0, blue: 67.0 / 255.0),
                accent: Color(red: 101.0 / 255.0, green: 157.0 / 255.0, blue: 168.0 / 255.0),
                accentHighlight: Color(red: 151.0 / 255.0, green: 194.0 / 255.0, blue: 203.0 / 255.0),
                panelTop: Color(red: 13.0 / 255.0, green: 39.0 / 255.0, blue: 52.0 / 255.0),
                panelBottom: Color(red: 5.0 / 255.0, green: 18.0 / 255.0, blue: 25.0 / 255.0),
                panelMist: Color(red: 115.0 / 255.0, green: 156.0 / 255.0, blue: 168.0 / 255.0)
            )
        case .cloudfieldWind:
            ReminderThemeStyle(
                backdrop: Color(red: 17.0 / 255.0, green: 28.0 / 255.0, blue: 37.0 / 255.0),
                surface: Color(red: 38.0 / 255.0, green: 54.0 / 255.0, blue: 65.0 / 255.0),
                accent: Color(red: 130.0 / 255.0, green: 158.0 / 255.0, blue: 170.0 / 255.0),
                accentHighlight: Color(red: 177.0 / 255.0, green: 199.0 / 255.0, blue: 208.0 / 255.0),
                panelTop: Color(red: 24.0 / 255.0, green: 41.0 / 255.0, blue: 52.0 / 255.0),
                panelBottom: Color(red: 8.0 / 255.0, green: 19.0 / 255.0, blue: 26.0 / 255.0),
                panelMist: Color(red: 142.0 / 255.0, green: 167.0 / 255.0, blue: 175.0 / 255.0)
            )
        }
    }
}
