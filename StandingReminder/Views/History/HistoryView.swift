import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum HistoryDisplayMode: String, CaseIterable, Identifiable {
    case hourGrid
    case timeline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hourGrid: "24 格"
        case .timeline: "时间轴"
        }
    }

    var symbolName: String {
        switch self {
        case .hourGrid: "rectangle.grid.1x2.fill"
        case .timeline: "timeline.selection"
        }
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: SessionController

    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var sessions: [WorkSession] = []
    @State private var editingSession: WorkSession?
    @State private var loadError: String?
    @State private var exportError: String?
    @AppStorage("historyDisplayMode") private var displayMode = HistoryDisplayMode.hourGrid

    var body: some View {
        TimelineView(.periodic(from: selectedDate, by: 30)) { context in
            let slices = TimelineCalculator.slices(
                for: sessions,
                on: selectedDate,
                now: context.date
            )
            let totals = TimelineCalculator.totals(for: slices)
            let hourGridRows = TimelineCalculator.hourGridRows(
                for: slices,
                on: selectedDate
            )

            ScrollView {
                VStack(spacing: 22) {
                    dateNavigator
                    displayModePicker

                    switch displayMode {
                    case .hourGrid:
                        DailyHourGridView(rows: hourGridRows, onSelect: selectSession)
                    case .timeline:
                        DailyTimelineView(
                            slices: slices,
                            date: selectedDate,
                            onSelect: selectSession
                        )
                    }

                    summaryView(totals: totals)

                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .padding(30)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear(perform: loadSessions)
        .onChange(of: selectedDate) { _, _ in loadSessions() }
        .onChange(of: controller.revision) { _, _ in loadSessions() }
        .sheet(item: $editingSession) { session in
            SessionEditSheet(session: session) {
                controller.sessionDidChangeExternally()
                loadSessions()
            }
        }
        .alert("导出失败", isPresented: exportErrorIsPresented) {
            Button("好", role: .cancel) {}
        } message: {
            Text(exportError ?? "未知错误")
        }
    }

    private var displayModePicker: some View {
        HStack {
            Spacer()

            Picker("历史显示模式", selection: $displayMode) {
                ForEach(HistoryDisplayMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbolName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)

            Spacer()
        }
    }

    private var dateNavigator: some View {
        HStack {
            Button {
                moveDay(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("前一天")

            Spacer()

            VStack(spacing: 4) {
                Text(selectedDate, format: .dateTime.year().month().day().weekday(.wide))
                    .font(.title2.weight(.bold))
                if Calendar.current.isDateInToday(selectedDate) {
                    Text("今天")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Button {
                    moveDay(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canMoveForward)
                .help("后一天")

                Divider()
                    .frame(height: 20)

                Button(action: exportExcel) {
                    Label("导出 Excel", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .help("导出全部工作状态记录")
            }
        }
    }

    private var exportErrorIsPresented: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { isPresented in
                if !isPresented {
                    exportError = nil
                }
            }
        )
    }

    private func summaryView(totals: [WorkState: TimeInterval]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("当日汇总")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(WorkState.allCases) { state in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(state.title, systemImage: state.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(state.color)
                        Text(durationText(totals[state, default: 0]))
                            .font(.title2.weight(.bold).monospacedDigit())
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(state.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private var canMoveForward: Bool {
        selectedDate < Calendar.current.startOfDay(for: .now)
    }

    private func moveDay(by offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        selectedDate = min(date, Calendar.current.startOfDay(for: .now))
    }

    private func loadSessions() {
        do {
            let descriptor = FetchDescriptor<WorkSession>(
                sortBy: [SortDescriptor(\WorkSession.startAt)]
            )
            sessions = try modelContext.fetch(descriptor)
            loadError = nil
        } catch {
            loadError = "读取记录失败：\(error.localizedDescription)"
        }
    }

    private func selectSession(_ sessionID: UUID) {
        editingSession = sessions.first { $0.id == sessionID && $0.endAt != nil }
    }

    private func exportExcel() {
        let panel = NSSavePanel()
        panel.title = "导出工作状态记录"
        panel.prompt = "导出"
        panel.nameFieldStringValue = defaultExportFileName
        panel.canCreateDirectories = true
        if let excelType = UTType(filenameExtension: "xlsx") {
            panel.allowedContentTypes = [excelType]
        }

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let workbook = try ExcelExporter.export(sessions: sessions)
            try workbook.write(to: destinationURL, options: .atomic)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var defaultExportFileName: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "StandingReminder-\(formatter.string(from: .now)).xlsx"
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let minutes = max(0, Int(duration) / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(hours)小时 \(remainder)分钟"
        }
        return "\(remainder)分钟"
    }
}
