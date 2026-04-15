import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: TimeCalculatorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("시간 계산기")
                    .font(.title3.weight(.semibold))
                Text("메뉴바에서 바로 근무 시간을 계산할 수 있어요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("메뉴바 표시")
                        .font(.headline)

                    Picker("메뉴바 표시", selection: viewModel.menuBarDisplayModeBinding) {
                        Text("선택 안 함").tag(TimeCalculatorViewModel.MenuBarDisplayMode?.none)
                        menuBarDisplayModeOption(.totalWorkedToday)
                        menuBarDisplayModeOption(.remainingWorkToday)
                    }
                    .pickerStyle(.radioGroup)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("목표 근무 시간")
                        .font(.headline)

                    Picker("목표 근무 시간", selection: viewModel.targetHoursBinding) {
                        targetHourOption(6)
                        targetHourOption(7)
                        targetHourOption(8)
                        targetHourOption(9)
                    }
                    .pickerStyle(.segmented)
                }

                timePickerRow(title: "출근 시간", selection: viewModel.startTimeBinding)
                timePickerRow(title: "퇴근 시간", selection: viewModel.endTimeBinding)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                summaryLine("목표 근무 시간: \(viewModel.formattedTargetWork)")
                summaryLine("고정 휴게 시간: \(viewModel.fixedBreakDescription)")
                summaryLine("출근 시간: \(viewModel.formattedStartTime)")
                summaryLine("퇴근 시간: \(viewModel.formattedEndTime)")
                summaryLine("오늘 총 근무시간: \(viewModel.formattedWorkedToday)")
                summaryLine("오늘 남은 근무시간: \(viewModel.formattedRemainingToday)")
            }

            Divider()

            HStack {
                Button("앱 종료") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")

                Spacer()

                Text("메뉴바 표시: \(viewModel.menuBarTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private func timePickerRow(title: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DatePicker(
                "",
                selection: selection,
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
    }

    private func targetHourOption(_ hours: Int) -> some View {
        Text("\(hours)h").tag(hours)
    }

    private func menuBarDisplayModeOption(_ mode: TimeCalculatorViewModel.MenuBarDisplayMode) -> some View {
        Text(mode.label).tag(Optional(mode))
    }

    private func summaryLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
    }
}
