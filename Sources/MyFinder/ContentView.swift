import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                BrowserToolbarView()
                Divider()
                BreadcrumbBar()
                Divider()
                FileActionBarView()
                Divider()
                FileListView()
                Divider()
                StatusBarView()
            }
            .frame(minWidth: 760, minHeight: 520)
        }
        .frame(minWidth: 940, minHeight: 580)
        .sheet(item: $browser.renameRequest) { request in
            RenameSheet(
                request: request,
                onCommit: { newName in
                    browser.rename(url: request.url, to: newName)
                },
                onCancel: {
                    browser.cancelRename()
                }
            )
        }
        .alert(
            "Action Failed",
            isPresented: Binding(
                get: { browser.errorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        browser.clearError()
                    }
                }
            )
        ) {
            Button("OK") {
                browser.clearError()
            }
        } message: {
            Text(browser.errorMessage ?? "")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var browser: FileBrowserViewModel
    @State private var isConnectServerPresented = false

    var body: some View {
        List {
            ForEach(browser.sidebarSections) { section in
                Section(section.title) {
                    ForEach(section.locations) { location in
                        Button {
                            browser.navigate(to: location.url)
                        } label: {
                            Label(location.title, systemImage: location.systemImageName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 3)
                        .contextMenu {
                            LocationContextMenu(location: location)
                        }
                    }
                }
            }

            Section("Network") {
                Button {
                    isConnectServerPresented = true
                } label: {
                    Label("Connect Server...", systemImage: "network")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)

                Button {
                    browser.refreshSidebarLocations()
                } label: {
                    Label("Refresh Locations", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
        .sheet(isPresented: $isConnectServerPresented) {
            ConnectServerSheet(
                onConnect: { address in
                    browser.connectToServer(address)
                    isConnectServerPresented = false
                },
                onCancel: {
                    isConnectServerPresented = false
                }
            )
        }
    }
}

struct BrowserToolbarView: View {
    @EnvironmentObject private var browser: FileBrowserViewModel
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ToolbarIconButton(systemImageName: "chevron.left", help: "Back") {
                browser.goBack()
            }
            .disabled(!browser.canGoBack)

            ToolbarIconButton(systemImageName: "chevron.right", help: "Forward") {
                browser.goForward()
            }
            .disabled(!browser.canGoForward)

            ToolbarIconButton(systemImageName: "arrow.up", help: "Up") {
                browser.goUp()
            }
            .disabled(!browser.canGoUp)

            ToolbarIconButton(systemImageName: "arrow.clockwise", help: "Reload") {
                browser.reload()
            }

            TextField("Path", text: $browser.addressText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isAddressFocused)
                .onSubmit {
                    browser.submitAddress()
                    isAddressFocused = false
                }

            Button {
                browser.submitAddress()
                isAddressFocused = false
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .help("Go")

            Toggle(isOn: $browser.showHiddenFiles) {
                Image(systemName: browser.showHiddenFiles ? "eye" : "eye.slash")
            }
            .toggleStyle(.button)
            .help("Show hidden files")

            ToolbarIconButton(systemImageName: "folder.badge.plus", help: "New Folder") {
                browser.createFolder()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct ToolbarIconButton: View {
    let systemImageName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImageName)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(help)
    }
}

struct BreadcrumbBar: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(browser.breadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                    Button {
                        browser.navigate(to: crumb.url)
                    } label: {
                        Text(crumb.title)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )

                    if index < browser.breadcrumbs.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .frame(height: 38)
    }
}

struct FileActionBarView: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    var body: some View {
        HStack(spacing: 8) {
            Picker("View", selection: $browser.viewMode) {
                Image(systemName: "list.bullet")
                    .tag(BrowserViewMode.list)

                Image(systemName: "square.grid.2x2")
                    .tag(BrowserViewMode.icons)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 92)
            .help("View mode")

            Divider()
                .frame(height: 22)

            ToolbarIconButton(systemImageName: "arrow.up", help: "Up") {
                browser.goUp()
            }
            .disabled(!browser.canGoUp)

            ToolbarIconButton(systemImageName: "folder.badge.plus", help: "New Folder") {
                browser.createFolder()
            }

            ToolbarIconButton(systemImageName: "doc.badge.plus", help: "New File") {
                browser.createFile()
            }

            ToolbarIconButton(systemImageName: "trash", help: "Move to Trash") {
                browser.trashSelection()
            }
            .disabled(browser.selectedIDs.isEmpty)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 42)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct FileListView: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    var body: some View {
        VStack(spacing: 0) {
            if browser.viewMode == .list {
                FileHeaderRow()
            }

            if browser.items.isEmpty {
                Spacer()
                Text("Empty Folder")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                switch browser.viewMode {
                case .list:
                    List(selection: $browser.selectedIDs) {
                        ForEach(browser.items) { item in
                            FileRow(item: item)
                                .tag(item.url)
                                .contextMenu {
                                    FileContextMenu(item: item)
                                }
                                .onTapGesture(count: 2) {
                                    browser.open(item)
                                }
                        }
                    }
                    .listStyle(.plain)
                case .icons:
                    FileIconGridView()
                }
            }
        }
        .contextMenu {
            FolderContextMenu()
        }
    }
}

struct FileIconGridView: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(browser.items) { item in
                    FileIconCell(item: item)
                        .contextMenu {
                            FileContextMenu(item: item)
                        }
                        .onTapGesture(count: 2) {
                            browser.selectedIDs = [item.url]
                            browser.open(item)
                        }
                        .onTapGesture {
                            browser.selectedIDs = [item.url]
                        }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct FileIconCell: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    let item: FileItem

    private var isSelected: Bool {
        browser.selectedIDs.contains(item.url)
    }

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: item.systemImageName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isDirectory ? .blue : .primary)
                .font(.system(size: 38))
                .frame(width: 52, height: 46)

            Text(item.displayName)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(width: 92, height: 34, alignment: .top)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: 108, height: 104)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

struct FileHeaderRow: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    var body: some View {
        HStack(spacing: 0) {
            HeaderCell(title: "Name", column: .name)
                .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)

            HeaderCell(title: "Modified", column: .modifiedAt)
                .frame(width: 180, alignment: .leading)

            HeaderCell(title: "Size", column: .size)
                .frame(width: 110, alignment: .trailing)

            HeaderCell(title: "Kind", column: .kind)
                .frame(width: 170, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct HeaderCell: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    let title: String
    let column: FileSortColumn

    var body: some View {
        Button {
            browser.sort(by: column)
        } label: {
            HStack(spacing: 4) {
                Text(title)

                if browser.sortColumn == column {
                    Image(systemName: browser.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: column == .size ? .trailing : .leading)
        }
        .buttonStyle(.plain)
    }
}

struct FileRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: item.systemImageName)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(item.isDirectory ? .blue : .primary)
                    .frame(width: 20)

                Text(item.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)

            Text(item.formattedModifiedAt)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            Text(item.formattedSize)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 110, alignment: .trailing)

            Text(item.kind)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 170, alignment: .leading)
        }
        .font(.system(size: 13))
        .frame(height: 28)
        .contentShape(Rectangle())
    }
}

struct FileContextMenu: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    let item: FileItem

    var body: some View {
        Button("Open") {
            browser.open(item)
        }

        Divider()

        Button("Rename") {
            browser.beginRename(item)
        }

        Button("Duplicate") {
            browser.duplicate(item)
        }

        Divider()

        Button("Copy") {
            browser.selectedIDs = [item.url]
            browser.copySelection()
        }

        Button("Cut") {
            browser.selectedIDs = [item.url]
            browser.cutSelection()
        }

        Button("Paste Into Folder") {
            browser.paste(into: item.url)
        }
        .disabled(!item.canNavigateInto)

        Divider()

        Button("Copy Path") {
            browser.copyPath(item)
        }

        Button("Reveal in Finder") {
            browser.revealInFinder(item)
        }

        Button("Open in Terminal") {
            browser.openInTerminal(item.url)
        }

        Button("Open in iTerm") {
            browser.openIniTerm(item.url)
        }
        .disabled(!browser.isITermAvailable)

        Divider()

        Button("Move to Trash") {
            browser.selectedIDs = [item.url]
            browser.trashSelection()
        }
    }
}

struct FolderContextMenu: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    var body: some View {
        Button("New Folder") {
            browser.createFolder()
        }

        Button("New File") {
            browser.createFile()
        }

        Divider()

        Button("Paste") {
            browser.pasteIntoCurrentFolder()
        }

        Divider()

        Button("Open in Terminal") {
            browser.openInTerminal(browser.currentURL)
        }

        Button("Open in iTerm") {
            browser.openIniTerm(browser.currentURL)
        }
        .disabled(!browser.isITermAvailable)

        Divider()

        Button("Copy Path") {
            browser.copyPath(browser.currentURL)
        }

        Button("Reveal in Finder") {
            browser.revealInFinder(browser.currentURL)
        }
    }
}

struct LocationContextMenu: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    let location: SidebarLocation

    var body: some View {
        Button("Open") {
            browser.navigate(to: location.url)
        }

        Divider()

        Button("Open in Terminal") {
            browser.openInTerminal(location.url)
        }

        Button("Open in iTerm") {
            browser.openIniTerm(location.url)
        }
        .disabled(!browser.isITermAvailable)

        Divider()

        Button("Copy Path") {
            browser.copyPath(location.url)
        }

        Button("Reveal in Finder") {
            browser.revealInFinder(location.url)
        }
    }
}

struct StatusBarView: View {
    @EnvironmentObject private var browser: FileBrowserViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("\(browser.items.count) items")

            if !browser.selectedIDs.isEmpty {
                Text("\(browser.selectedIDs.count) selected")
            }

            if let operation = browser.pendingClipboardOperation {
                Text(operation.mode == .cut ? "Cut ready" : "Copy ready")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(browser.currentURL.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct RenameSheet: View {
    let request: RenameRequest
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @FocusState private var isFocused: Bool

    init(
        request: RenameRequest,
        onCommit: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.request = request
        self.onCommit = onCommit
        self.onCancel = onCancel
        _name = State(initialValue: request.currentName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename")
                .font(.headline)

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    onCommit(name)
                }

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    onCommit(name)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 380)
        .onAppear {
            isFocused = true
        }
    }
}

struct ConnectServerSheet: View {
    let onConnect: (String) -> Void
    let onCancel: () -> Void

    @State private var address = "smb://"
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Server")
                .font(.headline)

            TextField("smb://server/share", text: $address)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .focused($isFocused)
                .onSubmit {
                    onConnect(address)
                }

            HStack {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Connect") {
                    onConnect(address)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 420)
        .onAppear {
            isFocused = true
        }
    }
}
