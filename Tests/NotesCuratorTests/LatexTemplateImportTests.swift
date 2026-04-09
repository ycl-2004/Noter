import Testing
@testable import NotesCurator

struct LatexTemplateImportTests {
    @Test
    func technicalLatexImportBuildsTechnicalNoteDraft() throws {
        let result = try LatexTemplateImporter.importTemplate(from: SampleLatexSources.technicalNote)

        #expect(result.inferredArchetype == .technicalNote)
        #expect(result.templatePack.schema.fields.map(\.key).contains("warning_boxes"))
        #expect(result.templatePack.layout.blocks.map(\.fieldBinding).contains("sections"))
    }

    @Test
    func extractorFindsPaletteAndBoxDefinitionsFromSupportedLatex() throws {
        let source = SampleLatexSources.technicalNote
        let fingerprint = try LatexTemplateImporter.extractFingerprint(from: source)

        #expect(fingerprint.palette.accentHex == "#2E5AAC")
        #expect(fingerprint.boxStyles.map(\.name).contains("WarningBox"))
    }

    @Test
    func extractorReadsHeadingHierarchyAndRhythm() throws {
        let fingerprint = try LatexTemplateImporter.extractFingerprint(from: SampleLatexSources.technicalNote)

        #expect(fingerprint.headingSystem == .academicStructured)
        #expect(fingerprint.recurringSections.contains("Q&A"))
    }

    @Test
    func importedTemplateRetainsPreviewLayoutAndSpecializedBoxStyles() throws {
        let result = try LatexTemplateImporter.importTemplate(from: SampleLatexSources.technicalNote)
        let preview = try #require(result.templatePack.importedPreview)

        #expect(preview.title.contains("Graph"))
        #expect(preview.blocks.contains(where: { $0.kind == .box && $0.styleVariant == TemplateBlockStyleVariant.code.rawValue }))
        #expect(preview.blocks.contains(where: { $0.kind == .box && $0.styleVariant == TemplateBlockStyleVariant.warning.rawValue }))
        #expect(result.templatePack.style.boxStyles.contains(where: { $0.variant == .summary }))
        #expect(result.templatePack.style.boxStyles.contains(where: { $0.variant == .code }))
    }

    @Test
    func importedTemplateHidesEmptySectionsAcrossAllSurfacesByDefault() throws {
        let result = try LatexTemplateImporter.importTemplate(from: SampleLatexSources.technicalNote)

        for block in result.templatePack.layout.blocks {
            #expect(block.emptyBehavior.authoring == .hide)
            #expect(block.emptyBehavior.preview == .hide)
            #expect(block.emptyBehavior.export == .hide)
        }
    }

    @Test
    func importedTemplateCreatesBoxAwareSectionsFromDefinedLatexBoxes() throws {
        let result = try LatexTemplateImporter.importTemplate(from: SampleLatexSources.boxHeavyTemplate)
        let bindings = result.templatePack.layout.blocks.compactMap(\.fieldBinding)

        #expect(bindings == [
            "summary_boxes",
            "key_boxes",
            "warning_boxes",
            "exam_boxes",
            "code_boxes",
            "result_boxes",
            "sections",
        ])
    }
}

enum SampleLatexSources {
    static let technicalNote = #"""
    \documentclass{article}
    \usepackage[margin=1in]{geometry}
    \usepackage{titlesec}
    \usepackage[most]{tcolorbox}

    \definecolor{AccentBlue}{HTML}{2E5AAC}
    \definecolor{SurfaceGray}{HTML}{F7F9FC}
    \definecolor{BoxBorder}{HTML}{D6DEEE}

    \titleformat{\section}{\Large\bfseries\color{AccentBlue}}{\thesection}{1em}{}
    \titleformat{\subsection}{\large\bfseries\color{AccentBlue}}{\thesubsection}{1em}{}

    \tcbset{colframe=BoxBorder,colback=SurfaceGray}
    \newtcolorbox{SummaryBox}{colframe=AccentBlue!35,colback=SurfaceGray,title=Summary}
    \newtcolorbox{WarningBox}{colframe=AccentBlue,colback=SurfaceGray,title=Warning}
    \newtcolorbox{CodeBox}{colframe=black!15,colback=black!2,title=Code}

    \begin{document}
    {\Huge\bfseries\color{AccentBlue} The Graph 实战笔记：给抽奖合约做数据索引}\\[-2pt]
    {\large Indexing on-chain events \& Query with GraphQL}\\[8pt]
    \hrule height 0.9pt

    \section{Overview}
    \begin{SummaryBox}{一句话总结}
    我们把链上事件整理成可查询的数据。
    \end{SummaryBox}
    \section{Q&A}
    \subsection{Key Concepts}
    \begin{CodeBox}{ASCII}
    \code{
    events -> mapping -> entities
    }
    \end{CodeBox}
    \begin{WarningBox}{最重要的事实}
    schema.graphql 与 mapping 都要自己写。
    \end{WarningBox}
    \end{document}
    """#

    static let boxHeavyTemplate = #"""
    \documentclass[11pt]{article}
    \usepackage[UTF8]{ctex}
    \usepackage[a4paper,margin=1in]{geometry}
    \usepackage{xcolor}
    \usepackage{tcolorbox}

    \definecolor{Accent}{HTML}{2E5AAC}
    \definecolor{Soft}{HTML}{F5F7FB}
    \definecolor{BoxBorder}{HTML}{D6DEEE}

    \tcbset{
      enhanced,
      sharp corners,
      boxrule=0.7pt,
      colback=Soft,
      colframe=BoxBorder,
    }

    \newtcolorbox{SummaryBox}[1]{colback=Soft,colframe=Accent!35,title=\textbf{#1}}
    \newtcolorbox{KeyBox}[1]{colback=Accent!6,colframe=Accent!55,title=\textbf{#1}}
    \newtcolorbox{WarningBox}[1]{colback=red!5,colframe=red!60,title=\textbf{#1}}
    \newtcolorbox{ExamBox}[1]{colback=white,colframe=Accent!55,title=\textbf{#1}}
    \newtcolorbox{CodeBox}[1]{colback=black!2,colframe=black!15,title=\textbf{#1}}
    \newtcolorbox{ResultBox}[1]{colback=white,colframe=green!50!black,title=\textbf{#1}}

    \begin{document}
    {\Huge\bfseries\color{Accent} The Graph 实战笔记：给抽奖合约做数据索引}\\[-2pt]
    \section{Overview}
    \begin{SummaryBox}{一句话总结}
    测试内容
    \end{SummaryBox}
    \end{document}
    """#
}
