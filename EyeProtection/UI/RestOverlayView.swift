import SwiftUI

enum RestOverlayMode: Equatable {
    case decision
    case resting
}

enum RestOverlayLayout {
    static let actionButtonSize = CGSize(width: 210, height: 52)
    static let actionSpacing: CGFloat = 24
    static let decisionContentWidth: CGFloat = 720
}

struct RestOverlayPresentation: Equatable {
    let mode: RestOverlayMode
    let fatigueDisplay: String
    let overloadDuration: TimeInterval
    let restSecondsRemaining: TimeInterval
    let restProgress: Double
    var language: AppLanguage = .zhHans

    var overloadDurationDisplay: String {
        EyeDurationFormatter.compact(overloadDuration, language: language)
    }

    var decisionDetailText: String {
        AppLocalization.format(
            .overlayDecisionDetail,
            language: language,
            arguments: [fatigueDisplay, overloadDurationDisplay]
        )
    }

    var decisionAccessibilityValue: String {
        AppLocalization.format(
            .overlayDecisionAccessibilityValue,
            language: language,
            arguments: [fatigueDisplay, overloadDurationDisplay]
        )
    }

    var wholeSecondsRemaining: Int {
        max(0, Int(ceil(restSecondsRemaining)))
    }

    var clampedRestProgress: Double {
        min(max(restProgress, 0), 1)
    }

    var restingAccessibilityLabel: String {
        AppLocalization.format(
            .overlayRestingAccessibility,
            language: language,
            arguments: [wholeSecondsRemaining]
        )
    }
}

struct RestOverlayView: View {
    @ObservedObject var model: AppModel
    let mode: RestOverlayMode
    let onBeginRest: () -> Void
    let onContinueWorking: () -> Void

    var body: some View {
        RestOverlayScene(
            presentation: RestOverlayPresentation(
                mode: mode,
                fatigueDisplay: model.fatigueDisplay,
                overloadDuration: model.overloadDuration,
                restSecondsRemaining: model.restSecondsRemaining,
                restProgress: model.restProgress,
                language: model.resolvedLanguage
            ),
            theme: model.reminderTheme,
            language: model.resolvedLanguage,
            onBeginRest: onBeginRest,
            onContinueWorking: onContinueWorking
        )
    }
}

struct RestOverlayScene: View {
    let presentation: RestOverlayPresentation
    let theme: ReminderTheme
    let language: AppLanguage
    let onBeginRest: () -> Void
    let onContinueWorking: () -> Void

    private let reduceMotionOverride: Bool?
    private let reduceTransparencyOverride: Bool?
    private let backgroundMaximumPixelDimensionOverride: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        presentation: RestOverlayPresentation,
        theme: ReminderTheme = .quietHorizon,
        language: AppLanguage = .zhHans,
        onBeginRest: @escaping () -> Void,
        onContinueWorking: @escaping () -> Void,
        reduceMotionOverride: Bool? = nil,
        reduceTransparencyOverride: Bool? = nil,
        backgroundMaximumPixelDimensionOverride: Int? = nil
    ) {
        self.presentation = presentation
        self.theme = theme
        self.language = language
        self.onBeginRest = onBeginRest
        self.onContinueWorking = onContinueWorking
        self.reduceMotionOverride = reduceMotionOverride
        self.reduceTransparencyOverride = reduceTransparencyOverride
        self.backgroundMaximumPixelDimensionOverride = backgroundMaximumPixelDimensionOverride
    }

    var body: some View {
        ZStack {
            RestThemeBackground(
                theme: theme,
                restProgress: presentation.mode == .resting
                    ? presentation.clampedRestProgress
                    : 0,
                reduceMotion: effectiveReduceMotion,
                reduceTransparency: effectiveReduceTransparency,
                maximumPixelDimensionOverride: backgroundMaximumPixelDimensionOverride
            )
            .id(theme)

            RestContentReadabilityScrim(
                mode: presentation.mode,
                reduceTransparency: effectiveReduceTransparency
            )

            VStack(spacing: 0) {
                Spacer(minLength: 36)

                switch presentation.mode {
                case .decision:
                    decisionContent
                case .resting:
                    restingContent
                }

                Spacer(minLength: 36)
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.style.backdrop)
        .ignoresSafeArea()
    }

    private var decisionContent: some View {
        VStack(spacing: 0) {
            Image("MenuBarTaiji")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)
                .padding(.bottom, 28)

            Text(localized(.overlayDecisionTitle))
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .accessibilityAddTraits(.isHeader)

            Text(presentation.decisionDetailText)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.80)
                .padding(.top, 16)
                .accessibilityLabel(presentation.decisionAccessibilityValue)

            HStack(spacing: RestOverlayLayout.actionSpacing) {
                Button(
                    ReminderDecisionAction.deferRest.title(language: language),
                    action: onContinueWorking
                )
                    .buttonStyle(RestOverlayActionButtonStyle(
                        emphasis: .secondary,
                        style: theme.style,
                        reduceTransparency: effectiveReduceTransparency
                    ))
                    .accessibilityIdentifier("defer-rest")
                    .accessibilityHint(localized(.overlayDecisionDeferHint))

                Button(
                    ReminderDecisionAction.beginRest.title(language: language),
                    action: onBeginRest
                )
                    .buttonStyle(RestOverlayActionButtonStyle(
                        emphasis: .primary,
                        style: theme.style,
                        reduceTransparency: effectiveReduceTransparency
                    ))
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("begin-rest")
                    .accessibilityHint(localized(.overlayDecisionBeginHint))
            }
            .padding(.top, 66)
        }
        .frame(maxWidth: RestOverlayLayout.decisionContentWidth)
        .accessibilityElement(children: .contain)
    }

    private var restingContent: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(effectiveReduceTransparency ? 0.24 : 0.14), lineWidth: 11)

                Circle()
                    .trim(from: 0, to: presentation.clampedRestProgress)
                    .stroke(
                        theme.style.accent,
                        style: StrokeStyle(lineWidth: 11, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(
                        effectiveReduceMotion ? nil : .linear(duration: 0.35),
                        value: presentation.clampedRestProgress
                    )

                VStack(spacing: 2) {
                    Text("\(presentation.wholeSecondsRemaining)")
                        .font(.system(size: 68, weight: .light, design: .rounded))
                        .monospacedDigit()
                    Text(localized(.overlayRestingSecondsUnit))
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.64))
                }
            }
            .frame(width: 230, height: 230)

            VStack(spacing: 10) {
                Text(localized(.overlayRestingTitle))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(localized(.overlayRestingSubtitle))
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }

            Text(localized(.overlayRestingInterruptionNotice))
                .font(.callout)
                .foregroundStyle(.white.opacity(0.70))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.restingAccessibilityLabel)
    }

    private var effectiveReduceMotion: Bool {
        reduceMotionOverride ?? reduceMotion
    }

    private var effectiveReduceTransparency: Bool {
        reduceTransparencyOverride ?? reduceTransparency
    }

    private func localized(_ key: L10nKey) -> String {
        AppLocalization.string(key, language: language)
    }
}

private struct RestContentReadabilityScrim: View {
    let mode: RestOverlayMode
    let reduceTransparency: Bool

    var body: some View {
        GeometryReader { proxy in
            RadialGradient(
                colors: [
                    .black.opacity(centerOpacity),
                    .black.opacity(reduceTransparency ? 0.22 : 0.09),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: max(proxy.size.width * 0.48, proxy.size.height * 0.62)
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var centerOpacity: Double {
        let regular = mode == .decision ? 0.22 : 0.30
        return reduceTransparency ? regular + 0.16 : regular
    }
}

private struct RestThemeBackground: View {
    let theme: ReminderTheme
    let restProgress: Double
    let reduceMotion: Bool
    let reduceTransparency: Bool

    @StateObject private var backgroundLease: RestBackgroundImageLease

    @MainActor
    init(
        theme: ReminderTheme,
        restProgress: Double,
        reduceMotion: Bool,
        reduceTransparency: Bool,
        maximumPixelDimensionOverride: Int?
    ) {
        self.theme = theme
        self.restProgress = restProgress
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        let maximumPixelDimension = maximumPixelDimensionOverride
            ?? RestBackgroundImageLoader.recommendedMaximumPixelDimension()
        _backgroundLease = StateObject(wrappedValue: RestBackgroundImageLoader.shared.lease(
            for: theme,
            maximumPixelDimension: maximumPixelDimension
        ))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                let imageFrame = horizonImageFrame(for: proxy.size)

                LinearGradient(
                    colors: [theme.style.surface, theme.style.backdrop],
                    startPoint: .top,
                    endPoint: .bottom
                )

                if let backgroundImage = backgroundLease.image {
                    Image(decorative: backgroundImage, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: imageFrame.width, height: imageFrame.height)
                        .position(
                            x: proxy.size.width / 2,
                            y: imageFrame.height / 2 + imageFrame.offsetY
                        )
                        .transition(.opacity)
                }

                Color.black.opacity(backgroundDimOpacity)

                if restProgress > 0 {
                    RadialGradient(
                        colors: [
                            theme.style.accent.opacity(0.40),
                            theme.style.accent.opacity(0.10),
                            .clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.77),
                        startRadius: 0,
                        endRadius: max(proxy.size.width * 0.34, proxy.size.height * 0.52)
                    )
                    .blendMode(.screen)
                    .opacity(0.06 + (0.28 * restProgress))
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.9),
                        value: restProgress
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.24),
                value: backgroundLease.image != nil
            )
        }
        .accessibilityHidden(true)
    }

    private func horizonImageFrame(for viewport: CGSize) -> (
        width: CGFloat,
        height: CGFloat,
        offsetY: CGFloat
    ) {
        let source = CGSize(width: 1536, height: 960)
        let scale = max(viewport.width / source.width, viewport.height / source.height)
        let width = source.width * scale
        let height = source.height * scale
        let focusPosition: CGFloat = 0.74
        let desiredOffset = (viewport.height * focusPosition) - (height * focusPosition)
        let offsetY = min(0, max(viewport.height - height, desiredOffset))
        return (width, height, offsetY)
    }

    private var backgroundDimOpacity: Double {
        if theme == .rainwashedSeaCliff {
            return reduceTransparency ? 0.40 : 0.23
        }
        return reduceTransparency ? 0.32 : 0.15
    }
}

private enum RestOverlayActionEmphasis {
    case secondary
    case primary
}

private struct RestOverlayActionButtonStyle: ButtonStyle {
    let emphasis: RestOverlayActionEmphasis
    let style: ReminderThemeStyle
    let reduceTransparency: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(foregroundColor)
            .frame(
                width: RestOverlayLayout.actionButtonSize.width,
                height: RestOverlayLayout.actionButtonSize.height
            )
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fillColor)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1.2)
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }

    private var foregroundColor: Color {
        switch emphasis {
        case .secondary:
            .white.opacity(0.80)
        case .primary:
            style.backdrop.opacity(0.98)
        }
    }

    private var fillColor: Color {
        switch emphasis {
        case .secondary:
            style.backdrop
                .opacity(reduceTransparency ? 0.92 : 0.30)
        case .primary:
            style.accent.opacity(reduceTransparency ? 1 : 0.90)
        }
    }

    private var borderColor: Color {
        switch emphasis {
        case .secondary:
            style.accent.opacity(reduceTransparency ? 0.72 : 0.46)
        case .primary:
            .white.opacity(reduceTransparency ? 0.22 : 0.12)
        }
    }
}
