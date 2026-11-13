import SwiftUI

struct FlexActionButton: View {
    @ObservedObject private var flex = FlexConnection.shared
    let returningTo: WorkTab
    var body: some View {
        Button {
            if flex.connected && !flex.needsLogin {
                flex.readRecords()
            } else {
                flex.open(returningTo: returningTo)
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
}

struct FlexSyncSummaryView: View {
    @ObservedObject private var flex = FlexConnection.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(flex.autoSync ? "flex 자동 동기화" : "자동 동기화 중지됨", systemImage: "link")
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
}

struct FlexTodayStatusView: View {
    @ObservedObject private var flex = FlexConnection.shared
    var body: some View {
        if flex.connected || flex.needsLogin || flex.loginResultTitle != nil {
            VStack(alignment: .leading, spacing: 3) {
                if flex.needsLogin {
                    Text("flex에 다시 로그인해주세요.")
                } else if flex.isReading {
                    Text("오늘 출근 시각을 동기화하고 있어요.")
                } else if let syncedAt = flex.todaySyncedAt,
                    !Calendar.current.isDateInToday(syncedAt)
                {
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
}
