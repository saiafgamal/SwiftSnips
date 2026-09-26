import SwiftUI
import SwiftSnipsCore

struct LibraryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var keyboard: KeyboardService
    @State private var search = ""

    private var filtered: [Snippet] {
        model.snippets.filter { search.isEmpty || $0.trigger.localizedCaseInsensitiveContains(search) || $0.replacement.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text(search.isEmpty ? "\(model.snippets.count) snippets" : "\(filtered.count) results")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                        if !search.isEmpty && filtered.isEmpty {
                            Text("No shortcuts match this search.")
                                .font(.callout).foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                        }
                        ForEach(filtered) { snippet in
                            Button { model.selectedID = snippet.id } label: {
                                sidebarRow(snippet)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12)
                                    .background(model.selectedID == snippet.id ? Color.accentColor.opacity(0.18) : .clear)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(model.selectedID == snippet.id ? .isSelected : [])
                        }
                    }
                }
                .id(search)
                Divider()
                HStack {
                    Button(action: model.add) { Image(systemName: "plus") }.help("New snippet")
                    Button { model.showDeleteConfirmation = true } label: { Image(systemName: "minus") }
                        .disabled(model.selectedID == nil).help("Delete selected snippet")
                    Spacer()

                }.buttonStyle(.borderless).padding(12)
            }
            .searchable(text: $search, prompt: "Find a snippet")
            .navigationSplitViewColumnWidth(min: 230, ideal: 265, max: 350)
        } detail: {
            GeometryReader { detail in
                VStack(spacing: 0) {
                    HealthView(model: model, keyboard: keyboard)
                    Divider()
                    if let snippet = model.snippets.first(where: { $0.id == model.selectedID }) {
                        SnippetEditor(snippet: model.drafts[snippet.id] ?? snippet, model: model).id(snippet.id)
                    } else if !search.isEmpty && filtered.isEmpty {
                        ContentUnavailableView {
                            Label("No matching shortcuts", systemImage: "magnifyingglass")
                        } description: {
                            Text("Try another search, or clear it to see all \(model.snippets.count) shortcuts.")
                        } actions: {
                            Button("Clear search") { search = "" }
                        }
                    } else {
                        ContentUnavailableView {
                            Label("Your shortcuts, your Mac", systemImage: "text.cursor")
                        } description: {
                            Text("Create a text or date shortcut. Shell commands are disabled.")
                        } actions: {
                            Button("New snippet", action: model.add)
                        }
                    }
                }
                .frame(width: detail.size.width, height: detail.size.height, alignment: .top)
            }
        }
        .frame(minWidth: 820, minHeight: 590)
        .onChange(of: search) { _, _ in
            if !filtered.contains(where: { $0.id == model.selectedID }) {
                model.selectedID = filtered.first?.id
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: model.add) { Label("New snippet", systemImage: "plus") }
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Toggle("Open at login", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                    Button("Recover keyboard listener", action: keyboard.recover).disabled(!keyboard.enabled)
                    Button("Open library folder") { NSWorkspace.shared.open(model.store.folder) }
                    Divider()
                    Button("Quit SwiftSnips") { NSApplication.shared.terminate(nil) }
                } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .alert("SwiftSnips", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK") { model.message = nil }
        } message: { Text(model.message ?? "") }
        .confirmationDialog("Delete this snippet?", isPresented: $model.showDeleteConfirmation) {
            Button("Delete snippet", role: .destructive, action: model.deleteSelected)
        } message: { Text("A copy of the library is kept in the Backups folder.") }
    }

    private func sidebarRow(_ snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(snippet.trigger).font(.system(.body, design: .monospaced).weight(.semibold))
                Spacer()
                if snippet.hasShell { Image(systemName: "terminal").foregroundStyle(.secondary) }
                if !snippet.enabled { Image(systemName: "pause.circle").foregroundStyle(.secondary) }
            }
            Text(snippet.replacement.replacingOccurrences(of: "\n", with: " "))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.vertical, 4)
    }
}

private struct HealthView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var keyboard: KeyboardService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: keyboard.state == "Ready" ? "checkmark.circle.fill" : "circle.dotted")
                    .font(.title2).foregroundStyle(keyboard.state == "Ready" ? .green : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(keyboard.state).font(.headline)
                    Text(keyboard.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if !keyboard.permissionGranted {
                    Button("Allow Accessibility", action: keyboard.requestPermission).buttonStyle(.borderedProminent)
                } else if keyboard.enabled {
                    Button("Pause") { keyboard.stop() }
                } else {
                    Button("Turn on", action: model.turnOn).disabled(model.snippets.isEmpty).buttonStyle(.borderedProminent)
                }
            }
            if keyboard.expansions > 0 {
                Text("\(keyboard.expansions) expansions this session · \(keyboard.recoveries) listener recoveries")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(20)
    }
}

private struct SnippetEditor: View {
    @State var snippet: Snippet
    @ObservedObject var model: AppModel
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
          ScrollView {
           VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Shortcut").font(.title2.weight(.semibold))
                Spacer()
                Toggle("Enabled", isOn: Binding(get: { snippet.enabled && !snippet.hasShell }, set: { snippet.enabled = $0 })).toggleStyle(.switch).controlSize(.small).disabled(snippet.hasShell)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Trigger").font(.headline)
                TextField("/shortcut", text: $snippet.trigger).textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("Expands as soon as you finish typing the trigger. Matching is case-sensitive.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Replacement").font(.headline)
                TextEditor(text: $snippet.replacement)
                    .font(.system(size: 14)).scrollContentBackground(.hidden)
                    .padding(8).background(.background)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    .frame(height: 250)
            }
            if !snippet.variables.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Variables").font(.headline)
                    ForEach($snippet.variables) { $variable in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("{{\(variable.name)}}").font(.system(.callout, design: .monospaced)).frame(width: 120, alignment: .leading)
                            TextField(variable.kind == .date ? "%Y-%m-%d" : "Shell command", text: $variable.value)
                                .textFieldStyle(.roundedBorder)
                            Text(variable.kind == .date ? "Date" : "Shell").font(.caption).foregroundStyle(.secondary).frame(width: 35)
                        }
                    }
                    if snippet.hasShell {
                        Text("This legacy shell snippet is blocked. SwiftSnips never executes commands. Create a text/date snippet to replace it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
           }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
          }
          Divider()
          HStack {
                Menu("Add variable") {
                    Button("Date") { addVariable(.date) }
                }.fixedSize()
                Spacer()
                if saved { Text("Saved").font(.callout).foregroundStyle(.secondary) }
                else if snippet != model.snippets.first(where: { $0.id == snippet.id }) {
                    Text("Unsaved changes").font(.callout).foregroundStyle(.secondary)
                }
                Button("Save shortcut") { model.save(snippet); saved = model.message == nil }
                    .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
          }.padding(20)
        }
        .onChange(of: snippet) { _, value in
            saved = false
            if value == model.snippets.first(where: { $0.id == value.id }) { model.drafts.removeValue(forKey: value.id) }
            else { model.drafts[value.id] = value }
        }
    }

    private func addVariable(_ kind: SnippetVariable.Kind) {
        var index = 1
        while snippet.variables.contains(where: { $0.name == "value\(index)" }) { index += 1 }
        let name = "value\(index)"
        snippet.variables.append(.init(name: name, kind: kind, value: kind == .date ? "%Y-%m-%d" : "printf 'Hello'"))
        snippet.replacement += "{{\(name)}}"
    }
}
