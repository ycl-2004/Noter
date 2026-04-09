import SwiftUI

struct StyledDraftPreview: View {
    let version: DraftVersion

    private var pack: TemplatePack? {
        try? version.resolvedTemplatePackForRendering()
    }

    private var theme: DocumentTheme {
        if let pack {
            return DocumentTheme(
                name: version.structuredDoc.exportMetadata.visualTemplateName,
                accentHex: pack.style.accentHex,
                accentSoftHex: pack.style.surfaceHex,
                surfaceHex: pack.style.surfaceHex,
                borderHex: pack.style.borderHex,
                secondaryHex: pack.style.secondaryHex
            )
        }
        return DocumentTheme.named(version.structuredDoc.exportMetadata.visualTemplateName)
    }

    private var accent: Color {
        Color(hex: theme.accentHex) ?? .accentColor
    }

    private var accentSoft: Color {
        Color(hex: theme.accentSoftHex) ?? accent.opacity(0.1)
    }

    private var surface: Color {
        Color(hex: theme.surfaceHex) ?? .white
    }

    private var border: Color {
        Color(hex: theme.borderHex) ?? accent.opacity(0.14)
    }

    private var secondary: Color {
        Color(hex: theme.secondaryHex) ?? .secondary
    }

    private var renderedTemplate: RenderedTemplateDocument? {
        guard version.structuredDoc.exportMetadata.contentTemplatePackData != nil else {
            return nil
        }
        return try? version.renderedTemplateDocument(for: .preview)
    }

    private var markdownBlocks: [MarkdownBlock] {
        let markdown = (try? version.renderedMarkdown(for: .preview)) ?? version.editorDocument
        return (try? MarkdownDocument.parse(markdown).blocks) ?? [
            MarkdownBlock(kind: .paragraph, text: markdown, items: [])
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Text(version.structuredDoc.exportMetadata.contentTemplateName.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accentSoft)
                    .clipShape(Capsule())
                Text(version.outputLanguage == .chinese ? "中文 Output" : "English Output")
                    .font(.caption)
                    .foregroundStyle(secondary)
                Spacer()
                Text(version.structuredDoc.exportMetadata.visualTemplateName)
                    .font(.caption)
                    .foregroundStyle(secondary)
            }

            if let renderedTemplate, let pack {
                ForEach(renderedTemplate.blocks) { block in
                    renderedTemplateBlockView(block, pack: pack)
                }
            } else {
                ForEach(Array(markdownBlocks.enumerated()), id: \.offset) { index, block in
                    markdownBlockView(block, index: index)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(border.opacity(0.92), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func renderedTemplateBlockView(_ block: RenderedTemplateBlock, pack: TemplatePack) -> some View {
        let boxStyle = pack.style.boxStyle(for: block)

        if block.blockType == .section {
            VStack(alignment: .leading, spacing: 10) {
                Text(block.title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.top, 6)
                templateCard(
                    title: nil,
                    body: block.body,
                    items: block.items,
                    placeholder: block.placeholderText,
                    boxStyle: boxStyle,
                    codeStyle: false
                )
            }
        } else {
            templateCard(
                title: block.title,
                body: block.body,
                items: block.items,
                placeholder: block.placeholderText,
                boxStyle: boxStyle,
                codeStyle: TemplateBlockStyleVariant(rawValue: block.styleVariant) == .code
            )
        }
    }

    @ViewBuilder
    private func templateCard(
        title: String?,
        body: String?,
        items: [String],
        placeholder: String?,
        boxStyle: TemplateBoxStyle,
        codeStyle: Bool
    ) -> some View {
        let background = Color(hex: boxStyle.backgroundHex) ?? .white
        let stroke = Color(hex: boxStyle.borderHex) ?? accent.opacity(0.12)
        let titleTextColor = Color(hex: boxStyle.titleTextHex) ?? accent
        let bodyTextColor = Color(hex: boxStyle.bodyTextHex) ?? .primary
        let titleBackground = boxStyle.titleBackgroundHex.flatMap(Color.init(hex:))

        VStack(alignment: .leading, spacing: 0) {
            if let title, !title.isEmpty {
                Group {
                    if let titleBackground {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(titleTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(titleBackground)
                    } else {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(titleTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if let body, !body.isEmpty {
                    Text(body)
                        .font(codeStyle ? .system(.body, design: .monospaced) : .body)
                        .foregroundStyle(bodyTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(titleTextColor.opacity(codeStyle ? 0.45 : 0.88))
                                    .frame(width: 7, height: 7)
                                    .padding(.top, 7)
                                Text(item)
                                    .font(codeStyle ? .system(.body, design: .monospaced) : .body)
                                    .foregroundStyle(bodyTextColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                if let placeholder, !placeholder.isEmpty {
                    Text(placeholder)
                        .font(.body.italic())
                        .foregroundStyle(bodyTextColor.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, titleBackground == nil && title != nil ? 16 : 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(stroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder
    private func markdownBlockView(_ block: MarkdownBlock, index: Int) -> some View {
        switch block.kind {
        case .heading1:
            Text(block.text)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .padding(.top, index == 0 ? 0 : 4)
        case .heading2:
            Text(block.text)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(accent)
                .padding(.top, 6)
        case .heading3:
            Text(block.text)
                .font(.headline)
                .foregroundStyle(.primary)
        case .paragraph:
            Text(block.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.primary)
                .padding(18)
                .background(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(accent.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
        case .list:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(block.items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                            .padding(.top, 7)
                        Text(item)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        case .quote:
            Text(block.text)
                .foregroundStyle(secondary)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 4)
                        .padding(.vertical, 10)
                        .padding(.leading, 10)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(accent.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

struct ImportedTemplatePreviewCard: View {
    let preview: ImportedTemplatePreview
    let pack: TemplatePack

    private var accent: Color {
        Color(hex: pack.style.accentHex) ?? .accentColor
    }

    private var surface: Color {
        Color(hex: pack.style.surfaceHex) ?? .white
    }

    private var border: Color {
        Color(hex: pack.style.borderHex) ?? accent.opacity(0.14)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(preview.title)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(accent)

            if let subtitle = preview.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(preview.blocks) { block in
                previewBlockView(block)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(border.opacity(0.92), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func previewBlockView(_ block: ImportedTemplatePreviewBlock) -> some View {
        switch block.kind {
        case .separator:
            Rectangle()
                .fill(accent.opacity(0.72))
                .frame(height: 1)
        case .heading:
            Text(block.title)
                .font(headingFont(for: block.level))
                .foregroundStyle(accent)
                .padding(.top, block.level == 1 ? 8 : 4)
        case .paragraph:
            Text(block.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .box:
            let style = pack.style.boxStyle(
                variantName: block.styleVariant,
                fallback: .summary
            )
            let isCode = TemplateBlockStyleVariant(rawValue: block.styleVariant ?? "") == .code
            VStack(alignment: .leading, spacing: 0) {
                if !block.title.isEmpty {
                    if let titleBackground = style.titleBackgroundHex.flatMap(Color.init(hex:)) {
                        Text(block.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color(hex: style.titleTextHex) ?? accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(titleBackground)
                    } else {
                        Text(block.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(Color(hex: style.titleTextHex) ?? accent)
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    if !block.body.isEmpty {
                        Text(block.body)
                            .font(isCode ? .system(.body, design: .monospaced) : .body)
                            .foregroundStyle(Color(hex: style.bodyTextHex) ?? .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !block.items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(block.items, id: \.self) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Circle()
                                        .fill((Color(hex: style.titleTextHex) ?? accent).opacity(0.82))
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 7)
                                    Text(item)
                                        .font(isCode ? .system(.body, design: .monospaced) : .body)
                                        .foregroundStyle(Color(hex: style.bodyTextHex) ?? .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: style.backgroundHex) ?? .white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: style.borderHex) ?? accent.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 24, weight: .bold, design: .serif)
        case 2:
            return .system(size: 18, weight: .bold, design: .serif)
        default:
            return .headline
        }
    }
}

private extension StyleKit {
    func boxStyle(for block: RenderedTemplateBlock) -> TemplateBoxStyle {
        let fallback: TemplateBlockStyleVariant = switch block.blockType {
        case .summary:
            .summary
        case .keyPoints:
            .key
        case .warningBox:
            .warning
        case .studyCards, .reviewQuestions, .exercise:
            .exam
        case .actionItems:
            .result
        case .title, .section, .cueQuestions, .callouts, .glossary:
            .standard
        }

        return boxStyle(variantName: block.styleVariant, fallback: fallback)
    }

    func boxStyle(
        variantName: String?,
        fallback: TemplateBlockStyleVariant
    ) -> TemplateBoxStyle {
        let resolvedVariant = TemplateBlockStyleVariant(rawValue: variantName ?? "") ?? fallback
        return boxStyles.first(where: { $0.variant == resolvedVariant })
            ?? boxStyles.first(where: { $0.variant == .standard })
            ?? TemplateBoxStyle(
                variant: resolvedVariant,
                borderHex: borderHex,
                backgroundHex: "#FFFFFF",
                titleBackgroundHex: nil,
                titleTextHex: accentHex,
                bodyTextHex: "#22304A"
            )
    }
}

extension Color {
    init?(hex: String) {
        let cleaned = hex.replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
