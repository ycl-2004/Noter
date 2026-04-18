import SwiftUI

struct LatexTemplateImportSheet: View {
    @Bindable var model: NotesCuratorAppModel
    let onDismiss: () -> Void

    @State private var latexSource = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Import LaTeX Template")
                    .font(.title2.bold())
                Text("Import a full LaTeX project folder / zip / main `.tex`, or paste a supported LaTeX subset to build a reviewable in-app template.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Choose Project Folder / Zip / .tex") {
                    Task { @MainActor in
                        if let url = await presentOpenPanelURL(configure: { panel in
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = true
                            panel.allowsMultipleSelection = false
                            panel.resolvesAliases = true
                        }) {
                            do {
                                try model.beginLatexTemplateProjectImport(url)
                                onDismiss()
                            } catch {
                                model.present(error: error)
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                Text("Full project import keeps your original `.tex` layout and assets as the template source of truth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Or paste a supported single-file source below")
                .font(.headline)

            TextEditor(text: $latexSource)
                .padding(16)
                .frame(minHeight: 320)
                .background(Color.white.opacity(0.96))
                .clipShape(RoundedRectangle(cornerRadius: 22))

            HStack(spacing: 12) {
                Button("Cancel") {
                    onDismiss()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Import") {
                    Task { @MainActor in
                        do {
                            try model.beginLatexTemplateImport(latexSource)
                            onDismiss()
                        } catch {
                            model.present(error: error)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(latexSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 900, minHeight: 520, alignment: .topLeading)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct TemplateImportReviewView: View {
    @Bindable var model: NotesCuratorAppModel

    var body: some View {
        if let review = model.pendingTemplateImportReview {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LaTeX Import Review")
                            .font(.title.bold())
                        Text("Review the inferred archetype, extracted visual system, and recommended schema before saving this template.")
                            .foregroundStyle(.secondary)
                    }

                    reviewHeader(review)
                    extractedVisuals(review)
                    if let importedPreview = review.templatePack.importedPreview {
                        importedLayoutPreview(importedPreview, pack: review.templatePack)
                    }
                    if let editingPack = model.editingTemplatePack {
                        sectionsConfiguration(review, pack: editingPack)
                    }
                    importActions(review)
                }
                .padding(32)
            }
        }
    }

    private func reviewHeader(_ review: TemplateImportReview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(review.templatePack.identity.name)
                .font(.title.bold())

            Picker("Template Type", selection: Binding(
                get: { review.inferredArchetype },
                set: { model.adjustPendingImportArchetype($0) }
            )) {
                ForEach(TemplateArchetype.allCases, id: \.self) { archetype in
                    Text(archetypeLabel(archetype)).tag(archetype)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                pill(review.latexProjectSource == nil ? "Import LaTeX Template" : "Project-backed Template")
                pill("Adjust Type")
                pill("Use Template")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func extractedVisuals(_ review: TemplateImportReview) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Visual Extraction")
                .font(.title3.bold())

            HStack(spacing: 16) {
                colorChip(title: "Accent", hex: review.fingerprint.palette.accentHex)
                if let surface = review.fingerprint.palette.surfaceHex {
                    colorChip(title: "Surface", hex: surface)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Heading System")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(review.fingerprint.headingSystem == .academicStructured ? "Academic Structured" : "Simple Document")
                        .font(.subheadline.weight(.medium))
                }
            }

            if !review.fingerprint.boxStyles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detected Boxes")
                        .font(.headline)
                    ForEach(review.fingerprint.boxStyles) { style in
                        Text(style.name)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !review.fingerprint.recurringSections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recurring Sections")
                        .font(.headline)
                    Text(review.fingerprint.recurringSections.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func sectionsConfiguration(_ review: TemplateImportReview, pack: TemplatePack) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sections")
                .font(.title3.bold())
            Text("This order is shared by preview and export. If a section has no content, it stays hidden automatically.")
                .foregroundStyle(.secondary)

            if !review.fingerprint.boxStyles.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Detected Boxes")
                        .font(.headline)
                    Text(review.fingerprint.boxStyles.map(\.name).joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(Array(pack.layout.blocks.enumerated()), id: \.element.id) { index, block in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sectionTitle(for: block, fingerprint: review.fingerprint))
                            .font(.headline)
                        Text(sectionSubtitle(for: block))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            model.moveEditingTemplateBlock(from: index, to: max(index - 1, 0))
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(index == 0)

                        Button {
                            model.moveEditingTemplateBlock(from: index, to: min(index + 1, pack.layout.blocks.count - 1))
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(index == pack.layout.blocks.count - 1)
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func importedLayoutPreview(_ preview: ImportedTemplatePreview, pack: TemplatePack) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Imported Layout Preview")
                .font(.title3.bold())
            Text("This keeps the source LaTeX's title, section rhythm, and box styles as a local preview reference.")
                .foregroundStyle(.secondary)
            ImportedTemplatePreviewCard(preview: preview, pack: pack)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func importActions(_ review: TemplateImportReview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Review Actions")
                .font(.title3.bold())

            HStack(spacing: 12) {
                Button("Use Template") {
                    Task { @MainActor in
                        do {
                            _ = try await model.savePendingTemplateImport()
                        } catch {
                            model.present(error: error)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Dismiss Review") {
                    model.discardPendingTemplateImport()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func colorChip(title: String, hex: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: hex) ?? .clear)
                .frame(width: 34, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(hex)
                    .font(.subheadline.monospaced())
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func pill(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .clipShape(Capsule())
    }

    private func archetypeLabel(_ archetype: TemplateArchetype) -> String {
        switch archetype {
        case .technicalNote:
            return "Technical Note"
        case .meetingBrief:
            return "Meeting Brief"
        case .formalBrief:
            return "Formal Brief"
        }
    }

    private func humanLabel(for blockType: TemplateBlockType) -> String {
        switch blockType {
        case .title:
            return "Title"
        case .summary:
            return "Summary"
        case .section:
            return "Section"
        case .keyPoints:
            return "Key Points"
        case .cueQuestions:
            return "Cue Questions"
        case .callouts:
            return "Callouts"
        case .glossary:
            return "Glossary"
        case .studyCards:
            return "Study Cards"
        case .reviewQuestions:
            return "Review Questions"
        case .actionItems:
            return "Action Items"
        case .warningBox:
            return "Warnings"
        case .exercise:
            return "Exercises"
        }
    }

    private func sectionTitle(for block: TemplateBlockSpec, fingerprint: SourceFingerprint) -> String {
        if block.blockType == .section {
            return "Sections"
        }
        if let titleOverride = block.titleOverride?.nonEmpty {
            return titleOverride
        }
        if let importedName = importedBoxName(for: block, fingerprint: fingerprint) {
            return importedName
        }
        return humanLabel(for: block.blockType)
    }

    private func sectionSubtitle(for block: TemplateBlockSpec) -> String {
        let binding = block.fieldBinding?.nonEmpty ?? block.blockType.rawValue
        return "auto · \(binding)"
    }

    private func importedBoxName(for block: TemplateBlockSpec, fingerprint: SourceFingerprint) -> String? {
        let variant = TemplateBlockStyleVariant(rawValue: block.styleVariant)
        return fingerprint.boxStyles.first {
            inferredVariant(for: $0) == variant
        }?.name
    }

    private func inferredVariant(for style: LatexBoxStyle) -> TemplateBlockStyleVariant {
        let combined = "\(style.name) \(style.title ?? "")".lowercased()
        if combined.contains("warning") { return .warning }
        if combined.contains("result") { return .result }
        if combined.contains("code") { return .code }
        if combined.contains("exam") || combined.contains("exercise") { return .exam }
        if combined.contains("key") { return .key }
        if combined.contains("summary") { return .summary }
        return .summary
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
