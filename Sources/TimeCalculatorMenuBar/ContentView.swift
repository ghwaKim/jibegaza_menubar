import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var viewModel: TimeCalculatorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            controlsSection
            summarySection
            footerSection
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("근무 시간 계산기")
                .font(.title3.weight(.semibold))

            HStack(spacing: 0) {
                Text("주간 근무 시간 계산기 👉 ")
                    .foregroundStyle(.secondary)
                Link(
                    "https://jibegaza.vercel.app/",
                    destination: URL(string: "https://jibegaza.vercel.app/")!
                )
            }
            .font(.subheadline)
        }
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("계산 설정")

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("메뉴바 표시")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker("메뉴바 표시", selection: viewModel.menuBarDisplayModeBinding) {
                        Text("선택 안 함").tag(TimeCalculatorViewModel.MenuBarDisplayMode?.none)
                        menuBarDisplayModeOption(TimeCalculatorViewModel.MenuBarDisplayMode.totalWorkedToday)
                        menuBarDisplayModeOption(TimeCalculatorViewModel.MenuBarDisplayMode.remainingWorkToday)
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("목표 근무 시간")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Picker("목표 근무 시간", selection: viewModel.targetHoursBinding) {
                        targetHourOption(6)
                        targetHourOption(7)
                        targetHourOption(8)
                        targetHourOption(9)
                    }
                    .pickerStyle(.segmented)
                }

                Divider()

                timePickerRow(title: "출근 시간", selection: viewModel.startTimeBinding)
                timePickerRow(title: "퇴근 시간", selection: viewModel.endTimeBinding)
            }
        }
        .cardStyle()
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("요약")

            VStack(alignment: .leading, spacing: 10) {
                summaryLine(title: "목표 근무 시간", value: viewModel.formattedTargetWork)
                summaryLine(title: "고정 휴게 시간", value: viewModel.fixedBreakDescription)
                summaryLine(title: "출근 시간", value: viewModel.formattedStartTime)
                summaryLine(title: "퇴근 시간", value: viewModel.formattedEndTime)
                summaryLine(title: "오늘 총 근무시간", value: viewModel.formattedWorkedToday)
                summaryLine(title: "오늘 남은 근무시간", value: viewModel.formattedRemainingToday)
            }
        }
        .cardStyle()
    }

    private var footerSection: some View {
        HStack(alignment: .center) {
            Button("앱 종료") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .buttonStyle(.bordered)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("메뉴바 표시")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("\(viewModel.menuBarIcon) \(viewModel.menuBarTitle)")
                    .font(.caption.weight(.medium))
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
                .font(.body)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    private func targetHourOption(_ hours: Int) -> some View {
        Text("\(hours)h").tag(hours)
    }

    private func menuBarDisplayModeOption(_ mode: TimeCalculatorViewModel.MenuBarDisplayMode) -> some View {
        Text("\(mode.icon) \(mode.label)").tag(Optional(mode))
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
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.6)
            )
    }
}

private extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
