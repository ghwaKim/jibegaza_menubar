import SwiftUI

struct TodayMenuBarSettingsView: View {
    @EnvironmentObject private var viewModel: TimeCalculatorViewModel
    var body: some View {
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
}

struct TodayWorkView: View {
    @EnvironmentObject private var viewModel: TimeCalculatorViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                targetHoursSelector

                Divider()

                timePickerRow(title: "출근 시간", selection: viewModel.startTimeBinding)
                    .font(.body.weight(.bold))
                timePickerRow(title: "퇴근 시간", selection: viewModel.endTimeBinding)
                    .font(.body.weight(.bold))

                FlexTodayStatusView()
            }
            .panelStyle()

            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("요약")
                VStack(alignment: .leading, spacing: 10) {
                    summaryLine(title: "목표 근무 시간", value: viewModel.formattedTargetWork)
                    summaryLine(title: "출근 시간", value: viewModel.formattedStartTime)
                    summaryLine(title: "퇴근 가능 시각", value: viewModel.formattedEndTime)
                    summaryLine(title: "오늘 총 근무시간", value: viewModel.formattedWorkedToday)
                    summaryLine(
                        title: viewModel.remainingWorkLabel, value: viewModel.formattedRemainingToday,
                        description: "(목표 근무시간까지 남은 시간 · 휴게시간 제외)")
                    summaryLine(
                        title: "퇴근까지 남은 시간", value: viewModel.formattedRemainingDeparture,
                        description: "(퇴근 가능 시각까지 남은 시간 · 휴게시간 및 코어타임 반영)")
                }
            }
            .panelStyle()
        }
    }

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
                        ManualTimeField(title: "시간", text: viewModel.targetManualHoursBinding, disabled: false)
                        ManualTimeField(title: "분", text: viewModel.targetManualMinutesBinding, disabled: false)
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
    }

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
}
