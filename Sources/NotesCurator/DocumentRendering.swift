import SwiftUI

struct StyledDraftPreview: View {
    let version: DraftVersion

    private var theme: DocumentTheme {
        DocumentTheme.named(version.structuredDoc.exportMetadata.visualTemplateName)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
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
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(version.structuredDoc.exportMetadata.visualTemplateName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(version.structuredDoc.title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)

                Text(version.structuredDoc.summary)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(accent.opacity(0.18), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
            }

            previewListSection(title: label(.cueQuestions), items: version.structuredDoc.cueQuestions, icon: "questionmark.bubble", tone: accentSoft)
            previewListSection(title: label(.keyPoints), items: version.structuredDoc.keyPoints, icon: "sparkles", tone: accent.opacity(0.08))

            if !version.structuredDoc.callouts.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    previewHeading(label(.callouts))
                    ForEach(Array(version.structuredDoc.callouts.enumerated()), id: \.offset) { _, callout in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(calloutTitle(for: callout.kind))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(accent)
                            Text(callout.title)
                                .font(.headline)
                            Text(callout.body)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(calloutBackground(for: callout.kind))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }
            }

            ForEach(Array(version.structuredDoc.sections.enumerated()), id: \.offset) { index, section in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accent)
                            .frame(width: 22, height: 22)
                            .background(accentSoft)
                            .clipShape(Circle())
                        Text(section.title)
                            .font(.title3.weight(.semibold))
                    }
                    Text(section.body)
                        .foregroundStyle(.primary)
                    if !section.bulletPoints.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(section.bulletPoints, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(accent)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 7)
                                    Text(bullet)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(accent.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }

            if !version.structuredDoc.glossary.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    previewHeading(label(.glossary))
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(version.structuredDoc.glossary.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.term)
                                    .font(.headline)
                                    .foregroundStyle(accent)
                                Text(item.definition)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
            }

            if !version.structuredDoc.studyCards.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    previewHeading(label(.studyCards))
                    ForEach(Array(version.structuredDoc.studyCards.enumerated()), id: \.offset) { _, card in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(card.question)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(card.answer)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(accent.opacity(0.12), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }
            }

            previewListSection(title: label(.reviewQuestions), items: version.structuredDoc.reviewQuestions, icon: "checklist", tone: accent.opacity(0.08))
            previewListSection(title: label(.actionItems), items: version.structuredDoc.actionItems, icon: "flag", tone: accentSoft)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(accent.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func previewListSection(title: String, items: [String], icon: String, tone: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                previewHeading(title)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items, id: \.self) { item in
                        Label {
                            Text(item)
                                .foregroundStyle(.primary)
                        } icon: {
                            Image(systemName: icon)
                                .foregroundStyle(accent)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tone)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func previewHeading(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(accent)
            .tracking(1.1)
    }

    private func calloutTitle(for kind: StructuredCalloutKind) -> String {
        if version.outputLanguage == .chinese {
            switch kind {
            case .keyIdea: return "核心观点"
            case .note: return "补充说明"
            case .warning: return "注意事项"
            case .example: return "例子"
            }
        }

        switch kind {
        case .keyIdea: return "KEY IDEA"
        case .note: return "NOTE"
        case .warning: return "WATCH OUT"
        case .example: return "EXAMPLE"
        }
    }

    private func calloutBackground(for kind: StructuredCalloutKind) -> Color {
        switch kind {
        case .keyIdea: return accent.opacity(0.08)
        case .note: return .white
        case .warning: return .orange.opacity(0.12)
        case .example: return .green.opacity(0.10)
        }
    }

    private func label(_ section: PreviewSectionLabel) -> String {
        switch (section, version.outputLanguage) {
        case (.cueQuestions, .chinese): return "复习提示"
        case (.keyPoints, .chinese): return "重点"
        case (.callouts, .chinese): return "提示框"
        case (.glossary, .chinese): return "术语"
        case (.studyCards, .chinese): return "学习问答"
        case (.reviewQuestions, .chinese): return "自测问题"
        case (.actionItems, .chinese): return "行动项"
        case (.cueQuestions, .english): return "Cue Questions"
        case (.keyPoints, .english): return "Key Points"
        case (.callouts, .english): return "Callouts"
        case (.glossary, .english): return "Glossary"
        case (.studyCards, .english): return "Study Cards"
        case (.reviewQuestions, .english): return "Review Questions"
        case (.actionItems, .english): return "Action Items"
        }
    }
}

private enum PreviewSectionLabel {
    case cueQuestions
    case keyPoints
    case callouts
    case glossary
    case studyCards
    case reviewQuestions
    case actionItems
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
