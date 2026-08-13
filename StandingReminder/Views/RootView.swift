import SwiftUI

struct RootView: View {
    @EnvironmentObject private var controller: SessionController

    var body: some View {
        Group {
            switch controller.selectedSection {
            case .record:
                RecordView()
            case .history:
                HistoryView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 520, idealHeight: 620)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("页面", selection: $controller.selectedSection) {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.symbolName)
                            .labelStyle(.titleAndIcon)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
        }
        .alert("出现问题", isPresented: errorBinding) {
            Button("好") { controller.dismissError() }
        } message: {
            Text(controller.errorMessage ?? "未知错误")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.dismissError() } }
        )
    }
}
