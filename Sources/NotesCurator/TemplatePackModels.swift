import Foundation

enum TemplatePackError: Error, Equatable, LocalizedError {
    case invalidStoredPack

    var errorDescription: String? {
        switch self {
        case .invalidStoredPack:
            return "The stored template pack data could not be decoded."
        }
    }
}

struct TemplatePack: Codable, Equatable, Sendable {
    var identity: TemplatePackIdentity
    var archetype: TemplateArchetype
    var schema: RecommendedSchema
    var layout: LayoutSpec
    var style: StyleKit
    var behavior: TemplateBehaviorRules
    var importedPreview: ImportedTemplatePreview?

    init(
        identity: TemplatePackIdentity,
        archetype: TemplateArchetype,
        schema: RecommendedSchema,
        layout: LayoutSpec,
        style: StyleKit,
        behavior: TemplateBehaviorRules,
        importedPreview: ImportedTemplatePreview? = nil
    ) {
        self.identity = identity
        self.archetype = archetype
        self.schema = schema
        self.layout = layout
        self.style = style
        self.behavior = behavior
        self.importedPreview = importedPreview
    }

    private enum CodingKeys: String, CodingKey {
        case identity
        case archetype
        case schema
        case layout
        case style
        case behavior
        case importedPreview
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        identity = try container.decode(TemplatePackIdentity.self, forKey: .identity)
        archetype = try container.decode(TemplateArchetype.self, forKey: .archetype)
        schema = try container.decode(RecommendedSchema.self, forKey: .schema)
        layout = try container.decode(LayoutSpec.self, forKey: .layout)
        style = try container.decode(StyleKit.self, forKey: .style)
        behavior = try container.decode(TemplateBehaviorRules.self, forKey: .behavior)
        importedPreview = try container.decodeIfPresent(ImportedTemplatePreview.self, forKey: .importedPreview)
    }
}

struct TemplateImportReview: Equatable, Sendable {
    var source: String
    var fingerprint: SourceFingerprint
    var inferredArchetype: TemplateArchetype
    var templatePack: TemplatePack
}

struct TemplatePackIdentity: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var description: String

    init(
        id: UUID = UUID(),
        name: String,
        description: String = ""
    ) {
        self.id = id
        self.name = name
        self.description = description
    }
}

enum TemplateArchetype: String, Codable, CaseIterable, Equatable, Sendable {
    case technicalNote
    case meetingBrief
    case formalBrief
}

struct RecommendedSchema: Codable, Equatable, Sendable {
    var fields: [RecommendedField]
}

struct RecommendedField: Codable, Equatable, Sendable, Identifiable {
    var id: String { key }
    var key: String
    var label: String
    var requiredLevel: TemplateFieldRequiredLevel
}

enum TemplateFieldRequiredLevel: String, Codable, Equatable, Sendable {
    case coreRequired
    case templateRequired
    case preferredOptional
    case decorative
}

struct LayoutSpec: Codable, Equatable, Sendable {
    var blocks: [TemplateBlockSpec]
}

struct TemplateBlockSpec: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var blockType: TemplateBlockType
    var fieldBinding: String?
    var titleOverride: String?
    var styleVariant: String
    var emptyBehavior: SurfaceEmptyBehavior

    init(
        id: UUID = UUID(),
        blockType: TemplateBlockType,
        fieldBinding: String? = nil,
        titleOverride: String? = nil,
        styleVariant: String = "default",
        emptyBehavior: SurfaceEmptyBehavior = .placeholder
    ) {
        self.id = id
        self.blockType = blockType
        self.fieldBinding = fieldBinding
        self.titleOverride = titleOverride
        self.styleVariant = styleVariant
        self.emptyBehavior = emptyBehavior
    }
}

enum TemplateBlockType: String, Codable, Equatable, Sendable {
    case title
    case summary
    case section
    case keyPoints
    case cueQuestions
    case callouts
    case glossary
    case studyCards
    case reviewQuestions
    case actionItems
    case warningBox
    case exercise
}

struct SurfaceEmptyBehavior: Codable, Equatable, Sendable {
    var authoring: EmptyBlockBehavior
    var preview: EmptyBlockBehavior
    var export: EmptyBlockBehavior

    static let placeholder = Self(authoring: .placeholder, preview: .placeholder, export: .placeholder)
    static let hidden = Self(authoring: .hide, preview: .hide, export: .hide)

    init(
        authoring: EmptyBlockBehavior,
        preview: EmptyBlockBehavior,
        export: EmptyBlockBehavior
    ) {
        self.authoring = authoring
        self.preview = preview
        self.export = export
    }
}

enum EmptyBlockBehavior: String, Codable, CaseIterable, Equatable, Sendable {
    case hide
    case placeholder
    case show
}

enum TemplateBlockStyleVariant: String, Codable, CaseIterable, Equatable, Sendable {
    case standard = "default"
    case summary
    case key
    case warning
    case exam
    case code
    case result
}

struct TemplateBoxStyle: Codable, Equatable, Sendable, Identifiable {
    var id: String { variant.rawValue }
    var variant: TemplateBlockStyleVariant
    var borderHex: String
    var backgroundHex: String
    var titleBackgroundHex: String?
    var titleTextHex: String
    var bodyTextHex: String

    init(
        variant: TemplateBlockStyleVariant,
        borderHex: String,
        backgroundHex: String,
        titleBackgroundHex: String? = nil,
        titleTextHex: String = "#22304A",
        bodyTextHex: String = "#22304A"
    ) {
        self.variant = variant
        self.borderHex = borderHex
        self.backgroundHex = backgroundHex
        self.titleBackgroundHex = titleBackgroundHex
        self.titleTextHex = titleTextHex
        self.bodyTextHex = bodyTextHex
    }
}

struct StyleKit: Codable, Equatable, Sendable {
    var accentHex: String
    var surfaceHex: String
    var borderHex: String
    var secondaryHex: String
    var boxStyles: [TemplateBoxStyle]

    init(
        accentHex: String,
        surfaceHex: String = "#F7F9FC",
        borderHex: String = "#DCE3EF",
        secondaryHex: String = "#5D6B82",
        boxStyles: [TemplateBoxStyle] = []
    ) {
        self.accentHex = accentHex
        self.surfaceHex = surfaceHex
        self.borderHex = borderHex
        self.secondaryHex = secondaryHex
        self.boxStyles = boxStyles
    }

    private enum CodingKeys: String, CodingKey {
        case accentHex
        case surfaceHex
        case borderHex
        case secondaryHex
        case boxStyles
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accentHex = try container.decode(String.self, forKey: .accentHex)
        surfaceHex = try container.decode(String.self, forKey: .surfaceHex)
        borderHex = try container.decode(String.self, forKey: .borderHex)
        secondaryHex = try container.decode(String.self, forKey: .secondaryHex)
        boxStyles = try container.decodeIfPresent([TemplateBoxStyle].self, forKey: .boxStyles) ?? []
    }
}

struct TemplateBehaviorRules: Codable, Equatable, Sendable {
    var placeholderPrefix: String
    var followsVisualTheme: Bool

    init(
        placeholderPrefix: String = "Add",
        followsVisualTheme: Bool = false
    ) {
        self.placeholderPrefix = placeholderPrefix
        self.followsVisualTheme = followsVisualTheme
    }
}

struct ImportedTemplatePreview: Codable, Equatable, Sendable {
    var title: String
    var subtitle: String?
    var blocks: [ImportedTemplatePreviewBlock]

    init(
        title: String,
        subtitle: String? = nil,
        blocks: [ImportedTemplatePreviewBlock]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.blocks = blocks
    }
}

enum ImportedTemplatePreviewBlockKind: String, Codable, Equatable, Sendable {
    case heading
    case paragraph
    case box
    case separator
}

struct ImportedTemplatePreviewBlock: Codable, Equatable, Sendable, Identifiable {
    var id: UUID
    var kind: ImportedTemplatePreviewBlockKind
    var title: String
    var body: String
    var items: [String]
    var styleVariant: String?
    var level: Int

    init(
        id: UUID = UUID(),
        kind: ImportedTemplatePreviewBlockKind,
        title: String = "",
        body: String = "",
        items: [String] = [],
        styleVariant: String? = nil,
        level: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.items = items
        self.styleVariant = styleVariant
        self.level = level
    }
}

enum LegacyTemplatePackAdapter {
    static func makePack(from template: Template) throws -> TemplatePack {
        let archetype = inferArchetype(from: template)
        var pack = TemplatePackDefaults.pack(
            for: archetype,
            named: template.name,
            description: template.subtitle.isEmpty ? template.templateDescription : template.subtitle,
            style: style(from: template)
        )
        pack.identity.id = template.id
        return pack
    }

    private static func inferArchetype(from template: Template) -> TemplateArchetype {
        switch template.configuredGoalType {
        case .actionItems:
            return .meetingBrief
        case .formalDocument:
            return .formalBrief
        case .summary, .structuredNotes:
            return .technicalNote
        }
    }
    private static func style(from template: Template) -> StyleKit {
        let accent = template.config["accent"] ?? "#2E5AAC"
        let surface = template.config["surface"] ?? "#F7F9FC"
        return StyleKit(accentHex: accent, surfaceHex: surface)
    }
}

extension Template {
    static func packBacked(
        _ pack: TemplatePack,
        scope: TemplateScope,
        goalType: GoalType? = nil,
        templateDescription: String? = nil,
        latexSource: String? = nil
    ) -> Template {
        var template = Template(
            kind: .content,
            scope: scope,
            name: pack.identity.name,
            subtitle: pack.identity.description,
            templateDescription: templateDescription ?? (pack.identity.description.isEmpty ? "Pack-backed template" : pack.identity.description),
            format: .markdownTemplate,
            body: "",
            config: ["template_pack": "v1", "goal": (goalType ?? pack.legacyGoalType).rawValue],
            storedPackData: try? JSONEncoder().encode(pack),
            storedLatexSource: latexSource
        )
        if template.storedLatexSource?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            template.storedLatexSource = TemplatePackLatexCodec.emit(template: template, pack: pack)
        }
        return template
    }

    func editableCopy(scope: TemplateScope) -> Template {
        Template(
            kind: kind,
            scope: scope,
            name: name,
            subtitle: subtitle,
            templateDescription: templateDescription,
            format: format,
            body: body,
            config: config,
            storedPackData: storedPackData,
            storedLatexSource: storedLatexSource
        )
    }

    func updatedForAuthoring(
        name: String,
        subtitle: String,
        templateDescription: String,
        body: String,
        config: [String: String]
    ) -> Template {
        Template(
            id: id,
            kind: .content,
            scope: .user,
            name: name,
            subtitle: subtitle,
            templateDescription: templateDescription,
            format: .markdownTemplate,
            body: body,
            config: config,
            storedPackData: storedPackData,
            storedLatexSource: storedLatexSource
        )
    }

    func updatedForLatexAuthoring(
        name: String,
        subtitle: String,
        templateDescription: String,
        latexSource: String,
        pack: TemplatePack,
        goalType: GoalType
    ) -> Template {
        Template(
            id: id,
            kind: .content,
            scope: scope,
            name: name,
            subtitle: subtitle,
            templateDescription: templateDescription,
            format: .markdownTemplate,
            body: "",
            config: ["template_pack": "v1", "goal": goalType.rawValue],
            storedPackData: try? JSONEncoder().encode(pack),
            storedLatexSource: latexSource
        )
    }

    func duplicated(named newName: String, scope: TemplateScope = .user) -> Template {
        Template(
            kind: kind,
            scope: scope,
            name: newName,
            subtitle: subtitle,
            templateDescription: templateDescription,
            format: format,
            body: body,
            config: config,
            storedPackData: storedPackData,
            storedLatexSource: storedLatexSource
        )
    }

    func withTemplatePack(_ pack: TemplatePack) -> Template {
        var copy = self
        copy.storedPackData = try? JSONEncoder().encode(pack)
        copy.config["template_pack"] = "v1"
        copy.config["goal"] = pack.legacyGoalType.rawValue
        if copy.subtitle.isEmpty {
            copy.subtitle = pack.identity.description
        }
        if copy.storedLatexSource?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            copy.storedLatexSource = TemplatePackLatexCodec.emit(template: copy, pack: pack)
        }
        return copy
    }

    func templatePack() throws -> TemplatePack {
        if let storedPackData {
            guard let pack = try? JSONDecoder().decode(TemplatePack.self, from: storedPackData) else {
                throw TemplatePackError.invalidStoredPack
            }
            return pack
        }
        return try LegacyTemplatePackAdapter.makePack(from: self)
    }

    var isPackBacked: Bool {
        storedPackData != nil || config["template_pack"] == "v1"
    }

    var latexAuthoringSource: String? {
        if let storedLatexSource, storedLatexSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return storedLatexSource
        }
        guard isPackBacked, let pack = try? templatePack() else { return nil }
        return TemplatePackLatexCodec.emit(template: self, pack: pack)
    }
}

private extension TemplatePack {
    var legacyGoalType: GoalType {
        switch archetype {
        case .meetingBrief:
            return .actionItems
        case .formalBrief:
            return .formalDocument
        case .technicalNote:
            return .structuredNotes
        }
    }
}
