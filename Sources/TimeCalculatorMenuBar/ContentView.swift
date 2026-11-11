import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var flex = FlexConnection.shared
    @EnvironmentObject private var viewModel: TimeCalculatorViewModel
    @Environment(\.colorScheme) private var colorScheme
    private let koreanLocale = Locale(identifier: "ko_KR")

private var appVersionText: String {
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    
    if let version = version {
        return "v\(version)"
    } else {
        return "알 수 없음"
    }
}

    // 팝오버 전체 레이아웃
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // 상단 헤더 이모지
    private var headerSection: some View {
        HStack(spacing: 0) {
            HStack(spacing: 24) {
                Text("🏡")
                Text("🏃‍♂️💨")
            }
            Spacer()
            Button("업데이트 확인…") { updater.checkForUpdates() }
                .font(.caption)
                .disabled(!updater.canCheckForUpdates)
                .padding(.trailing, 10)
            Text(appVersionText)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .font(.headline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 메뉴바 설정 + 주간 요약 상단 영역
    private var topControlSection: some View {
        Group {
            switch viewModel.selectedTab {
            case .today:
                menuBarSettingsSection
            case .week:
                weekSummarySection
            }
        }
    }

    // 메뉴바 표시 설정 카드
    private var menuBarSettingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("메뉴바 설정")
                .font(.body.weight(.bold))

            Picker("", selection: viewModel.menuBarMetricBinding) {
                Text("⏱️ 오늘 총 근무시간").tag(MenuBarMetric.worked)
                Text("⏳ 퇴근까지 남은 시간").tag(MenuBarMetric.untilDeparture)
                Text("🏃‍♂️ 시간 숨기기").tag(MenuBarMetric.hidden)
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }

    // 주간 시간 계산 요약 카드
    private var weekSummarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("주간 시간 계산").font(.body.weight(.bold))
            if flex.connected || flex.lastSync != nil {
                flexSyncSummary
            } else {
                Text("연결하면 이번 주 근무기록을 가져오고 이후 자동으로 동기화합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                weekSummaryCard(title: "주간 합계", value: viewModel.weekTotalText)
                weekSummaryCard(title: "남은 시간", value: viewModel.weekRemainingText, valueColor: viewModel.hasRemainingWeeklyWork ? .red : .primary)
            }
            if let notice = viewModel.weeklyCalculationNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelStyle()
    }

    private func flexActionButton(returningTo tab: WorkTab) -> some View {
        Button {
            if flex.connected && !flex.needsLogin {
                flex.readRecords()
            } else {
                flex.open(returningTo: tab)
            }
        } label: {
            if flex.isReading {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini)
                    Text("동기화 중")
                }
            } else if flex.needsLogin {
                Text("flex 다시 로그인")
            } else if flex.connected {
                Label("flex 동기화", systemImage: "arrow.clockwise")
            } else {
                Text("flex 연결")
            }
        }
        .font(.caption.weight(.regular))
        .disabled(flex.isReading || flex.isDisconnecting)
    }

    private var flexSyncSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(flex.autoSync ? "flex 자동 동기화" : "flex 연결됨", systemImage: "link")
                Spacer()
                if flex.isReading {
                    ProgressView().controlSize(.small)
                } else if let lastSync = flex.lastSync {
                    Text(lastSync, style: .time)
                }
            }
            if let title = flex.loginResultTitle {
                Text(title).fontWeight(.semibold).foregroundStyle(.primary)
            }
            Text(flex.message).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("상세 정보") {
                Text(flex.diagnostic).textSelection(.enabled)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // 오늘 근무 / 주간 시간 계산 탭 스위치
    private var tabPickerSection: some View {
        HStack(spacing: 10) {
            Picker("", selection: $viewModel.selectedTab) {
                ForEach(WorkTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 10)

            if flex.connected {
                Menu {
                    Toggle("자동 동기화", isOn: $flex.autoSync)
                    Button("연결 해제", role: .destructive) { flex.disconnect() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel("flex 설정")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(flex.isDisconnecting)
            }

            flexActionButton(returningTo: viewModel.selectedTab)
                .fixedSize()
        }
    }

    // 오늘 근무 탭 전체
    private var todayTabSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                targetHoursSelector

                Divider()

                timePickerRow(title: "출근 시간", selection: viewModel.startTimeBinding)
                    .font(.body.weight(.bold))
                timePickerRow(title: "퇴근 시간", selection: viewModel.endTimeBinding)
                    .font(.body.weight(.bold))

                if flex.connected || flex.needsLogin || flex.loginResultTitle != nil {
                    VStack(alignment: .leading, spacing: 3) {
                        if flex.needsLogin {
                            Text("flex에 다시 로그인해주세요.")
                        } else if flex.isReading {
                            Text("오늘 출근 시각을 동기화하고 있어요.")
                        } else if let syncedAt = flex.todaySyncedAt,
                                  !Calendar.current.isDateInToday(syncedAt) {
                            Text("오늘 출근 시각을 아직 동기화하지 않았어요.")
                        } else {
                            Text(flex.todaySyncMessage)
                            if let syncedAt = flex.todaySyncedAt {
                                HStack(spacing: 4) {
                                    Text("마지막 동기화")
                                    Text(syncedAt, style: .time)
                                }
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .panelStyle()

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("요약")
                VStack(alignment: .leading, spacing: 10) {
                    summaryLine(title: "목표 근무 시간", value: viewModel.formattedTargetWork)
                    summaryLine(title: "출근 시간", value: viewModel.formattedStartTime)
                    summaryLine(title: "퇴근 가능 시각", value: viewModel.formattedEndTime)
                    summaryLine(title: "오늘 총 근무시간", value: viewModel.formattedWorkedToday)
                    summaryLine(title: viewModel.remainingWorkLabel, value: viewModel.formattedRemainingToday, description: "(목표 근무시간까지 남은 시간 · 휴게시간 제외)")
                    summaryLine(title: "퇴근까지 남은 시간", value: viewModel.formattedRemainingDeparture, description: "(퇴근 가능 시각까지 남은 시간 · 휴게시간 및 코어타임 반영)")
                }
            }
            .panelStyle()
        }
    }

    // 목표 근무 시간 커스텀 세그먼트 버튼
    private var targetHoursSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Text("목표 근무 시간")
                    .font(.body.weight(.bold))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(TodayTargetSelection.allCases) { selection in
                        Button {
                            viewModel.todayTargetSelectionBinding.wrappedValue = selection
                        } label: {
                            Text(selection.title)
                                .font(.subheadline.weight(.semibold))
                                .frame(width: selection == .manual ? 60 : 44)
                                .padding(.vertical, 4)
                                .foregroundStyle(
                                    viewModel.todayTargetSelectionBinding.wrappedValue == selection
                                        ? Color.white
                                        : Color.primary.opacity(0.7)
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            viewModel.todayTargetSelectionBinding.wrappedValue == selection
                                                ? Color.accentColor
                                                : Color(nsColor: .quaternaryLabelColor).opacity(0.5)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(
                                            viewModel.todayTargetSelectionBinding.wrappedValue == selection
                                                ? Color.clear
                                                : Color(nsColor: .separatorColor).opacity(0.22),
                                            lineWidth: 0.8
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if viewModel.shouldShowManualTargetInputs {
                HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 12) {
                    manualField(title: "시간", text: viewModel.targetManualHoursBinding, disabled: false)
                    manualField(title: "분", text: viewModel.targetManualMinutesBinding, disabled: false)
                }

                    Spacer(minLength: 0)

                    if viewModel.canRestoreAutoSuggestedTarget {
                        Button("자동계산") {
                            viewModel.restoreAutoSuggestedTarget()
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.9))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(1), lineWidth: 0.9)
                        )
                        .buttonStyle(.plain)
                    }
                }
            }

            if viewModel.shouldShowTodayTargetGuideText, let guideText = viewModel.todayTargetGuideText {
                Text(guideText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // 주간 시간 계산 탭 전체
    private var weekTabSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { item in
                weekDayCard(index: item.offset)
            }
        }
        .padding(4)
    }

    // 하단 앱 종료 / 리셋 버튼
    private var footerSection: some View {
        HStack {
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("앱 종료", systemImage: "power")
                    .imageScale(.small)
            }
            .keyboardShortcut("q")
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: .systemGray))
            
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
            .buttonStyle(.borderedProminent)
            .tint(Color(nsColor: .systemGray))
        }
    }

    // 주간 합계 / 남은 시간 요약 아이템
    private func weekSummaryCard(title: String, value: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    // 월~금 각각의 주간 카드
    private func weekDayCard(index: Int) -> some View {
        let day = viewModel.weeklyDay(at: index)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text("\(day.day)요일")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.primary)
                if day.importedFromFlex {
                    Text("flex").font(.caption).foregroundStyle(.secondary)
                }
                if viewModel.isWeeklyAutoCalculated(at: index) {
                    Text("자동 계산")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 2)

                HStack(spacing: 6) {
                    borderlessMenuPicker(
                        selection: weeklyLeaveTypeBinding(index: index),
                        width: 76
                    ) { leaveType in
                        leaveType.title
                    }
                    
                    borderlessMenuPicker(
                        selection: weeklyModeBinding(index: index),
                        width: 66
                    ) { mode in
                        mode.title
                    }
                }
                .disabled(day.isConfirmed || day.lockStart || day.lockEnd || day.lockManual)

                if day.mode == .range && day.leaveType != .annual {
                    Menu {
                        Button(day.lockStart ? "출근 고정 해제" : "출근 고정") {
                            viewModel.toggleWeeklyLock(idx: index, field: .start)
                        }.disabled(day.start.isEmpty)
                        Button(day.lockEnd ? "퇴근 고정 해제" : "퇴근 고정") {
                            viewModel.toggleWeeklyLock(idx: index, field: .end)
                        }.disabled(day.end.isEmpty)
                    } label: {
                        Image(systemName: day.lockStart || day.lockEnd ? "pin.fill" : "pin")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(day.isConfirmed)
                    .accessibilityLabel("시간 고정")
                }

                Button {
                    viewModel.toggleWeeklyConfirmation(idx: index)
                } label: {
                    Image(systemName: day.isConfirmed ? "lock.fill" : "lock.open")
                }
                .buttonStyle(.plain)
                .foregroundStyle(day.isConfirmed ? Color.accentColor : Color.secondary)
                .disabled(!viewModel.canConfirmWeeklyDay(at: index))
                .accessibilityLabel(day.isConfirmed ? "기록 확정 해제" : "요일 기록 확정")
            }

            if day.leaveType != .annual {
                weeklyInputRow(day: day, index: index)
            } else {
                HStack {
                    Spacer()
                    Text("일 인정 시간: \(viewModel.weeklyDayRecognizedText(at: index))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colorScheme == .dark ? Color(white: 0.23) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.12), radius: 3, x: 0, y: 2)
    }

    // 주간 카드의 입력 행: 구간 입력 또는 합계 입력
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
                    .disabled(day.isLocked(.start))

                    Text("~")
                        .frame(width: 10, alignment: .center)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)

                    weeklyTimeSlotField(
                        timeText: day.end,
                        selection: weeklyEndDateBinding(index: index),
                        activate: { viewModel.updateWeeklyEnd(idx: index, value: "18:00") }
                    )
                    .disabled(day.isLocked(.end))
                }
            } else {
                HStack(spacing: 12) {
                    manualField(
                        title: "시간",
                        text: weeklyManualHoursBinding(index: index),
                        disabled: day.isLocked(.manual)
                    )
                    manualField(
                        title: "분",
                        text: weeklyManualMinutesBinding(index: index),
                        disabled: day.isLocked(.manual)
                    )
                }
            }

            Spacer(minLength: 4)

            Text("인정 \(viewModel.weeklyDayRecognizedText(at: index))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityLabel("일 인정 시간: \(viewModel.weeklyDayRecognizedText(at: index))")

            Button {
                viewModel.resetWeeklyDay(idx: index)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                    .padding(6)
            }
            .buttonStyle(.plain)
            .disabled(day.isConfirmed || day.lockStart || day.lockEnd || day.lockManual)
            .foregroundStyle(.tertiary) 
            .background(
                Circle() 
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.7))
            )
        }
    }

    // 주간 구간 입력 시간 슬롯
    @ViewBuilder
    private func weeklyTimeSlotField(timeText: String, selection: Binding<Date>, activate: @escaping () -> Void) -> some View {
        Group {
            if timeText.isEmpty {
                Button {
                    activate()
                } label: {
                    Text("-- -- --")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: 54, height: 24, alignment: .center)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 0) {
                    BorderlessTimePicker(selection: selection)
                        .frame(width: 88, height: 24)
                }
            }
        }
        // 공통 스타일 적용 (스타일 통일)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor)) 
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8) 
        )
    }

    // 주간 합계 입력 필드
    private func manualField(
        title: String,
        text: Binding<String>,
        disabled: Bool
    ) -> some View {
        HStack(spacing: 8) {
            TextField("0", text: text)
                .textFieldStyle(.plain)
                .frame(width: 28, alignment: .leading)
                .disabled(disabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(1), lineWidth: 0.8)
                )
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    // 공통 섹션 제목
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

    // 주간 탭의 정상근무 / 구간 셀렉트 박스
    private func borderlessMenuPicker<Option: CaseIterable & Hashable & Identifiable>(
        selection: Binding<Option>,
        width: CGFloat,
        title: @escaping (Option) -> String
    ) -> some View where Option.AllCases: RandomAccessCollection {
        Menu {
            ForEach(Array(Option.allCases), id: \.id) { option in
                Button(title(option)) {
                    selection.wrappedValue = option
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(title(selection.wrappedValue))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
            .frame(width: width)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5))
            )
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    // 오늘 탭의 출근 / 퇴근 시간 입력 행
    private func timePickerRow(title: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(title)
            if title == "출근 시간", viewModel.isStartTimeFromFlex {
                Text("flex").font(.caption).foregroundStyle(.secondary)
            }
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
                        .frame(width: 88, height: 24)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(1), lineWidth: 0.8)
                )
            }
        }
    }

    // 오늘 탭 요약 행
    private func summaryLine(title: String, value: String, description: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
            .font(.system(size: 13))
            if let description {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // 오늘 탭 비어 있는 시간 placeholder 표시 제어
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

    // 오늘 탭 placeholder 클릭 시 시간 입력 활성화
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

    // 주간 휴가 타입 바인딩
    private func weeklyLeaveTypeBinding(index: Int) -> Binding<LeaveType> {
        Binding(
            get: { viewModel.weeklyDay(at: index).leaveType },
            set: { viewModel.updateWeeklyLeaveType(idx: index, leaveType: $0) }
        )
    }

    // 주간 입력 모드(구간/합계) 바인딩
    private func weeklyModeBinding(index: Int) -> Binding<InputMode> {
        Binding(
            get: { viewModel.weeklyDay(at: index).mode },
            set: { _ in viewModel.toggleWeeklyMode(idx: index) }
        )
    }

    // 주간 시작 시간 Date 바인딩
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

    // 주간 종료 시간 Date 바인딩
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

    // 저장된 HH:mm 문자열을 DatePicker용 Date로 변환
    private func dateFromWeeklyTimeString(_ time: String, fallbackHour: Int, fallbackMinute: Int) -> Date {
        let minutes = time.isEmpty ? (fallbackHour * 60 + fallbackMinute) : timeToMinutes(time)
        let hour = minutes / 60
        let minute = minutes % 60
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    // DatePicker 값을 분 단위로 변환
    private func minutesFromDate(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        return hour * 60 + minute
    }

    // 주간 합계 입력 시간 바인딩
    private func weeklyManualHoursBinding(index: Int) -> Binding<String> {
        Binding(
            get: { viewModel.weeklyDay(at: index).manualHours },
            set: { viewModel.updateWeeklyManualHours(idx: index, value: $0) }
        )
    }

    // 주간 합계 입력 분 바인딩
    private func weeklyManualMinutesBinding(index: Int) -> Binding<String> {
        Binding(
            get: { viewModel.weeklyDay(at: index).manualMinutes },
            set: { viewModel.updateWeeklyManualMinutes(idx: index, value: $0) }
        )
    }
}

// 공통 패널 카드 스타일
private struct PanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8)) 
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5) 
            )
    }
}

// 오늘 탭 시간 입력용 borderless AppKit NSDatePicker
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

private extension View {
    func panelStyle() -> some View {
        modifier(PanelModifier())
    }
}
