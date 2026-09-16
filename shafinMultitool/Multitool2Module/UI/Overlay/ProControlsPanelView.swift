import SwiftUI

/// One control surface over CameraManager's device. Draft slider values are
/// explicit requests; the readback beneath them comes only from the manager.
struct ProControlsPanelView: View {
    @ObservedObject var viewModel: CameraViewModel
    let locale: Locale
    let onClose: () -> Void
    let onSelectFocusPoint: () -> Void

    @State private var exposureBias: Double = 0
    @State private var shutterAngle: Double = 180
    @State private var iso: Double = 100
    @State private var lensPosition: Double = 0.5
    @State private var temperature: Double = 5500

    private var state: CameraProControlsSnapshot? { viewModel.proControlsSnapshot }
    private var readback: CameraProControlReadback? { state?.readback }

    var body: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x3) {
            HStack(alignment: .firstTextBaseline) {
                Text(copy(.proControlsTitle))
                    .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.title, relativeTo: .headline))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(minWidth: SETComponentMetric.minimumHitTarget,
                               minHeight: SETComponentMetric.minimumHitTarget)
                }
                .accessibilityLabel(copy(.proControlClose))
                .accessibilityIdentifier("pro_controls_close")
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: SETSpacing.x3) {
                    status
                    formatControls
                    Divider()
                    exposureControls
                    Divider()
                    focusControls
                    Divider()
                    whiteBalanceControls
                    Divider()
                    lightAndAudioControls
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("pro_controls_scroll")
        }
        .foregroundStyle(.setTextPrimary)
        .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.label, relativeTo: .callout))
        .tint(.setOrange)
        .padding(SETSpacing.x3)
        .frame(maxWidth: 440, maxHeight: .infinity, alignment: .topLeading)
        .background(.setInk)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro_controls_panel")
        .onAppear(perform: loadDrafts)
        .onChange(of: state?.deviceID) { _, _ in loadDrafts() }
        .onChange(of: state?.readback.formatID) { _, _ in loadDrafts() }
        .onChange(of: viewModel.isApplyingProControl) { _, applying in
            if !applying { loadDrafts() }
        }
        .task(id: viewModel.lifecycleState == .running) {
            await viewModel.observeProControlsWhilePresented()
        }
    }

    @ViewBuilder private var status: some View {
        if viewModel.isApplyingProControl {
            HStack {
                ProgressView()
                Text(copy(viewModel.isFocusingProControl ? .proControlFocusConverging : .proControlApplying))
            }
            .accessibilityIdentifier("pro_controls_applying")
        } else if state == nil || viewModel.lifecycleState != .running {
            Text(copy(.proControlUnavailable)).foregroundStyle(.setTextSecondary)
        }
        if let error = viewModel.proControlError {
            Text(copy(ProControlsPresentation.errorKey(error)))
                .foregroundStyle(.setTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("pro_controls_error")
        }
    }

    private var formatControls: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x1) {
            title(.proControlFormat)
            Picker(copy(.proControlFormat), selection: Binding(
                get: { readback?.formatID ?? "" },
                set: { viewModel.applyProControl(.format($0)) }
            )) {
                if readback?.formatID == nil {
                    Text(value(.formatResolutionFPS)).tag("")
                }
                ForEach(state?.capabilities.formats ?? []) { format in
                    Text(format.label).tag(format.id)
                }
            }
            .pickerStyle(.menu)
            .frame(minHeight: SETComponentMetric.minimumHitTarget)
            .disabled(!enabled(.formatResolutionFPS))
            .accessibilityIdentifier("pro_control_formatResolutionFPS")
            observed(.formatResolutionFPS)
            unsupported(.formatResolutionFPS)
        }
    }

    private var exposureControls: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            action(.proControlExposureAuto, control: .exposureAuto, command: .exposureAuto)
            observed(.exposureAuto)
            unsupported(.exposureAuto)
            if let range = state?.capabilities.exposureBiasRange, range.lowerBound < range.upperBound {
                slider(.proControlExposureEV, value: $exposureBias,
                       range: Double(range.lowerBound)...Double(range.upperBound),
                       text: String(format: "%+.1f EV", exposureBias),
                       enabled: enabled(.exposureEV), identifier: "pro_control_exposureEV") { editing in
                    if !editing { viewModel.applyProControl(.exposureBias(Float(exposureBias))) }
                }
            } else {
                title(.proControlExposureEV)
                unsupported(.exposureEV)
            }
            observed(.exposureEV)
            if readback?.exposureIsAuto == false { caption(.proControlEVRequiresAuto) }
            title(.proControlExposureManual)
            slider(.proControlShutterAngle, value: $shutterAngle, range: 1...360,
                   text: String(format: "%.0f°", shutterAngle),
                   enabled: enabled(.exposureManualShutterAngleISO),
                   identifier: "pro_control_shutter_angle")
            if let range = state?.capabilities.isoRange, range.lowerBound < range.upperBound {
                slider(.proControlISO, value: $iso,
                       range: Double(range.lowerBound)...Double(range.upperBound),
                       text: String(format: "ISO %.0f", iso),
                       enabled: enabled(.exposureManualShutterAngleISO),
                       identifier: "pro_control_iso")
            }
            action(.proControlApply, control: .exposureManualShutterAngleISO,
                   command: .exposureManual(shutterAngle: shutterAngle, iso: Float(iso)))
            observed(.exposureManualShutterAngleISO)
            if readback?.fixedFPS == nil {
                caption(.proControlExposureChooseFPS)
            } else {
                unsupported(.exposureManualShutterAngleISO)
            }
        }
    }

    private var focusControls: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            action(.proControlFocusAuto, control: .focusAuto, command: .focusAuto)
            observed(.focusAuto)
            unsupported(.focusAuto)
            Button(copy(.proControlFocusTapLock), action: onSelectFocusPoint)
                .buttonStyle(.bordered)
                .frame(minHeight: SETComponentMetric.minimumHitTarget)
                .disabled(!enabled(.focusTapLock))
                .accessibilityIdentifier("pro_control_focusTapLock")
            // An accessible alternative to choosing a spatial point by touch.
            action(.proControlFocusAtCenter, control: .focusTapLock,
                   command: .focusPoint(CGPoint(x: 0.5, y: 0.5)), identifier: "pro_control_focus_center")
            observed(.focusTapLock)
            unsupported(.focusTapLock)
            slider(.proControlFocusManual, value: $lensPosition, range: 0...1,
                   text: String(format: "%.2f", lensPosition), enabled: enabled(.focusManual),
                   identifier: "pro_control_focusManual") { editing in
                if !editing { viewModel.applyProControl(.focusManual(Float(lensPosition))) }
            }
            caption(.proControlFocusPosition)
            observed(.focusManual)
            unsupported(.focusManual)
        }
    }

    private var whiteBalanceControls: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            action(.proControlWBAuto, control: .whiteBalanceAuto, command: .whiteBalanceAuto)
            observed(.whiteBalanceAuto)
            unsupported(.whiteBalanceAuto)
            action(.proControlWBLock, control: .whiteBalanceLock, command: .whiteBalanceLock)
            observed(.whiteBalanceLock)
            unsupported(.whiteBalanceLock)
            title(.proControlWBPreset)
            ViewThatFits(in: .horizontal) {
                HStack { whiteBalancePresets }
                VStack(alignment: .leading) { whiteBalancePresets }
            }
            slider(.proControlWBTemperature, value: $temperature, range: 2000...10000,
                   text: String(format: "%.0f K", temperature),
                   enabled: enabled(.whiteBalanceTemperature),
                   identifier: "pro_control_whiteBalanceTemperature")
            action(.proControlApply, control: .whiteBalanceTemperature,
                   command: .whiteBalanceTemperature(Float(temperature)))
            observed(.whiteBalanceTemperature)
            unsupported(.whiteBalanceTemperature)
        }
    }

    @ViewBuilder private var whiteBalancePresets: some View {
        action(.proControlWBWarm, control: .whiteBalancePreset,
               command: .whiteBalanceTemperature(3200), identifier: "pro_control_wb_warm")
        action(.proControlWBDaylight, control: .whiteBalancePreset,
               command: .whiteBalanceTemperature(5600), identifier: "pro_control_wb_daylight")
        action(.proControlWBCloudy, control: .whiteBalancePreset,
               command: .whiteBalanceTemperature(6500), identifier: "pro_control_wb_cloudy")
    }

    private var lightAndAudioControls: some View {
        VStack(alignment: .leading, spacing: SETSpacing.x2) {
            action(.proControlTorch, control: .torch, command: .torch(!(readback?.torchActive ?? false)))
            observed(.torch)
            unsupported(.torch)
            title(.proControlAudioMeter)
            if viewModel.proAudioMeterEnabled {
                Text(ProControlsPresentation.valueText(for: .audioMeter, readback: readback,
                     meterLevel: viewModel.proAudioLevel, locale: locale) ?? copy(.proControlAudioWaiting))
                    .monospacedDigit()
                    .accessibilityIdentifier("pro_control_audioMeter")
                ProgressView(value: Double(viewModel.proAudioLevel ?? 0), total: 1)
                    .accessibilityHidden(true)
                Button(copy(.proControlMicrophoneDisable)) { viewModel.disableProAudioMeter() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: SETComponentMetric.minimumHitTarget)
                    .disabled(!viewModel.canApplyProControl)
                    .accessibilityIdentifier("pro_control_microphone_disable")
            } else {
                Button(copy(.proControlMicrophoneEnable)) { viewModel.enableProAudioMeter() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: SETComponentMetric.minimumHitTarget)
                    .disabled(!viewModel.canApplyProControl)
                    .accessibilityIdentifier("pro_control_microphone_enable")
            }
            caption(.proControlMicrophoneDescription)
        }
    }

    private func action(_ key: SETCopyKey, control: ProCameraControl,
                        command: CameraProControlCommand, identifier: String? = nil) -> some View {
        Button(copy(key)) { viewModel.applyProControl(command) }
            .buttonStyle(.bordered)
            .frame(minHeight: SETComponentMetric.minimumHitTarget)
            .disabled(!enabled(control))
            .accessibilityIdentifier(identifier ?? "pro_control_\(control.rawValue)")
    }

    private func slider(_ key: SETCopyKey, value: Binding<Double>, range: ClosedRange<Double>,
                        text: String, enabled: Bool, identifier: String,
                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) -> some View {
        VStack(alignment: .leading, spacing: SETSpacing.x1) {
            HStack {
                Text(copy(key))
                Spacer(minLength: SETSpacing.x1)
                Text(text).monospacedDigit()
            }
            Slider(value: value, in: range, onEditingChanged: onEditingChanged)
                .disabled(!enabled)
                .frame(minHeight: SETComponentMetric.minimumHitTarget)
                .accessibilityLabel(copy(key))
                .accessibilityValue(text)
                .accessibilityIdentifier(identifier)
        }
    }

    private func enabled(_ control: ProCameraControl) -> Bool {
        viewModel.canApplyProControl && ProCameraControlContracts.isSupported(control, by: state)
    }

    @ViewBuilder private func unsupported(_ control: ProCameraControl) -> some View {
        if state != nil && !ProCameraControlContracts.isSupported(control, by: state) {
            caption(.proControlUnsupported)
        }
    }

    private func observed(_ control: ProCameraControl) -> some View {
        Text("\(copy(.proControlReadback)): \(value(control))")
            .foregroundStyle(.setTextSecondary)
            .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.micro, relativeTo: .caption2))
            .monospacedDigit()
            .accessibilityIdentifier("pro_readback_\(control.rawValue)")
    }

    private func title(_ key: SETCopyKey) -> some View {
        Text(copy(key)).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
    }

    private func caption(_ key: SETCopyKey) -> some View {
        Text(copy(key))
            .font(SETTypography.scaledFont(.hudMono, size: SETTypographySize.micro, relativeTo: .caption2))
            .foregroundStyle(.setTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func value(_ control: ProCameraControl) -> String {
        ProControlsPresentation.valueText(for: control, readback: readback, locale: locale) ?? "—"
    }

    private func copy(_ key: SETCopyKey) -> String { key.localizedString(locale: locale) }

    private func loadDrafts() {
        guard let state else { return }
        exposureBias = Double(state.readback.exposureBias ?? 0)
        shutterAngle = min(max(state.readback.shutterAngle ?? 180, 1), 360)
        if let range = state.capabilities.isoRange {
            iso = Double(min(max(state.readback.iso ?? range.lowerBound, range.lowerBound), range.upperBound))
        }
        lensPosition = Double(min(max(state.readback.lensPosition ?? 0.5, 0), 1))
        temperature = Double(min(max(state.readback.temperature ?? 5500, 2000), 10000))
    }
}
