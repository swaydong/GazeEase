import SwiftUI

@main
@MainActor
struct EyeProtectionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarStatusLabel(
                fatigueDisplay: model.menuBarText,
                isMonitoringComplete: model.isMonitoringComplete,
                language: model.resolvedLanguage
            )
        }
        .menuBarExtraStyle(.window)

        Window(
            AppLocalization.string(.appAnalyticsWindowTitle, language: model.resolvedLanguage),
            id: "analytics"
        ) {
            DashboardView(model: model)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 900, height: 680)

        Settings {
            SettingsView(model: model)
                .frame(width: 560, height: 650)
        }
    }
}

struct MenuBarStatusLabel: View {
    let fatigueDisplay: String
    let isMonitoringComplete: Bool
    var language: AppLanguage = .zhHans

    var body: some View {
        HStack(spacing: 1) {
            Image("MenuBarTaiji")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)

            Text(fatigueDisplay)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, -4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.string(
            .menuBarStatusAccessibilityLabel,
            language: language
        ))
        .accessibilityValue(
            isMonitoringComplete
                ? AppLocalization.format(
                    .menuBarStatusAccessibilityValue,
                    language: language,
                    arguments: [fatigueDisplay]
                )
                : AppLocalization.format(
                    .menuBarStatusAccessibilityValueMonitoringIncomplete,
                    language: language,
                    arguments: [fatigueDisplay]
                )
        )
    }
}
