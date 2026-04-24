import SwiftUI
import UniformTypeIdentifiers

// Listens for mouse-up to clear dragging state when a drag ends without hitting a drop target.
// onEnd is stored as a @MainActor property so it never crosses an isolation boundary;
// only a weak self reference (Sendable) is captured by the NSEvent handler.
@MainActor
private final class DragObserver: ObservableObject {
    private var monitor: Any?
    private var onEnd: (() -> Void)?

    func begin(onEnd: @escaping () -> Void) {
        end()
        self.onEnd = onEnd
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            Task { @MainActor [weak self] in
                // Defer slightly so DropDelegate.performDrop runs first on a valid drop.
                try? await Task.sleep(for: .milliseconds(50))
                self?.fire()
            }
            return event
        }
    }

    private func fire() {
        onEnd?()
        end()
    }

    func end() {
        onEnd = nil
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

struct WidgetContainerView: View {
    @Binding var dashboard: Dashboard
    @Environment(ConfigService.self) private var configService
    @Environment(DashboardService.self) private var dashboardService
    @Environment(MetricsStore.self) private var metricsStore
    @State private var isAddingWidget = false
    @State private var configuringWidget: Widget? = nil
    @State private var draggingId: String? = nil
    @StateObject private var dragObserver = DragObserver()
    @State private var resizingId: String? = nil
    @State private var resizingStartHeight: Double = 0
    @State private var resizingDelta: Double = 0
    @State private var metricsExpanded = false

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
    }

    var body: some View {
        ScrollView {
            if dashboard.widgets.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(dashboard.widgets) { widget in
                            widgetCard(widget)
                                .gridCellColumns(widget.size == .full ? 2 : 1)
                                .opacity(draggingId == widget.id ? 0.4 : 1.0)
                                .animation(.easeInOut(duration: 0.15), value: draggingId)
                        }
                    }
                    metricsSection
                }
                .padding(20)
            }
        }
        .navigationTitle(dashboard.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAddingWidget = true
                } label: {
                    Label("Add Widget", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isAddingWidget) {
            AddWidgetSheet(dashboard: $dashboard)
                .environment(configService)
                .environment(dashboardService)
        }
        .sheet(item: $configuringWidget) { widget in
            WidgetConfigView(widget: widget, dashboard: $dashboard)
                .environment(configService)
                .environment(dashboardService)
        }
    }

    @ViewBuilder
    private func widgetCard(_ widget: Widget) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            widgetHeader(widget)
            Divider()
            widgetBody(widget)
            resizeHandle(widget)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .onDrag {
            let id = widget.id
            draggingId = id
            dragObserver.begin {
                // If performDrop already cleared draggingId, this is a no-op.
                if draggingId == id { draggingId = nil }
            }
            return NSItemProvider(object: id as NSString)
        }
        .onDrop(
            of: [UTType.text],
            delegate: WidgetDropDelegate(
                targetId: widget.id,
                widgets: dashboard.widgets,
                draggingId: $draggingId,
                move: { dashboardService.moveWidget(in: dashboard, from: $0, to: $1) }
            )
        )
    }

    @ViewBuilder
    private func widgetHeader(_ widget: Widget) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.system(size: 11))
            Label(widgetTitle(widget), systemImage: widgetIcon(widget.type))
                .font(.subheadline.bold())
            Spacer()
            Menu {
                Button("Configure…") { configuringWidget = widget }
                Divider()
                Button("Delete", role: .destructive) {
                    dashboardService.deleteWidget(widget, from: dashboard)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func widgetBody(_ widget: Widget) -> some View {
        Group {
            switch widget.config {
            case .velocity(let cfg):
                VelocityWidgetView(config: cfg, widgetId: widget.id)
                    .environment(configService)
            case .burndown(let cfg):
                BurndownWidgetView(config: cfg, widgetId: widget.id)
                    .environment(configService)
            case .projectBurnRate(let cfg):
                ProjectBurnRateWidgetView(config: cfg, widgetId: widget.id)
                    .environment(configService)
            }
        }
        .frame(minHeight: effectiveHeight(for: widget))
    }

    // MARK: - Metrics Section

    @ViewBuilder
    private var metricsSection: some View {
        let metricEntries = metricsStore.ordered(for: dashboard.widgets.map(\.id))
        if !metricEntries.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { metricsExpanded.toggle() }
                } label: {
                    HStack {
                        Label("Dashboard Metrics", systemImage: "chart.bar.doc.horizontal")
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: metricsExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if metricsExpanded {
                    Divider()
                    let cols = min(metricEntries.count, 3)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: cols),
                        spacing: 12
                    ) {
                        ForEach(metricEntries) { entry in
                            MetricsCardView(entry: entry)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
    }

    @ViewBuilder
    private func resizeHandle(_ widget: Widget) -> some View {
        HStack {
            Spacer()
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .frame(height: 14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    if resizingId != widget.id {
                        resizingId = widget.id
                        resizingStartHeight = widget.customHeight ?? 260
                        resizingDelta = 0
                    }
                    resizingDelta = value.translation.height
                }
                .onEnded { _ in
                    let newHeight = max(160, resizingStartHeight + resizingDelta)
                    var updated = widget
                    updated.customHeight = newHeight
                    dashboardService.updateWidget(updated, in: dashboard)
                    resizingId = nil
                    resizingDelta = 0
                }
        )
        .onHover { isHovering in
            if isHovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
    }

    private func effectiveHeight(for widget: Widget) -> Double {
        let base = widget.customHeight ?? 260
        guard resizingId == widget.id else { return base }
        return max(160, base + resizingDelta)
    }

    private func widgetIcon(_ type: WidgetType) -> String {
        switch type {
        case .velocity: return "chart.bar.fill"
        case .burndown: return "chart.line.downtrend.xyaxis"
        case .projectBurnRate: return "chart.xyaxis.line"
        }
    }

    private func widgetTitle(_ widget: Widget) -> String {
        switch widget.config {
        case .velocity(let cfg): return cfg.displayTitle
        case .burndown(let cfg): return cfg.boardName
        case .projectBurnRate(let cfg): return cfg.projectName
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Widgets", systemImage: "square.dashed")
        } description: {
            Text("Add a widget to start tracking your team's metrics.")
        } actions: {
            Button("Add Widget") { isAddingWidget = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Metrics Card

private struct MetricsCardView: View {
    let entry: MetricsStore.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(entry.title, systemImage: iconFor(entry.widgetType))
                .font(.caption.bold())
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Divider()

            ForEach(entry.metrics) { metric in
                HStack {
                    Image(systemName: metric.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(metric.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(metric.value)
                        .font(.system(size: 11, weight: .semibold))
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }

    private func iconFor(_ type: WidgetType) -> String {
        switch type {
        case .velocity: return "chart.bar.fill"
        case .burndown: return "chart.line.downtrend.xyaxis"
        case .projectBurnRate: return "chart.xyaxis.line"
        }
    }
}

// MARK: - Drop delegate

struct WidgetDropDelegate: DropDelegate {
    let targetId: String
    let widgets: [Widget]
    let draggingId: Binding<String?>
    let move: (IndexSet, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingId.wrappedValue != nil && draggingId.wrappedValue != targetId
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let fromId = draggingId.wrappedValue,
              fromId != targetId,
              let fromIdx = widgets.firstIndex(where: { $0.id == fromId }),
              let toIdx = widgets.firstIndex(where: { $0.id == targetId })
        else {
            draggingId.wrappedValue = nil
            return false
        }
        withAnimation {
            move(IndexSet(integer: fromIdx), toIdx > fromIdx ? toIdx + 1 : toIdx)
        }
        draggingId.wrappedValue = nil
        return true
    }
}

// MARK: - Add widget sheet

struct AddWidgetSheet: View {
    @Binding var dashboard: Dashboard
    @Environment(ConfigService.self) private var configService
    @Environment(DashboardService.self) private var dashboardService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: WidgetType = .velocity
    @State private var size: WidgetSize = .full
    @State private var selectedBoard: JiraBoard? = nil
    @State private var projectName = "My Project"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Widget").font(.headline)

            Picker("Type", selection: $selectedType) {
                ForEach(WidgetType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedType) { _, newType in
                selectedBoard = nil
                size = newType == .velocity ? .full : .half
            }

            Text(selectedType.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Size", selection: $size) {
                ForEach(WidgetSize.allCases, id: \.self) { s in
                    Text(s.displayName).tag(s)
                }
            }
            .pickerStyle(.segmented)

            if selectedType == .projectBurnRate {
                TextField("Project name", text: $projectName)
                    .textFieldStyle(.roundedBorder)
            } else {
                BoardSearchField(selectedBoard: $selectedBoard)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { addWidget(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedType != .projectBurnRate && selectedBoard == nil)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func addWidget() {
        let config: WidgetConfig
        switch selectedType {
        case .velocity:
            guard let board = selectedBoard else { return }
            config = .velocity(VelocityConfig(boardId: board.id, boardName: board.name))
        case .burndown:
            guard let board = selectedBoard else { return }
            config = .burndown(BurndownConfig(boardId: board.id, boardName: board.name))
        case .projectBurnRate:
            config = .projectBurnRate(ProjectBurnRateConfig(projectName: projectName))
        }
        dashboardService.addWidget(Widget(type: selectedType, size: size, config: config), to: dashboard)
    }
}
