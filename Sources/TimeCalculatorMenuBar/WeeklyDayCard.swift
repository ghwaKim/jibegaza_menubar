import SwiftUI

struct WeeklyDayCard: View {
    @EnvironmentObject private var viewModel: TimeCalculatorViewModel
    @Environment(\.colorScheme) private var colorScheme
    let index: Int
    @State private var inputRevision = UUID()

    var body: some View {
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
                    BorderlessMenuPicker(
                        selection: weeklyLeaveTypeBinding(index: index),
                        width: 76
                    ) { leaveType in
                        leaveType.title
                    }

                    BorderlessMenuPicker(
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
                    .id(inputRevision)
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

    @ViewBuilder
    private func weeklyInputRow(day: DayWorkData, index: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if day.mode == .range {
                HStack(spacing: 10) {
                    WeeklyTimeSlotField(
                        timeText: day.start,
                        selection: weeklyStartDateBinding(index: index),
                        activate: { viewModel.updateWeeklyStart(idx: index, value: "09:00") }
                    )
                    .disabled(day.isLocked(.start))

                    Text("~")
                        .frame(width: 10, alignment: .center)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)

                    WeeklyTimeSlotField(
                        timeText: day.end,
                        selection: weeklyEndDateBinding(index: index),
                        activate: { viewModel.updateWeeklyEnd(idx: index, value: "18:00") }
                    )
                    .disabled(day.isLocked(.end))
                }
            } else {
                HStack(spacing: 12) {
                    ManualTimeField(
                        title: "시간",
                        text: weeklyManualHoursBinding(index: index),
                        disabled: day.isLocked(.manual)
                    )
                    ManualTimeField(
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
                // Invalidate the old editor before clearing the model. Its delayed
                // callbacks must not restore the text that Reset just removed.
                inputRevision = UUID()
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
        let revision = inputRevision
        return Binding(
            get: {
                dateFromWeeklyTimeString(
                    viewModel.weeklyDay(at: index).start,
                    fallbackHour: 9,
                    fallbackMinute: 0
                )
            },
            set: {
                guard revision == inputRevision else { return }
                viewModel.updateWeeklyStart(idx: index, value: minutesToTime(minutesFromDate($0)))
            }
        )
    }

    private func weeklyEndDateBinding(index: Int) -> Binding<Date> {
        let revision = inputRevision
        return Binding(
            get: {
                dateFromWeeklyTimeString(
                    viewModel.weeklyDay(at: index).end,
                    fallbackHour: 18,
                    fallbackMinute: 0
                )
            },
            set: {
                guard revision == inputRevision else { return }
                viewModel.updateWeeklyEnd(idx: index, value: minutesToTime(minutesFromDate($0)))
            }
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
        let revision = inputRevision
        return Binding(
            get: { viewModel.weeklyDay(at: index).manualHours },
            set: {
                guard revision == inputRevision else { return }
                viewModel.updateWeeklyManualHours(idx: index, value: $0)
            }
        )
    }

    private func weeklyManualMinutesBinding(index: Int) -> Binding<String> {
        let revision = inputRevision
        return Binding(
            get: { viewModel.weeklyDay(at: index).manualMinutes },
            set: {
                guard revision == inputRevision else { return }
                viewModel.updateWeeklyManualMinutes(idx: index, value: $0)
            }
        )
    }
}
