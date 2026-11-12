import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject private var updater = AppUpdater.shared
    @ObservedObject private var flex = FlexConnection.shared
    @EnvironmentObject private var viewModel: TimeCalculatorViewModel

    private var appVersionText: String {
        Bundle.main.object(forInfoDictionaryKey: "JibegazaDisplayVersion") as? String
            ?? "(Local beta)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if WeekRolloverPreview.isEnabled {
                Text("주차 전환 테스트 · 실제 기록과 분리된 샘플")
                    .font(.caption).foregroundStyle(.orange)
            }
            headerSection
            tabPickerSection
            topControlSection

            Group {
                switch viewModel.selectedTab {
                case .today:
                    TodayWorkView()
                case .week:
                    WeeklyWorkView()
                }
            }

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
            Button(updater.buttonTitle) { updater.checkForUpdates() }
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

    private var topControlSection: some View {
        Group {
            switch viewModel.selectedTab {
            case .today:
                TodayMenuBarSettingsView()
            case .week:
                WeeklySummaryView()
            }
        }
    }

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
                .disabled(flex.isDisconnecting || WeekRolloverPreview.isEnabled)
            }

            FlexActionButton(returningTo: viewModel.selectedTab)
                .fixedSize()
                .disabled(WeekRolloverPreview.isEnabled)
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

}
