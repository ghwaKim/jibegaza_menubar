import SwiftUI

struct WeeklySummaryView: View {
    @EnvironmentObject private var viewModel: TimeCalculatorViewModel
    @ObservedObject private var flex = FlexConnection.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("주간 시간 계산").font(.body.weight(.bold))
                    .fixedSize()
                Text(viewModel.weeklyDateRange).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let notice = viewModel.weekChangeNotice {
                Text(notice).font(.caption).foregroundStyle(.orange)
                Button("보관하고 이번 주 시작") { viewModel.archiveAndStartCurrentWeek() }
                Text("직전 보관 기록 1개를 유지합니다. 새로 보관하면 기존 보관 기록을 대체합니다.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let archive = viewModel.previousWeek {
                DisclosureGroup("보관 기록 · " + viewModel.previousWeekTitle) {
                    ForEach(Array(archive.data.enumerated()), id: \.offset) { _, day in
                        HStack {
                            Text(day.day + " · " + day.leaveType.title)
                            Spacer()
                            Text(formatMinutesToKorean(getDailyMinutes(day)))
                        }.font(.caption)
                    }
                    Text("보관 기록은 현재 주간 합계와 오늘 목표 계산에 포함되지 않습니다.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if flex.connected || flex.lastSync != nil {
                FlexSyncSummaryView()
            } else {
                Text("연결하면 이번 주 근무기록을 가져오고 이후 자동으로 동기화합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                weekSummaryCard(title: "주간 합계", value: viewModel.weekTotalText)
                weekSummaryCard(
                    title: "남은 시간", value: viewModel.weekRemainingText,
                    valueColor: viewModel.hasRemainingWeeklyWork ? .red : .primary)
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
}

struct WeeklyWorkView: View {

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(weekDays.enumerated()), id: \.offset) { item in
                WeeklyDayCard(index: item.offset)
            }
        }
        .padding(4)
    }
}
