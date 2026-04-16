import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: TimeCalculatorViewModel
    private let topPanelHeight: CGFloat = 64
    private let koreanLocale = Locale(identifier: "ko_KR")

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            tabPickerSection
            topControlSection

            Group {
                switch viewModel.selectedTab {
                case .today:
                    todayTabSection
                case .week:
                    weekTabSection
                }
            }

            footerSection
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var headerSection: some View {
        HStack(spacing: 0) {
            HStack(spacing: 24) {
                Text("🏡")
                Text("🏃‍♂️💨")
            }
        }
        .font(.headline.weight(.medium))
    }

    private var topControlSection: some View {
        HStack(alignment: .top, spacing: 12) {
            menuBarSettingsSection

            if viewModel.selectedTab == .week {
                weekSummarySection
            }
        }
    }

    private var menuBarSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("메뉴바 설정")
                .font(.body.weight(.bold))

            Picker("", selection: viewModel.menuBarMetricBinding) {
                Text("⏱️ 오늘 총 근무시간").tag(MenuBarMetric.worked)
                Text("⏳ 오늘 남은 근무시간").tag(MenuBarMetric.remaining)
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
        }
        .frame(height: topPanelHeight, alignment: .topLeading)
        .frame(maxWidth: viewModel.selectedTab == .week ? 200 : .infinity, alignment: .leading)
        .panelStyle()
    }

    private var weekSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("주간 시간 계산")
                .font(.body.weight(.bold))
            HStack {
                weekSummaryCard(title: "주간 합계", value: viewModel.weekTotalText)
                weekSummaryCard(title: "남은 시간", value: viewModel.weekRemainingText)
            }
        }
        .frame(height: topPanelHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }

    private var tabPickerSection: some View {
        Picker("", selection: $viewModel.selectedTab) {
            ForEach(WorkTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    private var todayTabSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                targetHoursSelector

                Divider()

                timePickerRow(title: "출근 시간", selection: viewModel.startTimeBinding)
                    .font(.body.weight(.bold))
                timePickerRow(title: "퇴근 시간", selection: viewModel.endTimeBinding)
                    .font(.body.weight(.bold))
            }
            .panelStyle()

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("요약")
                VStack(alignment: .leading, spacing: 10) {
                    summaryLine(title: "목표 근무 시간", value: viewModel.formattedTargetWork)
                    summaryLine(title: "출근 시간", value: viewModel.formattedStartTime)
                    summaryLine(title: "퇴근 시간", value: viewModel.formattedEndTime)
                    summaryLine(title: "오늘 총 근무시간", value: viewModel.formattedWorkedToday)
                    summaryLine(title: "오늘 남은 근무시간", value: viewModel.formattedRemainingToday)
                }
            }
            .panelStyle()
        }
    }

    private var targetHoursSelector: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("목표 근무 시간")
                .font(.body.weight(.bold))

            HStack(spacing: 6) {
                ForEach([6, 7, 8, 9], id: \.self) { hour in
                    Button {
                        viewModel.targetHoursBinding.wrappedValue = hour
                    } label: {
                        Text("\(hour)h")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(
                                viewModel.targetHoursBinding.wrappedValue == hour
                                    ? Color.white
                                    : Color.primary.opacity(0.7)
                            )
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        viewModel.targetHoursBinding.wrappedValue == hour
                                            ? Color(nsColor: .tertiaryLabelColor)
                                            : Color(nsColor: .underPageBackgroundColor).opacity(0.4)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        viewModel.targetHoursBinding.wrappedValue == hour
                                            ? Color.clear
                                            : Color(nsColor: .separatorColor).opacity(0.22),
                                        lineWidth: 0.8
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
            )
        }
    }

    private var weekTabSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(weekDays.enumerated()), id: \.offset) { item in
                        weekDayCard(index: item.offset)
                    }
                }
            }
            .frame(height: 560)
        }
    }

    private var footerSection: some View {
        HStack {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("앱 종료", systemImage: "power")
                    .imageScale(.small)
            }
            .keyboardShortcut("q")
            .buttonStyle(.bordered)
            .tint(Color(nsColor: .systemBrown))

            Spacer()

            Button {
                if viewModel.selectedTab == .today {
                    viewModel.resetTodayState()
                } else {
                    viewModel.resetWeeklyState()
                }
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .imageScale(.small)
            }
            .buttonStyle(.bordered)
            .tint(Color(nsColor: .systemGray))
        }
    }

    private func weekSummaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    private func weekDayCard(index: Int) -> some View {
        let day = viewModel.weeklyDay(at: index)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("\(day.day)요일")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Picker("", selection: weeklyLeaveTypeBinding(index: index)) {
                    ForEach(LeaveType.allCases) { leaveType in
                        Text(leaveType.title).tag(leaveType)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .pickerChrome()

                Picker("", selection: weeklyModeBinding(index: index)) {
                    ForEach(InputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 118)
                .pickerChrome()
            }

            if day.leaveType != .annual {
                weeklyInputRow(day: day, index: index)
            }

            HStack {
                Spacer()
                Text("일 인정 시간: \(viewModel.weeklyDayRecognizedText(at: index))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private func weeklyInputRow(day: DayWorkData, index: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if day.mode == .range {
                HStack(spacing: 10) {
                    weeklyTimeSlotField(
                        timeText: day.start,
                        selection: weeklyStartDateBinding(index: index),
                        activate: { viewModel.updateWeeklyStart(idx: index, value: "09:00") }
                    )

                    Text("~")
                        .frame(width: 10, alignment: .center)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)

                    weeklyTimeSlotField(
                        timeText: day.end,
                        selection: weeklyEndDateBinding(index: index),
                        activate: { viewModel.updateWeeklyEnd(idx: index, value: "18:00") }
                    )
                }
            } else {
                HStack(spacing: 10) {
                    manualField(title: "시간", text: weeklyManualHoursBinding(index: index), disabled: false)
                    manualField(title: "분", text: weeklyManualMinutesBinding(index: index), disabled: false)
                }
            }

            Spacer(minLength: 8)

            Button("Delete") {
                viewModel.resetWeeklyDay(idx: index)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(Color(nsColor: .systemGray))
            .font(.caption.weight(.medium))
        }
    }

    @ViewBuilder
    private func weeklyTimeSlotField(timeText: String, selection: Binding<Date>, activate: @escaping () -> Void) -> some View {
        if timeText.isEmpty {
            Button("-- --") {
                activate()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .frame(width: 32, alignment: .leading)
        } else {
            HStack(spacing: 0) {
                DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.locale, koreanLocale)
                    .frame(width: 86, alignment: .leading)
            }
        }
    }

    private func manualField(title: String, text: Binding<String>, disabled: Bool) -> some View {
        HStack(spacing: 4) {
            TextField("0", text: text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .disabled(disabled)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    private func timePickerRow(title: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let placeholder = placeholderText(for: title) {
                Button(placeholder) {
                    activateTimeSelection(for: title)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.38))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 0.8)
                )
            } else {
                HStack(spacing: 0) {
                    BorderlessTimePicker(selection: selection)
                        .frame(width: 108, height: 24)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .underPageBackgroundColor).opacity(0.38))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.22), lineWidth: 0.8)
                )
            }
        }
    }

    private func summaryLine(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13))
    }

    private func placeholderText(for title: String) -> String? {
        switch title {
        case "출근 시간":
            return viewModel.isStartTimeUnset ? "-- --" : nil
        case "퇴근 시간":
            return viewModel.isEndTimeUnset ? "-- --" : nil
        default:
            return nil
        }
    }

    private func activateTimeSelection(for title: String) {
        switch title {
        case "출근 시간":
            viewModel.activateStartTimeSelection()
        case "퇴근 시간":
            viewModel.activateEndTimeSelection()
        default:
            break
        }
    }

    private func weeklyLeaveTypeBinding(index: Int) -> Binding<LeaveType> {
        Binding(
            get: { viewModel.weeklyDay(at: index).leaveType },
            set: { viewModel.updateWeeklyLeaveType(idx: index, leaveType: $0) }
        )
    }

    private func weeklyModeBinding(index: Int) -> Binding<InputMode> {
        Binding(
            get: { viewModel.weeklyDay(at: index).mode },
            set: { _ in viewModel.toggleWeeklyMode(idx: index) }
        )
    }

    private func weeklyStartDateBinding(index: Int) -> Binding<Date> {
        Binding(
            get: {
                dateFromWeeklyTimeString(
                    viewModel.weeklyDay(at: index).start,
                    fallbackHour: 9,
                    fallbackMinute: 0
                )
            },
            set: { viewModel.updateWeeklyStart(idx: index, value: minutesToTime(minutesFromDate($0))) }
        )
    }

    private func weeklyEndDateBinding(index: Int) -> Binding<Date> {
        Binding(
            get: {
                dateFromWeeklyTimeString(
                    viewModel.weeklyDay(at: index).end,
                    fallbackHour: 18,
                    fallbackMinute: 0
                )
            },
            set: { viewModel.updateWeeklyEnd(idx: index, value: minutesToTime(minutesFromDate($0))) }
        )
    }

    private func dateFromWeeklyTimeString(_ time: String, fallbackHour: Int, fallbackMinute: Int) -> Date {
        let minutes = time.isEmpty ? (fallbackHour * 60 + fallbackMinute) : timeToMinutes(time)
        let hour = minutes / 60
        let minute = minutes % 60
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private func minutesFromDate(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }

    private func weeklyManualHoursBinding(index: Int) -> Binding<String> {
        Binding(
            get: { viewModel.weeklyDay(at: index).manualHours },
            set: { viewModel.updateWeeklyManualHours(idx: index, value: $0) }
        )
    }

    private func weeklyManualMinutesBinding(index: Int) -> Binding<String> {
        Binding(
            get: { viewModel.weeklyDay(at: index).manualMinutes },
            set: { viewModel.updateWeeklyManualMinutes(idx: index, value: $0) }
        )
    }
}

private struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}

private struct BorderlessTimePicker: NSViewRepresentable {
    @Binding var selection: Date

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerElements = [.hourMinute]
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerMode = .single
        picker.locale = Locale(identifier: "ko_KR")
        picker.isBordered = false
        picker.drawsBackground = false
        picker.backgroundColor = .clear
        picker.focusRingType = .none
        picker.font = .systemFont(ofSize: NSFont.systemFontSize)
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.valueChanged(_:))
        return picker
    }

    func updateNSView(_ nsView: NSDatePicker, context: Context) {
        if nsView.dateValue != selection {
            nsView.dateValue = selection
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding var selection: Date

        init(selection: Binding<Date>) {
            _selection = selection
        }

        @objc func valueChanged(_ sender: NSDatePicker) {
            selection = sender.dateValue
        }
    }
}

private struct PickerChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .underPageBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.8)
            )
    }
}

private extension View {
    func panelStyle() -> some View {
        modifier(PanelModifier())
    }

    func pickerChrome() -> some View {
        modifier(PickerChromeModifier())
    }
}
