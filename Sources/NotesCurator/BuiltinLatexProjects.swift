import Foundation

enum BuiltinLatexProjects {
    static func systemTemplate(
        name: String,
        subtitle: String,
        templateDescription: String,
        goalType: GoalType,
        pack: TemplatePack,
        customProjectSource: LatexProjectSource? = nil
    ) -> Template {
        Template.latexProject(
            customProjectSource ?? genericProjectSource(
                name: name,
                subtitle: subtitle,
                templateDescription: templateDescription,
                pack: pack
            ),
            scope: .system,
            name: name,
            subtitle: subtitle,
            templateDescription: templateDescription,
            goalType: goalType,
            pack: pack
        )
    }

    static let formalDocumentProjectSource = LatexProjectSource(
        mainFilePath: "main.tex",
        compiler: .xelatex,
        files: [
            .text(path: "main.tex", contents: formalDocumentMainFile)
        ],
        slotBindings: [
            LatexProjectSlotBinding(token: "{{notescurator.title}}", field: .title),
            LatexProjectSlotBinding(token: "{{notescurator.meta_boxes}}", field: .metaBoxes),
            LatexProjectSlotBinding(token: "{{notescurator.summary_boxes}}", field: .summaryBoxes),
            LatexProjectSlotBinding(token: "{{notescurator.key_boxes}}", field: .keyBoxes),
            LatexProjectSlotBinding(token: "{{notescurator.sections}}", field: .sectionBlocks),
            LatexProjectSlotBinding(token: "{{notescurator.explanation_boxes}}", field: .explanationBoxes),
            LatexProjectSlotBinding(token: "{{notescurator.warning_boxes}}", field: .warningBoxes),
            LatexProjectSlotBinding(token: "{{notescurator.code_boxes}}", field: .codeBoxes),
            LatexProjectSlotBinding(token: "{{notescurator.question_boxes}}", field: .questionBoxes),
            LatexProjectSlotBinding(token: "{{notescurator.result_boxes}}", field: .resultBoxes)
        ]
    )

    static func genericProjectSource(
        name: String,
        subtitle: String,
        templateDescription: String,
        pack: TemplatePack
    ) -> LatexProjectSource {
        var bindings = [LatexProjectSlotBinding(token: "{{notescurator.title}}", field: .title)]
        var lines = latexPreamble(
            name: name,
            subtitle: subtitle,
            templateDescription: templateDescription,
            pack: pack
        )

        for block in pack.layout.blocks {
            let snippet = latexSnippet(for: block, bindings: &bindings)
            guard snippet.isEmpty == false else { continue }
            lines.append("")
            lines.append(contentsOf: snippet)
        }

        lines.append("")
        lines.append("\\end{document}")

        return LatexProjectSource(
            mainFilePath: "main.tex",
            compiler: .xelatex,
            files: [
                .text(path: "main.tex", contents: lines.joined(separator: "\n"))
            ],
            slotBindings: deduplicated(bindings)
        )
    }

    private static func latexPreamble(
        name: String,
        subtitle: String,
        templateDescription: String,
        pack: TemplatePack
    ) -> [String] {
        var lines: [String] = [
            "\\documentclass[11pt]{article}",
            "\\usepackage[UTF8]{ctex}",
            "\\usepackage[a4paper,margin=1in]{geometry}",
            "\\usepackage{parskip}",
            "\\usepackage{enumitem}",
            "\\usepackage{xcolor}",
            "\\usepackage[most]{tcolorbox}",
            "\\usepackage{hyperref}",
            "\\usepackage{microtype}",
            "\\usepackage{titlesec}",
            "\\usepackage{amsmath}",
            "\\usepackage{amssymb}",
            "",
            "\\hypersetup{",
            "  colorlinks=true,",
            "  linkcolor=Accent!70!black,",
            "  urlcolor=Accent!70!black",
            "}",
            "",
            "\\definecolor{Accent}{HTML}{\(latexHex(pack.style.accentHex))}",
            "\\definecolor{Soft}{HTML}{\(latexHex(pack.style.surfaceHex))}",
            "\\definecolor{BoxBorder}{HTML}{\(latexHex(pack.style.borderHex))}",
            "\\definecolor{Secondary}{HTML}{\(latexHex(pack.style.secondaryHex))}",
            ""
        ]

        for variant in TemplateBlockStyleVariant.allCases {
            let style = boxStyle(for: variant, pack: pack)
            let prefix = colorPrefix(for: variant)
            lines.append("\\definecolor{\(prefix)Frame}{HTML}{\(latexHex(style.borderHex))}")
            lines.append("\\definecolor{\(prefix)Background}{HTML}{\(latexHex(style.backgroundHex))}")
            lines.append("\\definecolor{\(prefix)Title}{HTML}{\(latexHex(style.titleBackgroundHex ?? style.borderHex))}")
            lines.append("\\definecolor{\(prefix)TitleText}{HTML}{\(latexHex(style.titleTextHex))}")
        }

        lines.append("")
        lines.append("\\tcbset{")
        lines.append("  enhanced,")
        lines.append("  sharp corners,")
        lines.append("  boxrule=0.7pt,")
        lines.append("  left=10pt,right=10pt,top=8pt,bottom=8pt,")
        lines.append("}")
        lines.append("")
        lines.append(newTColorBoxLine(environment: "SummaryBox", variant: .summary))
        lines.append(newTColorBoxLine(environment: "KeyBox", variant: .key))
        lines.append(newTColorBoxLine(environment: "WarningBox", variant: .warning))
        lines.append(newTColorBoxLine(environment: "ExamBox", variant: .exam))
        lines.append(newTColorBoxLine(environment: "CodeBox", variant: .code))
        lines.append(newTColorBoxLine(environment: "ResultBox", variant: .result))
        lines.append(newTColorBoxLine(environment: "StandardBox", variant: .standard))
        lines.append("")
        lines.append("\\newcommand{\\code}[1]{\\texttt{#1}}")
        lines.append("\\titleformat{\\section}{\\Large\\bfseries\\color{Accent}}{}{0pt}{}")
        lines.append("\\titleformat{\\subsection}{\\bfseries\\color{Accent!90!black}}{}{0pt}{}")
        lines.append("\\titleformat{\\subsubsection}{\\bfseries\\color{Accent!80!black}}{}{0pt}{}")
        lines.append("\\setlist[itemize]{itemsep=3pt,topsep=4pt,leftmargin=18pt}")
        lines.append("")
        lines.append("\\begin{document}")
        lines.append("{\\Huge\\bfseries\\color{Accent} {{notescurator.title}}}\\\\[-2pt]")
        if subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append("{\\large\\color{Secondary} \(latexEscaped(subtitle))}\\\\[8pt]")
        } else {
            lines.append("\\vspace{8pt}")
        }
        if templateDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            lines.append("% \(latexEscaped(templateDescription))")
        }
        lines.append("\\hrule height 0.9pt")
        lines.append("\\vspace{10pt}")

        return lines
    }

    private static func latexSnippet(
        for block: TemplateBlockSpec,
        bindings: inout [LatexProjectSlotBinding]
    ) -> [String] {
        let binding = block.fieldBinding?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? defaultFieldBinding(for: block.blockType)
        guard let mapped = slotField(for: binding) else { return [] }

        let token = "{{notescurator.\(binding)}}"
        bindings.append(LatexProjectSlotBinding(token: token, field: mapped))

        let title = block.titleOverride?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? defaultTitle(for: block.blockType)
        let variant = resolvedVariant(for: block)
        let isBoxBinding = binding.hasSuffix("_boxes")

        if block.blockType == .section {
            let lines = [
                "\\section{\(latexEscaped(title))}",
                token
            ]
            return wrappedIfOptional(lines, field: mapped, isOptional: block.emptyBehavior.export == .hide)
        }

        if let variant, variant != .standard || isBoxBinding {
            let environment = boxEnvironmentName(for: variant)
            let lines = [
                "\\begin{\(environment)}{\(latexEscaped(title))}",
                token,
                "\\end{\(environment)}"
            ]
            return wrappedIfOptional(lines, field: mapped, isOptional: block.emptyBehavior.export == .hide)
        }

        switch block.blockType {
        case .summary:
            let lines = [
                "\\section{\(latexEscaped(title))}",
                token
            ]
            return wrappedIfOptional(lines, field: mapped, isOptional: block.emptyBehavior.export == .hide)
        case .callouts, .warningBox:
            let lines = [
                "\\subsection*{\(latexEscaped(title))}",
                token
            ]
            return wrappedIfOptional(lines, field: mapped, isOptional: block.emptyBehavior.export == .hide)
        default:
            let lines = [
                "\\section*{\(latexEscaped(title))}",
                token
            ]
            return wrappedIfOptional(lines, field: mapped, isOptional: block.emptyBehavior.export == .hide)
        }
    }

    private static func wrappedIfOptional(
        _ lines: [String],
        field: LatexProjectSlotField,
        isOptional: Bool
    ) -> [String] {
        guard isOptional else { return lines }
        return ["% notescurator.optional.begin:\(field.rawValue)"] + lines + ["% notescurator.optional.end:\(field.rawValue)"]
    }

    private static func deduplicated(_ bindings: [LatexProjectSlotBinding]) -> [LatexProjectSlotBinding] {
        var seen: Set<String> = []
        var ordered: [LatexProjectSlotBinding] = []

        for binding in bindings {
            let key = "\(binding.field.rawValue)|\(binding.token)"
            if seen.insert(key).inserted {
                ordered.append(binding)
            }
        }

        return ordered
    }

    private static func slotField(for binding: String) -> LatexProjectSlotField? {
        switch binding {
        case "title":
            return .title
        case "overview", "summary":
            return .summary
        case "key_points":
            return .keyPoints
        case "sections", "context", "recommendation", "decisions":
            return .sections
        case "action_items":
            return .actionItems
        case "review_questions":
            return .reviewQuestions
        case "glossary":
            return .glossary
        case "study_cards":
            return .studyCards
        case "cue_questions":
            return .cueQuestions
        case "callouts":
            return .callouts
        case "warnings":
            return .warnings
        case "summary_boxes":
            return .summaryBoxes
        case "key_boxes":
            return .keyBoxes
        case "meta_boxes":
            return .metaBoxes
        case "warning_boxes":
            return .warningBoxes
        case "code_boxes":
            return .codeBoxes
        case "result_boxes":
            return .resultBoxes
        case "exam_boxes":
            return .examBoxes
        case "checklist_boxes":
            return .checklistBoxes
        case "question_boxes":
            return .questionBoxes
        case "explanation_boxes":
            return .explanationBoxes
        case "example_boxes":
            return .exampleBoxes
        default:
            return nil
        }
    }

    private static func defaultFieldBinding(for blockType: TemplateBlockType) -> String {
        switch blockType {
        case .title:
            return "title"
        case .summary:
            return "overview"
        case .section:
            return "sections"
        case .keyPoints:
            return "key_points"
        case .cueQuestions:
            return "cue_questions"
        case .callouts:
            return "callouts"
        case .glossary:
            return "glossary"
        case .studyCards:
            return "study_cards"
        case .reviewQuestions, .exercise:
            return "review_questions"
        case .actionItems:
            return "action_items"
        case .warningBox:
            return "warnings"
        }
    }

    private static func defaultTitle(for blockType: TemplateBlockType) -> String {
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

    private static func resolvedVariant(for block: TemplateBlockSpec) -> TemplateBlockStyleVariant? {
        if let parsed = TemplateBlockStyleVariant(rawValue: block.styleVariant) {
            return parsed
        }
        if let binding = block.fieldBinding, binding.hasSuffix("_boxes") {
            switch binding {
            case "summary_boxes", "explanation_boxes":
                return .summary
            case "key_boxes":
                return .key
            case "meta_boxes":
                return .standard
            case "warning_boxes":
                return .warning
            case "exam_boxes", "question_boxes":
                return .exam
            case "checklist_boxes", "result_boxes":
                return .result
            case "code_boxes":
                return .code
            case "example_boxes":
                return .standard
            default:
                return .summary
            }
        }
        return nil
    }

    private static func boxStyle(for variant: TemplateBlockStyleVariant, pack: TemplatePack) -> TemplateBoxStyle {
        if let explicit = pack.style.boxStyles.first(where: { $0.variant == variant }) {
            return explicit
        }

        switch variant {
        case .summary:
            return TemplateBoxStyle(
                variant: .summary,
                borderHex: pack.style.accentHex,
                backgroundHex: pack.style.surfaceHex,
                titleBackgroundHex: pack.style.surfaceHex,
                titleTextHex: pack.style.accentHex,
                bodyTextHex: "#22304A"
            )
        case .key:
            return TemplateBoxStyle(
                variant: .key,
                borderHex: pack.style.accentHex,
                backgroundHex: pack.style.surfaceHex,
                titleBackgroundHex: pack.style.accentHex,
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#22304A"
            )
        case .warning:
            return TemplateBoxStyle(
                variant: .warning,
                borderHex: "#C95A4A",
                backgroundHex: "#FFF7F4",
                titleBackgroundHex: "#C95A4A",
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#5A2A21"
            )
        case .exam:
            return TemplateBoxStyle(
                variant: .exam,
                borderHex: "#6D5BD0",
                backgroundHex: "#F7F5FF",
                titleBackgroundHex: "#6D5BD0",
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#2C225A"
            )
        case .code:
            return TemplateBoxStyle(
                variant: .code,
                borderHex: "#202733",
                backgroundHex: "#F4F6FA",
                titleBackgroundHex: "#202733",
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#202733"
            )
        case .result:
            return TemplateBoxStyle(
                variant: .result,
                borderHex: "#2F6A57",
                backgroundHex: "#F4FBF8",
                titleBackgroundHex: "#2F6A57",
                titleTextHex: "#FFFFFF",
                bodyTextHex: "#1F4034"
            )
        case .standard:
            return TemplateBoxStyle(
                variant: .standard,
                borderHex: pack.style.borderHex,
                backgroundHex: pack.style.surfaceHex,
                titleBackgroundHex: pack.style.surfaceHex,
                titleTextHex: pack.style.accentHex,
                bodyTextHex: "#22304A"
            )
        }
    }

    private static func newTColorBoxLine(environment: String, variant: TemplateBlockStyleVariant) -> String {
        let prefix = colorPrefix(for: variant)
        return "\\newtcolorbox{\(environment)}[1]{colback=\(prefix)Background,colframe=\(prefix)Frame,coltitle=\(prefix)TitleText,fonttitle=\\bfseries,colbacktitle=\(prefix)Title,title={#1}}"
    }

    private static func colorPrefix(for variant: TemplateBlockStyleVariant) -> String {
        switch variant {
        case .summary:
            return "SummaryBox"
        case .key:
            return "KeyBox"
        case .warning:
            return "WarningBox"
        case .exam:
            return "ExamBox"
        case .code:
            return "CodeBox"
        case .result:
            return "ResultBox"
        case .standard:
            return "StandardBox"
        }
    }

    private static func boxEnvironmentName(for variant: TemplateBlockStyleVariant) -> String {
        switch variant {
        case .summary:
            return "SummaryBox"
        case .key:
            return "KeyBox"
        case .warning:
            return "WarningBox"
        case .exam:
            return "ExamBox"
        case .code:
            return "CodeBox"
        case .result:
            return "ResultBox"
        case .standard:
            return "StandardBox"
        }
    }

    private static func latexHex(_ hex: String) -> String {
        hex.replacingOccurrences(of: "#", with: "").uppercased()
    }

    private static func latexEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\textbackslash{}")
            .replacingOccurrences(of: "{", with: "\\{")
            .replacingOccurrences(of: "}", with: "\\}")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "&", with: "\\&")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "~", with: "\\textasciitilde{}")
            .replacingOccurrences(of: "^", with: "\\textasciicircum{}")
    }

    private static let formalDocumentMainFile = """
    \\documentclass[11pt]{article}
    \\usepackage[UTF8]{ctex}
    \\usepackage[a4paper,margin=1in]{geometry}
    \\usepackage{parskip}
    \\usepackage{enumitem}
    \\usepackage{xcolor}
    \\usepackage[most]{tcolorbox}
    \\usepackage{hyperref}
    \\usepackage{microtype}
    \\usepackage{titlesec}
    \\usepackage{amsmath}
    \\usepackage{amssymb}

    \\hypersetup{
      colorlinks=true,
      linkcolor=Accent!70!black,
      urlcolor=Accent!70!black
    }

    \\definecolor{Accent}{HTML}{2E5AAC}
    \\definecolor{Soft}{HTML}{F5F7FB}
    \\definecolor{BoxBorder}{HTML}{D6DEEE}
    \\definecolor{Secondary}{HTML}{5B6573}

    \\tcbset{
      enhanced,
      sharp corners,
      boxrule=0.7pt,
      colback=Soft,
      colframe=BoxBorder,
      left=10pt,right=10pt,top=8pt,bottom=8pt,
    }

    \\newtcolorbox{SummaryBox}[1]{
      colback=Soft,
      colframe=Accent!35,
      title=\\textbf{#1},
    }

    \\newtcolorbox{KeyBox}[1]{
      colback=Accent!6,
      colframe=Accent!55,
      title=\\textbf{#1},
    }

    \\newtcolorbox{WarningBox}[1]{
      colback=red!5,
      colframe=red!60,
      title=\\textbf{#1},
    }

    \\newtcolorbox{ExamBox}[1]{
      colback=white,
      colframe=Accent!55,
      title=\\textbf{#1},
    }

    \\newtcolorbox{CodeBox}[1]{
      colback=black!2,
      colframe=black!15,
      title=\\textbf{#1},
    }

    \\newtcolorbox{ResultBox}[1]{
      colback=white,
      colframe=green!50!black,
      title=\\textbf{#1},
    }

    \\newtcolorbox{StandardBox}[1]{
      colback=Soft,
      colframe=BoxBorder,
      title=\\textbf{#1},
    }

    \\newcommand{\\code}[1]{\\texttt{#1}}

    \\titleformat{\\section}{\\Large\\bfseries\\color{Accent}}{}{0pt}{}
    \\titleformat{\\subsection}{\\bfseries\\color{Accent!90!black}}{}{0pt}{}
    \\titleformat{\\subsubsection}{\\bfseries\\color{Accent!80!black}}{}{0pt}{}

    \\setlist[itemize]{itemsep=3pt,topsep=4pt,leftmargin=18pt}

    \\begin{document}

    {\\Huge\\bfseries\\color{Accent} {{notescurator.title}}}\\\\[-2pt]
    {\\large\\color{Secondary} Polished stakeholder-ready document}\\\\[8pt]
    \\hrule height 0.9pt
    \\vspace{10pt}

    % notescurator.optional.begin:metaBoxes
    \\begin{StandardBox}{Document Metadata}
    {{notescurator.meta_boxes}}
    \\end{StandardBox}
    % notescurator.optional.end:metaBoxes

    \\begin{SummaryBox}{Executive Summary}
    {{notescurator.summary_boxes}}
    \\end{SummaryBox}

    % notescurator.optional.begin:keyBoxes
    \\begin{KeyBox}{Key Insight}
    {{notescurator.key_boxes}}
    \\end{KeyBox}
    % notescurator.optional.end:keyBoxes

    % notescurator.optional.begin:explanationBoxes
    \\begin{SummaryBox}{Scope / Context}
    {{notescurator.explanation_boxes}}
    \\end{SummaryBox}
    % notescurator.optional.end:explanationBoxes

    \\tableofcontents
    \\vspace{10pt}

    \\section*{Main Sections}
    {{notescurator.sections}}

    % notescurator.optional.begin:warningBoxes
    \\begin{WarningBox}{Risks and Warnings}
    {{notescurator.warning_boxes}}
    \\end{WarningBox}
    % notescurator.optional.end:warningBoxes

    % notescurator.optional.begin:codeBoxes
    \\begin{CodeBox}{Reference Snippets}
    {{notescurator.code_boxes}}
    \\end{CodeBox}
    % notescurator.optional.end:codeBoxes

    % notescurator.optional.begin:questionBoxes
    \\begin{ExamBox}{Questions for Review}
    {{notescurator.question_boxes}}
    \\end{ExamBox}
    % notescurator.optional.end:questionBoxes

    % notescurator.optional.begin:resultBoxes
    \\begin{ResultBox}{Recommendations and Next Steps}
    {{notescurator.result_boxes}}
    \\end{ResultBox}
    % notescurator.optional.end:resultBoxes

    \\end{document}
    """
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
