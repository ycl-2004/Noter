import AppKit
import Observation
import SwiftUI

@MainActor
private enum AppBrand {
    static let displayName = "Noter"
    static let subtitle = "by YC"
    static let monogram = "YC"
    static let artwork = loadArtwork()

    private static func loadArtwork() -> NSImage? {
        if let bundledURL = Bundle.main.url(forResource: "BrandArtwork", withExtension: "png"),
           let bundledImage = NSImage(contentsOf: bundledURL) {
            return bundledImage
        }

        let localPath = "/Users/yichenlin/Desktop/App/App_Icon.png"
        return NSImage(contentsOfFile: localPath)
    }
}

struct NotesCuratorRootView: View {
    @Bindable var model: NotesCuratorAppModel
    @State private var didLoad = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AppSidebar(model: model)
        } detail: {
            detailView
                .background(WorkspaceBackdrop())
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            guard !didLoad else { return }
            didLoad = true
            do {
                try await model.load()
            } catch {
                model.present(error: error)
            }
        }
        .alert(
            "Something needs attention",
            isPresented: Binding(
                get: { model.lastErrorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("OK") {
                model.clearError()
            }
        } message: {
            Text(model.lastErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch model.selectedSidebarSection {
        case .home:
            DashboardHomeView(model: model)
        case .workspaces:
            WorkspacesSectionView(model: model, columnVisibility: $columnVisibility)
        case .drafts:
            DraftsView(model: model)
        case .templates:
            TemplateLibraryView(model: model)
        case .exports:
            ExportsView(model: model)
        case .settings:
            SettingsView(model: model)
        }
    }
}

private struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.43, blue: 0.97),
                            Color(red: 0.37, green: 0.78, blue: 0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)

            Text(AppBrand.monogram)
                .font(.system(size: size * 0.34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(
            color: Color(red: 0.12, green: 0.43, blue: 0.97).opacity(0.18),
            radius: 14,
            x: 0,
            y: 8
        )
    }
}

private struct BrandedAppIcon: View {
    let size: CGFloat

    var body: some View {
        if let artwork = AppBrand.artwork {
            Image(nsImage: artwork)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.34, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                )
                .shadow(
                    color: Color.black.opacity(0.12),
                    radius: 16,
                    x: 0,
                    y: 8
                )
        } else {
            BrandMark(size: size)
        }
    }
}

private struct WorkspaceBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 1.0),
                    Color(red: 0.94, green: 0.96, blue: 0.99),
                    Color(red: 0.98, green: 0.98, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.10))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: 320, y: -220)

            Circle()
                .fill(Color.cyan.opacity(0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(x: -360, y: 260)
        }
        .ignoresSafeArea()
    }
}

private struct AppSidebar: View {
    @Bindable var model: NotesCuratorAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            branding
            newNoteButton
            navigationLinks

            Spacer(minLength: 28)

            activeWorkspaceCard
        }
        .padding(24)
        .frame(minWidth: 260, maxWidth: 280, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.95), Color(red: 0.93, green: 0.95, blue: 0.99)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var branding: some View {
        HStack(alignment: .top, spacing: 14) {
            BrandedAppIcon(size: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppBrand.displayName)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text(AppBrand.subtitle)
                    .font(.caption)
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 24)
    }

    private var newNoteButton: some View {
        Button {
            runModelTask(model) {
                try await model.beginNewNote(in: model.selectedWorkspaceID)
            }
        } label: {
            Label("New Note", systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PrimarySidebarButtonStyle())
    }

    private var navigationLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SidebarSection.allCases, id: \.self) { section in
                sidebarButton(for: section)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var activeWorkspaceCard: some View {
        Group {
            if let workspace = model.selectedWorkspace {
                let badge = SidebarWorkspaceBadgePresentation.compact(
                    workspaceName: workspace.name,
                    draftCount: model.workspaceItems(in: workspace.id, kind: .draft).count
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Workspace")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(badge.title)
                                .font(.headline)
                            Text(badge.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "rectangle.stack.badge.person.crop")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(8)
                            .background(Color.accentColor.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        model.selectedSidebarSection = .workspaces
                    } label: {
                        Label("Open Workspace", systemImage: "arrow.up.right.square")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(14)
                .background(Color.white.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.78), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private func sidebarButton(for section: SidebarSection) -> some View {
        Button {
            model.selectedSidebarSection = section
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: section))
                Text(title(for: section))
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(model.selectedSidebarSection == section ? Color.accentColor.opacity(0.14) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(model.selectedSidebarSection == section ? Color.accentColor : Color.primary)
    }

    private func title(for section: SidebarSection) -> String {
        switch section {
        case .home: "Home"
        case .workspaces: "Workspaces"
        case .drafts: "Drafts"
        case .templates: "Templates"
        case .exports: "Exports"
        case .settings: "Settings"
        }
    }

    private func icon(for section: SidebarSection) -> String {
        switch section {
        case .home: "house"
        case .workspaces: "rectangle.grid.2x2"
        case .drafts: "doc.text"
        case .templates: "wand.and.stars"
        case .exports: "square.and.arrow.up"
        case .settings: "gearshape"
        }
    }
}

private struct DashboardHomeView: View {
    @Bindable var model: NotesCuratorAppModel
    @State private var searchQuery = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if bodySections.contains(.resume) {
                    currentWorkSection
                }

                if bodySections.contains(.recentActivity) {
                    recentDrafts
                }

                if bodySections.contains(.quickActions) {
                    quickActions
                }

                if !filteredWorkspaces.isEmpty {
                    supportingWorkspaceSection
                }
            }
            .padding(32)
        }
        .task {
            await model.refreshProviderStatus()
        }
    }

    private var bodySections: [HomeSurfaceSection] {
        HomeSurfacePolicy.defaultSections(hasSavedSession: model.hasSavedSession)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resume Flow")
                        .font(.caption)
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    Text("Pick up the note that matters right now.")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("Keep workspaces as context, but keep today's active note at the center of intake, editing, review, and export.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 680, alignment: .leading)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    HStack(spacing: 10) {
                        StatusChip(
                            title: "Provider",
                            value: model.providerStatusMessage ?? "Checking...",
                            accent: (model.providerStatusMessage ?? "").localizedCaseInsensitiveContains("ready") ? .green : .orange
                        )
                        StatusChip(
                            title: "Session",
                            value: model.hasSavedSession ? "Ready to resume" : "Fresh workspace",
                            accent: model.hasSavedSession ? .blue : .gray
                        )
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search workspaces or drafts", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .frame(width: 280)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.78))
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }
            .padding(24)
            .background(Color.white.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .overlay(
                RoundedRectangle(cornerRadius: 30)
                    .stroke(Color.white.opacity(0.65), lineWidth: 1)
            )
        }
    }

    private var currentWorkSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Current Work", subtitle: "Return to the note that already has momentum.")

            Group {
                if model.hasSavedSession {
                    currentWorkCard(
                        eyebrow: "Ready to resume",
                        title: model.selectedDraftItem?.title ?? "Resume last session",
                        detail: model.selectedWorkspace?.name ?? "Workspace",
                        buttonTitle: "Resume Session",
                        buttonSystemImage: "arrow.clockwise"
                    ) {
                        runModelTask(model) {
                            try await model.resumeLastSession()
                        }
                    }
                } else if let workspace = model.selectedWorkspace ?? model.workspaces.first {
                    currentWorkCard(
                        eyebrow: "Current workspace",
                        title: workspace.name,
                        detail: "Start a new note without leaving your workspace context.",
                        buttonTitle: "Start New Note",
                        buttonSystemImage: "plus"
                    ) {
                        runModelTask(model) {
                            try await model.beginNewNote(in: workspace.id)
                        }
                    }
                } else {
                    currentWorkCard(
                        eyebrow: "Fresh start",
                        title: "Create your first workspace",
                        detail: "Set up a workspace first, then move one note through the full Noter flow.",
                        buttonTitle: "New Workspace",
                        buttonSystemImage: "square.grid.2x2"
                    ) {
                        runModelTask(model) {
                            _ = try await model.createWorkspace(named: "Untitled Workspace")
                        }
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Quick Actions", subtitle: "Jump back into work immediately.")
            HStack(spacing: 16) {
                QuickActionCard(
                    title: "New Workspace",
                    subtitle: "Create a fresh folder-like project.",
                    icon: "square.grid.2x2.fill"
                ) {
                    runModelTask(model) {
                        _ = try await model.createWorkspace(named: "Untitled Workspace")
                    }
                }
                QuickActionCard(
                    title: "Import Text",
                    subtitle: "Paste or upload source material into a new note.",
                    icon: "tray.and.arrow.down.fill"
                ) {
                    runModelTask(model) {
                        try await model.beginNewNote(in: model.selectedWorkspaceID)
                    }
                }
                QuickActionCard(
                    title: "Resume Last Session",
                    subtitle: model.hasSavedSession ? "Return to the last draft you were editing." : "No saved working session yet.",
                    icon: "clock.arrow.circlepath",
                    isDisabled: !model.hasSavedSession
                ) {
                    runModelTask(model) {
                        try await model.resumeLastSession()
                    }
                }
            }
        }
    }

    private var supportingWorkspaceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Workspaces", subtitle: "Keep nearby project context visible without turning Home into another dashboard.")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 18)], spacing: 18) {
                ForEach(filteredWorkspaces.prefix(3)) { workspace in
                    WorkspaceCard(workspace: workspace, draftCount: model.workspaceItems(in: workspace.id, kind: .draft).count) {
                        runModelTask(model) {
                            try await model.openWorkspace(workspace.id)
                        }
                    }
                }
            }
        }
    }

    private var recentDrafts: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(title: "Recent Activity", subtitle: "Recent notes stay close so you can reopen them fast.")

            if filteredDrafts.isEmpty {
                Text("No recent notes yet. Start a new note to create your first active flow.")
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            } else {
                VStack(spacing: 12) {
                    ForEach(filteredDrafts.prefix(5)) { draft in
                        DraftRowCard(
                            item: draft,
                            action: {
                                runModelTask(model) {
                                    try await model.openDraft(draft.id)
                                }
                            },
                            onDelete: {
                                runModelTask(model) {
                                    try await model.deleteWorkspaceItem(draft.id)
                                }
                            }
                        )
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func currentWorkCard(
        eyebrow: String,
        title: String,
        detail: String,
        buttonTitle: String,
        buttonSystemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(eyebrow)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .foregroundStyle(.secondary)
            }

            Button(action: action) {
                Label(buttonTitle, systemImage: buttonSystemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var filteredWorkspaces: [Workspace] {
        guard !searchQuery.isEmpty else { return model.workspaces }
        return model.workspaces.filter { workspace in
            workspace.name.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    private var filteredDrafts: [WorkspaceItem] {
        guard !searchQuery.isEmpty else { return model.recentDrafts }
        return model.recentDrafts.filter { draft in
            draft.title.localizedCaseInsensitiveContains(searchQuery)
                || draft.summaryPreview.localizedCaseInsensitiveContains(searchQuery)
        }
    }
}

private struct WorkspacesSectionView: View {
    @Bindable var model: NotesCuratorAppModel
    @Binding var columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        if let workspace = model.selectedWorkspace {
            if let selectedItem = model.selectedDraftItem,
               selectedItem.workspaceId == workspace.id,
               model.currentFlow != nil {
                ProjectWorkspaceView(
                    model: model,
                    workspace: workspace,
                    item: selectedItem,
                    columnVisibility: $columnVisibility
                )
            } else {
                WorkspaceDetailView(model: model, workspace: workspace)
            }
        } else {
            DashboardHomeView(model: model)
        }
    }
}

private struct WorkspaceDetailView: View {
    @Bindable var model: NotesCuratorAppModel
    let workspace: Workspace
    @State private var showOlderItems = false
    @State private var showWorkspaceEditor = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 20) {
                            workspaceHeaderText
                            Spacer()
                            HStack(spacing: 10) {
                                customizeWorkspaceButton
                                newNoteButton
                            }
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            workspaceHeaderText
                            HStack(spacing: 10) {
                                customizeWorkspaceButton
                                newNoteButton
                            }
                        }
                    }
                    .padding(24)
                    .background(Color.white.opacity(0.62))
                    .clipShape(RoundedRectangle(cornerRadius: 28))

                    workspaceStatusStrip

                    ResponsiveSplitLayout(
                        leadingMinWidth: 280,
                        trailingMinWidth: 760,
                        leadingFixedWidth: 290,
                        spacing: 24
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            workspaceFocusPanel

                            if selectedItem != nil {
                                if !nonSelectedItems.isEmpty {
                                    workspaceHistoryRail
                                }
                            } else {
                                if !recentItems.isEmpty {
                                    workspaceRailSection(
                                        title: "Recent Notes",
                                        subtitle: "The workspace shell stays light while your active note takes the main canvas."
                                    ) {
                                        VStack(spacing: 10) {
                                            ForEach(recentItems) { item in
                                                railCard(for: item)
                                            }
                                        }
                                    }
                                }

                                if !olderItems.isEmpty {
                                    DisclosureGroup(isExpanded: $showOlderItems) {
                                        VStack(spacing: 10) {
                                            ForEach(olderItems) { item in
                                                railCard(for: item)
                                            }
                                        }
                                        .padding(.top, 10)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Earlier in This Workspace")
                                                    .font(.headline)
                                                Text("\(olderItems.count) older drafts stay out of the way until you need to reopen them.")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                        }
                                    }
                                    .padding(18)
                                    .background(Color.white.opacity(0.62))
                                    .clipShape(RoundedRectangle(cornerRadius: 22))
                                }
                            }
                        }
                    } trailing: {
                        Group {
                            if model.selectedWorkspaceID == workspace.id, let currentFlow = model.currentFlow {
                                WorkspaceFlowContainer(model: model, flow: currentFlow, workspace: workspace)
                            } else {
                                EmptyWorkspaceState()
                            }
                        }
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(!showWorkspaceEditor)
            }

            if showWorkspaceEditor {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showWorkspaceEditor = false
                    }

                WorkspaceCustomizationSheet(
                    model: model,
                    workspace: workspace,
                    onDismiss: {
                        showWorkspaceEditor = false
                    }
                )
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .zIndex(1)
            }
        }
    }

    private var workspaceHeaderText: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(workspace.coverBadgeTitle)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                Text("Workspace")
                    .font(.caption)
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }
                Text(workspace.name)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(workspace.subtitle)
                    .foregroundStyle(.secondary)
        }
    }

    private var customizeWorkspaceButton: some View {
        Button("Customize") {
            showWorkspaceEditor = true
        }
        .buttonStyle(.bordered)
    }

    private var newNoteButton: some View {
        Button("New Note") {
            runModelTask(model) {
                try await model.beginNewNote(in: workspace.id)
            }
        }
        .buttonStyle(.borderedProminent)
    }

    private var workspaceStatusStrip: some View {
        HStack(spacing: 10) {
            InfoPill(title: "Drafts", value: "\(workspaceDrafts.count)")
            InfoPill(
                title: "Active Note",
                value: selectedItem?.title ?? "None"
            )
            if let latestDraft = workspaceDrafts.first {
                InfoPill(
                    title: "Last Edited",
                    value: latestDraft.lastEditedAt.formatted(date: .abbreviated, time: .shortened)
                )
            }
            Spacer()
            Text(summaryLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var workspaceDrafts: [WorkspaceItem] {
        model.workspaceItems(in: workspace.id, kind: .draft)
    }

    private var selectedItem: WorkspaceItem? {
        guard let item = model.selectedDraftItem, item.workspaceId == workspace.id else {
            return nil
        }
        return item
    }

    private var nonSelectedItems: [WorkspaceItem] {
        guard let selectedItem else { return workspaceDrafts }
        return workspaceDrafts.filter { $0.id != selectedItem.id }
    }

    private var recentItems: [WorkspaceItem] {
        Array(nonSelectedItems.prefix(selectedItem == nil ? 4 : 3))
    }

    private var olderItems: [WorkspaceItem] {
        Array(nonSelectedItems.dropFirst(selectedItem == nil ? 4 : 3))
    }

    private var summaryLabel: String {
        let count = workspaceDrafts.count
        if count == 0 {
            return "No drafts yet"
        }
        if count == 1 {
            return "1 draft in this workspace"
        }
        return "\(count) drafts in this workspace"
    }

    private var workspaceFocusPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedItem {
                workspaceRailSection(
                    title: "Focus",
                    subtitle: flowFocusSubtitle(for: selectedItem)
                ) {
                    railCard(for: selectedItem, isActive: true)
                }
            } else {
                workspaceRailSection(
                    title: "Focus",
                    subtitle: "Open or create the note you're actively shaping so the workspace shell can stay quiet around it."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nothing is pinned yet")
                            .font(.headline)
                        Text("Older workspace content will stay compact while your active note takes the main stage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Start New Note") {
                            runModelTask(model) {
                                try await model.beginNewNote(in: workspace.id)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }

    private var workspaceHistoryRail: some View {
        workspaceRailSection(
            title: "In This Workspace",
            subtitle: "Nearby drafts stay in a compact rail while the active note owns the canvas."
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(nonSelectedItems) { item in
                        compactWorkspaceCard(for: item)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func workspaceRailSection<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(18)
        .background(Color.white.opacity(0.58))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func railCard(for item: WorkspaceItem, isActive: Bool = false) -> some View {
        DraftRowCard(
            item: item,
            action: {
                if item.kind == .draft {
                    runModelTask(model) {
                        try await model.openDraft(item.id)
                    }
                }
            },
            onDelete: {
                runModelTask(model) {
                    try await model.deleteWorkspaceItem(item.id)
                }
            },
            isActive: isActive,
            compact: true
        )
    }

    private func compactWorkspaceCard(for item: WorkspaceItem) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if item.kind == .draft {
                    runModelTask(model) {
                        try await model.openDraft(item.id)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(item.lastEditedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(item.summaryPreview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        if item.status != .ready {
                            DraftStatusBadge(status: item.status)
                        }
                        if item.refinementStatus != .none {
                            DraftRefinementBadge(status: item.refinementStatus)
                        }
                        Text(item.kind == .draft ? "Draft" : item.kind.rawValue.capitalized)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(width: 240, alignment: .topLeading)
                .background(Color.white.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                runModelTask(model) {
                    try await model.deleteWorkspaceItem(item.id)
                }
            } label: {
                Image(systemName: item.status == .processing ? "stop.fill" : "trash")
                    .font(.caption.weight(.bold))
                    .padding(8)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(10)
            .help(deleteHelpText(for: item))
        }
    }

    private func deleteHelpText(for item: WorkspaceItem) -> String {
        switch item.status {
        case .processing:
            return "Stop processing and delete draft"
        case .failed:
            return "Delete failed draft"
        case .ready:
            switch item.kind {
            case .draft, .note:
                return "Delete note"
            case .export:
                return "Delete export"
            case .template:
                return "Delete item"
            }
        }
    }

    private func flowFocusSubtitle(for item: WorkspaceItem) -> String {
        switch item.status {
        case .processing:
            return "This is the active item. Keep the surrounding workspace quiet while processing finishes."
        case .failed:
            return "This item needs attention before you continue. Older drafts stay collapsed below."
        case .ready:
            if model.currentFlow == .editing {
                return "Editing stays centered here while older workspace history remains tucked away."
            }
            if model.currentFlow == .preview || model.currentFlow == .export {
                return "Preview and export stay focused on this item while the rest of the workspace is collapsed."
            }
            return "This is the current workspace focus."
        }
    }
}

private struct WorkspaceFlowContainer: View {
    @Bindable var model: NotesCuratorAppModel
    let flow: WorkspaceFlowStage
    let workspace: Workspace
    var fullHeight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FlowStageStrip(currentFlow: flow)

            switch flow {
            case .intake:
                NewNoteIntakeView(model: model, workspace: workspace)
            case .processing:
                ProcessingView(model: model)
            case .editing:
                EditDocumentView(model: model, fullHeight: fullHeight)
            case .preview:
                PreviewView(model: model, fullHeight: fullHeight)
            case .export:
                ExportPageView(model: model, fullHeight: fullHeight)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: fullHeight ? .infinity : nil, alignment: .topLeading)
        .background(Color.white.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 30))
    }
}

private struct ProjectWorkspaceView: View {
    @Bindable var model: NotesCuratorAppModel
    let workspace: Workspace
    let item: WorkspaceItem
    @Binding var columnVisibility: NavigationSplitViewVisibility

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            projectHeader

            if let currentFlow = model.currentFlow {
                WorkspaceFlowContainer(model: model, flow: currentFlow, workspace: workspace, fullHeight: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var headerPresentation: FocusCanvasHeaderPresentation {
        FocusCanvasHeaderPresentation(
            workspaceName: workspace.name,
            noteTitle: item.title,
            showsLargeDuplicatedTitle: false
        )
    }

    private var projectHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 10) {
                Button {
                    runModelTask(model) {
                        try await model.showWorkspaceOverview()
                    }
                } label: {
                    Label("Back to Workspace", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                VStack(alignment: .leading, spacing: 2) {
                    Text(headerPresentation.workspaceName)
                        .font(.caption)
                        .tracking(1.6)
                        .foregroundStyle(.secondary)
                    Text(headerPresentation.noteTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    toggleSidebar()
                } label: {
                    Label(
                        columnVisibility == .detailOnly ? "Show Sidebar" : "Hide Sidebar",
                        systemImage: "sidebar.left"
                    )
                }
                .buttonStyle(.bordered)

                Button("New Note") {
                    runModelTask(model) {
                        try await model.beginNewNote(in: workspace.id)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.44))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func toggleSidebar() {
        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
    }
}

private struct NewNoteIntakeView: View {
    @Bindable var model: NotesCuratorAppModel
    let workspace: Workspace
    @State private var pastedText = ""
    @State private var fileURLs: [URL] = []
    @State private var outputLanguage: OutputLanguage = .english
    @State private var contentTemplateName = "Structured Notes"
    @State private var visualTemplateName = "Oceanic Blue"

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle(title: "New Note", subtitle: "Paste first, then lightly choose the goal.")
            HStack(spacing: 10) {
                InfoPill(title: "Workspace", value: workspace.name)
                InfoPill(title: "Language", value: outputLanguage == .chinese ? "中文" : "English")
                InfoPill(title: "Files", value: fileURLs.isEmpty ? "None yet" : "\(fileURLs.count) attached")
            }

            ResponsiveSplitLayout(
                leadingMinWidth: 620,
                trailingMinWidth: 320,
                trailingFixedWidth: 320
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    ClipboardTextEditor(text: $pastedText)
                        .font(.body)
                        .padding(18)
                        .frame(minHeight: 360)
                        .background(Color.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 24))

                    HStack {
                        Button("Add Files") {
                            Task { @MainActor in
                                let urls = await presentOpenPanelURLs { panel in
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = true
                                    panel.allowedContentTypes = [.text, .plainText, .pdf, .rtf, .data]
                                }
                                if !urls.isEmpty {
                                    appendFiles(urls)
                                }
                            }
                        }
                        .buttonStyle(.bordered)

                        if !fileURLs.isEmpty {
                            Button("Clear All", role: .destructive) {
                                fileURLs.removeAll()
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }

                    if !fileURLs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(fileURLs, id: \.path) { url in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(url.lastPathComponent)
                                            .font(.subheadline.weight(.semibold))
                                        Text(url.deletingLastPathComponent().path)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Button(role: .destructive) {
                                        removeFile(url)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(14)
                                .background(Color.white.opacity(0.88))
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                            }
                        }
                    }

                    Text("Supports pasted text, TXT, Markdown, DOCX, and PDF. Images inside DOCX/PDF will be inspected for OCR and suggestion generation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } trailing: {
                VStack(alignment: .leading, spacing: 18) {
                    ControlPanelCard(title: "Output Type") {
                        Text(resolvedGoalType.displayName)
                            .font(.headline)
                        Text("This now follows the content template, so you are not choosing the same structure twice.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    ControlPanelCard(title: "Output Language") {
                        Picker("Language", selection: $outputLanguage) {
                            Text("English").tag(OutputLanguage.english)
                            Text("中文").tag(OutputLanguage.chinese)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    ControlPanelCard(title: "Templates") {
                        Picker("Content Template", selection: $contentTemplateName) {
                            ForEach(model.contentTemplates, id: \.name) { template in
                                Text(template.name).tag(template.name)
                            }
                        }
                        .labelsHidden()

                        Picker("Visual Template", selection: $visualTemplateName) {
                            ForEach(model.visualTemplates, id: \.name) { template in
                                Text(template.name).tag(template.name)
                            }
                        }
                        .labelsHidden()
                    }

                    Button {
                        runModelTask(model) {
                            try await model.startProcessingNewNote(
                                in: workspace.id,
                                intake: IntakeRequest(
                                    pastedText: pastedText,
                                    fileURLs: fileURLs,
                                    goalType: resolvedGoalType,
                                    outputLanguage: outputLanguage,
                                    contentTemplateName: contentTemplateName,
                                    visualTemplateName: visualTemplateName
                                )
                            )
                        }
                    } label: {
                        Label("Start Curating", systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && fileURLs.isEmpty)
                }
            }
        }
        .onAppear {
            outputLanguage = model.preferences.defaultOutputLanguage
        }
        .onAppear {
            if let pendingContent = model.pendingContentTemplateName {
                contentTemplateName = pendingContent
                model.pendingContentTemplateName = nil
            }
            if let pendingVisual = model.pendingVisualTemplateName {
                visualTemplateName = pendingVisual
                model.pendingVisualTemplateName = nil
            }
            if model.contentTemplates.contains(where: { $0.name == contentTemplateName }) == false,
               let firstTemplate = model.contentTemplates.first {
                contentTemplateName = firstTemplate.name
            }
        }
    }

    private var resolvedGoalType: GoalType {
        model.contentTemplates
            .first(where: { $0.name == contentTemplateName })?
            .configuredGoalType ?? .structuredNotes
    }

    private func appendFiles(_ urls: [URL]) {
        let existingPaths = Set(fileURLs.map(\.path))
        let newURLs = urls.filter { !existingPaths.contains($0.path) }
        fileURLs.append(contentsOf: newURLs)
    }

    private func removeFile(_ url: URL) {
        fileURLs.removeAll { $0.path == url.path }
    }
}

private struct ProcessingView: View {
    @Bindable var model: NotesCuratorAppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle(title: "AI Processing", subtitle: "Accuracy-first pipeline with visible stages.")
                let progress = processingProgress
                VStack(alignment: .leading, spacing: 10) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                    HStack {
                        if currentActiveStage != nil {
                            ProcessingActivityDots(referenceDate: context.date)
                        }
                        Text(currentStageDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(progress * 100))%")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(18)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 20))

                if let activeStage = currentActiveStage {
                    HStack(alignment: .top, spacing: 14) {
                        ProcessingActivityDots(referenceDate: context.date, size: 7)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Running \(stageLabel(activeStage))")
                                .font(.headline)
                            Text(stageHint(for: activeStage))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(stageElapsedLabel(referenceDate: context.date))
                                .font(.headline.monospacedDigit())
                            if let totalLabel = totalElapsedLabel(referenceDate: context.date) {
                                Text("Total \(totalLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ProcessingStage.allCases, id: \.self) { stage in
                        HStack {
                            stageIndicator(for: stage, referenceDate: context.date)
                            Text(stageLabel(stage))
                                .font(.headline)
                            Spacer()
                            Text(statusLabel(for: stage, referenceDate: context.date))
                                .foregroundStyle(stage == currentActiveStage ? Color.accentColor : .secondary)
                                .fontWeight(stage == currentActiveStage ? .semibold : .regular)
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(24)
                .background(Color.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
        }
    }

    private var processingProgress: Double {
        let visibleStages = ProcessingStage.allCases.filter { $0 != .completed }
        guard !visibleStages.isEmpty else { return 0 }
        let completed = model.processingStages.filter { $0 != .completed }.count
        return min(Double(completed) / Double(visibleStages.count), 1)
    }

    private var currentStageDescription: String {
        guard let last = model.processingStages.last else {
            return "Waiting for the local pipeline to begin."
        }
        switch last {
        case .parseDocument:
            return "Normalizing input sources and preparing content."
        case .extractText:
            return "Collecting long-form text from pasted and uploaded material."
        case .extractImages:
            return "Inspecting imported files for visual evidence worth preserving."
        case .runOCR:
            return "Reading embedded image text with on-device OCR."
        case .chunkAndMerge:
            return "Digesting long content and merging chunk summaries. This can take a while on local models."
        case .renderOutputLanguage:
            return "Rendering the final response in the selected output language. The app is still working."
        case .validateDraft:
            return "Checking for missing points and cleaning the structure."
        case .generateImageSuggestions:
            return "Preparing suggested images for the editor rail."
        case .completed:
            return "The draft is ready for editing."
        }
    }

    private func stageLabel(_ stage: ProcessingStage) -> String {
        switch stage {
        case .parseDocument: "Parse document"
        case .extractText: "Extract text"
        case .extractImages: "Detect images"
        case .runOCR: "Run OCR"
        case .chunkAndMerge: "Chunk and merge"
        case .renderOutputLanguage: "Render output language"
        case .validateDraft: "Validate draft"
        case .generateImageSuggestions: "Generate image suggestions"
        case .completed: "Complete"
        }
    }

    private var currentActiveStage: ProcessingStage? {
        guard let last = model.processingStages.last, last != .completed else { return nil }
        return last
    }

    @ViewBuilder
    private func stageIndicator(for stage: ProcessingStage, referenceDate: Date) -> some View {
        if stage == currentActiveStage {
            HStack(spacing: 4) {
                ProcessingActivityDots(referenceDate: referenceDate, size: 5)
            }
            .frame(width: 18, alignment: .leading)
        } else if model.processingStages.contains(stage) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
        } else {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: 12, height: 12)
                .frame(width: 18)
        }
    }

    private func statusLabel(for stage: ProcessingStage, referenceDate: Date) -> String {
        if stage == currentActiveStage { return "Running \(stageElapsedLabel(referenceDate: referenceDate))" }
        if model.processingStages.contains(stage) { return "Done" }
        return "Pending"
    }

    private func stageElapsedLabel(referenceDate: Date) -> String {
        guard let startedAt = model.currentProcessingStageStartedAt else { return "0s" }
        return formatDuration(referenceDate.timeIntervalSince(startedAt))
    }

    private func totalElapsedLabel(referenceDate: Date) -> String? {
        guard let startedAt = model.processingStartedAt else { return nil }
        return formatDuration(referenceDate.timeIntervalSince(startedAt))
    }

    private func formatDuration(_ rawSeconds: TimeInterval) -> String {
        let seconds = max(Int(rawSeconds.rounded(.down)), 0)
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(remainder)s"
        }
        return "\(remainder)s"
    }

    private func stageHint(for stage: ProcessingStage) -> String {
        switch stage {
        case .chunkAndMerge:
            return "Long inputs are being condensed into smaller summaries before the final note is generated."
        case .renderOutputLanguage:
            return "This is often the slowest local-model step. If the timer is moving, the app is still alive."
        case .validateDraft:
            return "The structure is being cleaned up and checked for missing details."
        case .generateImageSuggestions:
            return "OCR-derived visual suggestions are being prepared for the editor."
        case .parseDocument, .extractText, .extractImages, .runOCR, .completed:
            return currentStageDescription
        }
    }
}

private struct EditDocumentView: View {
    @Bindable var model: NotesCuratorAppModel
    @State private var editorText = ""
    @State private var showSources = false
    @State private var showRefinedComparison = false
    var fullHeight = false

    private var editorPanelHeight: CGFloat {
        fullHeight ? 620 : 520
    }

    var body: some View {
        if let version = model.currentVersion {
            ResponsiveSplitLayout(
                leadingMinWidth: 960,
                trailingMinWidth: 320,
                trailingFixedWidth: 320
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            SectionTitle(title: "Edit", subtitle: "Refine the current note here, then move into review when the structure feels right.")
                            Spacer()
                            editorActions
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            SectionTitle(title: "Edit", subtitle: "Refine the current note here, then move into review when the structure feels right.")
                            editorActions
                        }
                    }

                    HStack(spacing: 10) {
                        InfoPill(title: "Words", value: "\(wordCount(for: editorText))")
                        InfoPill(title: "Images", value: "\(version.imageSuggestions.filter(\.isSelected).count) selected")
                        if let item = model.selectedDraftItem, item.refinementStatus != .none {
                            InfoPill(title: "Refinement", value: refinementLabel(for: item.refinementStatus))
                        }
                    }

                    if let item = model.selectedDraftItem, item.refinementStatus != .none {
                        refinementBanner(for: item)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Document")
                            .font(.headline)

                        KeyboardFriendlyTextEditor(text: $editorText) {
                            commitEditorChanges()
                        }
                        .padding(20)
                        .frame(height: editorPanelHeight)
                        .background(Color.white.opacity(0.96))
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .onAppear {
                        editorText = version.editorDocument
                    }
                    .onChange(of: version.id) { _, _ in
                        if let currentVersion = model.currentVersion {
                            editorText = currentVersion.editorDocument
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: fullHeight ? .infinity : nil, alignment: .topLeading)
            } trailing: {
                EditInspectorPanel(
                    version: version,
                    showSources: $showSources,
                    onInsertImage: { imageID in
                        runModelTask(model) {
                            try await model.insertImageSuggestion(imageID)
                            if let refreshed = model.currentVersion?.editorDocument {
                                editorText = refreshed
                            }
                        }
                    }
                )
            }
            .sheet(isPresented: $showRefinedComparison) {
                if let currentVersion = model.currentVersion,
                   let refinedVersion = model.pendingRefinedVersion {
                    RefinedComparisonSheet(
                        currentVersion: currentVersion,
                        refinedVersion: refinedVersion,
                        onClose: { showRefinedComparison = false },
                        onApply: {
                            runModelTask(model) {
                                try await model.applyPendingRefinedVersion()
                                if let refreshed = model.currentVersion?.editorDocument {
                                    editorText = refreshed
                                }
                                showRefinedComparison = false
                            }
                        },
                        onDismissUpgrade: {
                            runModelTask(model) {
                                try await model.dismissPendingRefinedVersion()
                                showRefinedComparison = false
                            }
                        }
                    )
                }
            }
        } else if let failedItem = model.selectedDraftItem, failedItem.status == .failed {
            FailedDraftState(model: model, item: failedItem)
        } else if let processingItem = model.selectedDraftItem, processingItem.status == .processing {
            PendingDraftState(model: model, item: processingItem)
        } else {
            EmptyWorkspaceState()
        }
    }

    private var editorActions: some View {
        HStack(spacing: 12) {
            Button("Save Version") {
                commitAndSaveVersion()
            }
            .buttonStyle(.bordered)

            Button("Open Format Preview") {
                commitAndOpenPreview()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func refinementBanner(for item: WorkspaceItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch item.refinementStatus {
            case .refining:
                Label("Refining in the background", systemImage: "wand.and.stars")
                    .font(.headline)
                Text("You can keep editing this draft. A refined version will appear as a safe upgrade when it is ready.")
                    .foregroundStyle(.secondary)
            case .refined:
                Label("Refined version ready", systemImage: "sparkles.rectangle.stack")
                    .font(.headline)
                Text("Your current draft stays untouched. Compare the refinement first, then apply or dismiss the upgrade.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Compare Versions") {
                        showRefinedComparison = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Apply Refined Version") {
                        runModelTask(model) {
                            try await model.applyPendingRefinedVersion()
                            if let refreshed = model.currentVersion?.editorDocument {
                                editorText = refreshed
                            }
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Dismiss Upgrade") {
                        runModelTask(model) {
                            try await model.dismissPendingRefinedVersion()
                        }
                    }
                    .buttonStyle(.bordered)
                }
            case .failed:
                Label("Refinement failed", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text("Your editable draft is safe. The background polish and normalization pass did not finish.")
                    .foregroundStyle(.secondary)
            case .none:
                EmptyView()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.accentColor.opacity(0.12), lineWidth: 1)
        )
    }

    private func refinementLabel(for status: DraftRefinementStatus) -> String {
        switch status {
        case .none: "None"
        case .refining: "Refining"
        case .refined: "Ready"
        case .failed: "Failed"
        }
    }

    private func commitEditorChanges() {
        runModelTask(model) {
            try await model.updateEditorDocument(editorText)
        }
    }

    private func commitAndSaveVersion() {
        runModelTask(model) {
            try await model.updateEditorDocument(editorText)
            try await model.saveManualVersion()
        }
    }

    private func commitAndOpenPreview() {
        runModelTask(model) {
            try await model.updateEditorDocument(editorText)
            model.showPreview()
        }
    }

    private func editorDisplayTitle(fallback: String) -> String {
        EditorDocumentSync.inferredTitle(document: editorText, fallback: fallback)
    }
}

private struct EditInspectorPanel: View {
    let version: DraftVersion
    @Binding var showSources: Bool
    let onInsertImage: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InspectorSuggestionsCard(keyPoints: version.structuredDoc.keyPoints)
                    .equatable()

                InspectorImagesCard(
                    images: version.imageSuggestions,
                    onInsertImage: onInsertImage
                )
                .equatable()

                DisclosureGroup("Source Drawer", isExpanded: $showSources) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(version.sourceRefs) { source in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.title).font(.headline)
                                Text(source.excerpt)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(16)
                .background(Color.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
    }
}

private struct InspectorSuggestionsCard: View, Equatable {
    let keyPoints: [String]

    var body: some View {
        ControlPanelCard(title: "AI Suggestions") {
            ForEach(keyPoints, id: \.self) { point in
                Text("• \(point)")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct InspectorImagesCard: View, Equatable {
    let images: [ImageSuggestion]
    let onInsertImage: (UUID) -> Void

    nonisolated static func == (lhs: InspectorImagesCard, rhs: InspectorImagesCard) -> Bool {
        lhs.images == rhs.images
    }

    var body: some View {
        ControlPanelCard(title: "Important Images") {
            if images.isEmpty {
                Text("No image suggestions for this draft.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(images) { image in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(image.title).font(.headline)
                            Spacer()
                            if image.isSelected {
                                Text("Inserted")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.14))
                                    .clipShape(Capsule())
                            } else {
                                Button("Insert") {
                                    onInsertImage(image.id)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        Text(image.summary).foregroundStyle(.secondary)
                        Text(image.ocrText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 10)
                }
            }
        }
    }
}

private struct RefinedComparisonSheet: View {
    let currentVersion: DraftVersion
    let refinedVersion: DraftVersion
    let onClose: () -> Void
    let onApply: () -> Void
    let onDismissUpgrade: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compare Draft Upgrade")
                        .font(.title2.bold())
                    Text("Review the background refinement before replacing your current editable draft.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") {
                    onClose()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                InfoPill(title: "Current Words", value: "\(wordCount(for: currentVersion.editorDocument))")
                InfoPill(title: "Refined Words", value: "\(wordCount(for: refinedVersion.editorDocument))")
                InfoPill(title: "Current Version", value: currentVersion.origin.rawValue.capitalized)
                InfoPill(title: "Upgrade", value: refinedVersion.origin.rawValue.capitalized)
            }

            HStack(alignment: .top, spacing: 16) {
                comparisonColumn(
                    title: "Current Draft",
                    summary: currentVersion.structuredDoc.summary,
                    document: currentVersion.editorDocument
                )
                comparisonColumn(
                    title: "Refined Draft",
                    summary: refinedVersion.structuredDoc.summary,
                    document: refinedVersion.editorDocument
                )
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 12) {
                Button("Dismiss Upgrade") {
                    onDismissUpgrade()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Apply Refined Version") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(minWidth: 980, minHeight: 680, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func comparisonColumn(title: String, summary: String, document: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            Text(summary)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            ScrollView {
                Text(document)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(20)
            }
            .background(Color.white.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DraftPreviewSurface: View {
    let version: DraftVersion
    let format: ExportFormat

    private let exporter = ExportCoordinator()

    var body: some View {
        if format.usesSourcePreview {
            Text(exporter.previewText(draft: version, format: format))
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(28)
                .background(Color.white.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 28))
        } else {
            StyledDraftPreview(version: version)
        }
    }
}

private struct StableDocumentScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            content
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .defaultScrollAnchor(.top)
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PreviewView: View {
    @Bindable var model: NotesCuratorAppModel
    @State private var format: ExportFormat = .markdown
    @State private var selectedVisualTemplate = "Oceanic Blue"
    var fullHeight = false

    var body: some View {
        if let version = model.currentVersion {
            let previewVersion = version.previewVersion(visualTemplateName: selectedVisualTemplate)
            VStack(alignment: .leading, spacing: 18) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        SectionTitle(title: "Preview", subtitle: "Switch among note-friendly export formats before saving.")
                        Spacer()
                        previewFormatPicker
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(title: "Preview", subtitle: "Switch among note-friendly export formats before saving.")
                        previewFormatPicker
                    }
                }

                HStack(spacing: 10) {
                    InfoPill(title: "Template", value: selectedVisualTemplate)
                    InfoPill(title: "Language", value: version.outputLanguage == .chinese ? "中文" : "English")
                    InfoPill(title: "Format", value: format.shortLabel)
                }

                ControlPanelCard(title: "Visual Template") {
                    Picker("Visual Template", selection: $selectedVisualTemplate) {
                        ForEach(model.visualTemplates, id: \.name) { template in
                            Text(template.name).tag(template.name)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)

                    Text("Change the color theme directly here if the original choice was wrong. Export will follow this selection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                StableDocumentScrollView {
                    DraftPreviewSurface(version: previewVersion, format: format)
                }

                HStack {
                    Button("Back to Editing") {
                        model.goBackToEditing()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Continue to Export") {
                        model.showExport()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onAppear {
                format = model.preferences.defaultExportFormat
                selectedVisualTemplate = version.structuredDoc.exportMetadata.visualTemplateName
            }
            .onChange(of: version.structuredDoc.exportMetadata.visualTemplateName) { _, newValue in
                selectedVisualTemplate = newValue
            }
            .onChange(of: selectedVisualTemplate) { _, newValue in
                guard model.currentVersion?.structuredDoc.exportMetadata.visualTemplateName != newValue else { return }
                runModelTask(model) {
                    try await model.updateVisualTemplate(newValue)
                }
            }
        }
    }

    private var previewFormatPicker: some View {
        Picker("Format", selection: $format) {
            ForEach(ExportFormat.allCases, id: \.self) { option in
                Text(option.displayName).tag(option)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 240)
    }
}

private struct ExportPageView: View {
    @Bindable var model: NotesCuratorAppModel
    @State private var selectedFormat: ExportFormat = .pdf
    @State private var selectedVisualTemplate = "Oceanic Blue"
    @State private var exportResult: String?
    @State private var lastExportURL: URL?
    private let exporter = ExportCoordinator()
    var fullHeight = false

    var body: some View {
        if let version = model.currentVersion {
            let previewVersion = version.previewVersion(visualTemplateName: selectedVisualTemplate)
            ResponsiveSplitLayout(
                leadingMinWidth: 760,
                trailingMinWidth: 320,
                trailingFixedWidth: 320
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(title: "Export Document", subtitle: "Large preview plus final export controls.")
                    StableDocumentScrollView {
                        if selectedFormat.usesSourcePreview {
                            Text(exporter.previewText(draft: previewVersion, format: selectedFormat))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .font(.system(.body, design: .monospaced))
                                .padding(28)
                                .background(Color.white.opacity(0.96))
                                .clipShape(RoundedRectangle(cornerRadius: 28))
                        } else {
                            StyledDraftPreview(version: previewVersion)
                        }
                    }
                }
            } trailing: {
                VStack(alignment: .leading, spacing: 18) {
                    ControlPanelCard(title: "Format") {
                        Picker("Format", selection: $selectedFormat) {
                            ForEach(ExportFormat.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)

                        Text(selectedFormat.compatibilityLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ControlPanelCard(title: "Visual Template") {
                        Picker("Template", selection: $selectedVisualTemplate) {
                            ForEach(model.visualTemplates, id: \.name) { template in
                                Text(template.name).tag(template.name)
                            }
                        }
                        .labelsHidden()
                    }

                    ControlPanelCard(title: "Current Output Language") {
                        Text(model.currentVersion?.outputLanguage == .chinese ? "中文" : "English")
                            .font(.headline)
                    }

                    ControlPanelCard(title: "Export Readiness") {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Preview and export stay aligned through the same rendering layer.", systemImage: "checkmark.seal")
                            Label("Current draft supports Markdown, TXT, HTML, RTF, DOCX, and PDF output.", systemImage: "doc.richtext")
                            Label("DOCX works well with Microsoft Word and Google Docs import.", systemImage: "globe")
                        }
                        .foregroundStyle(.secondary)
                    }

                    if let exportResult {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(exportResult, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.green)
                            if let lastExportURL {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([lastExportURL])
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    Button("Save Visual Template") {
                        runModelTask(model) {
                            try await model.saveUserTemplate(
                                kind: .visual,
                                name: "\(selectedVisualTemplate) Copy",
                                config: ["source": selectedVisualTemplate]
                            )
                        }
                    }
                    .buttonStyle(.bordered)

                    Button("Export to Folder") {
                        Task { @MainActor in
                            if let directory = await presentOpenPanelURL(configure: { panel in
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                            }) {
                                do {
                                    if let url = try await model.exportCurrentDraft(
                                        format: selectedFormat,
                                        visualTemplateName: selectedVisualTemplate,
                                        to: directory
                                    ) {
                                        exportResult = "Exported to \(url.lastPathComponent)"
                                        lastExportURL = url
                                    }
                                } catch {
                                    model.present(error: error)
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Back to Preview") {
                        model.showPreview()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .onAppear {
                selectedFormat = model.preferences.defaultExportFormat
                selectedVisualTemplate = version.structuredDoc.exportMetadata.visualTemplateName
            }
        }
    }
}

private struct DraftsView: View {
    @Bindable var model: NotesCuratorAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    SectionTitle(title: "All Drafts", subtitle: "Recent working documents across every workspace.")
                    Spacer()
                    if hasStuckDrafts {
                        Button("Stop & Delete Stuck Drafts", role: .destructive) {
                            runModelTask(model) {
                                try await model.clearStuckDrafts()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                ForEach(model.recentDrafts) { draft in
                    DraftRowCard(
                        item: draft,
                        action: {
                            runModelTask(model) {
                                try await model.openDraft(draft.id)
                            }
                        },
                        onDelete: {
                            runModelTask(model) {
                                try await model.deleteWorkspaceItem(draft.id)
                            }
                        }
                    )
                }
            }
            .padding(32)
        }
    }

    private var hasStuckDrafts: Bool {
        model.items.contains {
            $0.kind == .draft && ($0.status == .processing || $0.status == .failed)
        }
    }
}

private struct TemplateLibraryView: View {
    @Bindable var model: NotesCuratorAppModel
    @State private var selectedTemplate: Template?

    var body: some View {
        Group {
            if let selectedTemplate {
                TemplatePreviewPage(model: model, template: selectedTemplate) {
                    self.selectedTemplate = nil
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        SectionTitle(title: "Template Library", subtitle: "Structure and visual templates, including user-saved presets.")
                        templateSection(title: "Content Templates", templates: model.contentTemplates)
                        templateSection(title: "Visual Templates", templates: model.visualTemplates)
                    }
                    .padding(32)
                }
            }
        }
    }

    private func templateSection(title: String, templates: [Template]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                ForEach(templates) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(template.name)
                                .font(.headline)
                            Text(template.scope == .system ? "System preset" : "User saved")
                                .foregroundStyle(.secondary)
                            Text(templatePreviewLine(for: template))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                        .background(Color.white.opacity(0.92))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func templatePreviewLine(for template: Template) -> String {
        if template.kind == .content {
            return template.config["purpose"] ?? "Preview document structure"
        }
        if let mood = template.config["mood"] {
            return mood
        }
        if let accent = template.config["accent"] {
            return "Accent: \(accent)"
        }
        if let source = template.config["source"] {
            return "Based on \(source)"
        }
        return "Preview visual output"
    }
}

private struct ExportsView: View {
    @Bindable var model: NotesCuratorAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SectionTitle(title: "Exports", subtitle: "Simple result list for download and revisit.")
                ForEach(model.exports) { export in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(URL(fileURLWithPath: export.outputPath).lastPathComponent)
                                .font(.headline)
                            Text(export.createdAt.formatted(date: .numeric, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            Button("Reveal") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: export.outputPath)])
                            }
                            Button(role: .destructive) {
                                runModelTask(model) {
                                    try await model.deleteExportRecord(export.id)
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.headline)
                                    .padding(10)
                                    .background(Color.red.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .help("Delete this export record")
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                }
            }
            .padding(32)
        }
    }
}

private struct SettingsView: View {
    @Bindable var model: NotesCuratorAppModel
    @State private var draftPreferences: AppPreferences = .default

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: $draftPreferences.providerKind) {
                    ForEach(ProviderKind.allCases, id: \.self) { kind in
                        Text(providerTitle(for: kind)).tag(kind)
                    }
                }
                TextField("Model", text: $draftPreferences.modelName)
                if draftPreferences.providerKind == .localOllama {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Faster local presets")
                            .font(.footnote.weight(.semibold))
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                modelPresetButton("qwen3:8b")
                                modelPresetButton("qwen3:4b")
                                modelPresetButton("llama3.1:8b")
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                modelPresetButton("qwen3:8b")
                                modelPresetButton("qwen3:4b")
                                modelPresetButton("llama3.1:8b")
                            }
                        }
                        Text("Smaller 7B-8B models are usually much faster than qwen3:14b for note generation. Install missing models first with `ollama pull <model>`.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                if draftPreferences.providerKind == .customAPI {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Hosted Service", selection: $draftPreferences.hostedService) {
                            ForEach(HostedService.allCases, id: \.self) { service in
                                Text(service.displayName).tag(service)
                            }
                        }
                        .onChange(of: draftPreferences.hostedService) { _, service in
                            applyHostedServiceDefaults(service)
                        }

                        SecureField("\(draftPreferences.hostedService.displayName) API Key", text: $draftPreferences.customAPIKey)
                            .onChange(of: draftPreferences.customAPIKey) { _, newValue in
                                draftPreferences.setHostedAPIKey(newValue, for: draftPreferences.hostedService)
                            }

                        Text("\(draftPreferences.hostedService.displayName) presets")
                            .font(.footnote.weight(.semibold))
                        ForEach(AppPreferences.recommendedHostedPresetsByService[draftPreferences.hostedService] ?? []) { preset in
                            customProviderPresetRow(preset)
                        }
                        Text(serviceHelpText(for: draftPreferences.hostedService))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Saved Hosted API Keys")
                            .font(.footnote.weight(.semibold))
                        ForEach(HostedService.allCases, id: \.self) { service in
                            SecureField(service.displayName, text: apiKeyBinding(for: service))
                        }
                        Text("Keys are saved locally per provider. You can also skip filling these fields and set environment variables like `NOTESCURATOR_GEMINI_API_KEY` or `NOTESCURATOR_NVIDIA_API_KEY` once on your machine.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Enable staged workflow routing", isOn: $draftPreferences.enableWorkflowRouting)
                        if draftPreferences.enableWorkflowRouting {
                            Text("Chunk model: \(draftPreferences.customChunkModelName)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Polish model: \(draftPreferences.customPolishModelName)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Repair model: \(draftPreferences.customRepairModelName)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Long inputs are summarized with the chunk model, the main model writes the draft, translation or formal-document polish routes through the polish model, and the repair model normalizes the structure before export.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                TextField("Custom Base URL", text: $draftPreferences.customBaseURL)
                if let providerStatusMessage = model.providerStatusMessage {
                    Text(providerStatusMessage)
                        .foregroundStyle(providerStatusMessage.localizedCaseInsensitiveContains("ready") ? Color.green : Color.secondary)
                }
                if let providerStatusDetail = model.providerStatusDetail {
                    Text(providerStatusDetail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Check Provider") {
                    Task { @MainActor in
                        await model.refreshProviderStatus(using: draftPreferences)
                    }
                }
            }

            Section("Defaults") {
                Picker("Output Language", selection: $draftPreferences.defaultOutputLanguage) {
                    Text("English").tag(OutputLanguage.english)
                    Text("中文").tag(OutputLanguage.chinese)
                }
                Picker("Export Format", selection: $draftPreferences.defaultExportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text("\(format.displayName) · \(format.compatibilityLabel)").tag(format)
                    }
                }
                Toggle("Auto Save", isOn: $draftPreferences.autoSave)
            }

            Button("Save Settings") {
                runModelTask(model) {
                    let updated = draftPreferences
                    try await model.updatePreferences { prefs in
                        prefs = updated
                    }
                    await model.refreshProviderStatus()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .formStyle(.grouped)
        .padding(32)
        .onAppear {
            draftPreferences = model.preferences
            draftPreferences.syncSelectedHostedServiceAPIKey()
            Task { @MainActor in
                await model.refreshProviderStatus()
            }
        }
    }

    private func modelPresetButton(_ name: String) -> some View {
        Button(name) {
            draftPreferences.modelName = name
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func providerTitle(for kind: ProviderKind) -> String {
        switch kind {
        case .heuristicFallback:
            return "Heuristic Fallback"
        case .localOllama:
            return "Local Ollama"
        case .customAPI:
            return "Custom API"
        }
    }

    @ViewBuilder
    private func customProviderPresetRow(_ preset: HostedModelPreset) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.title)
                    .font(.subheadline.weight(.semibold))
                Text(preset.modelName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(preset.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
        if isSelectedPreset(preset) {
            Button("Selected") {}
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(true)
            } else {
                Button("Use") {
                    draftPreferences.providerKind = .customAPI
                    draftPreferences.hostedService = preset.service
                    draftPreferences.customBaseURL = preset.baseURL
                    draftPreferences.modelName = preset.modelName
                    draftPreferences.enableWorkflowRouting = true
                    draftPreferences.customChunkModelName = preset.service.recommendedChunkModel
                    draftPreferences.customPolishModelName = preset.service.recommendedPolishModel
                    draftPreferences.customRepairModelName = preset.service.recommendedRepairModel
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func isSelectedPreset(_ preset: HostedModelPreset) -> Bool {
        draftPreferences.providerKind == .customAPI &&
        draftPreferences.hostedService == preset.service &&
        draftPreferences.customBaseURL == preset.baseURL &&
        draftPreferences.modelName == preset.modelName
    }

    private func apiKeyBinding(for service: HostedService) -> Binding<String> {
        Binding(
            get: {
                draftPreferences.hostedAPIKeysByService[service.rawValue] ?? ""
            },
            set: { newValue in
                draftPreferences.setHostedAPIKey(newValue, for: service)
            }
        )
    }

    private func applyHostedServiceDefaults(_ service: HostedService) {
        draftPreferences.customBaseURL = service.defaultBaseURL
        draftPreferences.modelName = service.recommendedMainModel
        draftPreferences.syncSelectedHostedServiceAPIKey()
        if draftPreferences.enableWorkflowRouting {
            draftPreferences.customChunkModelName = service.recommendedChunkModel
            draftPreferences.customPolishModelName = service.recommendedPolishModel
            draftPreferences.customRepairModelName = service.recommendedRepairModel
        }
    }

    private func serviceHelpText(for service: HostedService) -> String {
        switch service {
        case .nvidia, .openAI, .zhipu, .mistral:
            return "Pick a preset, enter an API key, then save settings to run the full staged workflow with this hosted endpoint."
        case .anthropic:
            return "Claude uses Anthropic's native Messages API under the hood, but it still plugs into the same staged workflow once you add your API key."
        case .gemini:
            return "Gemini uses Google's native Generative Language API under the hood, and staged routing will still run once you add your API key."
        }
    }
}

private struct WorkspaceCustomizationSheet: View {
    @Bindable var model: NotesCuratorAppModel
    let workspace: Workspace
    let onDismiss: () -> Void
    @State private var name: String
    @State private var subtitle: String
    @State private var cover: WorkspaceCover
    @State private var coverImagePath: String?
    @State private var showDeleteConfirmation = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case subtitle
    }

    init(model: NotesCuratorAppModel, workspace: Workspace, onDismiss: @escaping () -> Void) {
        self.model = model
        self.workspace = workspace
        self.onDismiss = onDismiss
        _name = State(initialValue: workspace.name)
        _subtitle = State(initialValue: workspace.subtitle)
        _cover = State(initialValue: workspace.cover)
        _coverImagePath = State(initialValue: workspace.coverImagePath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionTitle(title: "Customize Workspace", subtitle: "Rename the workspace and shape how it presents itself.")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workspace Title")
                            .font(.headline)
                        TextField("Workspace Title", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .title)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Workspace Subtitle")
                            .font(.headline)
                        ZStack(alignment: .topLeading) {
                            if subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("Describe what this workspace is for.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $subtitle)
                                .focused($focusedField, equals: .subtitle)
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                        .frame(minHeight: 100)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.black.opacity(0.08), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cover Style")
                            .font(.headline)
                        Picker("Cover", selection: $cover) {
                            ForEach(WorkspaceCover.allCases, id: \.self) { option in
                                Text(option.rawValue.capitalized).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cover Image")
                            .font(.headline)
                        WorkspaceCoverArtwork(
                            workspace: Workspace(
                                id: workspace.id,
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? workspace.name,
                                subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? workspace.subtitle,
                                cover: cover,
                                coverImagePath: coverImagePath,
                                createdAt: workspace.createdAt,
                                updatedAt: workspace.updatedAt,
                                pinned: workspace.pinned
                            ),
                            height: 180
                        )

                        HStack(spacing: 10) {
                            Button("Choose Image") {
                                Task { @MainActor in
                                    if let url = await presentOpenPanelURL(configure: { panel in
                                        panel.canChooseFiles = true
                                        panel.canChooseDirectories = false
                                        panel.allowsMultipleSelection = false
                                        panel.allowedContentTypes = [.image]
                                    }) {
                                        coverImagePath = url.path
                                    }
                                }
                            }
                            .buttonStyle(.bordered)

                            if coverImagePath != nil {
                                Button("Remove Image") {
                                    coverImagePath = nil
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        Text("If you choose an image, it will replace the built-in Ocean / Graphite / Bloom preview for this workspace.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(28)
            }
            .frame(maxWidth: .infinity, maxHeight: 360, alignment: .top)

            Divider()

            HStack {
                Button("Delete Workspace", role: .destructive) {
                    showDeleteConfirmation = true
                }
                .buttonStyle(.bordered)

                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save Workspace") {
                    runModelTask(model) {
                        try await model.updateWorkspace(
                            workspace.id,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? workspace.name,
                            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? workspace.subtitle,
                            cover: cover,
                            coverImagePath: coverImagePath
                        )
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 560, alignment: .topLeading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: Color.black.opacity(0.16), radius: 32, y: 18)
        .onAppear {
            DispatchQueue.main.async {
                focusedField = .title
            }
        }
        .alert("Delete this workspace?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                runModelTask(model) {
                    try await model.deleteWorkspace(workspace.id)
                    onDismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the workspace and every draft, version, and export inside it.")
        }
    }
}

private struct TemplatePreviewPage: View {
    @Bindable var model: NotesCuratorAppModel
    let template: Template
    let onBack: () -> Void

    private var previewDraft: DraftVersion {
        SampleTemplateFactory.previewDraft(for: template)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        onBack()
                    } label: {
                        Label("Back to Templates", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Use This Template") {
                        runModelTask(model) {
                            try await model.startNewNote(using: template)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(template.kind == .content ? "Content Template Preview" : "Visual Template Preview")
                        .font(.caption)
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    Text(template.name)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(templateDescription(for: template))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    InfoPill(title: "Type", value: template.kind == .content ? "Content" : "Visual")
                    InfoPill(title: "Scope", value: template.scope == .system ? "System" : "User")
                    if let badge = templateBadge(for: template) {
                        InfoPill(title: "Hint", value: badge)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Why Use It", subtitle: template.config["purpose"] ?? templateDescription(for: template))
                    if let completeness = template.config["completeness"] {
                        Text("Completeness: \(completeness)")
                            .foregroundStyle(.secondary)
                    } else if let mood = template.config["mood"] {
                        Text("Mood: \(mood)")
                            .foregroundStyle(.secondary)
                    }
                }

                if template.kind == .content {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "Example Output", subtitle: "A representative structured note generated with this content template.")
                        StyledDraftPreview(version: previewDraft)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(title: "Visual Preview", subtitle: "The same sample content rendered with this visual style.")
                        StyledDraftPreview(version: previewDraft)
                    }
                }
            }
            .padding(32)
        }
    }

    private func templateDescription(for template: Template) -> String {
        if template.kind == .content {
            switch template.config["goal"] {
            case GoalType.summary.rawValue:
                return "Focuses on concise takeaways and a lighter structure for faster reading."
            case GoalType.formalDocument.rawValue:
                return "Organizes the output like a polished report with stronger sections and more detail."
            case GoalType.actionItems.rawValue:
                return "Pushes the note toward next steps, responsibilities, and concrete follow-up."
            default:
                return "Balanced study-oriented notes with structure, key points, and review support."
            }
        }

        return "Lets you inspect the document mood, contrast, and overall presentation before committing."
    }

    private func templateBadge(for template: Template) -> String? {
        if template.kind == .content {
            return template.config["goal"]
        }
        return template.config["accent"] ?? template.config["source"]
    }
}

@MainActor
private func runModelTask(
    _ model: NotesCuratorAppModel,
    operation: @escaping @MainActor () async throws -> Void
) {
    Task { @MainActor in
        do {
            try await operation()
        } catch {
            model.present(error: error)
        }
    }
}

private struct PendingDraftState: View {
    @Bindable var model: NotesCuratorAppModel
    let item: WorkspaceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Draft is still processing", systemImage: "clock.badge")
                .font(.title2.bold())
            Text(item.summaryPreview)
                .foregroundStyle(.secondary)
            Text("You can keep this workspace open while the pipeline finishes. If it fails, the card will switch to a removable failed state instead of getting stuck.")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Stop and Delete Draft", role: .destructive) {
                    runModelTask(model) {
                        try await model.stopAndDeleteDraft(item.id)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Start a New Note") {
                    runModelTask(model) {
                        try await model.beginNewNote(in: item.workspaceId)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white.opacity(0.76))
        )
    }
}

private struct FailedDraftState: View {
    @Bindable var model: NotesCuratorAppModel
    let item: WorkspaceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text("This draft did not finish")
                        .font(.title2.bold())
                    Text(primaryFailureMessage)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("What to try next")
                    .font(.headline)
                Text(suggestedRecoveryText)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 20))

            HStack(spacing: 12) {
                Button("Open Settings") {
                    model.openSettings()
                }
                .buttonStyle(.borderedProminent)

                Button("Start a New Note") {
                    runModelTask(model) {
                        try await model.beginNewNote(in: item.workspaceId)
                    }
                }
                .buttonStyle(.bordered)

                Button("Delete Failed Draft", role: .destructive) {
                    runModelTask(model) {
                        try await model.stopAndDeleteDraft(item.id)
                    }
                }
                .buttonStyle(.bordered)
            }

            DisclosureGroup("Technical details") {
                Text(item.summaryPreview)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
            .padding(16)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.orange.opacity(0.16), lineWidth: 1)
        )
    }

    private var primaryFailureMessage: String {
        item.summaryPreview
            .replacingOccurrences(of: "Processing failed. ", with: "")
            .replacingOccurrences(of: "Processing failed.", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestedRecoveryText: String {
        let lowercased = item.summaryPreview.lowercased()
        if lowercased.contains("http 504") || lowercased.contains("timed out") || lowercased.contains("timeout") {
            return "This usually means the provider took too long to answer. Try the same note again, switch to a faster model, or use another provider/API key in Settings."
        }
        if lowercased.contains("api key") {
            return "Check the provider API key in Settings, then retry the note."
        }
        if lowercased.contains("model") && lowercased.contains("available") {
            return "The selected model is not available for the current provider. Open Settings and choose another model."
        }
        return "Try the note again. If the problem keeps happening, open Settings and switch provider, API key, or model."
    }
}

private struct EmptyWorkspaceState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Workspace ready")
                .font(.largeTitle.bold())
            Text("Start a new note to move through intake, processing, editing, preview, and export inside one focused workspace.")
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                InfoPill(title: "Flow", value: "Guided stages")
                InfoPill(title: "Output", value: "Markdown / DOCX / PDF")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.white.opacity(0.76))
        )
    }
}

private struct SectionTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title2.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

private struct QuickActionCard: View {
    let title: String
    let subtitle: String
    let icon: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 42, height: 42)
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(22)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(Color.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .shadow(color: Color.black.opacity(0.06), radius: 18, y: 10)
            .opacity(isDisabled ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct WorkspaceCard: View {
    let workspace: Workspace
    let draftCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                WorkspaceCoverArtwork(workspace: workspace, height: 150)
                Text(workspace.name)
                    .font(.title3.bold())
                Text(workspace.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text("\(draftCount) drafts")
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(Color.white.opacity(0.94))
            .clipShape(RoundedRectangle(cornerRadius: 28))
        }
        .buttonStyle(.plain)
    }
}

private struct DraftRowCard: View {
    let item: WorkspaceItem
    let action: (() -> Void)?
    var onDelete: (() -> Void)?
    var isActive = false
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.headline)
                        if item.status != .ready {
                            DraftStatusBadge(status: item.status)
                        }
                        if item.refinementStatus != .none {
                            DraftRefinementBadge(status: item.refinementStatus)
                        }
                    }

                    Spacer()

                    Text(item.lastEditedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(item.summaryPreview)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: deleteIconName)
                        .font(.headline)
                        .padding(10)
                        .background(Color.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .help(deleteHelpText)
            }
        }
        .padding(compact ? 14 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(isActive ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1.2)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22))
        .onTapGesture {
            action?()
        }
    }

    private var deleteIconName: String {
        item.status == .processing ? "stop.fill" : "trash"
    }

    private var deleteHelpText: String {
        switch item.status {
        case .processing:
            return "Stop processing and delete draft"
        case .failed:
            return "Delete failed draft"
        case .ready:
            switch item.kind {
            case .draft, .note:
                return "Delete note"
            case .export:
                return "Delete export"
            case .template:
                return "Delete item"
            }
        }
    }

    private var cardBackground: Color {
        if isActive {
            return Color.accentColor.opacity(0.10)
        }
        return Color.white.opacity(0.92)
    }
}

private struct WorkspaceCoverArtwork: View {
    let workspace: Workspace
    var height: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = workspace.coverImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(workspace.accentGradient)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.36)],
                startPoint: .center,
                endPoint: .bottom
            )

            Text(workspace.coverBadgeTitle)
                .font(.headline)
                .foregroundStyle(.white)
                .padding(18)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

private struct DraftStatusBadge: View {
    let status: WorkspaceItemStatus

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accent.opacity(0.12))
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .processing: "Processing"
        case .ready: "Ready"
        case .failed: "Failed"
        }
    }

    private var accent: Color {
        switch status {
        case .processing: .blue
        case .ready: .green
        case .failed: .red
        }
    }
}

private struct DraftRefinementBadge: View {
    let status: DraftRefinementStatus

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .foregroundStyle(accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accent.opacity(0.12))
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .none: "Refinement"
        case .refining: "Refining"
        case .refined: "Refined Ready"
        case .failed: "Refinement Failed"
        }
    }

    private var accent: Color {
        switch status {
        case .none: .secondary
        case .refining: .orange
        case .refined: .green
        case .failed: .red
        }
    }
}

private extension Workspace {
    var coverBadgeTitle: String {
        coverImagePath == nil ? cover.rawValue.capitalized : "Custom Cover"
    }

    var accentGradient: LinearGradient {
        switch cover {
        case .ocean:
            LinearGradient(colors: [Color.blue.opacity(0.4), Color.cyan.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .graphite:
            LinearGradient(colors: [Color.gray.opacity(0.5), Color.black.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .bloom:
            LinearGradient(colors: [Color.pink.opacity(0.45), Color.orange.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var coverImage: NSImage? {
        guard let coverImagePath, FileManager.default.fileExists(atPath: coverImagePath) else {
            return nil
        }
        return NSImage(contentsOfFile: coverImagePath)
    }
}

private extension GoalType {
    var displayName: String {
        switch self {
        case .summary: "Summary"
        case .structuredNotes: "Structured Notes"
        case .formalDocument: "Formal Document"
        case .actionItems: "Action Items"
        }
    }
}

private extension Template {
    var configuredGoalType: GoalType {
        GoalType(rawValue: config["goal"] ?? "") ?? .structuredNotes
    }
}

@MainActor
private func presentOpenPanelURL(configure: (NSOpenPanel) -> Void) async -> URL? {
    let panel = NSOpenPanel()
    configure(panel)
    return await withCheckedContinuation { continuation in
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        } else {
            let response = panel.runModal()
            continuation.resume(returning: response == .OK ? panel.url : nil)
        }
    }
}

@MainActor
private func presentOpenPanelURLs(configure: (NSOpenPanel) -> Void) async -> [URL] {
    let panel = NSOpenPanel()
    configure(panel)
    return await withCheckedContinuation { continuation in
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .OK ? panel.urls : [])
            }
        } else {
            let response = panel.runModal()
            continuation.resume(returning: response == .OK ? panel.urls : [])
        }
    }
}

private struct ControlPanelCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

private struct StatusChip: View {
    let title: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.84))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct InfoPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.82))
        .clipShape(Capsule())
    }
}

private struct ClipboardTextEditor: View {
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
    }
}

private struct KeyboardFriendlyTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var selectAllOnAppear = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> ShortcutFriendlyTextField {
        let textField = ShortcutFriendlyTextField()
        textField.delegate = context.coordinator
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.backgroundColor = .textBackgroundColor
        textField.focusRingType = .default
        textField.font = .systemFont(ofSize: 16)
        textField.placeholderString = placeholder
        textField.stringValue = text

        if selectAllOnAppear {
            DispatchQueue.main.async {
                guard let window = textField.window else { return }
                window.makeFirstResponder(textField)
                textField.currentEditor()?.selectedRange = NSRange(location: 0, length: textField.stringValue.count)
            }
        }

        return textField
    }

    func updateNSView(_ nsView: ShortcutFriendlyTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let textField = obj.object as? NSTextField else { return }
            text = textField.stringValue
        }
    }
}

private struct KeyboardFriendlyTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSave: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSave: onSave)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false

        let textView = ShortcutFriendlyTextView()
        configurePlainTextEditingView(textView)
        textView.delegate = context.coordinator
        textView.string = text
        textView.onSave = context.coordinator.handleSave

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ShortcutFriendlyTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.onSave = context.coordinator.handleSave
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        private let onSave: (() -> Void)?

        init(text: Binding<String>, onSave: (() -> Void)?) {
            _text = text
            self.onSave = onSave
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }

        func handleSave() {
            onSave?()
        }
    }
}

private struct NativeClipboardTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false

        let textView = ShortcutFriendlyTextView()
        configurePlainTextEditingView(textView, inset: NSSize(width: 2, height: 10))
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ShortcutFriendlyTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

@MainActor
private func configurePlainTextEditingView(_ textView: NSTextView, inset: NSSize = NSSize(width: 8, height: 8)) {
    textView.isEditable = true
    textView.isSelectable = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.font = .systemFont(ofSize: 14)
    textView.textColor = .labelColor
    textView.insertionPointColor = .controlAccentColor
    textView.textContainerInset = inset
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.lineFragmentPadding = 0
    textView.layoutManager?.allowsNonContiguousLayout = true

    // AppKit's smart text services can make long plain-text documents feel sticky while scrolling.
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isAutomaticDataDetectionEnabled = false
    textView.isAutomaticLinkDetectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false
    textView.smartInsertDeleteEnabled = false
    textView.usesFindBar = false
    textView.enabledTextCheckingTypes = 0
}

private final class ShortcutFriendlyTextView: NSTextView {
    var onSave: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters {
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "s":
            onSave?()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private final class ShortcutFriendlyTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        switch characters {
        case "a":
            currentEditor()?.selectAll(nil)
            return true
        case "c":
            currentEditor()?.copy(nil)
            return true
        case "v":
            currentEditor()?.paste(nil)
            return true
        case "x":
            currentEditor()?.cut(nil)
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private struct ProcessingActivityDots: View {
    let referenceDate: Date
    var size: CGFloat = 6

    var body: some View {
        let phase = Int(referenceDate.timeIntervalSinceReferenceDate * 2) % 3
        HStack(spacing: size * 0.5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == phase ? Color.accentColor : Color.accentColor.opacity(0.25))
                    .frame(width: size, height: size)
                    .scaleEffect(index == phase ? 1.0 : 0.8)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: phase)
    }
}

private struct ResponsiveSplitLayout<Leading: View, Trailing: View>: View {
    let leadingMinWidth: CGFloat
    let trailingMinWidth: CGFloat
    var leadingFixedWidth: CGFloat?
    var trailingFixedWidth: CGFloat?
    var spacing: CGFloat = 20
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                horizontalLeading
                horizontalTrailing
            }
            VStack(alignment: .leading, spacing: spacing) {
                leading
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                trailing
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private var horizontalLeading: some View {
        if let leadingFixedWidth {
            leading
                .frame(width: leadingFixedWidth, alignment: .topLeading)
        } else {
            leading
                .frame(minWidth: leadingMinWidth, maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var horizontalTrailing: some View {
        if let trailingFixedWidth {
            trailing
                .frame(width: trailingFixedWidth, alignment: .topLeading)
        } else {
            trailing
                .frame(minWidth: trailingMinWidth, maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct FlowStageStrip: View {
    let currentFlow: WorkspaceFlowStage

    var body: some View {
        let items = FocusCanvasStageModel.items(currentFlow: currentFlow)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.stage) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(accent(for: item.state))
                            .frame(width: 8, height: 8)

                        Text(title(for: item.stage))
                            .font(.caption.weight(item.state == .current ? .semibold : .medium))
                            .foregroundStyle(item.state == .current ? Color.accentColor : Color.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(background(for: item.state))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(border(for: item.state), lineWidth: item.state == .current ? 1 : 0)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private func title(for stage: WorkspaceFlowStage) -> String {
        switch stage {
        case .intake: "Intake"
        case .processing: "Processing"
        case .editing: "Edit"
        case .preview: "Preview"
        case .export: "Export"
        }
    }

    private func accent(for state: FocusCanvasStageState) -> Color {
        switch state {
        case .completed, .current:
            return Color.accentColor
        case .upcoming:
            return Color.gray.opacity(0.28)
        }
    }

    private func background(for state: FocusCanvasStageState) -> Color {
        switch state {
        case .current:
            return Color.accentColor.opacity(0.10)
        case .completed:
            return Color.white.opacity(0.76)
        case .upcoming:
            return Color.white.opacity(0.48)
        }
    }

    private func border(for state: FocusCanvasStageState) -> Color {
        switch state {
        case .current:
            return Color.accentColor.opacity(0.18)
        case .completed, .upcoming:
            return .clear
        }
    }
}

private enum SampleTemplateFactory {
    static func previewDraft(for template: Template) -> DraftVersion {
        let goal = goalType(for: template)
        let contentTemplateName = template.kind == .content ? template.name : "Structured Notes"
        let visualTemplateName = template.kind == .visual ? template.name : "Oceanic Blue"
        let title: String
        let summary: String
        let keyPoints: [String]
        let sections: [StructuredSection]
        let actionItems: [String]

        switch goal {
        case .summary:
            title = "Executive Topic Snapshot"
            summary = "A concise overview that surfaces the main conclusion, the supporting evidence, and what matters next."
            keyPoints = ["Short read", "Fast understanding", "Best for quick context sharing"]
            sections = [
                StructuredSection(title: "Summary", body: "This format compresses the source into a lighter, faster note designed for quick review."),
            ]
            actionItems = ["Share the snapshot", "Open the full material only if needed"]
        case .formalDocument:
            title = "Quarterly Strategy Brief"
            summary = "A more polished structure with stronger headings, fuller explanations, and a presentation style suited for reports."
            keyPoints = ["Clear sections", "Longer explanations", "Stronger report framing"]
            sections = [
                StructuredSection(title: "Context", body: "This template presents the material with a more formal rhythm and fuller explanation."),
                StructuredSection(title: "Recommendation", body: "Use this when the output should feel closer to a brief, memo, or polished document.")
            ]
            actionItems = ["Review narrative flow", "Finalize for external sharing"]
        case .actionItems:
            title = "Action Plan"
            summary = "A task-first format that emphasizes next steps, accountability, and follow-through."
            keyPoints = ["Next steps first", "Operational focus", "Easy to turn into execution"]
            sections = [
                StructuredSection(title: "Immediate Priorities", body: "The output is shaped to move quickly from information to execution."),
            ]
            actionItems = ["Assign owners", "Track deadlines", "Review completion status"]
        case .structuredNotes:
            title = "Structured Study Notes"
            summary = "A balanced note format with cue questions, key points, and follow-up sections that support understanding and review."
            keyPoints = ["Balanced structure", "Readable at a glance", "Good default for deep study notes"]
            sections = [
                StructuredSection(title: "Core Idea", body: "The template organizes complex material into a study-friendly flow."),
                StructuredSection(title: "Why It Helps", body: "It balances summary, explanation, and review prompts without feeling too heavy.")
            ]
            actionItems = ["Review key points", "Use the prompts for revision"]
        }

        let structured = StructuredDocument(
            title: title,
            summary: summary,
            cueQuestions: ["What is the main value of this template?", "When should I choose it?"],
            keyPoints: keyPoints,
            sections: sections,
            glossary: [GlossaryItem(term: "Template", definition: "A preset that shapes either the content structure or the visual presentation.")],
            callouts: [StructuredCallout(kind: .note, title: "Preview", body: "This sample is illustrative so you can judge the format before using it.")],
            studyCards: [StudyCard(question: "What does this template optimize for?", answer: summary)],
            actionItems: actionItems,
            reviewQuestions: ["Does this output style match the way I want to work?"],
            imageSlots: [],
            exportMetadata: ExportMetadata(
                contentTemplateName: contentTemplateName,
                visualTemplateName: visualTemplateName,
                preferredFormat: .pdf
            )
        )

        return DraftVersion(
            workspaceItemId: UUID(),
            goalType: goal,
            outputLanguage: .english,
            editorDocument: """
            ## \(title)

            \(summary)
            """,
            structuredDoc: structured,
            sourceRefs: [],
            imageSuggestions: []
        )
    }

    private static func goalType(for template: Template) -> GoalType {
        guard template.kind == .content else { return .structuredNotes }
        return GoalType(rawValue: template.config["goal"] ?? "") ?? .structuredNotes
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension DraftVersion {
    func previewVersion(visualTemplateName: String) -> DraftVersion {
        var copy = self
        copy.structuredDoc.exportMetadata.visualTemplateName = visualTemplateName
        return copy
    }

    func livePreviewVersion(editorDocument: String, visualTemplateName: String) -> DraftVersion {
        var copy = self
        copy.editorDocument = editorDocument
        copy.structuredDoc.exportMetadata.visualTemplateName = visualTemplateName
        return copy
    }
}

private func wordCount(for text: String) -> Int {
    text.split { $0.isWhitespace || $0.isNewline }.count
}

private struct PrimarySidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
