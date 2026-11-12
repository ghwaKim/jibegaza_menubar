import AppKit
import SwiftUI

struct ManualTimeField: View {
    let title: String
    let text: Binding<String>
    let disabled: Bool
    var body: some View {
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
}

struct WeeklyTimeSlotField: View {
    let timeText: String
    let selection: Binding<Date>
    let activate: () -> Void
    var body: some View {
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
}

struct BorderlessMenuPicker<Option: CaseIterable & Hashable & Identifiable>: View
where Option.AllCases: RandomAccessCollection {
    let selection: Binding<Option>
    let width: CGFloat
    let title: (Option) -> String

    var body: some View {
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
struct BorderlessTimePicker: NSViewRepresentable {
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

extension View {
    func panelStyle() -> some View {
        modifier(PanelModifier())
    }
}
