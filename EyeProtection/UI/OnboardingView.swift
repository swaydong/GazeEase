import SwiftUI

enum OnboardingPermissionPhase: Equatable {
    case authorizationRequired
    case starting
    case ready

    init(inputPermissionGranted: Bool, isMonitoringComplete: Bool) {
        if !inputPermissionGranted {
            self = .authorizationRequired
        } else if !isMonitoringComplete {
            self = .starting
        } else {
            self = .ready
        }
    }

    var primaryAction: OnboardingPrimaryAction {
        switch self {
        case .authorizationRequired:
            .authorize
        case .starting:
            .recheck
        case .ready:
            .complete
        }
    }
}

enum OnboardingPrimaryAction: Equatable {
    case authorize
    case recheck
    case complete

    var titleKey: L10nKey {
        switch self {
        case .authorize:
            .onboardingPermissionAuthorize
        case .recheck:
            .onboardingPermissionRecheck
        case .complete:
            .onboardingFinish
        }
    }

    var accessibilityHintKey: L10nKey {
        switch self {
        case .authorize:
            .onboardingPermissionAuthorizeAccessibilityHint
        case .recheck:
            .onboardingPermissionRecheckAccessibilityHint
        case .complete:
            .onboardingFinishAccessibilityHint
        }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    let onComplete: () -> Void

    private var language: AppLanguage {
        model.resolvedLanguage
    }

    private var permissionPhase: OnboardingPermissionPhase {
        OnboardingPermissionPhase(
            inputPermissionGranted: model.inputPermissionGranted,
            isMonitoringComplete: model.isMonitoringComplete
        )
    }

    var body: some View {
        ZStack {
            OnboardingBackdrop()

            VStack(alignment: .leading, spacing: 16) {
                header
                introduction
                permissionCard
                privacyCard
                Spacer(minLength: 0)
                finishButton
            }
            .padding(24)
        }
        .frame(width: 520, height: 520)
        .onAppear {
            model.refreshMonitoringStatus()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("MenuBarTaiji")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.white.opacity(0.92))
                .frame(width: 30, height: 30)
                .accessibilityHidden(true)

            Text(AppLocalization.string(.appName, language: language))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Picker(
                AppLocalization.string(.onboardingLanguageLabel, language: language),
                selection: Binding(
                    get: { model.appLanguage },
                    set: { model.setAppLanguage($0) }
                )
            ) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.displayName(language: language))
                        .tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 155)
            .accessibilityLabel(
                AppLocalization.string(.onboardingLanguageAccessibilityLabel, language: language)
            )
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(AppLocalization.string(.onboardingTitle, language: language))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(AppLocalization.string(.onboardingSubtitle, language: language))
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var permissionCard: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    OnboardingIcon(systemName: "keyboard")

                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLocalization.string(.onboardingPermissionTitle, language: language))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(
                            AppLocalization.string(
                                .onboardingPermissionDescription,
                                language: language
                            )
                        )
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.67))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    permissionStatus
                    Spacer()

                    if permissionPhase == .starting {
                        Button(
                            AppLocalization.string(
                                .onboardingPermissionRepair,
                                language: language
                            )
                        ) {
                            model.openInputMonitoringSettings()
                        }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                    } else if permissionPhase == .ready {
                        Button(
                            AppLocalization.string(
                                .onboardingPermissionTestReminder,
                                language: language
                            )
                        ) {
                            model.showTestReminderPreview()
                        }
                        .buttonStyle(OnboardingSecondaryButtonStyle())
                        .disabled(!model.canShowTestReminderPreview)
                        .accessibilityHint(
                            AppLocalization.string(
                                .onboardingPermissionTestReminderAccessibilityHint,
                                language: language
                            )
                        )
                    }
                }
            }
        }
    }

    private var permissionStatus: some View {
        let configuration: (key: L10nKey, icon: String, color: Color) = switch permissionPhase {
        case .authorizationRequired:
            (
                .onboardingPermissionStatusAuthorizationRequired,
                "exclamationmark.circle.fill",
                Color(red: 0.90, green: 0.68, blue: 0.40)
            )
        case .starting:
            (
                .onboardingPermissionStatusStarting,
                "clock.fill",
                Color(red: 0.64, green: 0.78, blue: 0.84)
            )
        case .ready:
            (
                .onboardingPermissionStatusReady,
                "checkmark.circle.fill",
                Color(red: 0.50, green: 0.82, blue: 0.70)
            )
        }

        return Label(
            AppLocalization.string(configuration.key, language: language),
            systemImage: configuration.icon
        )
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(configuration.color)
    }

    private var privacyCard: some View {
        OnboardingCard {
            HStack(alignment: .top, spacing: 12) {
                OnboardingIcon(systemName: "hand.raised.fill")

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string(.onboardingPrivacyTitle, language: language))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(
                        AppLocalization.string(
                            .onboardingPrivacyDescription,
                            language: language
                        )
                    )
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.67))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var finishButton: some View {
        let action = permissionPhase.primaryAction
        return Button(AppLocalization.string(action.titleKey, language: language)) {
            switch action {
            case .authorize:
                model.requestInputPermission()
            case .recheck:
                model.refreshMonitoringStatus()
            case .complete:
                if model.completeOnboarding() {
                    onComplete()
                }
            }
        }
        .buttonStyle(OnboardingPrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
        .accessibilityHint(
            AppLocalization.string(action.accessibilityHintKey, language: language)
        )
    }
}

private struct OnboardingBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color(red: 0.012, green: 0.088, blue: 0.094),
                    Color(red: 0.004, green: 0.044, blue: 0.052)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if !reduceTransparency {
                RadialGradient(
                    colors: [
                        Color(red: 0.40, green: 0.76, blue: 0.67).opacity(0.20),
                        .clear
                    ],
                    center: .bottom,
                    startRadius: 8,
                    endRadius: 270
                )
                .frame(height: 230)
                .allowsHitTesting(false)
            }

            LinearGradient(
                colors: [.clear, Color.white.opacity(0.22), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 330, height: 1)
            .padding(.bottom, 46)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        Color(red: 0.035, green: 0.125, blue: 0.132)
                            .opacity(reduceTransparency ? 1 : 0.78)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            )
    }
}

private struct OnboardingIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color(red: 0.48, green: 0.80, blue: 0.71))
            .frame(width: 30, height: 30)
            .background(
                Circle()
                    .fill(Color(red: 0.48, green: 0.80, blue: 0.71).opacity(0.12))
            )
            .accessibilityHidden(true)
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.012, green: 0.090, blue: 0.090))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.57, green: 0.88, blue: 0.76),
                                Color(red: 0.40, green: 0.76, blue: 0.67)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.15 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }
}
