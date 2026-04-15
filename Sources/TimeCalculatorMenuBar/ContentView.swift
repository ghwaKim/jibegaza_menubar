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
        HStack(spacing: 0) {
            HStack(spacing: 24) {
                Text("🏡")
                Text("🏃‍♂️💨")
            }

            Spacer()

            HStack(spacing: 0) {
                Text("Weekly 👉 ")
                    .foregroundStyle(.secondary)
                Link(
                    "jibegaza.vercel.app",
                    destination: URL(string: "https://jibegaza.vercel.app/")!
                )
            }
        }
        .font(.headline.weight(.medium))
    }

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 16) {
                    Text("메뉴바 설정")
                        .font(.body.weight(.bold))

                    Picker("", selection: viewModel.menuBarDisplayModeBinding) {
                        menuBarDisplayModeOption(TimeCalculatorViewModel.MenuBarDisplayMode.totalWorkedToday)
                        menuBarDisplayModeOption(TimeCalculatorViewModel.MenuBarDisplayMode.remainingWorkToday)
                    }
                    .pickerStyle(.radioGroup)
                }

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    // Text("목표 근무 시간")
                    //     .font(.subheadline.weight(.semibold))
                    //     .foregroundStyle(.secondary)

                    Picker("목표 근무 시간", selection: viewModel.targetHoursBinding) {
                        targetHourOption(6)
                        targetHourOption(7)
                        targetHourOption(8)
                        targetHourOption(9)
                    }
                    .font(.body.weight(.bold))
                    .pickerStyle(.segmented)
                }

                Divider()

                timePickerRow(title: "출근 시간", selection: viewModel.startTimeBinding)
                    .font(.body.weight(.bold))
                timePickerRow(title: "퇴근 시간", selection: viewModel.endTimeBinding)
                    .font(.body.weight(.bold))
            }
        }
        .cardStyle()
    }

    private var summarySection: some View {
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
        .cardStyle()
    }

    private var footerSection: some View {
        HStack(alignment: .center) {
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
                viewModel.resetMenuBarAndTimes()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
                .imageScale(.small)
            }
            .buttonStyle(.bordered)
            .tint(Color(nsColor: .systemGray))
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
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            } else {
                DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
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
