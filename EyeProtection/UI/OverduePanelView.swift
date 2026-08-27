import SwiftUI

struct OverduePanelView: View {
    @ObservedObject var model: AppModel
    let presentation: ReminderPanelPresentation

    var body: some View {
        OverduePanelScene(
            fatigueDisplay: model.fatigueDisplay,
            overloadDuration: model.overloadDuration,
            presentation: presentation,
            theme: model.reminderTheme,
            language: model.resolvedLanguage,
            onContinueWorking: model.continueWorking,
            onBeginRest: model.beginRest
        )
    }
}

struct OverduePanelScene: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let fatigueDisplay: String
    let overloadDuration: TimeInterval
    let presentation: ReminderPanelPresentation
    var theme: ReminderTheme = .quietHorizon
    var language: AppLanguage = .zhHans
    let onContinueWorking: () -> Void
    let onBeginRest: () -> Void
    var reduceTransparencyOverride: Bool? = nil

    var body: some View {
        HStack(spacing: 0) {
            Image("MenuBarTaiji")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            theme.style.accent.opacity(0.98),
                            theme.style.accent.opacity(0.62)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
                .padding(.trailing, 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalization.string(.overduePanelTitle, language: language))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)

                Text(detailText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(
                        .white.opacity(effectiveReduceTransparency ? 0.76 : 0.54)
                    )
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.90)
            }
            .frame(width: 204, alignment: .leading)

            Spacer(minLength: 24)

            HStack(spacing: 10) {
                if presentation.showsDeferAction {
                    Button(
                        ReminderDecisionAction.deferRest.title(language: language),
                        action: onContinueWorking
                    )
                        .buttonStyle(OverdueActionButtonStyle(
                            emphasis: .secondary,
                            style: theme.style,
                            reduceTransparency: effectiveReduceTransparency
                        ))
                        .accessibilityIdentifier("defer-rest")
                }

                Button(
                    ReminderDecisionAction.beginRest.title(language: language),
                    action: onBeginRest
                )
                    .buttonStyle(OverdueActionButtonStyle(
                        emphasis: .primary,
                        style: theme.style,
                        reduceTransparency: effectiveReduceTransparency
                    ))
                    .accessibilityIdentifier("begin-rest")
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(width: presentation.contentWidth, height: 86)
        .background {
            OverduePanelBackground(
                theme: theme,
                reduceTransparency: effectiveReduceTransparency
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 11)
        .frame(width: presentation.panelSize.width, height: presentation.panelSize.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.format(
            .overduePanelAccessibility,
            language: language,
            arguments: [fatigueDisplay]
        ))
    }

    private var detailText: String {
        let duration = EyeDurationFormatter.compact(overloadDuration, language: language)
        return AppLocalization.format(
            .overduePanelDetail,
            language: language,
            arguments: [fatigueDisplay, duration]
        )
    }

    private var effectiveReduceTransparency: Bool {
        reduceTransparencyOverride ?? reduceTransparency
    }
}

private struct OverduePanelBackground: View {
    let theme: ReminderTheme
    let reduceTransparency: Bool

    private let cornerRadius: CGFloat = 24

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [theme.style.panelTop, theme.style.panelBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            GeometryReader { proxy in
                Image(theme.previewAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: treatment.imageAlignment
                    )
                    .saturation(treatment.saturation)
                    .contrast(treatment.contrast)
                    .brightness(treatment.brightness)
                    .clipped()
                    .opacity(
                        treatment.imageOpacity * (reduceTransparency ? 0.16 : 0.28)
                    )
                    .overlay(theme.style.backdrop.opacity(0.46))
            }

            if !reduceTransparency {
                LinearGradient(
                    colors: [
                        .clear,
                        theme.style.panelMist.opacity(0.24),
                        theme.style.panelMist.opacity(0.58),
                        theme.style.panelMist.opacity(0.24),
                        .clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 260, height: 30)
                .mask {
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.18),
                            .white.opacity(0.82),
                            .white
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .blur(radius: 5)
                .blendMode(.screen)
                .offset(y: 8)
            }

            LinearGradient(
                colors: [
                    .clear,
                    theme.style.accent.opacity(reduceTransparency ? 0.90 : 0.95),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 220, height: 1)
            .blendMode(.screen)
            .offset(y: -1.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    theme.style.accent.opacity(reduceTransparency ? 0.72 : 0.42),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var treatment: MenuThemeBackdropTreatment {
        theme.menuBackdropTreatment
    }
}

private enum OverdueActionButtonEmphasis {
    case secondary
    case primary
}

private struct OverdueActionButtonStyle: ButtonStyle {
    let emphasis: OverdueActionButtonEmphasis
    let style: ReminderThemeStyle
    let reduceTransparency: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(foregroundColor)
            .frame(width: 92, height: 44)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(fillStyle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }

    private var fillStyle: AnyShapeStyle {
        switch emphasis {
        case .secondary:
            AnyShapeStyle(style.backdrop.opacity(reduceTransparency ? 1 : 0.62))
        case .primary:
            AnyShapeStyle(
                LinearGradient(
                    colors: [
                        style.accentHighlight.opacity(reduceTransparency ? 1 : 0.98),
                        style.accent.opacity(reduceTransparency ? 1 : 0.88)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var borderColor: Color {
        switch emphasis {
        case .secondary:
            style.accent.opacity(reduceTransparency ? 0.72 : 0.52)
        case .primary:
            .white.opacity(reduceTransparency ? 0.22 : 0.14)
        }
    }

    private var foregroundColor: Color {
        switch emphasis {
        case .secondary:
            .white.opacity(reduceTransparency ? 0.86 : 0.72)
        case .primary:
            style.backdrop.opacity(0.98)
        }
    }
}
