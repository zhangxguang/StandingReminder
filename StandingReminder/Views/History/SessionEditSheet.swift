import SwiftData
import SwiftUI

struct SessionEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let session: WorkSession
    let onChange: () -> Void

    @State private var state: WorkState
    @State private var startAt: Date
    @State private var endAt: Date
    @State private var validationMessage: String?
    @State private var showsDeleteConfirmation = false

    init(session: WorkSession, onChange: @escaping () -> Void) {
        self.session = session
        self.onChange = onChange
        _state = State(initialValue: session.state)
        _startAt = State(initialValue: session.startAt)
        _endAt = State(initialValue: session.endAt ?? session.lastHeartbeatAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("编辑记录")
                .font(.title2.weight(.bold))

            Picker("状态", selection: $state) {
                ForEach(WorkState.allCases) { state in
                    Label(state.title, systemImage: state.symbolName)
                        .tag(state)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                GridRow {
                    Text("开始时间")
                    DatePicker("开始时间", selection: $startAt)
                        .labelsHidden()
                }
                GridRow {
                    Text("结束时间")
                    DatePicker("结束时间", selection: $endAt)
                        .labelsHidden()
                }
            }

            if let validationMessage {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Button("删除记录", role: .destructive) {
                    showsDeleteConfirmation = true
                }

                Spacer()

                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 430)
        .confirmationDialog("确定删除这条记录？", isPresented: $showsDeleteConfirmation) {
            Button("删除", role: .destructive) { deleteSession() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private func save() {
        guard endAt > startAt else {
            validationMessage = "结束时间必须晚于开始时间。"
            return
        }

        let allSessions: [WorkSession]
        do {
            allSessions = try modelContext.fetch(FetchDescriptor<WorkSession>())
        } catch {
            validationMessage = "读取其他记录失败，未保存修改：\(error.localizedDescription)"
            return
        }
        guard !TimelineCalculator.overlaps(
            start: startAt,
            end: endAt,
            excluding: session.id,
            sessions: allSessions
        ) else {
            validationMessage = "该时间段与其他记录重叠。"
            return
        }

        session.state = state
        session.startAt = startAt
        session.endAt = endAt
        session.lastHeartbeatAt = endAt
        session.isSystemGeneratedRest = false

        do {
            try modelContext.save()
            onChange()
            dismiss()
        } catch {
            modelContext.rollback()
            validationMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func deleteSession() {
        modelContext.delete(session)
        do {
            try modelContext.save()
            onChange()
            dismiss()
        } catch {
            modelContext.rollback()
            validationMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}
