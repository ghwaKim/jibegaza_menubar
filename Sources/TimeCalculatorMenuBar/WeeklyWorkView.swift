import SwiftUI

struct WeeklySummaryView: View {
    @EnvironmentObject private var viewModel: TimeCalculatorViewModel
    @ObservedObject private var flex = FlexConnection.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("주간 시간 계산").font(.body.weight(.bold))
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
