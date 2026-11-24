import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

private enum ClassicFolderRoute: Hashable {
    case personal(TaskScope)
    case shared(UUID)

    var isShared: Bool {
        if case .shared = self { return true }
        return false
    }

    var orderKey: String {
        switch self {
        case .personal(.tag(let id)): "personal-" + id.uuidString
        case .shared(let id): "shared-" + id.uuidString
        case .personal: "all-tasks"
        }
    }
}

private struct ClassicFolderInfo {
    let route: ClassicFolderRoute
    let title: String
    let tint: Color
    let icon: String
}

/// Keeps the collection mounted so a folder returns to its actual position, even after scrolling.
struct ClassicFoldersView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var completionFigureSize = 36
    @Query(sort: [SortDescriptor(\Tag.sortOrder), SortDescriptor(\Tag.createdAt)]) private var tags: [Tag]
    @Query private var tasks: [TaskItem]
    @Binding var isCaptureActive: Bool
    @Binding var captureTag: Tag?
    @Binding var sharedCaptureListID: UUID?
    @Binding var isFolderOpen: Bool
    @Binding var isFolderClosing: Bool
    var captureBottomInset: CGFloat = 88
    var homeRequest: Int = 0

    @AppStorage("monotask_classic_folder_order") private var folderOrder = ""
    @State private var folderPath: [ClassicFolderRoute] = []
    #if os(macOS)
    private let folderArtworkWidth: CGFloat = 168
    @GestureState private var isDraggingFolder = false
    @State private var tileFrames: [ClassicFolderRoute: CGRect] = [:]
    @State private var gridFrame: CGRect = .zero
    @State private var folderDrag: FolderDragSession?
    @State private var folderScrollPosition = ScrollPosition()
    @State private var folderScrollMetrics = FolderScrollMetrics(offset: 0, limit: 0, height: 0)
    #else
    private let folderArtworkWidth: CGFloat = 188
    @State private var folderVisibility = FolderVisibility()
    @State private var nativeFolderDragActive = false
    #endif
    @Namespace private var folderZoom
    @State private var sharedStore = SharedListStore.shared
    @State private var addingFolder = false
    @State private var pendingSharedFolderID: UUID?
    @State private var editingFolder: Tag?
    @State private var deletingFolder: ClassicFolderRoute?
    @State private var folderDeletionError: String?
    @State private var managingSharedFolder: SharedList?
    @State private var today = Date.now.startOfDay

    #if os(macOS)
    private var displayedFolders: [ClassicFolderRoute] {
        guard let folderDrag else { return orderedFolders }
        let available = Set(orderedFolders)
        return folderDrag.order.filter { available.contains($0) }
            + orderedFolders.filter { !folderDrag.order.contains($0) }
    }
    #endif
    private var selectedFolder: ClassicFolderRoute? { folderPath.last }

    private var visibleTasks: [TaskItem] {
        tasks.filter { !TaskDeletionManager.shared.isPending($0) }
    }

    private var orderedFolders: [ClassicFolderRoute] {
        var defaults: [ClassicFolderRoute] = [.personal(.all)] + tags.map { .personal(.tag($0.id)) }
        defaults += sharedStore.lists.map { .shared($0.id) }

        var remaining = Dictionary(uniqueKeysWithValues: defaults.map { ($0.orderKey, $0) })
        let saved = folderOrder.split(separator: ",").compactMap {
            remaining.removeValue(forKey: String($0))
        }
        let ordered = saved + defaults.filter { remaining[$0.orderKey] != nil }
        return [.personal(.all)] + ordered.filter { $0 != .personal(.all) }
    }

    var body: some View {
        NavigationStack(path: $folderPath) {
            folderCollection
                #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
                #endif
                .navigationDestination(for: ClassicFolderRoute.self) { route in
                    folderDestination(route)
                }
                #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Приоритет", systemImage: "star") {
                        open(.personal(.highPriority))
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Синхронизировать", systemImage: "arrow.triangle.2.circlepath") {
                        NotificationCenter.default.post(name: .macTriggerSync, object: nil)
                    }
                    .help("Синхронизировать (⌘R)")
                    .disabled(SupabaseService.shared.syncStatus.isSyncing)
                }
            }
            #endif
        }
        .background(Theme.Colors.background)
        .sheet(isPresented: $addingFolder, onDismiss: openPendingSharedFolder) {
            TagEditSheet(tagToEdit: nil, allowsSharedCreation: true, onOpenShared: { pendingSharedFolderID = $0 })
        }
        .sheet(item: $editingFolder) { TagEditSheet(tagToEdit: $0) }
        .alert(
            deletingFolder.map { "Удалить папку «\(info(for: $0).title)»?" } ?? "Удалить папку?",
            isPresented: Binding(
                get: { deletingFolder != nil },
                set: { if !$0 { deletingFolder = nil } }
            ),
            presenting: deletingFolder
        ) { route in
            Button("Удалить", role: .destructive) { deleteFolder(route) }
            Button("Отмена", role: .cancel) { deletingFolder = nil }
        } message: { route in
            if case .shared = route {
                Text("Общая папка будет удалена для всех участников.")
            } else {
                Text("Задачи сохранятся в «Все задачи» без этой папки.")
            }
        }
        .sharedErrorAlert($folderDeletionError)
        .sheet(item: $managingSharedFolder) { SharedMembersView(listID: $0.id) }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await sharedStore.sync()
        }
        .onAppear { updateCaptureContext() }
        .onChange(of: homeRequest) { _, _ in
            closeFolder()
        }
        .onChange(of: selectedFolder) { _, _ in updateCaptureContext() }
        .onChange(of: tags.map(\.id)) { _, ids in
            if case .personal(.tag(let id)) = selectedFolder, !ids.contains(id) { closeFolder() }
        }
        .onChange(of: sharedStore.lists.map(\.id)) { _, ids in
            if case .shared(let id) = selectedFolder, !ids.contains(id) { closeFolder() }
        }
        .onChange(of: NotificationService.shared.morningNavigationToken) { _, _ in
            let scope: TaskScope
            switch NotificationService.shared.preferences.morningScope {
            case "all": scope = .all
            case "priority": scope = .highPriority
            default: scope = .all
            }
            open(.personal(scope))
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            today = Date.now.startOfDay
        }
    }

    private var folderCollection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenTitle(text: "Папки")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        Button {
                            addingFolder = true
                        } label: {
                            Text("Добавить папку")
                                .font(Theme.Typography.callout.weight(.medium))
                                .foregroundStyle(Theme.Colors.accent)
                                .padding(.horizontal, 14).frame(minHeight: 44)
                        }
                        .buttonStyle(FullSurfaceButtonStyle())
                        .modifier(FloatingGlass(shape: Capsule(), interactive: true))
                        .accessibilityLabel("Добавить папку")
                        .accessibilityIdentifier("classic-add-folder")
                    }

                folderGrid
            }
            .padding(.horizontal, Theme.Spacing.screenPadding)
            .padding(.top, 20)
            .padding(.bottom, captureBottomInset)
            #if os(macOS)
            .frame(maxWidth: 1060)
            .frame(maxWidth: .infinity)
            #endif
        }
        #if os(macOS)
        .coordinateSpace(name: "classic-folder-viewport")
        .scrollPosition($folderScrollPosition)
        .onScrollGeometryChange(for: FolderScrollMetrics.self) { geometry in
            FolderScrollMetrics(
                offset: geometry.contentOffset.y + geometry.contentInsets.top,
                limit: max(
                    0,
                    geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                        - geometry.containerSize.height),
                height: geometry.containerSize.height
            )
        } action: { _, metrics in
            folderScrollMetrics = metrics
        }
        .task(id: folderDrag?.isLanding == false ? folderDrag?.id : nil) {
            await autoScrollFolderDrag()
        }
        .onDisappear { folderDrag = nil }
        #endif
        .background(Theme.Colors.background)
        .scrollBounceBehavior(.always, axes: .vertical)
        .monoScrollEdge()
        .refreshable {
            #if os(macOS)
            guard folderDrag == nil else { return }
            #else
            guard !nativeFolderDragActive else { return }
            #endif
            await sharedStore.sync()
            do {
                try await SupabaseSyncService.shared.sync(context: context)
                Haptics.success()
            } catch {
                Haptics.warning()
            }
        }
    }

    @ViewBuilder private var folderGrid: some View {
        #if os(iOS)
        NativeFolderGrid(
            items: orderedFolders,
            revision: orderedFolders.map { route in
                let folder = info(for: route)
                return FolderTileRevision(
                    route: route, title: folder.title, count: folderTaskCount(route),
                    tint: folder.tint, icon: folder.icon)
            },
            bottomInset: captureBottomInset,
            content: { route in
                let folder = info(for: route)
                return AnyView(
                    folderLabel(
                        folder, count: folderTaskCount(route),
                        isShared: route.isShared, measure: true
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityHidden(true))
            },
            title: { info(for: $0).title },
            accessibilityLabel: { route in
                info(for: route).title + (route.isShared ? ", общая папка, " : ", ")
                    + "\(folderTaskCount(route)) открыто"
            },
            identifier: { folderIdentifier($0) },
            image: { route, width in
                let folder = info(for: route)
                let renderer = ImageRenderer(
                    content: ClassicFolderArtwork(tint: folder.tint, icon: folder.icon)
                        .frame(width: width, height: 124)
                        .environment(\.colorScheme, Theme.colorScheme))
                renderer.scale = UIScreen.main.scale
                return renderer.uiImage
            },
            menu: { nativeFolderMenu($0) },
            onOpen: { open($0) },
            onReorder: { order in folderOrder = order.map(\.orderKey).joined(separator: ",") },
            onDragActivity: { nativeFolderDragActive = $0 },
            onTaskDrop: { value, route in _ = drop(value, on: route) }
        )
        #else
        macFolderGrid
        #endif
    }

    private func folderTaskCount(_ route: ClassicFolderRoute) -> Int {
        switch route {
        case .personal(.tag(let id)):
            visibleTasks.filter { !$0.isDone && $0.tags.contains { $0.id == id } }.count
        case .shared(let id): sharedStore.tasks(in: id).filter { !$0.isDone }.count
        case .personal: visibleTasks.filter { !$0.isDone }.count
        }
    }

    private func folderIdentifier(_ route: ClassicFolderRoute) -> String {
        switch route {
        case .personal(.tag(let id)): "classic-folder-\(id)"
        case .shared(let id): "classic-shared-folder-\(id)"
        case .personal: "classic-all-tasks-folder"
        }
    }

    #if os(iOS)
    private func nativeFolderMenu(_ route: ClassicFolderRoute) -> UIMenu {
        var actions = [
            UIAction(title: "Открыть папку", image: UIImage(systemName: "arrow.up.right")) { _ in open(route) }
        ]
        switch route {
        case .personal(.tag(let id)):
            actions.append(
                UIAction(title: "Изменить папку", image: UIImage(systemName: "pencil")) { _ in
                    editingFolder = tags.first { $0.id == id }
                })
            actions.append(
                UIAction(title: "Удалить папку", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    deletingFolder = route
                })
        case .shared(let id):
            if let list = sharedStore.lists.first(where: { $0.id == id }) {
                let owner = list.ownerID == sharedStore.accountID
                actions.append(
                    UIAction(
                        title: owner ? "Управлять папкой" : "Участники и доступ",
                        image: UIImage(systemName: "person.2")
                    ) { _ in managingSharedFolder = list })
                if owner {
                    actions.append(
                        UIAction(
                            title: "Удалить папку", image: UIImage(systemName: "trash"),
                            attributes: sharedStore.canManage ? [.destructive] : [.destructive, .disabled]
                        ) { _ in
                            deletingFolder = route
                        })
                }
            }
        case .personal: break
        }
        return UIMenu(children: actions)
    }
    #endif

    #if os(macOS)
    private var macFolderGrid: some View {
        let columns = [GridItem(.adaptive(minimum: folderArtworkWidth, maximum: folderArtworkWidth), spacing: 18)]
        return LazyVGrid(columns: columns, spacing: 24) {
            ForEach(displayedFolders, id: \.self) { route in
                folderTile(route)
            }
        }
        .coordinateSpace(name: "classic-folder-grid")
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("classic-folder-viewport"))
        } action: { frame in
            gridFrame = frame
            if let drag = folderDrag, !drag.isLanding {
                moveFolderPreview(to: drag.pointer)
            }
        }
        .overlay(alignment: .topLeading) {
            if let drag = folderDrag {
                let folder = info(for: drag.source)
                let point = pointInGrid(drag.pointer)
                ClassicFolderArtwork(tint: folder.tint, icon: folder.icon)
                    .frame(width: folderArtworkWidth, height: 124)
                    .position(x: point.x + drag.grabOffset.width, y: point.y + drag.grabOffset.height)
                    .transaction { transaction in
                        if !drag.isLanding { transaction.animation = nil }
                    }
                    .allowsHitTesting(false)
            }
        }
        .highPriorityGesture(folderReorderGesture)
        .onChange(of: isDraggingFolder) { _, dragging in
            guard !dragging, let id = folderDrag?.id else { return }
            // A cancelled gesture resets its state without calling onEnded.
            Task { @MainActor in
                await Task.yield()
                if !isDraggingFolder, folderDrag?.id == id {
                    finishFolderDrag(commit: false)
                }
            }
        }
    }

    private func folderTile(_ route: ClassicFolderRoute) -> some View {
        Button {
            open(route)
        } label: {
            folderLabel(info(for: route), count: folderTaskCount(route), isShared: route.isShared, measure: true)
                .opacity(folderDrag?.source == route ? 0 : 1)
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .named("classic-folder-grid"))
        } action: { frame in
            tileFrames[route] = frame
            // Keep the visible slots stable while neighbours animate into place.
            // Scrolling may reveal a slot that was not laid out at drag start.
            if let index = displayedFolders.firstIndex(of: route), var drag = folderDrag,
                !drag.isLanding, drag.slots.indices.contains(index), drag.slots[index].isNull
            {
                drag.slots[index] = frame
                folderDrag = drag
                moveFolderPreview(to: drag.pointer)
            }
        }
        .accessibilityIdentifier(folderIdentifier(route))
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first else { return false }
            return drop(value, on: route)
        }
        .contextMenu {
            Button("Открыть папку", systemImage: "arrow.up.right") { open(route) }
            switch route {
            case .personal(.tag(let id)):
                Button("Изменить папку", systemImage: "pencil") {
                    editingFolder = tags.first { $0.id == id }
                }
                Button("Удалить папку", systemImage: "trash", role: .destructive) {
                    deletingFolder = route
                }
            case .shared(let id):
                if let list = sharedStore.lists.first(where: { $0.id == id }) {
                    let title = list.ownerID == sharedStore.accountID ? "Управлять папкой" : "Участники и доступ"
                    Button(title, systemImage: "person.2") { managingSharedFolder = list }
                    if list.ownerID == sharedStore.accountID {
                        Button("Удалить папку", systemImage: "trash", role: .destructive) {
                            deletingFolder = route
                        }
                        .disabled(!sharedStore.canManage)
                    }
                }
            case .personal:
                EmptyView()
            }
        }
    }

    private var folderReorderGesture: some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named("classic-folder-viewport"))
            .updating($isDraggingFolder) { _, dragging, _ in dragging = true }
            .onChanged { value in
                if folderDrag == nil {
                    let order = orderedFolders
                    let start = pointInGrid(value.startLocation)
                    let frames = order.map { tileFrames[$0] ?? .null }
                    guard let index = frames.firstIndex(where: { $0.contains(start) }), index > 0 else { return }
                    let center = folderArtworkCenter(in: frames[index])
                    folderDrag = FolderDragSession(
                        source: order[index], order: order, slots: frames, pointer: value.startLocation,
                        grabOffset: CGSize(width: center.x - start.x, height: center.y - start.y)
                    )
                }
                moveFolderPreview(to: value.location)
            }
            .onEnded { value in
                guard let drag = folderDrag, !drag.isLanding else { return }
                let point = pointInGrid(value.location)
                let insideViewport = value.location.y >= 0 && value.location.y <= folderScrollMetrics.height
                if insideViewport, let target = drag.destination(at: point, includingGaps: true) {
                    moveFolderPreview(to: value.location, finalTarget: target)
                    finishFolderDrag(commit: true)
                } else {
                    finishFolderDrag(commit: false)
                }
            }
    }

    private func pointInGrid(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - gridFrame.minX, y: point.y - gridFrame.minY)
    }

    private func folderArtworkCenter(in slot: CGRect) -> CGPoint {
        CGPoint(x: slot.midX, y: slot.minY + 7 + 124 / 2)
    }

    private func moveFolderPreview(to pointer: CGPoint, finalTarget: Int? = nil) {
        guard var drag = folderDrag, !drag.isLanding else { return }
        if drag.pointer != pointer {
            drag.pointer = pointer
            folderDrag = drag
        }
        guard let target = finalTarget ?? drag.destination(at: pointInGrid(pointer)),
            drag.move(to: target)
        else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.18)) {
            folderDrag = drag
        }
    }

    private func finishFolderDrag(commit: Bool) {
        guard var drag = folderDrag, !drag.isLanding else { return }
        if commit {
            drag.order = displayedFolders
            folderOrder = drag.order.map(\.orderKey).joined(separator: ",")
        } else {
            drag.order = orderedFolders
        }
        guard !reduceMotion, let index = drag.order.firstIndex(of: drag.source),
            drag.slots.indices.contains(index), !drag.slots[index].isNull
        else {
            folderDrag = nil
            return
        }
        drag.isLanding = true
        let center = folderArtworkCenter(in: drag.slots[index])
        drag.pointer = CGPoint(
            x: center.x + gridFrame.minX - drag.grabOffset.width,
            y: center.y + gridFrame.minY - drag.grabOffset.height
        )
        let id = drag.id
        withAnimation(.smooth(duration: 0.2)) {
            folderDrag = drag
        } completion: {
            if folderDrag?.id == id { folderDrag = nil }
        }
    }

    private func autoScrollFolderDrag() async {
        guard let id = folderDrag?.id, folderDrag?.isLanding == false else { return }
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .milliseconds(16))
            } catch {
                return
            }
            guard let drag = folderDrag, drag.id == id, !drag.isLanding else { return }
            let viewport = folderScrollMetrics
            let bottom = viewport.height - captureBottomInset
            guard drag.pointer.x >= gridFrame.minX, drag.pointer.x <= gridFrame.maxX,
                drag.pointer.y >= 0, drag.pointer.y <= bottom
            else { continue }
            let delta = viewport.edgeScrollStep(at: drag.pointer.y, bottom: bottom)
            let next = min(viewport.limit, max(0, viewport.offset + delta))
            if delta != 0, abs(next - viewport.offset) >= 0.5 {
                folderScrollPosition.scrollTo(y: next)
            }
        }
    }
    #endif

    private func deleteFolder(_ route: ClassicFolderRoute) {
        switch route {
        case .personal(.tag(let id)):
            guard let tag = tags.first(where: { $0.id == id }) else { return }
            context.deleteWithSync(tag)
            context.saveAndSync()
        case .shared(let id):
            guard let list = sharedStore.lists.first(where: { $0.id == id }),
                list.ownerID == sharedStore.accountID, sharedStore.canManage
            else { return }
            Task {
                do {
                    try await sharedStore.updateList(list, title: list.title, delete: true)
                } catch {
                    folderDeletionError = SharedListStore.message(for: error)
                }
            }
        case .personal:
            return
        }
    }

    private func drop(_ value: String, on route: ClassicFolderRoute) -> Bool {
        guard case .personal(.tag(let tagID)) = route, let id = UUID(uuidString: value),
            let task = visibleTasks.first(where: { $0.id == id }), let tag = tags.first(where: { $0.id == tagID })
        else { return false }
        context.assign(task, to: tag)
        Haptics.selection()
        return true
    }

    private func folderLabel(
        _ folder: ClassicFolderInfo, count: Int, isShared: Bool, measure: Bool
    ) -> some View {
        VStack(spacing: 9) {
            if measure {
                folderZoomSource(folder)
            } else {
                ClassicFolderArtwork(tint: folder.tint, icon: folder.icon)
                    .frame(maxWidth: folderArtworkWidth).frame(height: 124)
            }
            Text(folder.title)
                .font(Theme.Typography.body.weight(.medium))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
            Text(isShared ? "Общая · \(count) открыто" : "\(count) открыто")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 22))
    }

    private func folderZoomSource(_ folder: ClassicFolderInfo) -> some View {
        ClassicFolderArtwork(tint: folder.tint, icon: folder.icon)
            .frame(maxWidth: folderArtworkWidth).frame(height: 124)
            .matchedTransitionSource(id: folder.route, in: folderZoom) {
                $0.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
    }

    @ViewBuilder private func folderDestination(_ route: ClassicFolderRoute) -> some View {
        #if os(iOS)
        if !reduceMotion, orderedFolders.contains(route) {
            folderPage(route).navigationTransition(.zoom(sourceID: route, in: folderZoom))
        } else {
            folderPage(route)
        }
        #else
        folderPage(route)
        #endif
    }

    private func folderPage(_ route: ClassicFolderRoute) -> some View {
        VStack(spacing: 12) {
            if case .personal = route {
                folderHeader(info(for: route))
                    .modifier(MediumPriorityDropTarget(tasks: tasks))
            } else {
                folderHeader(info(for: route))
            }
            folderContents(route)
                .id(route)
        }
        #if os(macOS)
        .frame(maxWidth: 820)
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.background.ignoresSafeArea())
        .allowsHitTesting(selectedFolder == route)
        .accessibilityHidden(selectedFolder != route)
        #if os(macOS)
        .navigationBarBackButtonHidden()
        .macNavigationHeader(maxWidth: 820) {
            Button("Назад", systemImage: "chevron.left", action: closeFolder)
            .accessibilityIdentifier("classic-folder-back")
        }
        #else
        .background {
            FolderVisibilityReader(route: route, visibility: folderVisibility) { closing in
                guard selectedFolder == route else { return }
                isFolderClosing = closing
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private func folderHeader(_ folder: ClassicFolderInfo) -> some View {
        let progress = folderProgress(folder.route)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ScreenTitle(text: folder.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("classic-folder-title")
                if case .shared(let id) = folder.route {
                    Button {
                        managingSharedFolder = sharedStore.lists.first { $0.id == id }
                    } label: {
                        Image(systemName: "person.2").frame(width: 44, height: 44)
                    }
                    .buttonStyle(FullSurfaceButtonStyle())
                    .accessibilityLabel("Участники и доступ")
                }
                completionCount(done: progress.done, total: progress.total)
            }
            ProgressLine(
                progress: progress.total == 0 ? 0 : Double(progress.done) / Double(progress.total),
                height: 9
            )
            .accessibilityHidden(true)
            HStack(spacing: 8) {

                Menu {
                    Section {
                        Button("К списку папок", action: closeFolder)
                            .accessibilityIdentifier("classic-close-folder")
                    }
                    #if os(macOS)
                    Button("Приоритет", systemImage: "star") {
                        open(.personal(.highPriority))
                    }
                    #endif
                    ForEach(orderedFolders, id: \.self) { route in
                        let option = info(for: route)
                        Button {
                            open(route)
                        } label: {
                            Label(option.title, systemImage: route == folder.route ? "checkmark" : option.icon)
                        }
                    }
                } label: {
                    folderShortcutLabel("Папки", icon: "chevron.down")
                }
                .menuStyle(.borderlessButton)
                .accessibilityIdentifier("classic-folder-menu")

                folderShortcut("Общие", icon: "person.2") {
                    sharedStore.isPresented = true
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.screenPadding)
        .padding(.top, 12)
    }

    private func completionCount(done: Int, total: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(done)")
                .font(.system(size: completionFigureSize, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.Colors.accent)
                .contentTransition(.numericText())
            Text("/ \(total)")
                .font(Theme.Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .layoutPriority(1)
        .animation(reduceMotion ? nil : Theme.Motion.standard, value: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Выполнено \(done) из \(total)")
        .accessibilityIdentifier("classic-folder-completion")
    }

    private func folderShortcut(
        _ title: String, icon: String, selected: Bool = false, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            folderShortcutLabel(title, icon: icon, selected: selected)
        }
        .buttonStyle(FullSurfaceButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func folderShortcutLabel(_ title: String, icon: String, selected: Bool = false) -> some View {
        Label(title, systemImage: icon)
            .font(Theme.Typography.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(selected ? Theme.Colors.onAccent : Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(selected ? Theme.Colors.accent : Theme.Colors.surfaceElevated, in: Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private func folderProgress(_ route: ClassicFolderRoute) -> (done: Int, total: Int) {
        switch route {
        case .personal(let scope):
            let scheduled = FocusService.shared.currentFocusTags(allTags: tags, override: nil)
            let matching = scope.filter(visibleTasks, scheduledTags: scheduled)
            return (matching.filter(\.isDone).count, matching.count)
        case .shared(let id):
            let matching = sharedStore.tasks(in: id)
            return (matching.filter(\.isDone).count, matching.count)
        }
    }

    @ViewBuilder private func folderContents(_ route: ClassicFolderRoute) -> some View {
        switch route {
        case .personal(let scope):
            TodayView(
                initialScope: scope, isCaptureActive: $isCaptureActive, captureTag: $captureTag,
                captureBottomInset: captureBottomInset, showsHeader: false,
                canEditTask: { canEditTask(in: route) }
            )
        case .shared(let id):
            SharedListDetailView(
                listID: id, folderLayout: true, isCaptureActive: $isCaptureActive,
                canEditTask: { canEditTask(in: route) }
            )
            .contentMargins(.bottom, captureBottomInset, for: .scrollContent)
        }
    }

    private func info(for route: ClassicFolderRoute) -> ClassicFolderInfo {
        switch route {
        case .personal(.tag(let id)):
            if let tag = tags.first(where: { $0.id == id }) {
                return ClassicFolderInfo(
                    route: route, title: tag.name, tint: tag.color, icon: tag.folderIconName)
            }
        case .shared(let id):
            if let list = sharedStore.lists.first(where: { $0.id == id }) {
                return ClassicFolderInfo(
                    route: route, title: list.title, tint: Theme.Colors.tagColor(Theme.Colors.tagColors[1]),
                    icon: "person.2.fill"
                )
            }
        case .personal(let scope):
            return ClassicFolderInfo(
                route: route, title: scope.title(tags: tags), tint: Theme.Colors.accent, icon: "tray.full.fill")
        }
        return ClassicFolderInfo(route: route, title: "Папка", tint: Theme.Colors.accent, icon: "folder.fill")
    }

    private func canEditTask(in route: ClassicFolderRoute) -> Bool {
        guard selectedFolder == route else { return false }
        #if os(iOS)
        // During a native interactive pop the path can still contain the departing folder.
        return folderVisibility.isVisible(route)
        #else
        return true
        #endif
    }

    private func openPendingSharedFolder() {
        guard let id = pendingSharedFolderID else { return }
        pendingSharedFolderID = nil
        open(.shared(id))
    }

    private func open(_ route: ClassicFolderRoute) {
        guard selectedFolder != route else { return }
        Haptics.selection()
        hideKeyboard()
        isCaptureActive = false
        isFolderClosing = false
        folderPath = [route]
    }

    private func closeFolder() {
        guard !folderPath.isEmpty else { return }
        Haptics.selection()
        hideKeyboard()
        isCaptureActive = false
        isFolderClosing = true
        folderPath.removeLast()
    }

    private func updateCaptureContext() {
        isFolderOpen = selectedFolder != nil
        isCaptureActive = false
        switch selectedFolder {
        case .personal(let scope):
            let scheduled = FocusService.shared.currentFocusTags(allTags: tags, override: nil)
            captureTag = scope.defaultTag(tags: tags, scheduledTags: scheduled)
            sharedCaptureListID = nil
        case .shared(let id):
            captureTag = nil
            sharedCaptureListID = id
        case nil:
            captureTag = nil
            sharedCaptureListID = nil
        }
    }
}

struct ClassicFolderArtwork: View {
    var tint: Color
    var icon: String = "square.stack.3d.up.fill"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    private var dark: Bool { scheme == .dark }
    private var pocketTop: Color { tint.mix(with: .white, by: dark ? 0.12 : 0.40) }
    private var pocketBottom: Color { dark ? tint.mix(with: .black, by: 0.28) : tint.mix(with: .white, by: 0.08) }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                Ellipse()
                    .fill(.black.opacity(dark ? 0.18 : 0.07))
                    .frame(width: width * 0.69, height: height * 0.09)
                    .blur(radius: 8)
                    .offset(y: height * 0.43)

                ClassicFolderBackCover()
                    .fill(
                        LinearGradient(
                            colors: [tint.mix(with: .white, by: 0.08), tint.mix(with: .black, by: dark ? 0.46 : 0.24)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay(ClassicFolderBackCover().classicStrokeBorderHighlight(dark: dark))
                    .frame(width: width * 0.82, height: height * 0.79)
                    .offset(y: -height * 0.015)

                ClassicFolderPocket()
                    .fill(
                        LinearGradient(
                            colors: [pocketTop, pocketBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .overlay {
                        ClassicFolderPocket().fill(
                            RadialGradient(
                                colors: [.white.opacity(dark ? 0.12 : 0.22), .clear],
                                center: .topLeading, startRadius: 0, endRadius: width * 0.9))
                    }
                    .overlay {
                        ClassicFolderPocket().stroke(
                            LinearGradient(
                                colors: [.white.opacity(dark ? 0.24 : 0.95), .black.opacity(dark ? 0.14 : 0.045)],
                                startPoint: .top, endPoint: .bottom), lineWidth: 0.9)
                    }
                    .shadow(color: .black.opacity(dark ? 0.22 : 0.065), radius: hovered ? 12 : 8, y: hovered ? 10 : 6)
                    .overlay(alignment: .bottomTrailing) {
                        recessedSymbol(width: width)
                            .padding(.trailing, width * 0.10)
                            .padding(.bottom, height * 0.12)
                    }
                    .frame(width: width * 0.86, height: height * 0.69)
                    .offset(y: height * 0.12)
            }
            .frame(width: width, height: height)
            .offset(y: hovered ? -3 : 0)
        }
        .onHover { value in
            withAnimation(reduceMotion ? nil : Theme.Motion.standard) { hovered = value }
        }
        .accessibilityHidden(true)
    }

    private func recessedSymbol(width: CGFloat) -> some View {
        let symbol = icon == "tag.fill" ? "square.stack.3d.up.fill" : icon
        let depth = max(0.6, width * 0.007)
        return Image(systemName: symbol)
            .resizable().scaledToFit()
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(
                tint.mix(with: .black, by: dark ? 0.64 : 0.52)
                    .shadow(.inner(color: .black.opacity(dark ? 0.55 : 0.3), radius: depth, x: 0, y: depth))
            )
            .frame(width: width * 0.25, height: width * 0.25)
            .shadow(color: .white.opacity(dark ? 0.28 : 0.7), radius: depth * 0.4, x: 0, y: depth)
    }

}

private struct ClassicFolderBackCover: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w * 0.12, y: 0))
        p.addLine(to: CGPoint(x: w * 0.34, y: 0))
        p.addCurve(
            to: CGPoint(x: w * 0.55, y: h * 0.13),
            control1: CGPoint(x: w * 0.43, y: 0), control2: CGPoint(x: w * 0.43, y: h * 0.13))
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.13))
        p.addQuadCurve(to: CGPoint(x: w, y: h * 0.27), control: CGPoint(x: w, y: h * 0.13))
        p.addLine(to: CGPoint(x: w, y: h * 0.86))
        p.addQuadCurve(to: CGPoint(x: w * 0.87, y: h), control: CGPoint(x: w, y: h))
        p.addLine(to: CGPoint(x: w * 0.13, y: h))
        p.addQuadCurve(to: CGPoint(x: 0, y: h * 0.86), control: CGPoint(x: 0, y: h))
        p.addLine(to: CGPoint(x: 0, y: h * 0.15))
        p.addQuadCurve(to: CGPoint(x: w * 0.12, y: 0), control: .zero)
        p.closeSubpath()
        return p
    }
}

private struct ClassicFolderPocket: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: 0, y: h * 0.29))
        p.addCurve(
            to: CGPoint(x: w * 0.2, y: h * 0.035),
            control1: CGPoint(x: 0, y: h * 0.08), control2: CGPoint(x: w * 0.07, y: h * 0.035))
        p.addLine(to: CGPoint(x: w * 0.34, y: h * 0.035))
        p.addCurve(
            to: CGPoint(x: w * 0.57, y: h * 0.16),
            control1: CGPoint(x: w * 0.45, y: h * 0.035), control2: CGPoint(x: w * 0.44, y: h * 0.16))
        p.addLine(to: CGPoint(x: w * 0.81, y: h * 0.16))
        p.addCurve(
            to: CGPoint(x: w, y: h * 0.39),
            control1: CGPoint(x: w * 0.95, y: h * 0.16), control2: CGPoint(x: w, y: h * 0.23))
        p.addLine(to: CGPoint(x: w, y: h * 0.78))
        p.addCurve(
            to: CGPoint(x: w * 0.8, y: h),
            control1: CGPoint(x: w, y: h * 0.95), control2: CGPoint(x: w * 0.94, y: h))
        p.addLine(to: CGPoint(x: w * 0.19, y: h))
        p.addCurve(
            to: CGPoint(x: 0, y: h * 0.78),
            control1: CGPoint(x: w * 0.04, y: h), control2: CGPoint(x: 0, y: h * 0.96))
        p.closeSubpath()
        return p
    }
}

private extension Shape {
    func classicStrokeBorderHighlight(dark: Bool) -> some View {
        stroke(
            LinearGradient(
                colors: [.white.opacity(dark ? 0.18 : 0.9), .black.opacity(0.05)],
                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
    }
}

#if os(iOS)
@MainActor
private final class FolderVisibility {
    weak var visiblePage: FolderVisibilityReader.Controller?

    func isVisible(_ route: ClassicFolderRoute) -> Bool {
        guard let visiblePage, visiblePage.route == route, visiblePage.viewIfLoaded?.window != nil else {
            return false
        }
        return visiblePage.transitionCoordinator?.isAnimated != true
    }
}

private struct FolderVisibilityReader: UIViewControllerRepresentable {
    let route: ClassicFolderRoute
    let visibility: FolderVisibility
    let onClosingChange: (Bool) -> Void

    func makeUIViewController(context: Context) -> Controller {
        Controller(route: route, visibility: visibility, onClosingChange: onClosingChange)
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.onClosingChange = onClosingChange
    }

    final class Controller: UIViewController {
        let route: ClassicFolderRoute
        private let visibility: FolderVisibility
        var onClosingChange: (Bool) -> Void
        private var appearanceRevision = 0
        private let observedGestures = NSHashTable<UIGestureRecognizer>.weakObjects()
        private var isClosingFromGesture = false

        init(route: ClassicFolderRoute, visibility: FolderVisibility, onClosingChange: @escaping (Bool) -> Void) {
            self.route = route
            self.visibility = visibility
            self.onClosingChange = onClosingChange
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            // A pop can interrupt the opening zoom before viewDidAppear is delivered.
            visibility.visiblePage = self
            observeNavigationGestures()
            if !isClosingFromGesture { publishClosing(false) }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            observeNavigationGestures()
        }

        override func viewWillDisappear(_ animated: Bool) {
            if visibility.visiblePage === self {
                visibility.visiblePage = nil
                publishClosing(true)
            }
            super.viewWillDisappear(animated)
        }

        private func observeNavigationGestures() {
            guard let navigationView = navigationController?.viewIfLoaded else { return }
            // UIKit installs the zoom gestures inside the destination's hosting hierarchy.
            var views = [navigationView]
            while let view = views.popLast() {
                views.append(contentsOf: view.subviews)
                for gesture in view.gestureRecognizers ?? [] where !observedGestures.contains(gesture) {
                    gesture.addTarget(self, action: #selector(navigationGestureChanged))
                    observedGestures.add(gesture)
                }
            }
        }

        @objc private func navigationGestureChanged(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed,
                !isClosingFromGesture,
                let transition = navigationController?.transitionCoordinator, transition.isInteractive
            else { return }

            // Reversing an in-flight opening can cancel the push rather than finish a pop.
            // Keep the dock collapsed until UIKit confirms which page is still visible.
            isClosingFromGesture = true
            publishClosing(true)
            transition.animate(alongsideTransition: nil) { [weak self] context in
                guard let self else { return }
                let visiblePage = context.viewController(forKey: context.isCancelled ? .from : .to)
                guard let visibleView = visiblePage?.viewIfLoaded, view.isDescendant(of: visibleView) else { return }
                isClosingFromGesture = false
                publishClosing(false)
            }
        }

        private func publishClosing(_ closing: Bool) {
            appearanceRevision += 1
            let revision = appearanceRevision
            // Defer SwiftUI mutations out of UIKit callbacks and discard superseded updates.
            Task { @MainActor in
                guard appearanceRevision == revision else { return }
                let activePage = visibility.visiblePage
                guard activePage === self || (closing && activePage == nil) else { return }
                onClosingChange(closing)
            }
        }
    }
}
#endif

#if os(macOS)
private struct FolderDragSession {
    let id = UUID()
    let source: ClassicFolderRoute
    var order: [ClassicFolderRoute]
    var slots: [CGRect]
    var pointer: CGPoint
    let grabOffset: CGSize
    var isLanding = false

    func destination(at point: CGPoint, includingGaps: Bool = false) -> Int? {
        slots.indices.dropFirst().first(where: { index in
            let slot = slots[index]
            guard !slot.isNull else { return false }
            let hitArea =
                includingGaps
                ? slot.insetBy(dx: -9, dy: -12)
                : slot.insetBy(dx: slot.width * 0.09, dy: slot.height * 0.09)
            return hitArea.contains(point)
        })
    }

    mutating func move(to destination: Int) -> Bool {
        guard destination > 0, order.indices.contains(destination),
            let sourceIndex = order.firstIndex(of: source), sourceIndex > 0, sourceIndex != destination
        else { return false }
        order.remove(at: sourceIndex)
        order.insert(source, at: destination)
        return true
    }
}

private struct FolderScrollMetrics: Equatable {
    let offset: CGFloat
    let limit: CGFloat
    let height: CGFloat

    func edgeScrollStep(at y: CGFloat, bottom: CGFloat) -> CGFloat {
        let edge: CGFloat = 44
        if y < edge { return -min(9, max(1.5, (edge - y) * 0.12)) }
        if y > bottom - edge { return min(9, max(1.5, (y - bottom + edge) * 0.12)) }
        return 0
    }
}
#endif

#if os(iOS)
private struct FolderTileRevision: Equatable {
    let route: ClassicFolderRoute
    let title: String
    let count: Int
    let tint: Color
    let icon: String
}

/// UIKit coordinates context menus, folder dragging and insertion animations.
private struct NativeFolderGrid: UIViewRepresentable {
    var items: [ClassicFolderRoute]
    var revision: [FolderTileRevision]
    var bottomInset: CGFloat
    var content: (ClassicFolderRoute) -> AnyView
    var title: (ClassicFolderRoute) -> String
    var accessibilityLabel: (ClassicFolderRoute) -> String
    var identifier: (ClassicFolderRoute) -> String
    var image: (ClassicFolderRoute, CGFloat) -> UIImage?
    var menu: (ClassicFolderRoute) -> UIMenu
    var onOpen: (ClassicFolderRoute) -> Void
    var onReorder: ([ClassicFolderRoute]) -> Void
    var onDragActivity: (Bool) -> Void
    var onTaskDrop: (String, ClassicFolderRoute) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 24
        layout.minimumInteritemSpacing = 18
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.isScrollEnabled = true
        view.bounces = false
        view.alwaysBounceVertical = false
        view.showsVerticalScrollIndicator = false
        view.contentInsetAdjustmentBehavior = .never
        view.clipsToBounds = false
        view.dragInteractionEnabled = true
        view.reorderingCadence = .immediate
        view.dataSource = context.coordinator
        view.delegate = context.coordinator
        view.dropDelegate = context.coordinator
        view.dragDelegate = context.coordinator
        view.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "folder")
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: UICollectionView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.applyContentUpdates(to: view)
    }

    static func dismantleUIView(_ view: UICollectionView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UICollectionView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0,
            let layout = uiView.collectionViewLayout as? UICollectionViewFlowLayout
        else { return nil }
        let columns = max(1, Int((width + 18) / 158))
        let itemWidth = min(240, (width - CGFloat(columns - 1) * 18) / CGFloat(columns))
        let font = UIFont.preferredFont(forTextStyle: .callout)
        let lines =
            items.map { item in
                (title(item) as NSString).boundingRect(
                    with: CGSize(width: itemWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil
                ).height
            }.max() ?? font.lineHeight
        let titleHeight = min(font.lineHeight * 2, max(font.lineHeight, ceil(lines)))
        let height = ceil(124 + 14 + 18 + titleHeight + UIFont.preferredFont(forTextStyle: .caption1).lineHeight)
        if layout.itemSize != CGSize(width: itemWidth, height: height) {
            layout.itemSize = CGSize(width: itemWidth, height: height)
        }
        let rows = Int(ceil(Double(items.count) / Double(columns)))
        return CGSize(width: width, height: CGFloat(rows) * height + CGFloat(max(0, rows - 1)) * 24)
    }

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate,
        UICollectionViewDragDelegate, UICollectionViewDropDelegate, UIDropInteractionDelegate
    {
        var parent: NativeFolderGrid
        var items: [ClassicFolderRoute]
        var dragActive = false
        private var menuVisible = false
        private var appliedRevision: [FolderTileRevision]
        private weak var collectionView: UICollectionView?
        private weak var scrollingParent: UIScrollView?
        private var dragSession: (any UIDragSession)?
        private var displayLink: CADisplayLink?
        private var menuButton: UIButton?
        private var edgeDropInteraction: UIDropInteraction?
        private var dragArtwork: UIImageView?
        private var dragArtworkRoute: ClassicFolderRoute?
        private var artworkTouchOffset = CGPoint.zero
        private var landingArtwork = false

        init(_ parent: NativeFolderGrid) {
            self.parent = parent
            self.items = parent.items
            self.appliedRevision = parent.revision
        }

        func applyContentUpdates(to view: UICollectionView) {
            guard !dragActive, !menuVisible, !landingArtwork else { return }
            if items != parent.items {
                items = parent.items
                view.reloadData()
            } else if appliedRevision != parent.revision {
                for cell in view.visibleCells {
                    guard let path = view.indexPath(for: cell), items.indices.contains(path.item) else { continue }
                    configure(cell, at: path)
                }
            }
            appliedRevision = parent.revision
        }

        func attach(to view: UICollectionView) {
            collectionView = view
        }

        func tearDown() {
            clearDragArtwork()
            removeEdgeDropInteraction()
            displayLink?.invalidate()
            displayLink = nil
            dragSession = nil
            dragActive = false
            menuVisible = false
            menuButton?.removeFromSuperview()
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func configure(_ cell: UICollectionViewCell, at indexPath: IndexPath) {
            let route = items[indexPath.item]
            cell.contentConfiguration = UIHostingConfiguration { parent.content(route) }.margins(.all, 0)
            cell.contentView.alpha = landingArtwork && route == dragArtworkRoute ? 0 : 1
            cell.backgroundColor = .clear
            cell.isOpaque = false
            cell.contentView.backgroundColor = .clear
            cell.contentView.isOpaque = false
            cell.isAccessibilityElement = true
            cell.accessibilityTraits = .button
            cell.accessibilityIdentifier = parent.identifier(route)
            cell.accessibilityLabel = parent.accessibilityLabel(route)
            cell.accessibilityCustomActions = [
                UIAccessibilityCustomAction(name: "Меню папки") { [weak self] _ in
                    guard let self, let index = self.items.firstIndex(of: route) else { return false }
                    self.showMenu(at: IndexPath(item: index, section: 0))
                    return true
                }
            ]
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath)
            -> UICollectionViewCell
        {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "folder", for: indexPath)
            configure(cell, at: indexPath)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            parent.onOpen(items[indexPath.item])
        }

        func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
            items[indexPath.item] != .personal(.all)
        }

        func collectionView(
            _ collectionView: UICollectionView,
            contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
            point: CGPoint
        ) -> UIContextMenuConfiguration? {
            guard indexPaths.count == 1, let path = indexPaths.first,
                items.indices.contains(path.item)
            else { return nil }
            let route = items[path.item]
            return UIContextMenuConfiguration(
                identifier: route.orderKey as NSString,
                previewProvider: nil
            ) { [weak self] _ in
                self?.parent.menu(route)
            }
        }

        private func folderPreview(in collectionView: UICollectionView, at path: IndexPath) -> UITargetedPreview? {
            guard items.indices.contains(path.item), let cell = collectionView.cellForItem(at: path),
                let image = parent.image(items[path.item], min(cell.bounds.width, 188))
            else { return nil }
            let frame = artworkFrame(in: cell)
            let preview = UIImageView(image: image)
            preview.frame = CGRect(origin: .zero, size: frame.size)
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            let center = collectionView.convert(CGPoint(x: frame.midX, y: frame.midY), from: cell.contentView)
            return UITargetedPreview(
                view: preview, parameters: parameters,
                target: UIPreviewTarget(container: collectionView, center: center))
        }

        private func artworkFrame(in cell: UICollectionViewCell) -> CGRect {
            let width = min(cell.bounds.width, 188)
            return CGRect(x: (cell.bounds.width - width) / 2, y: 7, width: width, height: 124)
        }

        func collectionView(
            _ collectionView: UICollectionView, contextMenuConfiguration: UIContextMenuConfiguration,
            highlightPreviewForItemAt indexPath: IndexPath
        ) -> UITargetedPreview? {
            folderPreview(in: collectionView, at: indexPath)
        }

        func collectionView(
            _ collectionView: UICollectionView, contextMenuConfiguration: UIContextMenuConfiguration,
            dismissalPreviewForItemAt indexPath: IndexPath
        ) -> UITargetedPreview? {
            folderPreview(in: collectionView, at: indexPath)
        }

        func collectionView(
            _ collectionView: UICollectionView, willDisplayContextMenu configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            menuVisible = true
            displayLink?.invalidate()
            displayLink = nil
        }

        func collectionView(
            _ collectionView: UICollectionView, willEndContextMenuInteraction configuration: UIContextMenuConfiguration,
            animator: (any UIContextMenuInteractionAnimating)?
        ) {
            let finish = { [weak self] in
                guard let self else { return }
                self.menuVisible = false
                if self.dragActive { self.startAutoScroll() }
                self.applyContentUpdates(to: collectionView)
            }
            if let animator { animator.addCompletion(finish) } else { finish() }
        }

        func collectionView(
            _ collectionView: UICollectionView, itemsForBeginning session: any UIDragSession,
            at indexPath: IndexPath
        ) -> [UIDragItem] {
            let route = items[indexPath.item]
            guard route != .personal(.all) else { return [] }
            session.localContext = self
            let item = UIDragItem(itemProvider: NSItemProvider(object: route.orderKey as NSString))
            item.localObject = route
            // UIKit retains its native menu and drag/drop gestures; the artwork is
            // drawn at a fixed size instead of using UIKit's scaled drag snapshot.
            item.previewProvider = { nil }
            return [item]
        }

        func collectionView(
            _ collectionView: UICollectionView,
            dragPreviewParametersForItemAt indexPath: IndexPath
        ) -> UIDragPreviewParameters? {
            guard let cell = collectionView.cellForItem(at: indexPath) else { return nil }
            let parameters = UIDragPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.visiblePath = UIBezierPath(rect: artworkFrame(in: cell))
            parameters.shadowPath = UIBezierPath()
            return parameters
        }

        func collectionView(
            _ collectionView: UICollectionView,
            dropPreviewParametersForItemAt indexPath: IndexPath
        ) -> UIDragPreviewParameters? {
            // Match the artwork-only drag preview. UIKit otherwise morphs it into the
            // entire cell (including the title and count) before revealing the folder.
            self.collectionView(collectionView, dragPreviewParametersForItemAt: indexPath)
        }

        func collectionView(
            _ collectionView: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: any UIDragSession
        ) -> Bool {
            true
        }

        func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: any UIDragSession) {
            dragSession = session
            beginDragArtwork(for: session, in: collectionView)
            // The dock overlays the scroll view. Accept this local drag on the window too,
            // so releasing above that overlay still inserts into the visible bottom row.
            if let window = collectionView.window {
                let interaction = UIDropInteraction(delegate: self)
                window.addInteraction(interaction)
                edgeDropInteraction = interaction
            }
            dragActive = true
            parent.onDragActivity(true)
            var ancestor = collectionView.superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    scrollingParent = scroll
                    break
                }
                ancestor = view.superview
            }
            startAutoScroll()
        }

        private func startAutoScroll() {
            guard displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(scrollDuringMovement))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: any UIDragSession) {
            removeEdgeDropInteraction()
            displayLink?.invalidate()
            displayLink = nil
            dragSession = nil
            scrollingParent = nil
            dragActive = false
            landDragArtwork(in: collectionView)
            parent.onDragActivity(false)
            applyContentUpdates(to: collectionView)
        }

        private func beginDragArtwork(for session: any UIDragSession, in collectionView: UICollectionView) {
            clearDragArtwork()
            guard let route = session.items.first?.localObject as? ClassicFolderRoute,
                let index = items.firstIndex(of: route), let window = collectionView.window,
                let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
            else { return }
            let frame = artworkFrame(in: cell)
            guard let image = parent.image(route, frame.width) else { return }
            let artwork = UIImageView(image: image)
            artwork.isUserInteractionEnabled = false
            artwork.frame = cell.contentView.convert(frame, to: window)
            window.addSubview(artwork)
            dragArtwork = artwork
            dragArtworkRoute = route
            let finger = session.location(in: window)
            artworkTouchOffset = CGPoint(x: artwork.center.x - finger.x, y: artwork.center.y - finger.y)
        }

        private func updateDragArtwork() {
            guard let artwork = dragArtwork, let window = artwork.window, let dragSession else { return }
            let finger = dragSession.location(in: window)
            artwork.center = CGPoint(x: finger.x + artworkTouchOffset.x, y: finger.y + artworkTouchOffset.y)
        }

        private func landDragArtwork(in collectionView: UICollectionView) {
            guard let artwork = dragArtwork, let window = artwork.window, let route = dragArtworkRoute,
                let index = items.firstIndex(of: route),
                let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
            else {
                clearDragArtwork()
                return
            }
            landingArtwork = true
            let destination = collectionView.convert(
                CGPoint(x: attributes.center.x, y: attributes.frame.minY + 69), to: window)
            let cell = collectionView.cellForItem(at: IndexPath(item: index, section: 0))
            cell?.contentView.alpha = 0
            // Only the center changes. The artwork's bounds and transform stay fixed.
            UIView.animate(
                withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.22, delay: 0,
                options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction]
            ) {
                artwork.center = destination
            } completion: { [weak self] _ in
                guard let self, self.dragArtwork === artwork else { return }
                self.clearDragArtwork()
                self.applyContentUpdates(to: collectionView)
            }
        }

        private func clearDragArtwork() {
            dragArtwork?.layer.removeAllAnimations()
            dragArtwork?.removeFromSuperview()
            dragArtwork = nil
            dragArtworkRoute = nil
            landingArtwork = false
            for cell in collectionView?.visibleCells ?? [] { cell.contentView.alpha = 1 }
        }

        private func removeEdgeDropInteraction() {
            if let interaction = edgeDropInteraction { interaction.view?.removeInteraction(interaction) }
            edgeDropInteraction = nil
        }

        private func edgeDestination(for session: any UIDropSession) -> IndexPath? {
            guard let collectionView, let window = collectionView.window, items.count > 1 else { return nil }
            let finger = session.location(in: window)
            let grid = collectionView.convert(collectionView.bounds, to: window)
            guard finger.x >= grid.minX - 20, finger.x <= grid.maxX + 20,
                finger.y >= max(grid.minY, window.safeAreaInsets.top),
                finger.y <= window.bounds.maxY - window.safeAreaInsets.bottom
            else { return nil }
            let point = session.location(in: collectionView)
            if let path = collectionView.indexPathForItem(at: point) {
                return IndexPath(item: max(1, path.item), section: 0)
            }
            let nearest = (1..<items.count).min { lhs, rhs in
                let left = collectionView.layoutAttributesForItem(at: IndexPath(item: lhs, section: 0))?.center ?? .zero
                let right =
                    collectionView.layoutAttributesForItem(at: IndexPath(item: rhs, section: 0))?.center ?? .zero
                return hypot(point.x - left.x, point.y - left.y) < hypot(point.x - right.x, point.y - right.y)
            }
            return nearest.map { IndexPath(item: $0, section: 0) }
        }

        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
            (session.localDragSession?.localContext as? Coordinator) === self
        }

        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession)
            -> UIDropProposal
        {
            UIDropProposal(operation: edgeDestination(for: session) == nil ? .forbidden : .move)
        }

        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
            guard let collectionView, let destination = edgeDestination(for: session),
                let route = session.items.first?.localObject as? ClassicFolderRoute,
                let source = items.firstIndex(of: route), source > 0
            else { return }
            collectionView.performBatchUpdates {
                items.remove(at: source)
                items.insert(route, at: destination.item)
                collectionView.moveItem(at: IndexPath(item: source, section: 0), to: destination)
            }
            parent.onReorder(items)
        }

        func dropInteraction(
            _ interaction: UIDropInteraction, previewForDropping item: UIDragItem,
            withDefault defaultPreview: UITargetedDragPreview
        ) -> UITargetedDragPreview? {
            guard let collectionView, let route = item.localObject as? ClassicFolderRoute,
                let index = items.firstIndex(of: route),
                let attributes = collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
            else { return nil }
            let target = UIDragPreviewTarget(
                container: collectionView,
                center: CGPoint(x: attributes.center.x, y: attributes.frame.minY + 69))
            return defaultPreview.retargetedPreview(with: target)
        }

        private func showMenu(at indexPath: IndexPath) {
            guard let collectionView, items.indices.contains(indexPath.item),
                let cell = collectionView.cellForItem(at: indexPath)
            else { return }
            menuButton?.removeFromSuperview()
            let button = FolderMenuAnchorButton(frame: .zero)
            button.frame = CGRect(x: cell.frame.midX, y: cell.frame.midY, width: 1, height: 1)
            button.alpha = 0.02
            button.isAccessibilityElement = false
            button.menu = parent.menu(items[indexPath.item])
            button.showsMenuAsPrimaryAction = true
            collectionView.addSubview(button)
            menuButton = button
            button.performPrimaryAction()
        }

        @objc private func scrollDuringMovement() {
            updateDragArtwork()
            guard dragActive, let scroll = scrollingParent, let window = scroll.window,
                let dragSession
            else { return }
            let viewport = scroll.convert(scroll.bounds, to: window)
            let finger = dragSession.location(in: window)
            let top = max(viewport.minY, window.safeAreaInsets.top) + 44
            let bottom = min(viewport.maxY, window.bounds.maxY - parent.bottomInset) - 44
            let frameTime = CGFloat(displayLink.map { $0.targetTimestamp - $0.timestamp } ?? (1.0 / 60.0))
            let delta: CGFloat
            if finger.y < top {
                delta = -min(540, max(90, (top - finger.y) * 7)) * frameTime
            } else if finger.y > bottom {
                delta = min(540, max(90, (finger.y - bottom) * 7)) * frameTime
            } else {
                delta = 0
            }
            if delta != 0 {
                let minimum = -scroll.adjustedContentInset.top
                let maximum = max(
                    minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                let y = min(maximum, max(minimum, scroll.contentOffset.y + delta))
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: y), animated: false)
            }
        }

        func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
            (session.localDragSession?.localContext as? Coordinator) === self
                || session.canLoadObjects(ofClass: NSString.self)
        }

        func collectionView(
            _ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
            withDestinationIndexPath destinationIndexPath: IndexPath?
        ) -> UICollectionViewDropProposal {
            if (session.localDragSession?.localContext as? Coordinator) === self {
                guard destinationIndexPath?.item != 0 else {
                    return UICollectionViewDropProposal(operation: .forbidden)
                }
                return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
            }
            return UICollectionViewDropProposal(operation: .copy, intent: .insertIntoDestinationIndexPath)
        }

        func collectionView(
            _ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator
        ) {
            if (coordinator.session.localDragSession?.localContext as? Coordinator) === self {
                guard let dropped = coordinator.items.first,
                    let route = dropped.dragItem.localObject as? ClassicFolderRoute,
                    let source = items.firstIndex(of: route), source > 0
                else { return }
                let destination = IndexPath(
                    item: min(
                        items.count - 1,
                        max(
                            1,
                            coordinator.destinationIndexPath?.item ?? items.count - 1)), section: 0)
                collectionView.performBatchUpdates {
                    items.remove(at: source)
                    items.insert(route, at: destination.item)
                    collectionView.moveItem(at: IndexPath(item: source, section: 0), to: destination)
                }
                coordinator.drop(dropped.dragItem, toItemAt: destination)
                parent.onReorder(items)
                return
            }
            guard let dropped = coordinator.items.first, let destination = coordinator.destinationIndexPath,
                items.indices.contains(destination.item)
            else { return }
            let key = items[destination.item].orderKey
            dropped.dragItem.itemProvider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                guard let value = value as? String else { return }
                Task { @MainActor [weak self] in
                    guard let self, let route = self.items.first(where: { $0.orderKey == key }) else { return }
                    self.parent.onTaskDrop(value, route)
                }
            }
        }
    }
}
/// The invisible menu anchor must never intercept the next tap on the folder underneath it.
private final class FolderMenuAnchorButton: UIButton {
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { false }
    override var canBecomeFocused: Bool { false }
}

#endif
