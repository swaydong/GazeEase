import AppKit
import SwiftUI

enum EyePalette {
    static let calm = Color(red: 0.20, green: 0.66, blue: 0.58)
    static let watch = Color(red: 0.96, green: 0.60, blue: 0.20)
    static let overdue = Color(red: 0.91, green: 0.25, blue: 0.21)

    static func fatigueColor(_ fatigue: Double) -> Color {
        switch fatigue {
        case ..<70: calm
        case ..<100: watch
        default: overdue
        }
    }
}

enum EyeDurationFormatter {
    static func compact(
        _ duration: TimeInterval,
        language: AppLanguage = .zhHans
    ) -> String {
        AppLocalization.duration(duration, language: language)
    }
}

struct MenuContentPresentation: Equatable {
    let fatigue: Double
    let fatigueDisplay: String
    let restRequired: Bool
    let isResting: Bool
    let overloadDuration: TimeInterval
    let presenceDescription: String
    let isMonitoringComplete: Bool
    let restSecondsRemaining: TimeInterval
    let theme: ReminderTheme
    var language: AppLanguage = .zhHans

    var fatigueProgress: Double {
        min(max(fatigue / 100, 0), 1)
    }

    var headerAccessibilityLabel: String {
        if restRequired {
            return AppLocalization.format(
                .menuHeaderAccessibilityRestRequired,
                language: language,
                arguments: [
                    fatigueDisplay,
                    EyeDurationFormatter.compact(overloadDuration, language: language)
                ]
            )
        }
        return AppLocalization.format(
            .menuHeaderAccessibilityCurrentFatigue,
            language: language,
            arguments: [fatigueDisplay]
        )
    }
}

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        MenuContentScene(
            presentation: MenuContentPresentation(
                fatigue: model.fatigue,
                fatigueDisplay: model.fatigueDisplay,
                restRequired: model.restRequired,
                isResting: model.isResting,
                overloadDuration: model.overloadDuration,
                presenceDescription: model.presenceDescription,
                isMonitoringComplete: model.isMonitoringComplete,
                restSecondsRemaining: model.restSecondsRemaining,
                theme: model.reminderTheme,
                language: model.resolvedLanguage
            ),
            onBeginRest: model.beginRest,
            onOpenAnalytics: {
                model.refreshAnalytics()
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "analytics")
            },
            onOpenSettings: {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            },
            onQuit: model.quit
        )
    }
}

struct MenuContentScene: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let presentation: MenuContentPresentation
    let onBeginRest: () -> Void
    let onOpenAnalytics: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    var reduceTransparencyOverride: Bool? = nil

    var body: some View {
        VStack(spacing: 0) {
            fatigueHeader

            themedDivider

            VStack(spacing: 10) {
                statusRow

                Button(action: onBeginRest) {
                    Label(
                        localized(
                            presentation.restRequired
                                ? .menuActionBeginRest
                                : .menuActionRestNow
                        ),
                        systemImage: "leaf.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(MenuRestButtonStyle(
                    style: presentation.theme.style,
                    isPrimary: presentation.restRequired,
                    reduceTransparency: effectiveReduceTransparency
                ))
                .accessibilityHint(
                    presentation.restRequired
                        ? localized(.menuActionBeginRestHintRequired)
                        : localized(.menuActionBeginRestHintOptional)
                )
            }
            .padding(16)

            themedDivider

            VStack(spacing: 2) {
                MenuActionButton(
                    title: localized(.menuActionAnalytics),
                    systemImage: "chart.xyaxis.line",
                    style: presentation.theme.style,
                    action: onOpenAnalytics
                )

                MenuActionButton(
                    title: localized(.menuActionSettings),
                    systemImage: "gearshape",
                    style: presentation.theme.style,
                    action: onOpenSettings
                )

                MenuActionButton(
                    title: localized(.menuActionQuit),
                    systemImage: "power",
                    style: presentation.theme.style,
                    action: onQuit
                )
                .keyboardShortcut("q")
            }
            .padding(6)
        }
        .frame(width: 320)
        .frame(minHeight: 300, alignment: .top)
        .background {
            MenuContentBackground(
                theme: presentation.theme,
                reduceTransparency: effectiveReduceTransparency
            )
        }
        .foregroundStyle(.white.opacity(0.90))
    }

    private var fatigueHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(effectiveReduceTransparency ? 0.16 : 0.10), lineWidth: 7)

                Circle()
                    .trim(from: 0, to: presentation.fatigueProgress)
                    .stroke(
                        LinearGradient(
                            colors: [
                                presentation.theme.style.accentHighlight,
                                presentation.theme.style.accent
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image("MenuBarTaiji")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(presentation.theme.style.accentHighlight)
                    .frame(width: 20, height: 20)
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(localized(
                    presentation.restRequired
                        ? .menuHeaderRestRequired
                        : .menuHeaderCurrentFatigue
                ))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(effectiveReduceTransparency ? 0.78 : 0.64))
                    .lineLimit(1)

                Text(presentation.fatigueDisplay)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(presentation.theme.style.accentHighlight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)

                if presentation.restRequired {
                    Text(AppLocalization.format(
                        .menuOverloadSince,
                        language: presentation.language,
                        arguments: [EyeDurationFormatter.compact(
                            presentation.overloadDuration,
                            language: presentation.language
                        )]
                    ))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(presentation.theme.style.accent.opacity(0.92))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.headerAccessibilityLabel)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(
                    presentation.isMonitoringComplete
                        ? presentation.theme.style.accent
                        : EyePalette.watch
                )
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(
                presentation.isResting
                    ? localized(.menuResting)
                    : presentation.presenceDescription
            )
            .lineLimit(1)

            Spacer(minLength: 8)

            if presentation.isResting {
                Text(AppLocalization.format(
                    .menuRestRemaining,
                    language: presentation.language,
                    arguments: [Int(ceil(presentation.restSecondsRemaining))]
                ))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            } else if !presentation.isMonitoringComplete {
                Text(localized(.menuMonitoringIncomplete))
                    .foregroundStyle(EyePalette.watch)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.white.opacity(effectiveReduceTransparency ? 0.86 : 0.72))
    }

    private var themedDivider: some View {
        Rectangle()
            .fill(
                presentation.theme.style.accent.opacity(
                    effectiveReduceTransparency ? 0.26 : 0.14
                )
            )
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var effectiveReduceTransparency: Bool {
        reduceTransparencyOverride ?? reduceTransparency
    }

    private func localized(_ key: L10nKey) -> String {
        AppLocalization.string(key, language: presentation.language)
    }
}

private struct MenuContentBackground: View {
    let theme: ReminderTheme
    let reduceTransparency: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                LinearGradient(
                    colors: [theme.style.panelTop, theme.style.panelBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if !reduceTransparency {
                    let treatment = theme.menuBackdropTreatment
                    let imageHeight = min(206, proxy.size.height)

                    Image(theme.previewAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: proxy.size.width,
                            height: imageHeight,
                            alignment: treatment.imageAlignment
                        )
                        .saturation(treatment.saturation)
                        .contrast(treatment.contrast)
                        .brightness(treatment.brightness)
                        .clipped()
                        .overlay {
                            LinearGradient(
                                colors: [
                                    theme.style.panelTop.opacity(treatment.topWashOpacity),
                                    theme.style.backdrop.opacity(treatment.bottomWashOpacity)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }
                        .opacity(treatment.imageOpacity)
                        .mask {
                            LinearGradient(
                                stops: [
                                    .init(color: .white, location: 0),
                                    .init(color: .white, location: 0.58),
                                    .init(color: .white.opacity(0.72), location: 0.78),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        }

                    RadialGradient(
                        colors: [
                            theme.style.accentHighlight.opacity(treatment.lightOpacity),
                            .clear
                        ],
                        center: treatment.lightCenter,
                        startRadius: 2,
                        endRadius: treatment.lightRadius
                    )
                    .frame(height: imageHeight)
                    .blendMode(.screen)
                    .mask {
                        LinearGradient(
                            colors: [.white, .white.opacity(0.42), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MenuThemeBackdropTreatment: Equatable {
    let imageAlignment: Alignment
    let imageOpacity: Double
    let saturation: Double
    let contrast: Double
    let brightness: Double
    let topWashOpacity: Double
    let bottomWashOpacity: Double
    let lightCenter: UnitPoint
    let lightOpacity: Double
    let lightRadius: CGFloat
}

extension ReminderTheme {
    var menuBackdropTreatment: MenuThemeBackdropTreatment {
        switch self {
        case .quietHorizon:
            MenuThemeBackdropTreatment(
                imageAlignment: .center,
                imageOpacity: 0.62,
                saturation: 0.80,
                contrast: 1.10,
                brightness: 0,
                topWashOpacity: 0.34,
                bottomWashOpacity: 0.54,
                lightCenter: .bottom,
                lightOpacity: 0.18,
                lightRadius: 176
            )
        case .forestLight:
            MenuThemeBackdropTreatment(
                imageAlignment: .top,
                imageOpacity: 0.72,
                saturation: 0.88,
                contrast: 1.18,
                brightness: 0.02,
                topWashOpacity: 0.24,
                bottomWashOpacity: 0.52,
                lightCenter: .top,
                lightOpacity: 0.24,
                lightRadius: 154
            )
        case .alpineMist:
            MenuThemeBackdropTreatment(
                imageAlignment: .trailing,
                imageOpacity: 0.60,
                saturation: 0.76,
                contrast: 1.08,
                brightness: -0.02,
                topWashOpacity: 0.32,
                bottomWashOpacity: 0.50,
                lightCenter: .topTrailing,
                lightOpacity: 0.19,
                lightRadius: 170
            )
        case .twilightDunes:
            MenuThemeBackdropTreatment(
                imageAlignment: .bottomTrailing,
                imageOpacity: 0.68,
                saturation: 0.92,
                contrast: 1.14,
                brightness: 0,
                topWashOpacity: 0.28,
                bottomWashOpacity: 0.48,
                lightCenter: .bottomTrailing,
                lightOpacity: 0.23,
                lightRadius: 164
            )
        }
    }
}

private struct MenuRestButtonStyle: ButtonStyle {
    let style: ReminderThemeStyle
    let isPrimary: Bool
    let reduceTransparency: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(isPrimary ? style.backdrop.opacity(0.98) : .white.opacity(0.84))
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(fillStyle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }

    private var fillStyle: AnyShapeStyle {
        if isPrimary {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [style.accentHighlight, style.accent],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(style.surface.opacity(reduceTransparency ? 1 : 0.72))
    }

    private var borderColor: Color {
        isPrimary
            ? .white.opacity(reduceTransparency ? 0.24 : 0.14)
            : style.accent.opacity(reduceTransparency ? 0.80 : 0.56)
    }
}

private struct MenuActionButton: View {
    let title: String
    let systemImage: String
    let style: ReminderThemeStyle
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(style.accent)
                    .frame(width: 16)
                    .accessibilityHidden(true)

                Text(title)

                Spacer(minLength: 0)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.84))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style.surface.opacity(isHovering ? 0.84 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel(title)
    }
}
