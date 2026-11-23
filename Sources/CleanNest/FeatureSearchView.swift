import SwiftUI
import CleanNestCore

struct FeatureSearchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    private var results: [FeatureDestination] { FeatureDirectory.search(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("查找功能").font(.title2.weight(.semibold))
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("例如：重复文件、模型、权限、温度…", text: $query)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .focused($searchFocused)
                .accessibilityLabel("搜索功能")
                .onSubmit { if let first = results.first { open(first) } }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(results) { destination in
                        Button { open(destination) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: destination.symbol)
                                    .foregroundStyle(CNTheme.accent).frame(width: 24)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(CNL10n.string(destination.title)).font(.headline).foregroundStyle(.primary)
                                    Text(CNL10n.string(destination.detail)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                            }
                            .padding(11).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(CNL10n.string(destination.title))
                        .accessibilityHint(CNL10n.string(destination.detail))
                    }
                    if results.isEmpty {
                        VStack(spacing: 10) {
                            Text("没有找到相关功能").font(.headline)
                            Text("换个关键词，或清空搜索查看全部功能。").foregroundStyle(.secondary)
                            Button("显示全部功能") { query = ""; searchFocused = true }
                        }.frame(maxWidth: .infinity).padding(30)
                    }
                }
            }
            Text("回车打开第一个结果 · 这里只导航，不执行清理或启停操作")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(width: 580, height: 550)
        .onAppear { searchFocused = true }
    }

    private func open(_ destination: FeatureDestination) {
        guard let page = SidebarItem(rawValue: destination.page) else { return }
        if let settings = destination.settingsSection { store.openSettings(settings) }
        else { store.selection = page }
        dismiss()
    }
}
