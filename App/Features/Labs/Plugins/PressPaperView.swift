import BoarAnswer
import BoarCore
import CoreText
import ImageIO
import SwiftUI

/// Where each unit of the paper sits (the title, each block, the Sources section, the footer), in the paper's own
/// coordinates: the page-break lines are drawn from it, and the screen keeps a moved block in view with it. A class, so
/// only the lines redraw when a block moves.
@MainActor
@Observable
final class PaperFrames {
    var rects: [String: CGRect] = [:]
}

/// The paper (android printer `PressScreen.kt` `PaperView`): white A4 at the width of the screen, Press's type at
/// `PressPaper`'s points times the paper's scale (the system text size doesn't change it), the blocks in the PDF's own
/// plan (PressLayout), the Sources section and the footer. Tapping a block selects it; the selected block, when open, is
/// typed on the page. The dashed lines are where the PDF's pages start (PressPDF.pageStarts).
struct PressPaperView: View {
    let page: PressPage
    let dir: URL
    let starts: [PressPDF.PageStart]
    @Binding var edit: PressEdit
    let focusTitle: Int
    let frames: PaperFrames
    @State private var width: CGFloat = 0

    var body: some View {
        let s = PaperScale(width > 0 ? width / PressPaper.w : 0.6)
        let project = page.project
        VStack(alignment: .leading, spacing: 0) {
            PaperTitle(project: project, s: s, focusTitle: focusTitle) { edit.close() }
                .id(project.id)
                .unit([PressPDF.titleUnit], frames)
            if page.options.date {
                Text(verbatim: page.date.uppercased())
                    .paper(s.date)
                    .padding(.top, s.pt(4))
                    .padding(.bottom, s.pt(PressPaper.gap + 4))
            } else {
                Spacer().frame(height: s.pt(PressPaper.gap))
            }
            if project.blocks.isEmpty {
                Text(verbatim: String(localized: "Nothing here yet.") + "\n" + String(localized: "Add answers from a chat: under an answer, open More (…) and tap Add to Press. Or add a heading, a note or a photo."))
                    .paper(s.note)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, s.pt(60))
            }
            // The same plan as the PDF: a side picture with the next text block beside it (PressLayout).
            ForEach(PressLayout.plan(project.blocks), id: \.key) { item in
                switch item {
                case .single(let b):
                    PaperBlock(block: b, page: page, dir: dir, s: s, edit: $edit)
                        .unit([b.id], frames)
                case .beside(let pic, let text, let left):
                    PaperBeside(picture: pic, text: text, left: left, page: page, dir: dir, s: s, edit: $edit)
                        .unit([pic.id] + (text.map { [$0.id] } ?? []), frames)
                }
                Spacer().frame(height: s.pt(PressPaper.gap))
            }
            // The Sources section at the end (adam, Nov 14), as the PDF prints it.
            if !page.sourceLines.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: page.sourcesLabel).paper(s.sourcesTitle).padding(.bottom, s.pt(6))
                    ForEach(Array(page.sourceLines.enumerated()), id: \.offset) { _, l in
                        Text(verbatim: l).paper(s.sourceLine).padding(.bottom, s.pt(3))
                    }
                }
                .padding(.top, s.pt(PressPaper.gap))
                .unit([PressPDF.sourcesUnit], frames)
            }
            PaperFooter(page: page, s: s)
                .unit([PressPDF.receiptUnit], frames)
        }
        .padding(s.pt(PressPaper.m))
        .frame(maxWidth: .infinity, alignment: .leading)
        // The shadow on the sheet's shape only: on the whole view every letter would get one.
        .background {
            RoundedRectangle(cornerRadius: 2).fill(Color.white).shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .overlay { PaperBreaks(starts: starts, frames: frames, s: s) }
        .coordinateSpace(.named(PaperScale.space))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .environment(\.colorScheme, .light)
    }
}

extension PressLayout.Item {
    /// The item's identity on the paper: its first block's id.
    var key: String {
        switch self {
        case .single(let b): b.id
        case .beside(let p, _, _): p.id
        }
    }
}

extension View {
    /// Records this view's frame on the paper under each of `ids`.
    fileprivate func unit(_ ids: [String], _ frames: PaperFrames) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(PaperScale.space)) } action: { r in
            for id in ids where frames.rects[id] != r { frames.rects[id] = r }
        }
    }

    fileprivate func paper(_ st: PaperStyle) -> some View {
        font(st.font).foregroundStyle(st.color).lineSpacing(st.lineSpacing).tracking(st.tracking)
    }

    /// A block's selection on the paper (android `selectable`): the accent around it on a warm white, a tap selects it.
    fileprivate func selectable(_ selected: Bool, _ onSelect: @escaping () -> Void) -> some View {
        background {
            if selected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(PaperStyle.rgb(0xFFFAF0))
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(.boar(.accent), lineWidth: 1.5) }
                    .padding(-6)
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - type

/// One text style on the paper: its font, colour and the space between its lines.
struct PaperStyle {
    var font: Font
    var color: Color
    var lineSpacing: CGFloat = 0
    var tracking: CGFloat = 0

    static func rgb(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// The paper's type at its scale (android `PaperScale`): `PressPaper`'s points times the paper's points per PDF point, as
/// fixed sizes; Georgia for Android's serif, the system's sans for its sans, as the PDF prints them. Each style's line
/// height is Android's, over its font size.
struct PaperScale {
    static let space = "press-paper"
    let k: CGFloat

    init(_ k: CGFloat) { self.k = k }

    func pt(_ v: Double) -> CGFloat { CGFloat(v) * k }

    private func style(_ size: Double, serif: Bool = true, bold: Bool = false, italic: Bool = false, color: UInt32 = PressPaper.ink,
                       line: Double = 1.25) -> PaperStyle {
        let px = pt(size)
        let font: Font
        let natural: CGFloat
        if serif {
            let name = bold ? (italic ? "Georgia-BoldItalic" : "Georgia-Bold") : (italic ? "Georgia-Italic" : "Georgia")
            font = .custom(name, fixedSize: px)
            let ct = CTFontCreateWithName(name as CFString, px, nil)
            natural = CTFontGetAscent(ct) + CTFontGetDescent(ct) + CTFontGetLeading(ct)
        } else {
            font = .system(size: px, weight: bold ? .bold : .regular)
            natural = px * 1.2
        }
        return PaperStyle(font: font, color: PaperStyle.rgb(color), lineSpacing: max(px * CGFloat(line) - natural, 0))
    }

    var title: PaperStyle { style(PressPaper.title, bold: true, line: 1.2) }
    var date: PaperStyle { var d = style(PressPaper.date, serif: false, color: PressPaper.dateInk); d.tracking = pt(PressPaper.date) * 0.04; return d }
    var heading: PaperStyle { style(PressPaper.heading, bold: true) }
    var question: PaperStyle { style(PressPaper.question, italic: true, color: PressPaper.muted) }
    var body: PaperStyle { style(PressPaper.body, line: PressPaper.line) }
    var refs: PaperStyle { style(PressPaper.refs, serif: false, color: PressPaper.meta) }
    var note: PaperStyle { style(PressPaper.note, italic: true, color: PressPaper.muted, line: PressPaper.line) }
    var caption: PaperStyle { style(PressPaper.caption, italic: true, color: PressPaper.muted) }
    var footer: PaperStyle { style(PressPaper.footer, serif: false, color: PressPaper.footInk, line: 1.3) }
    var sourcesTitle: PaperStyle { style(PressPaper.receiptTitle, serif: false, bold: true) }
    var sourceLine: PaperStyle { style(PressPaper.refs, serif: false, color: PressPaper.receiptInk) }
    var card: PaperStyle { style(PressPaper.card, serif: false, line: 1.15) }
    var cardMuted: PaperStyle { style(PressPaper.card, serif: false, color: PressPaper.muted, line: 1.15) }
    var cardTitle: PaperStyle { style(PressPaper.cardTitle, serif: false, bold: true, line: 1.15) }
    var cardHeader: PaperStyle { style(PressPaper.refs, serif: false, bold: true, color: PressPaper.meta) }

    func of(_ p: PressPDF.Piece.Style) -> PaperStyle {
        switch p {
        case .heading: heading
        case .question: question
        case .body: body
        case .refs: refs
        case .note: note
        }
    }

    /// A paragraph's or list's hint while it is empty, and a field's placeholder (the placeholder's grey).
    static let hint: UInt32 = 0xA2A6B4
}

// MARK: - the title

/// The title is the project's name: typed on the page, saved a moment after typing stops; empty keeps the old name.
private struct PaperTitle: View {
    let project: PressDoc.Project
    let s: PaperScale
    let focusTitle: Int
    let onFocus: () -> Void
    @State private var draft: String
    @FocusState private var focused: Bool

    init(project: PressDoc.Project, s: PaperScale, focusTitle: Int, onFocus: @escaping () -> Void) {
        self.project = project; self.s = s; self.focusTitle = focusTitle; self.onFocus = onFocus
        _draft = State(initialValue: project.name)
    }

    var body: some View {
        TextField(String(), text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .paper(s.title)
            .focused($focused)
            .accessibilityLabel(Text("Document title"))
            .onChange(of: draft) { _, d in if d.contains("\n") { draft = d.replacingOccurrences(of: "\n", with: " ") } }
            .task(id: draft) {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled else { return }
                let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty && t != project.name { PressStore.shared.change { $0.rename(project.id, draft) } }
            }
            .onChange(of: focused) { _, f in
                if f { onFocus() } else if draft.allSatisfy(\.isWhitespace) { draft = project.name }
            }
            .onChange(of: focusTitle) { _, _ in focused = true }
    }
}

// MARK: - blocks

/// One block on the paper (android `BlockView`), typed on the page while open.
private struct PaperBlock: View {
    let block: PressDoc.Block
    let page: PressPage
    let dir: URL
    let s: PaperScale
    @Binding var edit: PressEdit

    private var editing: Bool { edit.editing == block.id }
    private var fresh: Bool { edit.fresh == block.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .selectable(edit.selected == block.id) { edit.select(block.id) }
    }

    private func save(_ field: PressDoc.Field) -> (String) -> Void {
        let id = block.id
        return { v in PressStore.shared.change { $0.editText(id, field, v) } }
    }

    private func field(_ value: String, _ st: PaperStyle, fresh: Bool = false, placeholder: String? = nil, _ f: PressDoc.Field = .text) -> some View {
        PaperField(value: value, style: st, fresh: fresh, placeholder: placeholder, onFreshUsed: { edit.fresh = nil }, onSave: save(f))
    }

    @ViewBuilder private var content: some View {
        switch block {
        case .heading(_, let t):
            if editing { field(t, s.heading, fresh: fresh) } else { Text(verbatim: t).paper(s.heading) }
        case .note(_, let t):
            Group {
                if editing { field(t, s.note, fresh: fresh) } else { Text(verbatim: t).paper(s.note) }
            }
            .noteBar(s)
        case .answer(let a):
            if editing {
                PaperField(value: a.heading.allSatisfy(\.isWhitespace) ? a.shownHeading : a.heading, style: s.heading, fresh: false,
                           onFreshUsed: {}, onSave: save(.heading))
            } else {
                Text(verbatim: PressPage.oneLine(a.shownHeading)).paper(s.heading)
            }
            if let q = a.shownQuestion {
                Text(verbatim: q.trimmingCharacters(in: .whitespacesAndNewlines)).paper(s.question).padding(.top, s.pt(3))
            }
            Spacer().frame(height: s.pt(3))
            if editing { field(a.text, s.body) } else { Text(verbatim: page.answerText(a)).paper(s.body) }
            if let refs = page.refsLine(a) { Text(verbatim: refs).paper(s.refs).padding(.top, s.pt(4)) }
            if let card = a.card { PaperCard(card: card, page: page, s: s) }
        // A paragraph and a list start empty and open for typing; empty, they show their hint on the screen only.
        case .paragraph(_, let t):
            if editing {
                field(t, s.body, fresh: fresh, placeholder: String(localized: "Write a paragraph…"))
            } else if t.allSatisfy(\.isWhitespace) {
                Text("Write a paragraph…").paper(s.body).foregroundStyle(PaperStyle.rgb(PaperScale.hint))
            } else {
                Text(verbatim: t.trimmingCharacters(in: .whitespacesAndNewlines)).paper(s.body)
            }
        case .bullets(_, let t):
            if editing {
                field(t, s.body, fresh: fresh, placeholder: String(localized: "One item per line…"))
            } else if PressDoc.items(t).isEmpty {
                Text("One item per line…").paper(s.body).foregroundStyle(PaperStyle.rgb(PaperScale.hint))
            } else {
                Text(verbatim: PressDoc.bulleted(t)).paper(s.body)
            }
        // Tall enough to tap; the line itself is thin, as in the PDF.
        case .divider:
            Rectangle().fill(PaperStyle.rgb(PressPaper.rule)).frame(height: 1)
                .frame(maxWidth: .infinity, minHeight: s.pt(14))
                .accessibilityLabel(Text("Divider"))
        case .picture(let p):
            PaperPicture(picture: p, projectId: page.project.id, dir: dir, s: s, maxW: PressPaper.inner, editing: editing,
                         fresh: fresh, center: true, edit: $edit)
        case .unknown:
            EmptyView()
        }
    }
}

extension View {
    /// A note's bar on its left, as the PDF draws it.
    fileprivate func noteBar(_ s: PaperScale) -> some View {
        padding(.leading, s.pt(12))
            .overlay(alignment: .leading) { Rectangle().fill(PaperStyle.rgb(PressPaper.noteBar)).frame(width: 2).padding(.leading, 1) }
    }
}

/// A text typed on the page, in the paper's own style, on a warm highlight; saved a moment after typing stops, and when
/// it closes. A block just added (`fresh`) takes the focus with its text selected, so typing replaces it.
private struct PaperField: View {
    let value: String
    let style: PaperStyle
    let fresh: Bool
    var placeholder: String?
    var center = false
    let onFreshUsed: () -> Void
    let onSave: (String) -> Void
    @State private var draft: String
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    init(value: String, style: PaperStyle, fresh: Bool, placeholder: String? = nil, center: Bool = false,
         onFreshUsed: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self.value = value; self.style = style; self.fresh = fresh; self.placeholder = placeholder; self.center = center
        self.onFreshUsed = onFreshUsed; self.onSave = onSave
        _draft = State(initialValue: value)
    }

    var body: some View {
        TextField(String(), text: $draft, selection: $selection,
                  prompt: placeholder.map { Text(verbatim: $0).foregroundStyle(PaperStyle.rgb(PaperScale.hint)) }, axis: .vertical)
            .textFieldStyle(.plain)
            .paper(style)
            .multilineTextAlignment(center ? .center : .leading)
            .focused($focused)
            .background(PaperStyle.rgb(0xFFF3D6), in: .rect(cornerRadius: 2))
            .task(id: draft) {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, draft != value else { return }
                onSave(draft)
            }
            .onDisappear { if draft != value { onSave(draft) } }
            .task {
                guard fresh else { return }
                try? await Task.sleep(for: .milliseconds(150))
                focused = true
                selection = TextSelection(range: draft.startIndex..<draft.endIndex)
                onFreshUsed()
            }
    }
}

// MARK: - pictures

/// A picture in a box `maxW` points wide, in its own shape, its caption under it: typed on the page while open; an empty
/// one doesn't show, as it doesn't print (android `PictureContent`).
private struct PaperPicture: View {
    let picture: PressDoc.Picture
    let projectId: String
    let dir: URL
    let s: PaperScale
    let maxW: Double
    let editing: Bool
    let fresh: Bool
    let center: Bool
    @Binding var edit: PressEdit

    var body: some View {
        let file = PressStore.fileOf(dir, projectId)(picture)
        let ok = picture.width > 0 && picture.height > 0
        let (w, h) = PictureFit.within(ok ? picture.width : 1, ok ? picture.height : 1, maxW, PressPaper.pictureMaxH)
        VStack(spacing: 0) {
            Group {
                if let file {
                    PaperImage(url: file)
                        .frame(width: s.pt(w), height: s.pt(h))
                        .background(PaperStyle.rgb(0xEEEEEE))
                } else {
                    Text("This picture is no longer on this \(Platform.deviceNoun).")
                        .paper(s.caption)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(s.pt(20))
                        .background(PaperStyle.rgb(0xF1F2F5))
                }
            }
            .frame(maxWidth: .infinity, alignment: center ? .center : picture.place == .left ? .leading : .trailing)
            .accessibilityElement()
            .accessibilityLabel(Text(picture.caption.allSatisfy(\.isWhitespace) ? String(localized: "Photo") : picture.caption))
            if editing {
                PaperField(value: picture.caption, style: s.caption, fresh: fresh, placeholder: String(localized: "Add a caption"),
                           center: center, onFreshUsed: { edit.fresh = nil }) { v in
                    let id = picture.id
                    PressStore.shared.change { $0.editText(id, .caption, v) }
                }
                .padding(.top, s.pt(4))
            } else if !picture.caption.allSatisfy(\.isWhitespace) {
                // Empty captions don't show, as they don't print.
                Text(verbatim: picture.caption.trimmingCharacters(in: .whitespacesAndNewlines))
                    .paper(s.caption)
                    .multilineTextAlignment(center ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: center ? .center : .leading)
                    .padding(.top, s.pt(4))
            }
        }
    }
}

/// A picture's file, decoded off the main actor at the size the paper needs.
private struct PaperImage: View {
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            let u = url
            image = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let src = CGImageSourceCreateWithURL(u as CFURL, nil) else { return nil }
                let o: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1400,
                                          kCGImageSourceCreateThumbnailWithTransform: true]
                return CGImageSourceCreateThumbnailAtIndex(src, 0, o as CFDictionary)
            }.value
        }
    }
}

/// A picture on the left or right with the next text block beside it (android `BesideView`): the lines whose top is above
/// the picture's bottom go beside it, measured with the PDF's own lines (PressPDF.splitBeside), the rest continue below
/// at the full width. While the text is typed it stays beside the picture whole.
private struct PaperBeside: View {
    let picture: PressDoc.Picture
    let text: PressDoc.Block?
    let left: Bool
    let page: PressPage
    let dir: URL
    let s: PaperScale
    @Binding var edit: PressEdit
    @State private var picH: CGFloat?

    private var side: Double { PressLayout.sideWidth(PressPaper.inner) }

    private var pictureView: some View {
        PaperPicture(picture: picture, projectId: page.project.id, dir: dir, s: s, maxW: side, editing: edit.editing == picture.id,
                     fresh: edit.fresh == picture.id, center: false, edit: $edit)
            .frame(width: s.pt(side))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { picH = $0 }
            .selectable(edit.selected == picture.id) { edit.select(picture.id) }
    }

    var body: some View {
        let gutter = s.pt(PressLayout.gutter)
        if let text {
            if edit.editing == text.id {
                HStack(alignment: .top, spacing: gutter) {
                    if left { pictureView }
                    PaperBlock(block: text, page: page, dir: dir, s: s, edit: $edit)
                    if !left { pictureView }
                }
            } else {
                flow(text, gutter)
            }
        } else {
            HStack(spacing: 0) {
                if !left { Spacer(minLength: 0) }
                pictureView
                if left { Spacer(minLength: 0) }
            }
        }
    }

    @ViewBuilder private func flow(_ text: PressDoc.Block, _ gutter: CGFloat) -> some View {
        let note: Bool = if case .note = text { true } else { false }
        let ok = picture.width > 0 && picture.height > 0
        let fit = PictureFit.within(ok ? picture.width : 1, ok ? picture.height : 1, side, PressPaper.pictureMaxH).1
        // The picture's height on the paper, back in PDF points, and 8 more (as the PDF's float).
        let room = Double(picH.map { s.k > 0 ? $0 / s.k : fit } ?? fit) + 8
        let split = PressPDF.splitBeside(PressPDF.pieces(text, page), room: room, indent: note ? 12 : 0)
        let selected = edit.selected == text.id
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: gutter) {
                if left { pictureView }
                if split.beside.isEmpty {
                    Spacer(minLength: 0)
                } else {
                    pieces(split.beside, note: note)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .selectable(selected) { edit.select(text.id) }
                }
                if !left { pictureView }
            }
            if !split.below.isEmpty {
                Spacer().frame(height: s.pt(split.beside.isEmpty ? 8 : 2))
                pieces(split.below, note: note)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .selectable(selected) { edit.select(text.id) }
            }
            // An answer's card goes below the picture at the full width, as in the PDF.
            if case .answer(let a) = text, let card = a.card { PaperCard(card: card, page: page, s: s) }
        }
    }

    @ViewBuilder private func pieces(_ list: [PressPDF.Piece], note: Bool) -> some View {
        let v = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, p in
                Text(verbatim: p.text).paper(s.of(p.style)).padding(.top, s.pt(p.gap))
            }
        }
        if note { v.noteBar(s) } else { v }
    }
}

// MARK: - the card, the footer, the page breaks

/// An answer's card on the paper (android `PaperCard`), as the PDF draws it: a rule, its title, then bars, a table (a pie
/// or a line too), the steps with ✓ for a ticked one, the things compared side by side, or the facts.
private struct PaperCard: View {
    let card: AnswerCard
    let page: PressPage
    let s: PaperScale

    var body: some View {
        VStack(alignment: .leading, spacing: s.pt(3)) {
            rule.padding(.vertical, s.pt(4))
            if !card.title.allSatisfy(\.isWhitespace) {
                Text(verbatim: card.title.trimmingCharacters(in: .whitespacesAndNewlines)).paper(s.cardTitle)
            }
            if card.byModel && !page.cardByModel.allSatisfy(\.isWhitespace) { Text(verbatim: page.cardByModel).paper(s.refs) }
            content
        }
        .padding(.top, s.pt(4))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rule: some View { Rectangle().fill(PaperStyle.rgb(PressPaper.rule)).frame(height: 1) }

    @ViewBuilder private var content: some View {
        switch card.body {
        case .series(_, let points) where card.shape == .bars:
            let top = points.map { abs($0.value) }.max().flatMap { $0 > 0 ? $0 : nil } ?? 1
            ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                HStack {
                    Text(verbatim: pt.label).paper(s.card).lineLimit(1)
                    Spacer()
                    Text(verbatim: pt.written).paper(s.cardMuted)
                }
                GeometryReader { g in
                    Capsule().fill(PaperStyle.rgb(PressPaper.barTrack))
                        .overlay(alignment: .leading) {
                            Capsule().fill(PaperStyle.rgb(PressPaper.bar)).frame(width: g.size.width * min(max(abs(pt.value) / top, 0.01), 1))
                        }
                }
                .frame(height: s.pt(7))
            }
        case .series, .table:
            if let t = AnswerCard.asTable(card) {
                if t.header.contains(where: { !$0.allSatisfy(\.isWhitespace) }) { row(t.header.map { $0.uppercased() }, s.cardHeader) }
                ForEach(Array(t.rows.enumerated()), id: \.offset) { _, r in
                    rule
                    row(r, s.card)
                }
            }
        case .steps(let items):
            ForEach(Array(items.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 6) {
                    Text(verbatim: card.ticks.contains(i) ? "✓" : "\(i + 1)").paper(s.card).frame(width: s.pt(PressPaper.inner * 0.07), alignment: .leading)
                    Text(verbatim: step).paper(s.card).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .facts(let pairs):
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, f in
                rule
                HStack(alignment: .top, spacing: 0) {
                    Text(verbatim: f.label).paper(s.cardMuted).frame(width: s.pt(PressPaper.inner * 0.38), alignment: .leading)
                    Text(verbatim: f.value).paper(s.card).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .compare(let sides):
            row(sides.map { side in side.name + "\n" + side.points.map { "•  " + $0 }.joined(separator: "\n") }, s.card)
        }
    }

    private func row(_ cells: [String], _ st: PaperStyle) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                Text(verbatim: c).paper(st).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The footer as the PDF draws it (adam, Nov 13): a short hairline, two small light lines, centered.
private struct PaperFooter: View {
    let page: PressPage
    let s: PaperScale

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(PaperStyle.rgb(PressPaper.rule)).frame(width: s.pt(48), height: 1)
            Spacer().frame(height: s.pt(8))
            ForEach(Array(page.footer.enumerated()), id: \.offset) { _, l in
                Text(verbatim: l).paper(s.footer).multilineTextAlignment(.center).padding(.bottom, s.pt(2))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, s.pt(18))
    }
}

/// Where the PDF's pages start (PressPDF.pageStarts): a dashed line at the top of the block that starts a page, or as far
/// into a text block as the PDF got, never past its bottom; "page n" on the right.
private struct PaperBreaks: View {
    let starts: [PressPDF.PageStart]
    let frames: PaperFrames
    let s: PaperScale

    var body: some View {
        let color = PaperStyle.rgb(0xB9BFD3)
        Canvas { ctx, size in
            for (i, st) in starts.enumerated() {
                guard let r = frames.rects[st.unit] else { continue }
                let y = st.intoPt <= 1 ? r.minY - 4 : r.minY + min(s.pt(st.intoPt), r.height)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                let text = ctx.resolve(Text(verbatim: String(localized: "page \(i + 2)"))
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(PaperStyle.rgb(0x1D1D1F)))
                let t = text.measure(in: CGSize(width: 200, height: 40))
                let w = t.width + 12
                let pill = CGRect(x: size.width - w - 8, y: y - t.height / 2, width: w, height: t.height)
                ctx.fill(Path(roundedRect: pill, cornerRadius: t.height / 2), with: .color(color))
                ctx.draw(text, at: CGPoint(x: pill.midX, y: pill.midY))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
