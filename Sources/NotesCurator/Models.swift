import Foundation

enum WorkspaceCover: String, Codable, CaseIterable, Equatable, Sendable {
    case ocean
    case graphite
    case bloom
}

struct Workspace: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var subtitle: String
    var cover: WorkspaceCover
    var coverImagePath: String?
    var createdAt: Date
    var updatedAt: Date
    var pinned: Bool

    init(
        id: UUID = UUID(),
        name: String,
        subtitle: String = "Drafts, notes, exports, and templates all live here, with a guided path from intake to export.",
        cover: WorkspaceCover,
        coverImagePath: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        pinned: Bool = false
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.cover = cover
        self.coverImagePath = coverImagePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case subtitle
        case cover
        case coverImagePath
        case createdAt
        case updatedAt
        case pinned
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            ?? "Drafts, notes, exports, and templates all live here, with a guided path from intake to export."
        cover = try container.decode(WorkspaceCover.self, forKey: .cover)
        coverImagePath = try container.decodeIfPresent(String.self, forKey: .coverImagePath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }
}

enum WorkspaceItemKind: String, Codable, CaseIterable, Equatable, Sendable {
    case draft
    case export
    case note
    case template
}

enum WorkspaceItemStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case processing
    case ready
    case failed
}

enum DraftRefinementStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case refining
    case refined
    case failed
}

struct WorkspaceItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var workspaceId: UUID
    var kind: WorkspaceItemKind
    var title: String
    var summaryPreview: String
    var lastEditedAt: Date
    var currentVersionId: UUID?
    var status: WorkspaceItemStatus
    var refinementStatus: DraftRefinementStatus
    var pendingRefinedVersionId: UUID?

    init(
        id: UUID = UUID(),
        workspaceId: UUID,
        kind: WorkspaceItemKind,
        title: String,
        summaryPreview: String,
        lastEditedAt: Date = .now,
        currentVersionId: UUID? = nil,
        status: WorkspaceItemStatus = .ready,
        refinementStatus: DraftRefinementStatus = .none,
        pendingRefinedVersionId: UUID? = nil
    ) {
        self.id = id
        self.workspaceId = workspaceId
        self.kind = kind
        self.title = title
        self.summaryPreview = summaryPreview
        self.lastEditedAt = lastEditedAt
        self.currentVersionId = currentVersionId
        self.status = status
        self.refinementStatus = refinementStatus
        self.pendingRefinedVersionId = pendingRefinedVersionId
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case workspaceId
        case kind
        case title
        case summaryPreview
        case lastEditedAt
        case currentVersionId
        case status
        case refinementStatus
        case pendingRefinedVersionId
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workspaceId = try container.decode(UUID.self, forKey: .workspaceId)
        kind = try container.decode(WorkspaceItemKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        summaryPreview = try container.decode(String.self, forKey: .summaryPreview)
        lastEditedAt = try container.decode(Date.self, forKey: .lastEditedAt)
        currentVersionId = try container.decodeIfPresent(UUID.self, forKey: .currentVersionId)
        status = try container.decodeIfPresent(WorkspaceItemStatus.self, forKey: .status)
            ?? (currentVersionId == nil ? .failed : .ready)
        refinementStatus = try container.decodeIfPresent(DraftRefinementStatus.self, forKey: .refinementStatus) ?? .none
        pendingRefinedVersionId = try container.decodeIfPresent(UUID.self, forKey: .pendingRefinedVersionId)
    }
}

enum GoalType: String, Codable, CaseIterable, Equatable, Sendable {
    case summary
    case structuredNotes
    case formalDocument
    case actionItems
}

enum OutputLanguage: String, Codable, CaseIterable, Equatable, Sendable {
    case chinese
    case english
}

struct IntakeRequest: Equatable, Sendable {
    var pastedText: String
    var fileURLs: [URL]
    var goalType: GoalType
    var outputLanguage: OutputLanguage
    var contentTemplateName: String
    var visualTemplateName: String
}

enum ExportFormat: String, Codable, CaseIterable, Equatable, Sendable {
    case markdown
    case txt
    case html
    case rtf
    case docx
    case pdf
    case latex

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .txt: return "Plain Text"
        case .html: return "HTML"
        case .rtf: return "RTF"
        case .docx: return "DOCX"
        case .pdf: return "PDF"
        case .latex: return "LaTeX Project"
        }
    }

    var shortLabel: String {
        switch self {
        case .markdown: return "MD"
        case .txt: return "TXT"
        case .html: return "HTML"
        case .rtf: return "RTF"
        case .docx: return "DOCX"
        case .pdf: return "PDF"
        case .latex: return "TEX"
        }
    }

    var compatibilityLabel: String {
        switch self {
        case .markdown:
            return "Obsidian, Logseq, Notion-friendly"
        case .txt:
            return "Universal plain text notes"
        case .html:
            return "Web sharing and browser preview"
        case .rtf:
            return "Rich text editing in macOS and Word-compatible apps"
        case .docx:
            return "Microsoft Word and Google Docs import"
        case .pdf:
            return "Fixed-layout sharing and printing"
        case .latex:
            return "Full LaTeX project for local editors and Overleaf-style workflows"
        }
    }

    var usesSourcePreview: Bool {
        switch self {
        case .markdown, .txt, .latex:
            return true
        case .html, .rtf, .docx, .pdf:
            return false
        }
    }
}

struct StructuredSection: Codable, Equatable, Sendable {
    var title: String
    var body: String

    var bulletPoints: [String]

    init(title: String, body: String, bulletPoints: [String] = []) {
        self.title = title
        self.body = body
        self.bulletPoints = bulletPoints
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case body
        case bulletPoints
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        bulletPoints = try container.decodeIfPresent([String].self, forKey: .bulletPoints) ?? []
    }
}

enum StructuredCalloutKind: String, Codable, CaseIterable, Equatable, Sendable {
    case keyIdea
    case note
    case warning
    case example
}

struct StructuredCallout: Codable, Equatable, Sendable {
    var kind: StructuredCalloutKind
    var title: String
    var body: String

    init(kind: StructuredCalloutKind, title: String, body: String) {
        self.kind = kind
        self.title = title
        self.body = body
    }
}

enum StructuredTemplateBoxKind: String, Codable, CaseIterable, Equatable, Sendable {
    case summary
    case key
    case meta
    case warning
    case code
    case result
    case exam
    case checklist
    case question
    case explanation
    case example
}

struct StructuredTemplateBox: Codable, Equatable, Sendable {
    var kind: StructuredTemplateBoxKind
    var title: String
    var body: String
    var items: [String]

    init(
        kind: StructuredTemplateBoxKind,
        title: String,
        body: String,
        items: [String] = []
    ) {
        self.kind = kind
        self.title = title
        self.body = body
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case title
        case body
        case items
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(StructuredTemplateBoxKind.self, forKey: .kind)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        items = try container.decodeIfPresent([String].self, forKey: .items) ?? []
    }
}

struct GlossaryItem: Codable, Equatable, Sendable {
    var term: String
    var definition: String

    init(term: String, definition: String) {
        self.term = term
        self.definition = definition
    }
}

struct StudyCard: Codable, Equatable, Sendable {
    var question: String
    var answer: String

    init(question: String, answer: String) {
        self.question = question
        self.answer = answer
    }
}

struct ImageSlot: Codable, Equatable, Sendable {
    var suggestionID: UUID
    var caption: String
}

enum TemplateFormat: String, Codable, Equatable, Sendable {
    case legacyConfig
    case markdownTemplate
    case latexProject
}

struct ExportMetadata: Codable, Equatable, Sendable {
    var contentTemplateID: UUID?
    var contentTemplateName: String
    var contentTemplatePackData: Data?
    var contentTemplateLatexProjectData: Data?
    var renderedContentTemplateID: UUID?
    var visualTemplateID: UUID?
    var visualTemplateName: String
    var preferredFormat: ExportFormat

    init(
        contentTemplateID: UUID? = nil,
        contentTemplateName: String,
        contentTemplatePackData: Data? = nil,
        contentTemplateLatexProjectData: Data? = nil,
        renderedContentTemplateID: UUID? = nil,
        visualTemplateID: UUID? = nil,
        visualTemplateName: String,
        preferredFormat: ExportFormat
    ) {
        self.contentTemplateID = contentTemplateID
        self.contentTemplateName = contentTemplateName
        self.contentTemplatePackData = contentTemplatePackData
        self.contentTemplateLatexProjectData = contentTemplateLatexProjectData
        self.renderedContentTemplateID = renderedContentTemplateID
        self.visualTemplateID = visualTemplateID
        self.visualTemplateName = visualTemplateName
        self.preferredFormat = preferredFormat
    }

    private enum CodingKeys: String, CodingKey {
        case contentTemplateID
        case contentTemplateName
        case contentTemplatePackData
        case contentTemplateLatexProjectData
        case renderedContentTemplateID
        case visualTemplateID
        case visualTemplateName
        case preferredFormat
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentTemplateID = try container.decodeIfPresent(UUID.self, forKey: .contentTemplateID)
        contentTemplateName = try container.decode(String.self, forKey: .contentTemplateName)
        contentTemplatePackData = try container.decodeIfPresent(Data.self, forKey: .contentTemplatePackData)
        contentTemplateLatexProjectData = try container.decodeIfPresent(Data.self, forKey: .contentTemplateLatexProjectData)
        renderedContentTemplateID = try container.decodeIfPresent(UUID.self, forKey: .renderedContentTemplateID)
        visualTemplateID = try container.decodeIfPresent(UUID.self, forKey: .visualTemplateID)
        visualTemplateName = try container.decode(String.self, forKey: .visualTemplateName)
        preferredFormat = try container.decode(ExportFormat.self, forKey: .preferredFormat)
    }
}

struct DocumentTheme: Equatable, Sendable {
    var name: String
    var accentHex: String
    var accentSoftHex: String
    var surfaceHex: String
    var borderHex: String
    var secondaryHex: String

    static func named(_ name: String) -> DocumentTheme {
        switch name.lowercased() {
        case "graphite":
            return DocumentTheme(
                name: "Graphite",
                accentHex: "#2A3347",
                accentSoftHex: "#EEF1F6",
                surfaceHex: "#F7F8FB",
                borderHex: "#D9DFEA",
                secondaryHex: "#687387"
            )
        case "bloom":
            return DocumentTheme(
                name: "Bloom",
                accentHex: "#D7568B",
                accentSoftHex: "#FFF0F7",
                surfaceHex: "#FFF8FB",
                borderHex: "#F5D6E5",
                secondaryHex: "#8E5A72"
            )
        case "ivory lecture":
            return DocumentTheme(
                name: "Ivory Lecture",
                accentHex: "#7A5C2E",
                accentSoftHex: "#F8F2E8",
                surfaceHex: "#FFFCF8",
                borderHex: "#E7D7BC",
                secondaryHex: "#8C7A5B"
            )
        case "sage ledger":
            return DocumentTheme(
                name: "Sage Ledger",
                accentHex: "#2F6A57",
                accentSoftHex: "#EEF7F2",
                surfaceHex: "#F8FCFA",
                borderHex: "#D4E7DE",
                secondaryHex: "#5E7E73"
            )
        case "indigo ink":
            return DocumentTheme(
                name: "Indigo Ink",
                accentHex: "#4A56C8",
                accentSoftHex: "#EEF1FF",
                surfaceHex: "#F5F7FF",
                borderHex: "#D6DCFF",
                secondaryHex: "#646F9C"
            )
        case "emerald grove":
            return DocumentTheme(
                name: "Emerald Grove",
                accentHex: "#047857",
                accentSoftHex: "#ECFDF5",
                surfaceHex: "#F5FEFA",
                borderHex: "#CDEFE1",
                secondaryHex: "#4F7E71"
            )
        case "amber journal":
            return DocumentTheme(
                name: "Amber Journal",
                accentHex: "#D97706",
                accentSoftHex: "#FFF7E8",
                surfaceHex: "#FFFCF4",
                borderHex: "#F4E1BA",
                secondaryHex: "#8F6C31"
            )
        case "rose studio":
            return DocumentTheme(
                name: "Rose Studio",
                accentHex: "#BE4B75",
                accentSoftHex: "#FFF1F5",
                surfaceHex: "#FFF7F8",
                borderHex: "#F1D6DF",
                secondaryHex: "#8E6371"
            )
        case "teal current":
            return DocumentTheme(
                name: "Teal Current",
                accentHex: "#0F766E",
                accentSoftHex: "#F0FDFA",
                surfaceHex: "#F3FCFA",
                borderHex: "#CBEAE4",
                secondaryHex: "#517E7A"
            )
        default:
            return DocumentTheme(
                name: "Oceanic Blue",
                accentHex: "#165FCA",
                accentSoftHex: "#EEF4FF",
                surfaceHex: "#F6F9FF",
                borderHex: "#D6E3FF",
                secondaryHex: "#5D6F92"
            )
        }
    }
}

struct StructuredDocument: Codable, Equatable, Sendable {
    var title: String
    var summary: String
    var cueQuestions: [String]
    var keyPoints: [String]
    var sections: [StructuredSection]
    var glossary: [GlossaryItem]
    var callouts: [StructuredCallout]
    var templateBoxes: [StructuredTemplateBox]
    var studyCards: [StudyCard]
    var actionItems: [String]
    var reviewQuestions: [String]
    var imageSlots: [ImageSlot]
    var exportMetadata: ExportMetadata

    init(
        title: String,
        summary: String,
        cueQuestions: [String] = [],
        keyPoints: [String],
        sections: [StructuredSection],
        glossary: [GlossaryItem] = [],
        callouts: [StructuredCallout] = [],
        templateBoxes: [StructuredTemplateBox] = [],
        studyCards: [StudyCard] = [],
        actionItems: [String],
        reviewQuestions: [String] = [],
        imageSlots: [ImageSlot],
        exportMetadata: ExportMetadata
    ) {
        self.title = title
        self.summary = summary
        self.cueQuestions = cueQuestions
        self.keyPoints = keyPoints
        self.sections = sections
        self.glossary = glossary
        self.callouts = callouts
        self.templateBoxes = templateBoxes
        self.studyCards = studyCards
        self.actionItems = actionItems
        self.reviewQuestions = reviewQuestions
        self.imageSlots = imageSlots
        self.exportMetadata = exportMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case title
        case summary
        case cueQuestions
        case keyPoints
        case sections
        case glossary
        case callouts
        case templateBoxes
        case studyCards
        case actionItems
        case reviewQuestions
        case imageSlots
        case exportMetadata
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        cueQuestions = try container.decodeIfPresent([String].self, forKey: .cueQuestions) ?? []
        keyPoints = try container.decodeIfPresent([String].self, forKey: .keyPoints) ?? []
        sections = try container.decodeIfPresent([StructuredSection].self, forKey: .sections) ?? []
        glossary = try container.decodeIfPresent([GlossaryItem].self, forKey: .glossary) ?? []
        callouts = try container.decodeIfPresent([StructuredCallout].self, forKey: .callouts) ?? []
        templateBoxes = try container.decodeIfPresent([StructuredTemplateBox].self, forKey: .templateBoxes) ?? []
        studyCards = try container.decodeIfPresent([StudyCard].self, forKey: .studyCards) ?? []
        actionItems = try container.decodeIfPresent([String].self, forKey: .actionItems) ?? []
        reviewQuestions = try container.decodeIfPresent([String].self, forKey: .reviewQuestions) ?? []
        imageSlots = try container.decodeIfPresent([ImageSlot].self, forKey: .imageSlots) ?? []
        exportMetadata = try container.decode(ExportMetadata.self, forKey: .exportMetadata)
    }
}

enum SourceKind: String, Codable, Equatable, Sendable {
    case pastedText
    case txtFile
    case markdownFile
    case docxFile
    case pdfFile
    case imageFile
}

struct SourceReference: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: SourceKind
    var title: String
    var excerpt: String

    init(id: UUID = UUID(), kind: SourceKind, title: String, excerpt: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.excerpt = excerpt
    }
}

struct ImageSuggestion: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var summary: String
    var ocrText: String
    var isSelected: Bool

    init(
        id: UUID = UUID(),
        title: String,
        summary: String,
        ocrText: String,
        isSelected: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.ocrText = ocrText
        self.isSelected = isSelected
    }
}

struct ParsedImageAsset: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var summary: String
    var ocrText: String

    init(id: UUID = UUID(), title: String, summary: String, ocrText: String) {
        self.id = id
        self.title = title
        self.summary = summary
        self.ocrText = ocrText
    }
}

struct ParsedDocument: Equatable, Sendable {
    var text: String
    var sources: [SourceReference]
    var images: [ParsedImageAsset]
}

enum ProcessingStage: String, CaseIterable, Equatable, Sendable {
    case parseDocument
    case extractText
    case extractImages
    case runOCR
    case chunkAndMerge
    case renderOutputLanguage
    case validateDraft
    case generateImageSuggestions
    case completed
}

enum DraftVersionOrigin: String, Codable, CaseIterable, Equatable, Sendable {
    case interactive
    case refined
    case manual
}

struct DraftVersion: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var workspaceItemId: UUID
    var goalType: GoalType
    var outputLanguage: OutputLanguage
    var editorDocument: String
    var structuredDoc: StructuredDocument
    var sourceRefs: [SourceReference]
    var imageSuggestions: [ImageSuggestion]
    var origin: DraftVersionOrigin
    var parentVersionId: UUID?
    var createdAt: Date
    var generationSourceText: String?

    init(
        id: UUID = UUID(),
        workspaceItemId: UUID,
        goalType: GoalType,
        outputLanguage: OutputLanguage,
        editorDocument: String,
        structuredDoc: StructuredDocument,
        sourceRefs: [SourceReference],
        imageSuggestions: [ImageSuggestion],
        origin: DraftVersionOrigin = .manual,
        parentVersionId: UUID? = nil,
        createdAt: Date = .now,
        generationSourceText: String? = nil
    ) {
        self.id = id
        self.workspaceItemId = workspaceItemId
        self.goalType = goalType
        self.outputLanguage = outputLanguage
        self.editorDocument = editorDocument
        self.structuredDoc = structuredDoc
        self.sourceRefs = sourceRefs
        self.imageSuggestions = imageSuggestions
        self.origin = origin
        self.parentVersionId = parentVersionId
        self.createdAt = createdAt
        self.generationSourceText = generationSourceText
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case workspaceItemId
        case goalType
        case outputLanguage
        case editorDocument
        case structuredDoc
        case sourceRefs
        case imageSuggestions
        case origin
        case parentVersionId
        case createdAt
        case generationSourceText
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        workspaceItemId = try container.decode(UUID.self, forKey: .workspaceItemId)
        goalType = try container.decode(GoalType.self, forKey: .goalType)
        outputLanguage = try container.decode(OutputLanguage.self, forKey: .outputLanguage)
        editorDocument = try container.decode(String.self, forKey: .editorDocument)
        structuredDoc = try container.decode(StructuredDocument.self, forKey: .structuredDoc)
        sourceRefs = try container.decodeIfPresent([SourceReference].self, forKey: .sourceRefs) ?? []
        imageSuggestions = try container.decodeIfPresent([ImageSuggestion].self, forKey: .imageSuggestions) ?? []
        origin = try container.decodeIfPresent(DraftVersionOrigin.self, forKey: .origin) ?? .manual
        parentVersionId = try container.decodeIfPresent(UUID.self, forKey: .parentVersionId)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        generationSourceText = try container.decodeIfPresent(String.self, forKey: .generationSourceText)
    }
}

enum TemplateKind: String, Codable, CaseIterable, Equatable, Sendable {
    case content
    case visual
}

enum TemplateScope: String, Codable, CaseIterable, Equatable, Sendable {
    case system
    case user
}

struct Template: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var kind: TemplateKind
    var scope: TemplateScope
    var name: String
    var subtitle: String
    var templateDescription: String
    var format: TemplateFormat
    var body: String
    var config: [String: String]
    var storedPackData: Data?
    var storedLatexSource: String?
    var storedLatexProjectData: Data?

    init(
        id: UUID = UUID(),
        kind: TemplateKind,
        scope: TemplateScope,
        name: String,
        subtitle: String = "",
        templateDescription: String = "",
        format: TemplateFormat = .legacyConfig,
        body: String = "",
        config: [String: String],
        storedPackData: Data? = nil,
        storedLatexSource: String? = nil,
        storedLatexProjectData: Data? = nil
    ) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.name = name
        self.subtitle = subtitle
        self.templateDescription = templateDescription
        self.format = format
        self.body = body
        self.config = config
        self.storedPackData = storedPackData
        self.storedLatexSource = storedLatexSource
        self.storedLatexProjectData = storedLatexProjectData
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case kind
        case scope
        case name
        case subtitle
        case templateDescription
        case format
        case body
        case config
        case storedPackData
        case storedLatexSource
        case storedLatexProjectData
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(TemplateKind.self, forKey: .kind)
        scope = try container.decode(TemplateScope.self, forKey: .scope)
        name = try container.decode(String.self, forKey: .name)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        templateDescription = try container.decodeIfPresent(String.self, forKey: .templateDescription) ?? ""
        format = try container.decodeIfPresent(TemplateFormat.self, forKey: .format) ?? .legacyConfig
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        config = try container.decodeIfPresent([String: String].self, forKey: .config) ?? [:]
        storedPackData = try container.decodeIfPresent(Data.self, forKey: .storedPackData)
        storedLatexSource = try container.decodeIfPresent(String.self, forKey: .storedLatexSource)
        storedLatexProjectData = try container.decodeIfPresent(Data.self, forKey: .storedLatexProjectData)
    }
}

struct ExportRecord: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var draftVersionId: UUID
    var format: ExportFormat
    var templateId: UUID?
    var outputPath: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        draftVersionId: UUID,
        format: ExportFormat,
        templateId: UUID? = nil,
        outputPath: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.draftVersionId = draftVersionId
        self.format = format
        self.templateId = templateId
        self.outputPath = outputPath
        self.createdAt = createdAt
    }
}

struct HomeHeroCopy: Codable, Equatable, Sendable {
    var eyebrow: String
    var title: String
    var subtitle: String
    var searchPlaceholder: String

    static let defaultValue = Self(
        eyebrow: "Resume Flow",
        title: "Pick up the note that matters right now.",
        subtitle: "Keep workspaces as context, but keep today's active note at the center of intake, editing, review, and export.",
        searchPlaceholder: "Search workspaces or drafts"
    )
}

enum SidebarSection: String, Codable, CaseIterable, Equatable, Sendable {
    case home
    case workspaces
    case drafts
    case templates
    case exports
    case settings
}

enum ProviderKind: String, Codable, CaseIterable, Equatable, Sendable {
    case localOllama
    case customAPI
    case heuristicFallback
}

enum HostedService: String, Codable, CaseIterable, Equatable, Sendable {
    case nvidia
    case openAI
    case zhipu
    case mistral
    case anthropic
    case gemini

    var displayName: String {
        switch self {
        case .nvidia: return "NVIDIA"
        case .openAI: return "OpenAI"
        case .zhipu: return "Zhipu / BigModel"
        case .mistral: return "Mistral"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .nvidia:
            return "https://integrate.api.nvidia.com/v1"
        case .openAI:
            return "https://api.openai.com/v1"
        case .zhipu:
            return "https://open.bigmodel.cn/api/paas/v4"
        case .mistral:
            return "https://api.mistral.ai/v1"
        case .anthropic:
            return "https://api.anthropic.com"
        case .gemini:
            return "https://generativelanguage.googleapis.com"
        }
    }

    var apiKeyEnvironmentVariableName: String {
        switch self {
        case .nvidia:
            return "NOTESCURATOR_NVIDIA_API_KEY"
        case .openAI:
            return "NOTESCURATOR_OPENAI_API_KEY"
        case .zhipu:
            return "NOTESCURATOR_ZHIPU_API_KEY"
        case .mistral:
            return "NOTESCURATOR_MISTRAL_API_KEY"
        case .anthropic:
            return "NOTESCURATOR_ANTHROPIC_API_KEY"
        case .gemini:
            return "NOTESCURATOR_GEMINI_API_KEY"
        }
    }

    var recommendedMainModel: String {
        switch self {
        case .nvidia: return "deepseek-ai/deepseek-v3.2"
        case .openAI: return "gpt-5-mini"
        case .zhipu: return "glm-5"
        case .mistral: return "mistral-medium-2508"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    var recommendedChunkModel: String {
        switch self {
        case .nvidia: return "mistralai/mistral-small-3.1-24b-instruct-2503"
        case .openAI: return "gpt-5-nano"
        case .zhipu: return "glm-4.5-air"
        case .mistral: return "mistral-small-2506"
        case .anthropic: return "claude-3-5-haiku-20241022"
        case .gemini: return "gemini-2.5-flash-lite"
        }
    }

    var recommendedPolishModel: String {
        switch self {
        case .nvidia: return "mistralai/mistral-medium-3-instruct"
        case .openAI: return "gpt-4.1"
        case .zhipu: return "glm-5"
        case .mistral: return "mistral-medium-2508"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .gemini: return "gemini-2.5-pro"
        }
    }

    var recommendedRepairModel: String {
        switch self {
        case .nvidia: return "qwen/qwen3-coder-480b-a35b-instruct"
        case .openAI: return "gpt-5-mini"
        case .zhipu: return "glm-5"
        case .mistral: return "mistral-small-2506"
        case .anthropic: return "claude-sonnet-4-20250514"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    var presets: [HostedModelPreset] {
        switch self {
        case .nvidia:
            return [
                HostedModelPreset(service: self, title: "Balanced Notes", modelName: "deepseek-ai/deepseek-v3.2", baseURL: defaultBaseURL, summary: "Best default for long-form note writing, structured JSON, and reliable editing passes."),
                HostedModelPreset(service: self, title: "Writing + Translation", modelName: "mistralai/mistral-medium-3-instruct", baseURL: defaultBaseURL, summary: "Strong multilingual writing, polished rewrites, and translation-heavy note cleanup."),
                HostedModelPreset(service: self, title: "Fast Structured Output", modelName: "mistralai/mistral-small-3.1-24b-instruct-2503", baseURL: defaultBaseURL, summary: "Faster JSON-shaped drafting for shorter notes, formatting passes, and lighter translation work."),
                HostedModelPreset(service: self, title: "Code + Schema", modelName: "qwen/qwen3-coder-480b-a35b-instruct", baseURL: defaultBaseURL, summary: "Best fit for structured code generation, schema transforms, and formatting logic."),
            ]
        case .openAI:
            return [
                HostedModelPreset(service: self, title: "Balanced Notes", modelName: "gpt-5-mini", baseURL: defaultBaseURL, summary: "Fast, strong generalist for note generation and structured workflow steps."),
                HostedModelPreset(service: self, title: "Writing + Translation", modelName: "gpt-4.1", baseURL: defaultBaseURL, summary: "Strong rewrites, style polish, and multilingual editing."),
                HostedModelPreset(service: self, title: "Fast Structured Output", modelName: "gpt-5-nano", baseURL: defaultBaseURL, summary: "Low-cost chunking and cleanup for high-volume runs."),
                HostedModelPreset(service: self, title: "Code + Schema", modelName: "gpt-5.2", baseURL: defaultBaseURL, summary: "Best fit for code generation, schema transforms, and agentic tasks."),
            ]
        case .zhipu:
            return [
                HostedModelPreset(service: self, title: "Balanced Notes", modelName: "glm-5", baseURL: defaultBaseURL, summary: "Best default for Chinese-first and mixed-language structured notes."),
                HostedModelPreset(service: self, title: "High Accuracy", modelName: "glm-4.7", baseURL: defaultBaseURL, summary: "Higher-accuracy reasoning and writing for more demanding note generation and revision tasks."),
                HostedModelPreset(service: self, title: "Vision + OCR", modelName: "glm-4.6v", baseURL: defaultBaseURL, summary: "Useful when your workflow includes image-heavy materials, OCR follow-up, or visual context."),
                HostedModelPreset(service: self, title: "Fast Structured Output", modelName: "glm-4.5-air", baseURL: defaultBaseURL, summary: "Faster, lower-cost chunking and structured drafting."),
                HostedModelPreset(service: self, title: "Code + Agent", modelName: "glm-4.5", baseURL: defaultBaseURL, summary: "Good for coding, tool use, and agent-oriented workflows."),
            ]
        case .mistral:
            return [
                HostedModelPreset(service: self, title: "Balanced Notes", modelName: "mistral-medium-2508", baseURL: defaultBaseURL, summary: "Best default for polished documents and multilingual note writing."),
                HostedModelPreset(service: self, title: "Writing + Translation", modelName: "mistral-medium-2508", baseURL: defaultBaseURL, summary: "Best fit for polishing and translation-heavy document workflows."),
                HostedModelPreset(service: self, title: "Fast Structured Output", modelName: "mistral-small-2506", baseURL: defaultBaseURL, summary: "Lower-latency drafting and chunk summarization with JSON mode support."),
                HostedModelPreset(service: self, title: "Code + Automation", modelName: "devstral-small-2505", baseURL: defaultBaseURL, summary: "Good for code-oriented cleanup, structured transforms, and engineering-style prompts."),
            ]
        case .anthropic:
            return [
                HostedModelPreset(service: self, title: "Balanced Notes", modelName: "claude-sonnet-4-20250514", baseURL: defaultBaseURL, summary: "Best general-purpose Claude option for writing, reasoning, and structure."),
                HostedModelPreset(service: self, title: "Writing + Translation", modelName: "claude-sonnet-4-20250514", baseURL: defaultBaseURL, summary: "Strong polish, tone control, and multilingual rewrites."),
                HostedModelPreset(service: self, title: "Fast Structured Output", modelName: "claude-3-5-haiku-20241022", baseURL: defaultBaseURL, summary: "Faster low-cost chunking and lightweight cleanup."),
                HostedModelPreset(service: self, title: "Max Reasoning", modelName: "claude-opus-4-1-20250805", baseURL: defaultBaseURL, summary: "Top-end reasoning and coding quality when speed matters less."),
            ]
        case .gemini:
            return [
                HostedModelPreset(service: self, title: "Balanced Notes", modelName: "gemini-2.5-flash", baseURL: defaultBaseURL, summary: "Strong price-performance for large-volume note generation and routing."),
                HostedModelPreset(service: self, title: "Writing + Translation", modelName: "gemini-2.5-pro", baseURL: defaultBaseURL, summary: "Best Gemini option for polish, translation, and high-accuracy rewrites."),
                HostedModelPreset(service: self, title: "Fast Structured Output", modelName: "gemini-2.5-flash-lite", baseURL: defaultBaseURL, summary: "Fastest low-cost option for chunking and structured drafting."),
                HostedModelPreset(service: self, title: "High Accuracy", modelName: "gemini-2.5-pro", baseURL: defaultBaseURL, summary: "Best for complex reasoning, coding, and large-document tasks."),
            ]
        }
    }
}

struct HostedModelPreset: Identifiable, Equatable, Sendable {
    let service: HostedService
    let title: String
    let modelName: String
    let baseURL: String
    let summary: String

    var id: String { "\(service.rawValue):\(modelName)" }
}

struct AppPreferences: Codable, Equatable, Sendable {
    static let recommendedHostedPresetsByService: [HostedService: [HostedModelPreset]] = Dictionary(
        uniqueKeysWithValues: HostedService.allCases.map { ($0, $0.presets) }
    )

    var hostedService: HostedService
    var providerKind: ProviderKind
    var modelName: String
    var defaultOutputLanguage: OutputLanguage
    var defaultExportFormat: ExportFormat
    var autoSave: Bool
    var customBaseURL: String
    var customAPIKey: String
    var hostedAPIKeysByService: [String: String]
    var enableWorkflowRouting: Bool
    var customChunkModelName: String
    var customPolishModelName: String
    var customRepairModelName: String
    var homeHeroCopy: HomeHeroCopy

    init(
        providerKind: ProviderKind,
        hostedService: HostedService = .nvidia,
        modelName: String,
        defaultOutputLanguage: OutputLanguage,
        defaultExportFormat: ExportFormat,
        autoSave: Bool,
        customBaseURL: String,
        customAPIKey: String,
        hostedAPIKeysByService: [String: String] = [:],
        enableWorkflowRouting: Bool = false,
        customChunkModelName: String = HostedService.nvidia.recommendedChunkModel,
        customPolishModelName: String = HostedService.nvidia.recommendedPolishModel,
        customRepairModelName: String = HostedService.nvidia.recommendedRepairModel,
        homeHeroCopy: HomeHeroCopy = .defaultValue
    ) {
        self.hostedService = hostedService
        self.providerKind = providerKind
        self.modelName = modelName
        self.defaultOutputLanguage = defaultOutputLanguage
        self.defaultExportFormat = defaultExportFormat
        self.autoSave = autoSave
        self.customBaseURL = customBaseURL
        self.customAPIKey = customAPIKey
        self.hostedAPIKeysByService = hostedAPIKeysByService
        self.enableWorkflowRouting = enableWorkflowRouting
        self.customChunkModelName = customChunkModelName
        self.customPolishModelName = customPolishModelName
        self.customRepairModelName = customRepairModelName
        self.homeHeroCopy = homeHeroCopy
    }

    static let legacyDefaultLocalOllama = AppPreferences(
        providerKind: .localOllama,
        hostedService: .nvidia,
        modelName: "qwen3:14b",
        defaultOutputLanguage: .english,
        defaultExportFormat: .pdf,
        autoSave: true,
        customBaseURL: "",
        customAPIKey: "",
        hostedAPIKeysByService: [:],
        enableWorkflowRouting: false,
        customChunkModelName: HostedService.nvidia.recommendedChunkModel,
        customPolishModelName: HostedService.nvidia.recommendedPolishModel,
        customRepairModelName: HostedService.nvidia.recommendedRepairModel
    )

    static let recommendedLocalOllama = AppPreferences(
        providerKind: .localOllama,
        hostedService: .nvidia,
        modelName: "qwen3.5:9b",
        defaultOutputLanguage: .english,
        defaultExportFormat: .pdf,
        autoSave: true,
        customBaseURL: "",
        customAPIKey: "",
        hostedAPIKeysByService: [:],
        enableWorkflowRouting: false,
        customChunkModelName: HostedService.nvidia.recommendedChunkModel,
        customPolishModelName: HostedService.nvidia.recommendedPolishModel,
        customRepairModelName: HostedService.nvidia.recommendedRepairModel
    )

    static let `default` = AppPreferences(
        providerKind: .heuristicFallback,
        hostedService: .nvidia,
        modelName: "qwen3.5:9b",
        defaultOutputLanguage: .english,
        defaultExportFormat: .pdf,
        autoSave: true,
        customBaseURL: "",
        customAPIKey: "",
        hostedAPIKeysByService: [:],
        enableWorkflowRouting: false,
        customChunkModelName: HostedService.nvidia.recommendedChunkModel,
        customPolishModelName: HostedService.nvidia.recommendedPolishModel,
        customRepairModelName: HostedService.nvidia.recommendedRepairModel
    )

    static let recommendedNVIDIAHosted = AppPreferences(
        providerKind: .customAPI,
        hostedService: .nvidia,
        modelName: HostedService.nvidia.recommendedMainModel,
        defaultOutputLanguage: .english,
        defaultExportFormat: .pdf,
        autoSave: true,
        customBaseURL: HostedService.nvidia.defaultBaseURL,
        customAPIKey: "",
        hostedAPIKeysByService: [:],
        enableWorkflowRouting: true,
        customChunkModelName: HostedService.nvidia.recommendedChunkModel,
        customPolishModelName: HostedService.nvidia.recommendedPolishModel,
        customRepairModelName: HostedService.nvidia.recommendedRepairModel
    )

    private enum CodingKeys: String, CodingKey {
        case hostedService
        case providerKind
        case modelName
        case defaultOutputLanguage
        case defaultExportFormat
        case autoSave
        case customBaseURL
        case customAPIKey
        case hostedAPIKeysByService
        case enableWorkflowRouting
        case customChunkModelName
        case customPolishModelName
        case customRepairModelName
        case homeHeroCopy
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostedService = try container.decodeIfPresent(HostedService.self, forKey: .hostedService)
            ?? Self.inferHostedService(from: try container.decodeIfPresent(String.self, forKey: .customBaseURL) ?? "")
        providerKind = try container.decode(ProviderKind.self, forKey: .providerKind)
        modelName = try container.decode(String.self, forKey: .modelName)
        defaultOutputLanguage = try container.decode(OutputLanguage.self, forKey: .defaultOutputLanguage)
        defaultExportFormat = try container.decode(ExportFormat.self, forKey: .defaultExportFormat)
        autoSave = try container.decode(Bool.self, forKey: .autoSave)
        customBaseURL = try container.decodeIfPresent(String.self, forKey: .customBaseURL) ?? ""
        customAPIKey = try container.decodeIfPresent(String.self, forKey: .customAPIKey) ?? ""
        hostedAPIKeysByService = try container.decodeIfPresent([String: String].self, forKey: .hostedAPIKeysByService) ?? [:]
        if hostedAPIKeysByService[hostedService.rawValue]?.isEmpty != false, customAPIKey.isEmpty == false {
            hostedAPIKeysByService[hostedService.rawValue] = customAPIKey
        }
        enableWorkflowRouting = try container.decodeIfPresent(Bool.self, forKey: .enableWorkflowRouting) ?? false
        customChunkModelName = try container.decodeIfPresent(String.self, forKey: .customChunkModelName)
            ?? hostedService.recommendedChunkModel
        customPolishModelName = try container.decodeIfPresent(String.self, forKey: .customPolishModelName)
            ?? hostedService.recommendedPolishModel
        customRepairModelName = try container.decodeIfPresent(String.self, forKey: .customRepairModelName)
            ?? hostedService.recommendedRepairModel
        homeHeroCopy = try container.decodeIfPresent(HomeHeroCopy.self, forKey: .homeHeroCopy) ?? .defaultValue
    }

    var legacyMigrationTarget: AppPreferences? {
        guard self == Self.legacyDefaultLocalOllama else { return nil }
        return Self.recommendedLocalOllama
    }

    static func inferHostedService(from baseURL: String) -> HostedService {
        let normalized = baseURL.lowercased()
        if normalized.contains("open.bigmodel.cn") { return .zhipu }
        if normalized.contains("api.openai.com") { return .openAI }
        if normalized.contains("api.mistral.ai") { return .mistral }
        if normalized.contains("api.anthropic.com") { return .anthropic }
        if normalized.contains("generativelanguage.googleapis.com") { return .gemini }
        return .nvidia
    }

    func resolvedAPIKey(for service: HostedService? = nil) -> String {
        let targetService = service ?? hostedService
        let storedKey = hostedAPIKeysByService[targetService.rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if storedKey.isEmpty == false {
            return storedKey
        }

        let environmentKey = ProcessInfo.processInfo.environment[targetService.apiKeyEnvironmentVariableName]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if environmentKey.isEmpty == false {
            return environmentKey
        }

        if targetService == hostedService {
            return customAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    mutating func setHostedAPIKey(_ apiKey: String, for service: HostedService) {
        let normalizedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        hostedAPIKeysByService[service.rawValue] = normalizedKey
        if service == hostedService {
            customAPIKey = normalizedKey
        }
    }

    mutating func syncSelectedHostedServiceAPIKey() {
        customAPIKey = resolvedAPIKey(for: hostedService)
    }
}

struct LastSessionSnapshot: Codable, Equatable, Sendable {
    var sidebarSection: SidebarSection
    var workspaceId: UUID?
    var itemId: UUID?
}

struct RepositorySnapshot: Equatable, Sendable {
    var workspaces: [Workspace]
    var items: [WorkspaceItem]
    var versions: [DraftVersion]
    var templates: [Template]
    var exports: [ExportRecord]
    var preferences: AppPreferences
    var lastSession: LastSessionSnapshot?

    static let empty = RepositorySnapshot(
        workspaces: [],
        items: [],
        versions: [],
        templates: [],
        exports: [],
        preferences: .default,
        lastSession: nil
    )
}
