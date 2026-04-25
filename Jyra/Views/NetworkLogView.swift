import SwiftUI

struct NetworkLogView: View {
    var logger = NetworkLogger.shared
    @State private var selectedId: UUID? = nil
    @State private var errorsOnly = false
    @State private var searchText = ""

    private var filtered: [NetworkLogger.Entry] {
        logger.entries.filter { e in
            (searchText.isEmpty || e.url.localizedCaseInsensitiveContains(searchText)) &&
            (!errorsOnly || !e.isSuccess)
        }
    }

    private var selected: NetworkLogger.Entry? {
        guard let id = selectedId else { return nil }
        return filtered.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            listPane
            if let entry = selected {
                detailPane(entry)
            } else {
                Text("Select a request to inspect")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Toggle("Errors only", isOn: $errorsOnly)
                    .toggleStyle(.checkbox)

                Divider()

                Toggle(isOn: Binding(
                    get: { logger.isEnabled },
                    set: { logger.isEnabled = $0 }
                )) {
                    Label("Logging", systemImage: logger.isEnabled ? "record.circle.fill" : "record.circle")
                }
                .tint(.red)

                Button("Clear", systemImage: "trash") {
                    logger.clear()
                    selectedId = nil
                }
                .disabled(logger.entries.isEmpty)
            }
        }
        .searchable(text: $searchText, prompt: "Filter by URL")
        .navigationTitle("Network Log")
        .frame(minWidth: 900, minHeight: 500)
    }

    // MARK: - List

    private var listPane: some View {
        Table(filtered, selection: $selectedId) {
            TableColumn("") { e in
                Circle()
                    .fill(statusColor(e))
                    .frame(width: 7, height: 7)
            }
            .width(14)

            TableColumn("Method") { e in
                Text(e.method)
                    .font(.system(.caption, design: .monospaced).bold())
                    .foregroundStyle(statusColor(e))
            }
            .width(50)

            TableColumn("Status") { e in
                if let code = e.statusCode {
                    Text("\(code)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(statusColor(e))
                } else if e.error != nil {
                    Text("ERR")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
            .width(46)

            TableColumn("Path") { e in
                Text(e.shortURL)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
            }

            TableColumn("Duration") { e in
                Text(e.durationText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(64)

            TableColumn("Time") { e in
                Text(e.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .width(70)
        }
        .frame(minWidth: 380)
    }

    // MARK: - Detail

    @ViewBuilder
    private func detailPane(_ e: NetworkLogger.Entry) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerSection(e)
                if let err = e.error { bodySection("Error", text: err, color: .red) }
                if let req = e.requestBody { bodySection("Request Body", text: req, color: .blue) }
                if let res = e.responseBody { bodySection("Response Body", text: res, color: e.isSuccess ? .green : .orange) }
            }
            .padding(16)
        }
        .frame(minWidth: 380)
    }

    private func headerSection(_ e: NetworkLogger.Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(e.method)
                    .font(.headline.monospaced())
                    .foregroundStyle(statusColor(e))
                if let code = e.statusCode {
                    Text("\(code)")
                        .font(.headline.monospaced())
                        .foregroundStyle(statusColor(e))
                }
                Text(e.durationText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(e.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(e.url)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.primary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func bodySection(_ title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(color)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.25)))
        }
    }

    // MARK: - Helpers

    private func statusColor(_ e: NetworkLogger.Entry) -> Color {
        if e.error != nil { return .red }
        guard let code = e.statusCode else { return .secondary }
        switch code {
        case 200..<300: return .green
        case 300..<400: return .blue
        case 400..<500: return .orange
        default:        return .red
        }
    }
}
