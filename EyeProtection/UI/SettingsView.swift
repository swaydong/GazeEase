import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var isConfirmingClear = false
    @State private var workMinutesInput = ""
    @State private var restSecondsInput = ""
    @State private var inactivityRestMinutesInput = ""
    @State private var randomThemeRotationIntervalInput = ""
    @FocusState private var focusedDurationField: DurationField?

    private enum DurationField: Hashable {
        case workMinutes
        case restSeconds
        case inactivityRestMinutes
        case randomThemeRotationInterval
    }

    var body: some View {
        Form {
            Section(localized(.settingsSectionLanguage)) {
                Picker(
                    localized(.settingsLanguagePicker),
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

                Text(localized(.settingsLanguageFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(localized(.settingsSectionAppearance)) {
                ReminderThemeAtmosphere(
                    theme: model.reminderTheme,
                    rotationEnabled: model.randomThemeRotationEnabled,
                    rotationIntervalMinutes: model.randomThemeRotationIntervalMinutes,
                    language: language
                )

                ReminderThemePicker(
                    selection: model.reminderTheme,
                    language: language,
                    onSelect: model.setReminderTheme
                )

                Toggle(
                    localized(.settingsThemeRandomRotation),
                    isOn: Binding(
                        get: { model.randomThemeRotationEnabled },
                        set: { model.setRandomThemeRotationEnabled($0) }
                    )
                )

                if model.randomThemeRotationEnabled {
                    LabeledContent(localized(.settingsThemeRotationInterval)) {
                        HStack(spacing: 6) {
                            TextField("", text: $randomThemeRotationIntervalInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 72)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused(
                                    $focusedDurationField,
                                    equals: .randomThemeRotationInterval
                                )
                                .onSubmit(commitRandomThemeRotationIntervalInput)
                                .accessibilityLabel(localized(
                                    .settingsThemeRotationIntervalAccessibilityLabel
                                ))
                                .accessibilityHint(localized(
                                    .settingsThemeRotationIntervalAccessibilityHint
                                ))

                            Text(localized(.unitMinuteShort))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(AppLocalization.format(
                        .settingsThemeRotationFooter,
                        language: language,
                        arguments: [model.randomThemeRotationIntervalMinutes]
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .disabled(model.isResting)

            Section(localized(.settingsSectionEyeRules)) {
                LabeledContent(localized(.settingsWorkDuration)) {
                    HStack(spacing: 6) {
                        TextField("", text: $workMinutesInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($focusedDurationField, equals: .workMinutes)
                            .onSubmit(commitWorkMinutesInput)
                            .accessibilityLabel(localized(.settingsWorkDuration))
                            .accessibilityHint(localized(
                                .settingsWorkDurationAccessibilityHint
                            ))

                        Text(localized(.unitMinuteShort))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isResting)

                LabeledContent(localized(.settingsRestDuration)) {
                    HStack(spacing: 6) {
                        TextField("", text: $restSecondsInput)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 72)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($focusedDurationField, equals: .restSeconds)
                            .onSubmit(commitRestSecondsInput)
                            .accessibilityLabel(localized(.settingsRestDuration))
                            .accessibilityHint(localized(
                                .settingsRestDurationAccessibilityHint
                            ))

                        Text(localized(.unitSecondShort))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isResting)

                Text(
                    model.isResting
                        ? localized(.settingsDurationEditingDisabled)
                        : localized(.settingsDurationFooter)
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle(
                    localized(.settingsInactivityEnabled),
                    isOn: Binding(
                        get: { model.inactivityRestEnabled },
                        set: { model.setInactivityRestEnabled($0) }
                    )
                )

                if model.inactivityRestEnabled {
                    LabeledContent(localized(.settingsInactivityDuration)) {
                        HStack(spacing: 6) {
                            TextField("", text: $inactivityRestMinutesInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 72)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .focused(
                                    $focusedDurationField,
                                    equals: .inactivityRestMinutes
                                )
                                .onSubmit(commitInactivityRestMinutesInput)
                                .accessibilityLabel(localized(
                                    .settingsInactivityDurationAccessibilityLabel
                                ))
                                .accessibilityHint(localized(
                                    .settingsInactivityDurationAccessibilityHint
                                ))

                            Text(localized(.unitMinuteShort))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(localized(.settingsInactivityFooter))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Picker(localized(.settingsReminderMode), selection: $model.reminderMode) {
                    ForEach(ReminderMode.allCases) { mode in
                        Text(mode.displayName(language: language)).tag(mode)
                    }
                }

                Text(model.reminderMode.description(language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if model.notificationPermissionDenied {
                    HStack(spacing: 8) {
                        Label(
                            localized(.settingsNotificationDenied),
                            systemImage: "bell.slash.fill"
                        )
                            .font(.caption)
                            .foregroundStyle(EyePalette.watch)
                        Spacer()
                        Button(localized(.settingsNotificationOpen)) {
                            model.openNotificationSettings()
                        }
                    }
                }
            }

            Section(localized(.settingsSectionMonitoringPermission)) {
                PermissionRow(
                    title: localized(.settingsInputMonitoringTitle),
                    description: localized(.settingsInputMonitoringDescription),
                    granted: model.inputPermissionGranted,
                    language: language,
                    action: { model.requestInputPermission() }
                )

                if !model.inputPermissionGranted {
                    Label(
                        localized(.settingsInputMonitoringRequired),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                        .font(.caption)
                        .foregroundStyle(EyePalette.watch)
                    Text(localized(.settingsInputMonitoringStalePermission))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !model.isMonitoringComplete {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(localized(.settingsInputMonitoringStarting))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        localized(.settingsInputMonitoringRunning),
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(EyePalette.calm)
                }

                Button(localized(.settingsInputMonitoringRecheck)) {
                    model.refreshMonitoringStatus()
                }
            }

            Section(localized(.settingsSectionGeneral)) {
                Toggle(
                    localized(.settingsLaunchAtLogin),
                    isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { enabled in model.setLaunchAtLogin(enabled) }
                    )
                )

                Button(localized(.settingsShowOnboarding)) {
                    model.showOnboarding()
                }

                LabeledContent(localized(.settingsDataStorage)) {
                    Text(localized(.settingsDataStorageLocalOnly))
                        .foregroundStyle(.secondary)
                }

                Button(localized(.settingsClearData), role: .destructive) {
                    isConfirmingClear = true
                }
            }

            Section(localized(.settingsSectionPrivacy)) {
                Text(localized(.settingsPrivacyDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 650)
        .onAppear {
            resetDurationInputs()
            model.refreshMonitoringStatus()
        }
        .onChange(of: focusedDurationField) { _, focusedField in
            if focusedField != .workMinutes {
                commitWorkMinutesInput()
            }
            if focusedField != .restSeconds {
                commitRestSecondsInput()
            }
            if focusedField != .inactivityRestMinutes {
                commitInactivityRestMinutesInput()
            }
            if focusedField != .randomThemeRotationInterval {
                commitRandomThemeRotationIntervalInput()
            }
        }
        .onChange(of: model.isResting) { _, isResting in
            guard isResting else { return }
            focusedDurationField = nil
            resetDurationInputs()
        }
        .onDisappear {
            commitWorkMinutesInput()
            commitRestSecondsInput()
            commitInactivityRestMinutesInput()
            commitRandomThemeRotationIntervalInput()
        }
        .alert(localized(.settingsClearDataAlertTitle), isPresented: $isConfirmingClear) {
            Button(localized(.settingsClearDataCancel), role: .cancel) {}
            Button(localized(.settingsClearDataConfirm), role: .destructive) {
                model.clearData()
            }
        } message: {
            Text(localized(.settingsClearDataAlertMessage))
        }
    }

    private var language: AppLanguage {
        model.resolvedLanguage
    }

    private func localized(_ key: L10nKey) -> String {
        AppLocalization.string(key, language: language)
    }

    private func commitWorkMinutesInput() {
        let result = BoundedIntegerInputRule.commit(
            draft: workMinutesInput,
            current: model.workMinutes,
            range: Preferences.workMinutesRange
        )
        if result.shouldApply {
            model.setWorkMinutes(result.value)
        }
        workMinutesInput = String(model.workMinutes)
    }

    private func commitRestSecondsInput() {
        let result = BoundedIntegerInputRule.commit(
            draft: restSecondsInput,
            current: model.restSeconds,
            range: Preferences.restSecondsRange
        )
        if result.shouldApply {
            model.setRestSeconds(result.value)
        }
        restSecondsInput = String(model.restSeconds)
    }

    private func commitInactivityRestMinutesInput() {
        let result = BoundedIntegerInputRule.commit(
            draft: inactivityRestMinutesInput,
            current: model.inactivityRestMinutes,
            range: Preferences.inactivityRestMinutesRange
        )
        if result.shouldApply {
            model.setInactivityRestMinutes(result.value)
        }
        inactivityRestMinutesInput = String(model.inactivityRestMinutes)
    }

    private func commitRandomThemeRotationIntervalInput() {
        let result = BoundedIntegerInputRule.commit(
            draft: randomThemeRotationIntervalInput,
            current: model.randomThemeRotationIntervalMinutes,
            range: Preferences.randomThemeRotationIntervalMinutesRange
        )
        if result.shouldApply,
           result.value != model.randomThemeRotationIntervalMinutes {
            model.setRandomThemeRotationIntervalMinutes(result.value)
        }
        randomThemeRotationIntervalInput = String(model.randomThemeRotationIntervalMinutes)
    }

    private func resetDurationInputs() {
        workMinutesInput = String(model.workMinutes)
        restSecondsInput = String(model.restSeconds)
        inactivityRestMinutesInput = String(model.inactivityRestMinutes)
        randomThemeRotationIntervalInput = String(model.randomThemeRotationIntervalMinutes)
    }
}

enum ReminderThemePickerLayout {
    static let cardSize = CGSize(width: 112, height: 82)
    static let atmosphereSize = CGSize(width: 472, height: 116)
    static let spacing: CGFloat = 8

    static var totalWidth: CGFloat {
        (cardSize.width * CGFloat(ReminderTheme.allCases.count))
            + (spacing * CGFloat(ReminderTheme.allCases.count - 1))
    }
}

struct ReminderThemeAtmosphere: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let theme: ReminderTheme
    let rotationEnabled: Bool
    let rotationIntervalMinutes: Int
    var language: AppLanguage = .zhHans

    var body: some View {
        ReminderThemeAtmosphereScene(
            theme: theme,
            rotationEnabled: rotationEnabled,
            rotationIntervalMinutes: rotationIntervalMinutes,
            reduceTransparency: reduceTransparency,
            language: language
        )
    }
}

struct ReminderThemeAtmosphereScene: View {
    let theme: ReminderTheme
    let rotationEnabled: Bool
    let rotationIntervalMinutes: Int
    let reduceTransparency: Bool
    var language: AppLanguage = .zhHans

    var body: some View {
        ZStack {
            atmosphereBackground

            LinearGradient(
                colors: [
                    .black.opacity(reduceTransparency ? 0.42 : 0.18),
                    .black.opacity(reduceTransparency ? 0.78 : 0.72)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(AppLocalization.string(.themeCurrent, language: language))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.72))

                    Spacer()

                    Text(rotationStatus)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theme.style.accentHighlight)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(theme.style.panelBottom.opacity(0.92))
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(theme.style.accent.opacity(0.46), lineWidth: 1)
                        }
                }

                Spacer(minLength: 8)

                Text(theme.displayName(language: language))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(theme.description(language: language))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                    .padding(.top, 3)
            }
            .padding(14)
        }
        .frame(
            width: ReminderThemePickerLayout.atmosphereSize.width,
            height: ReminderThemePickerLayout.atmosphereSize.height
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(theme.style.accent.opacity(0.48), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.format(
            .themeCurrentAccessibility,
            language: language,
            arguments: [theme.displayName(language: language)]
        ))
        .accessibilityValue(accessibilityRotationStatus)
        .accessibilityHint(theme.description(language: language))
    }

    private var rotationStatus: String {
        rotationEnabled
            ? AppLocalization.format(
                .themeSelectionAutomatic,
                language: language,
                arguments: [rotationIntervalMinutes]
            )
            : AppLocalization.string(.themeSelectionManual, language: language)
    }

    private var accessibilityRotationStatus: String {
        rotationEnabled
            ? AppLocalization.format(
                .themeSelectionAccessibilityAutomatic,
                language: language,
                arguments: [rotationIntervalMinutes]
            )
            : AppLocalization.string(.themeSelectionAccessibilityManual, language: language)
    }

    @ViewBuilder
    private var atmosphereBackground: some View {
        if reduceTransparency {
            LinearGradient(
                colors: [theme.style.panelTop, theme.style.surface, theme.style.panelBottom],
                startPoint: theme.settingsCardTreatment.focus.anchor,
                endPoint: oppositePoint(to: theme.settingsCardTreatment.focus.anchor)
            )
            .accessibilityHidden(true)
        } else {
            Image(theme.previewAssetName)
                .resizable()
                .scaledToFill()
                .frame(
                    width: ReminderThemePickerLayout.atmosphereSize.width,
                    height: ReminderThemePickerLayout.atmosphereSize.height
                )
                .scaleEffect(
                    max(1.02, theme.settingsCardTreatment.scale - 0.04),
                    anchor: theme.settingsCardTreatment.focus.anchor
                )
                .saturation(theme.settingsCardTreatment.saturation)
                .contrast(theme.settingsCardTreatment.contrast)
                .brightness(theme.settingsCardTreatment.brightness)
                .clipped()
                .accessibilityHidden(true)

            RadialGradient(
                colors: [theme.style.accentHighlight.opacity(0.24), .clear],
                center: theme.settingsCardTreatment.focus.glowCenter,
                startRadius: 2,
                endRadius: 170
            )
            .blendMode(.screen)
            .accessibilityHidden(true)
        }
    }

    private func oppositePoint(to point: UnitPoint) -> UnitPoint {
        UnitPoint(x: 1 - point.x, y: 1 - point.y)
    }
}

struct ReminderThemePicker: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let selection: ReminderTheme
    var language: AppLanguage = .zhHans
    let onSelect: (ReminderTheme) -> Void

    var body: some View {
        ReminderThemePickerScene(
            selection: selection,
            reduceTransparency: reduceTransparency,
            language: language,
            onSelect: onSelect
        )
    }
}

struct ReminderThemePickerScene: View {
    let selection: ReminderTheme
    let reduceTransparency: Bool
    var language: AppLanguage = .zhHans
    let onSelect: (ReminderTheme) -> Void

    var body: some View {
        HStack(spacing: ReminderThemePickerLayout.spacing) {
            ForEach(ReminderTheme.allCases) { theme in
                ReminderThemeChoiceScene(
                    theme: theme,
                    isSelected: selection == theme,
                    reduceTransparency: reduceTransparency,
                    language: language,
                    action: { onSelect(theme) }
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.string(
            .themeBackgroundAccessibility,
            language: language
        ))
    }
}

enum ReminderThemePreviewFocus: String, CaseIterable, Hashable {
    case centeredValley
    case forestCanopy
    case rightPeak
    case rightHorizon

    var anchor: UnitPoint {
        switch self {
        case .centeredValley: .center
        case .forestCanopy: .top
        case .rightPeak: .topTrailing
        case .rightHorizon: .bottomTrailing
        }
    }

    var glowCenter: UnitPoint {
        switch self {
        case .centeredValley: .bottom
        case .forestCanopy: .top
        case .rightPeak: .topTrailing
        case .rightHorizon: .bottomTrailing
        }
    }
}

struct ReminderThemeCardTreatment: Equatable {
    let focus: ReminderThemePreviewFocus
    let scale: CGFloat
    let saturation: Double
    let contrast: Double
    let brightness: Double
}

extension ReminderTheme {
    var settingsCardTreatment: ReminderThemeCardTreatment {
        switch self {
        case .quietHorizon:
            ReminderThemeCardTreatment(
                focus: .centeredValley,
                scale: 1.08,
                saturation: 0.90,
                contrast: 1.08,
                brightness: 0.02
            )
        case .forestLight:
            ReminderThemeCardTreatment(
                focus: .forestCanopy,
                scale: 1.04,
                saturation: 0.86,
                contrast: 1.12,
                brightness: 0.04
            )
        case .alpineMist:
            ReminderThemeCardTreatment(
                focus: .rightPeak,
                scale: 1.10,
                saturation: 0.78,
                contrast: 1.08,
                brightness: -0.01
            )
        case .twilightDunes:
            ReminderThemeCardTreatment(
                focus: .rightHorizon,
                scale: 1.12,
                saturation: 0.94,
                contrast: 1.10,
                brightness: 0.01
            )
        }
    }
}

struct ReminderThemeChoiceScene: View {
    let theme: ReminderTheme
    let isSelected: Bool
    let reduceTransparency: Bool
    var language: AppLanguage = .zhHans
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottom) {
                if reduceTransparency {
                    reducedTransparencyBackground
                } else {
                    Image(theme.previewAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(
                            width: ReminderThemePickerLayout.cardSize.width,
                            height: ReminderThemePickerLayout.cardSize.height
                        )
                        .scaleEffect(
                            theme.settingsCardTreatment.scale,
                            anchor: theme.settingsCardTreatment.focus.anchor
                        )
                        .saturation(theme.settingsCardTreatment.saturation)
                        .contrast(theme.settingsCardTreatment.contrast)
                        .brightness(theme.settingsCardTreatment.brightness)
                        .clipped()
                        .accessibilityHidden(true)

                    RadialGradient(
                        colors: [
                            theme.style.accentHighlight.opacity(0.22),
                            .clear
                        ],
                        center: theme.settingsCardTreatment.focus.glowCenter,
                        startRadius: 1,
                        endRadius: 84
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                LinearGradient(
                    colors: [
                        .black.opacity(0.02),
                        .black.opacity(reduceTransparency ? 0.48 : 0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                HStack {
                    Text(theme.displayName(language: language))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.style.accentHighlight)
                            .background(Circle().fill(.black.opacity(0.48)))
                    }
                }
                .padding(8)
            }
            .frame(
                width: ReminderThemePickerLayout.cardSize.width,
                height: ReminderThemePickerLayout.cardSize.height
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? theme.style.accentHighlight : .white.opacity(0.22),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .frame(
            width: ReminderThemePickerLayout.cardSize.width,
            height: ReminderThemePickerLayout.cardSize.height
        )
        .accessibilityLabel(theme.displayName(language: language))
        .accessibilityValue(AppLocalization.string(
            isSelected ? .themeSelected : .themeNotSelected,
            language: language
        ))
        .accessibilityHint(theme.description(language: language))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var reducedTransparencyBackground: some View {
        LinearGradient(
            colors: [
                theme.style.panelTop,
                theme.style.surface,
                theme.style.panelBottom
            ],
            startPoint: theme.settingsCardTreatment.focus.anchor,
            endPoint: oppositePoint(to: theme.settingsCardTreatment.focus.anchor)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func oppositePoint(to point: UnitPoint) -> UnitPoint {
        UnitPoint(x: 1 - point.x, y: 1 - point.y)
    }
}

struct BoundedIntegerInputCommit: Equatable {
    let value: Int
    let shouldApply: Bool
}

enum BoundedIntegerInputRule {
    static func commit(
        draft: String,
        current: Int,
        range: ClosedRange<Int>
    ) -> BoundedIntegerInputCommit {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed) else {
            return BoundedIntegerInputCommit(value: current, shouldApply: false)
        }

        let normalized = min(max(parsed, range.lowerBound), range.upperBound)
        return BoundedIntegerInputCommit(
            value: normalized,
            shouldApply: normalized != current
        )
    }
}

private struct PermissionRow: View {
    let title: String
    let description: String
    let granted: Bool
    let language: AppLanguage
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(granted ? EyePalette.calm : EyePalette.watch)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Text(AppLocalization.string(.settingsPermissionGranted, language: language))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(EyePalette.calm)
            } else {
                Button(
                    AppLocalization.string(.settingsPermissionAuthorize, language: language),
                    action: action
                )
            }
        }
        .padding(.vertical, 4)
    }
}
