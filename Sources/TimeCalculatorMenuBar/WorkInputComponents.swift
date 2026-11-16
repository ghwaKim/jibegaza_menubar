import AppKit
import SwiftUI

enum WorkControlColors {
    static let disabledBackground = Color(nsColor: .quaternaryLabelColor).opacity(0.5)
}

struct ManualTimeField: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let text: Binding<String>
    let disabled: Bool
    var maximumDigits = 2
    var body: some View {
        HStack(spacing: 8) {
            NumericTimeInput(text: text, maximumDigits: maximumDigits)
                .frame(width: 28, alignment: .leading)
                .disabled(disabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(disabled || !isEnabled ? WorkControlColors.disabledBackground : Color(nsColor: .windowBackgroundColor))
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

/// Validate the field editor itself, including paste and IME input.
final class TimeDigitsFormatter: Formatter {
    let maximumDigits: Int

    init(maximumDigits: Int) {
        self.maximumDigits = maximumDigits
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func string(for obj: Any?) -> String? { obj as? String }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        guard accepts(string) else { return false }
        obj?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(_ partialString: String,
                                      newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
                                      errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        accepts(partialString)
    }

    func accepts(_ value: String) -> Bool {
        value.count <= maximumDigits && value.utf8.allSatisfy { (48...57).contains($0) }
    }
}

private struct NumericTimeInput: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    let maximumDigits: Int

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = "0"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.formatter = TimeDigitsFormatter(maximumDigits: maximumDigits)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.text = $text
        field.isEnabled = isEnabled
        if field.stringValue != text { field.stringValue = text }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            // Reflect model normalization (such as minutes capped at 59) while editing.
            let normalized = text.wrappedValue
            if field.stringValue != normalized {
                field.stringValue = normalized
                if let editor = field.currentEditor() {
                    editor.string = normalized
                    editor.selectedRange = NSRange(location: normalized.utf16.count, length: 0)
                }
            }
        }
    }
}

struct WeeklyTimeSlotField: View {
    @Environment(\.isEnabled) private var isEnabled
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
                .fill(isEnabled ? Color(nsColor: .windowBackgroundColor) : WorkControlColors.disabledBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.8)
        )
    }
}

struct BorderlessMenuPicker<Option: CaseIterable & Hashable & Identifiable>: View
where Option.AllCases: RandomAccessCollection {
    @Environment(\.isEnabled) private var isEnabled
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
                    .fill(isEnabled ? Color(nsColor: .windowBackgroundColor) : WorkControlColors.disabledBackground)
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
