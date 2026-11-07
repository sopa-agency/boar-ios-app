import BoarAnswer
import BoarCore
import SwiftUI

/// Boar Press (android labs/plugins/printer `PrinterLab.kt`): the research basket as a document. Answers come in from any
/// chat (More → Add to the Printer basket); here they're reordered, edited or dropped, and compiled to an A4 PDF
/// (BoarAnswer `PressPDF`) or a Markdown file, shared through the share sheet (Save to Files included). iOS has no Image
/// Gen, so there are no drawings to pick and the drawing switches stay hidden, as Android hides them when no answer has
/// a drawing.
struct PressLab: LabPlugin {
    let id = "printer"
    let order = 30
    let emoji = "🖨️"
    let art: String? = "truffle_steampunk"
    let status = LabStatus.beta
    var title: String { String(localized: "Boar Press") }
    var body: String { String(localized: "Collect answers from any chat into a basket, then compile them into a PDF or a Markdown file.") }

    func content() -> AnyView { AnyView(PressSections()) }

    /// 📎 in the answer's More menu: into the basket with its question, sources and chat title; again takes it out.
    func answerActions(_ a: AnswerRef) -> [LabAnswerAction] {
        let basket = BasketModel.shared
        let added = basket.contains(a.id)
        return [LabAnswerAction(id: "printer.basket",
                                title: added ? String(localized: "In the Printer basket (tap to remove)") : String(localized: "Add to the Printer basket"),
                                systemImage: "paperclip", done: added) {
            if added {
                basket.remove(a.id)
            } else {
                basket.add(Basket.Item(id: a.id, chatTitle: a.chatTitle, question: a.question, text: a.text,
                                       sources: a.sources.map { Basket.Source(title: $0.0, source: $0.1) },
                                       addedAt: Int64(Date().timeIntervalSince1970 * 1000), model: a.model, tokPerSec: a.tokPerSec))
            }
        }]
    }

    /// 📎 n in the chat's toolbar while the basket has something: opens the Press.
    func headerBadge(open: @escaping () -> Void) -> AnyView? {
        BasketModel.shared.items.isEmpty ? nil : AnyView(PressBadge(open: open))
    }

    /// The basket holds answers' text: it goes with the chats.
    func eraseUserData() { BasketModel.shared.eraseAll() }
}

/// The basket the app shows (Basket.kt's state flow): the list in memory, the file written whole after each change.
@MainActor
@Observable
final class BasketModel {
    static let shared = BasketModel(url: AppPaths.filesDir.appending(path: "labs/basket.json"))

    private(set) var items: [Basket.Item] = []
    @ObservationIgnored private let url: URL
    /// Read successfully (or nothing saved yet). Until then nothing is written, so a file that failed to read is never
    /// replaced by an empty basket.
    @ObservationIgnored private var loaded = false

    init(url: URL) {
        self.url = url
        load()
    }

    func load() {
        guard !loaded else { return }
        switch Basket.load(from: url) {
        case .none: items = []; loaded = true
        case .items(let list): items = list; loaded = true
        case .unreadable: BoarLog.logger("labs").warning("basket unreadable, kept as is; will retry")
        }
    }

    func contains(_ id: String) -> Bool { items.contains { $0.id == id } }

    func add(_ item: Basket.Item) { change { Basket.adding(item, to: $0) } }
    func remove(_ id: String) { change { Basket.removing(id, from: $0) } }
    func edit(_ id: String, text: String) { change { Basket.editing(id, text: text, in: $0) } }
    func edit(_ id: String, heading: String) { change { Basket.editing(id, heading: heading, in: $0) } }
    func move(_ id: String, by: Int) { change { Basket.moving(id, by: by, in: $0) } }
    func clear() { change { _ in [] } }

    /// SwiftUI's onMove: the rows at `from` go before `to`.
    func move(from: IndexSet, to: Int) {
        change { list in
            var out = list
            out.move(fromOffsets: from, toOffset: to)
            return out
        }
    }

    /// Erased with the chats: the file goes even if it couldn't be read, and the basket starts empty.
    func eraseAll() {
        try? FileManager.default.removeItem(at: url)
        items = []
        loaded = true
    }

    private func change(_ f: ([Basket.Item]) -> [Basket.Item]) {
        load()
        guard loaded else { return }
        let next = f(items)
        guard next != items else { return }
        do {
            try Basket.save(next, to: url)
            items = next
        } catch {
            BoarLog.logger("labs").warning("basket not saved: \(String(describing: error), privacy: .public)")
        }
    }
}

/// What prints besides the text, and the document's title, kept between visits (android LabPrefs `printer.*`).
enum PressPrefs {
    private static var d: UserDefaults { AppPaths.defaults }

    static var title: String {
        get { d.string(forKey: "labs.printer.title") ?? "" }
        set { d.set(newValue, forKey: "labs.printer.title") }
    }

    static var meta: Press.Meta {
        get {
            Press.Meta(date: d.string(forKey: "labs.printer.date") != "off", model: d.string(forKey: "labs.printer.model") == "on",
                       sources: d.string(forKey: "labs.printer.sources") != "off",
                       images: Press.Placement.of(d.string(forKey: "labs.printer.images")),
                       drawings: d.string(forKey: "labs.printer.drawings") != "off",
                       drawingFirst: d.string(forKey: "labs.printer.drawingPos") == "before")
        }
        set {
            d.set(newValue.date ? "on" : "off", forKey: "labs.printer.date")
            d.set(newValue.model ? "on" : "off", forKey: "labs.printer.model")
            d.set(newValue.sources ? "on" : "off", forKey: "labs.printer.sources")
            d.set(newValue.images.rawValue, forKey: "labs.printer.images")
            d.set(newValue.drawings ? "on" : "off", forKey: "labs.printer.drawings")
            d.set(newValue.drawingFirst ? "before" : "after", forKey: "labs.printer.drawingPos")
        }
    }

    static var footer: String { String(localized: "compiled offline with BOAR") }

    static var labels: ChatExport.Labels {
        ChatExport.Labels(reasoning: String(localized: "Reasoning"), sources: String(localized: "Retrieved sources"))
    }

    static var today: String { Date().formatted(date: .long, time: .omitted) }
}

private struct PressBadge: View {
    let open: () -> Void
    @State private var basket = BasketModel.shared

    var body: some View {
        let n = basket.items.count
        if n > 0 {
            Button(action: open) {
                // Never wider than "9+".
                Text(verbatim: "📎 " + (n > 9 ? "9+" : "\(n)"))
                    .font(.boar("mono.xs").weight(.heavy))
                    .lineLimit(1)
            }
            .accessibilityLabel(Text("Boar Press: \(n) answers in the basket"))
        }
    }
}

private struct PressSections: View {
    @State private var basket = BasketModel.shared
    @State private var title = PressPrefs.title
    @State private var meta = PressPrefs.meta
    @State private var preview = false
    @State private var editing: Basket.Item?

    private var defaultTitle: String {
        basket.items.first.map(\.chatTitle).flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 } ?? String(localized: "Field notes")
    }

    private var docTitle: String { title.allSatisfy(\.isWhitespace) ? defaultTitle : title }

    var body: some View {
        Group {
            if basket.items.isEmpty {
                Section {
                    Text("The basket is empty.")
                } footer: {
                    BoarFooter {
                        Text("Under any answer in a chat, open More (…) and add it to the basket. Collect from as many chats as you like, then come back to arrange and compile.")
                    }
                }
            } else {
                Section("Document title") {
                    TextField(text: $title, prompt: Text(verbatim: defaultTitle)) { Text("Document title") }
                }
                Section("Print") {
                    Toggle("Date", isOn: metaBinding(\.date))
                    Toggle("Model & speed", isOn: metaBinding(\.model))
                    Toggle("Sources", isOn: metaBinding(\.sources))
                }
                Section {
                    Picker("Show", selection: $preview) {
                        Text("Arrange").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if preview {
                    Section { PressPreview(title: docTitle, items: basket.items, meta: meta) }
                        .listRowInsets(EdgeInsets())
                } else {
                    itemsSection
                }
                Section {
                    ShareLink(item: pdfFile, preview: SharePreview(Text(verbatim: pdfFile.filename))) {
                        Label("Print to PDF", systemImage: "printer")
                    }
                    ShareLink(item: markdownFile, preview: SharePreview(Text(verbatim: markdownFile.filename))) {
                        Label("Save as Markdown", systemImage: "doc.text")
                    }
                }
            }
        }
        .task(id: title) {
            // Saved a moment after typing stops.
            try? await Task.sleep(for: .milliseconds(800))
            if title != PressPrefs.title { PressPrefs.title = title }
        }
        .sheet(item: $editing) { item in PressItemEditor(item: item) }
    }

    private var itemsSection: some View {
        Section {
            ForEach(Array(basket.items.enumerated()), id: \.element.id) { i, item in
                Button { editing = item } label: { PressItemRow(number: i + 1, item: item) }
                    .buttonStyle(.plain)
                    .accessibilityAction(named: Text("Move up")) { basket.move(item.id, by: -1) }
                    .accessibilityAction(named: Text("Move down")) { basket.move(item.id, by: 1) }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editing = item }
                        Button("Move up", systemImage: "arrow.up") { basket.move(item.id, by: -1) }
                            .disabled(i == 0)
                        Button("Move down", systemImage: "arrow.down") { basket.move(item.id, by: 1) }
                            .disabled(i == basket.items.count - 1)
                        Button("Remove", systemImage: "trash", role: .destructive) { basket.remove(item.id) }
                    }
            }
            .onMove { basket.move(from: $0, to: $1) }
            .onDelete { offsets in offsets.map { basket.items[$0].id }.forEach(basket.remove) }
        } header: {
            HStack {
                Text(basket.items.count == 1 ? String(localized: "1 item") : String(localized: "\(basket.items.count) items"))
                Spacer()
                Button("Clear", role: .destructive) { basket.clear() }
                    .font(.boar("ui.caption").weight(.semibold))
            }
        } footer: {
            BoarFooter {
                if basket.items.count > 1 { Text("Touch and hold an answer, then drag it to change the order.") }
            }
        }
    }

    private func metaBinding(_ key: WritableKeyPath<Press.Meta, Bool>) -> Binding<Bool> {
        Binding(get: { meta[keyPath: key] }, set: { meta[keyPath: key] = $0; PressPrefs.meta = meta })
    }

    /// The A4 PDF, compiled when the share sheet asks for it.
    private var pdfFile: ExportedFile {
        let (title, items, meta, date) = (docTitle, basket.items, meta, PressPrefs.today)
        let footer = PressPrefs.footer
        return ExportedFile(filename: Press.slug(title) + ".pdf") {
            PressPDF.compile(title: title, items: items, footer: footer, meta: meta, date: date)
        }
    }

    private var markdownFile: ExportedFile {
        let md = Press.markdown(title: docTitle, items: basket.items, footer: PressPrefs.footer, meta: meta, labels: PressPrefs.labels, date: PressPrefs.today)
        return ExportedFile(filename: Press.slug(docTitle) + ".md") { Data(md.utf8) }
    }
}

/// One answer in the basket: its number, heading, the start of its text and how many sources it has.
private struct PressItemRow: View {
    let number: Int
    let item: Basket.Item

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: "\(number)")
                .font(.boar("mono.xs").weight(.heavy))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: Press.heading(item))
                    .font(.boar("ui.titleSm"))
                    .lineLimit(2)
                Text(verbatim: Press.plain(item.text))
                    .font(.boar("ui.caption"))
                    .foregroundStyle(.boar(.muted))
                    .lineLimit(3)
                if !item.sources.isEmpty {
                    Text(item.sources.count == 1 ? String(localized: "1 source") : String(localized: "\(item.sources.count) sources"))
                        .font(.boar("mono.xs"))
                        .foregroundStyle(.boar(.dim))
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}

/// The heading printed above an answer, then its text; both saved as you type.
private struct PressItemEditor: View {
    let item: Basket.Item
    @State private var heading = ""
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Heading") {
                    TextField(text: $heading) { Text("Heading") }
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 240)
                }
            }
            .navigationTitle(Text(verbatim: Press.heading(item)))
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear {
            heading = Press.heading(item)
            text = item.text
        }
        .onChange(of: heading) { _, h in BasketModel.shared.edit(item.id, heading: h) }
        .onChange(of: text) { _, t in BasketModel.shared.edit(item.id, text: t) }
    }
}

/// The document as it will print, on paper colors: same order, same switches.
private struct PressPreview: View {
    let title: String
    let items: [Basket.Item]
    let meta: Press.Meta

    private static let ink = Color(red: 0x22 / 255, green: 0x22 / 255, blue: 0x22 / 255)
    private static let dim = Color(red: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255)
    private static let green = Color(red: 0x1B / 255, green: 0x4D / 255, blue: 0x3E / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: title).font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(Self.ink)
            Text(verbatim: (meta.date ? PressPrefs.today + " · " : "") + PressPrefs.footer)
                .font(.system(size: 10, design: .serif)).foregroundStyle(Self.dim)
            Rectangle().fill(Color(red: 0.8, green: 0.8, blue: 0.8)).frame(height: 1)
            ForEach(items) { item in
                Text(verbatim: Press.plain(Press.heading(item)))
                    .font(.system(size: 14, weight: .bold, design: .serif)).foregroundStyle(Self.green)
                    .padding(.top, 6)
                Text(verbatim: Press.plain(item.text))
                    .font(.system(size: 12, design: .serif)).lineSpacing(5).foregroundStyle(Self.ink)
                if meta.model, let line = Press.modelLine(item) {
                    Text(verbatim: line).font(.system(size: 9, design: .serif)).foregroundStyle(Self.green)
                }
                if meta.sources, !item.sources.isEmpty {
                    Text(verbatim: Press.sourceLines(item)).font(.system(size: 9, design: .serif))
                        .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color(red: 0xF7 / 255, green: 0xF4 / 255, blue: 0xEC / 255))
        .environment(\.colorScheme, .light)
    }
}
