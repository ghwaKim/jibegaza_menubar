import SwiftUI
import WebKit

struct FlexBrowser: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct FlexConnectionView: View {
    @ObservedObject var connection: FlexConnection
    let webView: WKWebView

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("flex 연결").font(.headline)
                    Text(connection.message).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if connection.isReading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("연결 확인") { connection.readRecords() }
                }
            }
            .padding(16)
            Divider()
            FlexBrowser(webView: webView)
        }
        .frame(minWidth: 680, minHeight: 540)
    }
}
