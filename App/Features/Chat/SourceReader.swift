import BoarRAG
import SwiftUI

/// A source under an answer, read whole (port of android `SourceReaderScreen`, Oct 24): the article or file as it is on
/// the phone (SourceArticle), with the passage the answer used marked and scrolled into view. Offline: the source's
/// address is shown, not opened.
struct SourceReader: View {
    let source: ChatSource
    @Environment(AppModel.self) private var model
    @State private var article: SourceArticle.Article?
    @State private var loaded = false

    var body: some View {
        Group {
            if !loaded {
                ProgressView("Opening…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let article {
                SourceReaderBody(article: article, passage: source.body)
            } else {
                ContentUnavailableView {
                    Label("Not on This Device", systemImage: Symbols.sources)
                } description: {
                    Text("This article is no longer on this \(Platform.deviceNoun): its pack or collection was removed.")
                }
            }
        }
        .navigationTitle(article?.title ?? source.title)
        .inlineNavigationTitle()
        .task(id: source.docId) { await load() }
    }

    private func load() async {
        guard let services = model.services, let docId = source.docId else {
            loaded = true
            return
        }
        let title = source.title
        article = try? await services.background { $0.readSource(docId: docId, title: title) }
        loaded = true
    }
}

/// The article's text in three runs: before the passage BOAR used, the passage (marked), and after it.
private struct SourceReaderBody: View {
    let article: SourceArticle.Article
    let passage: String

    /// Found once: the passage search runs over the whole article, not on every redraw (PR #1 review).
    @State private var split: (before: String, used: String, after: String)?
    @State private var splitDone = false

    private static func split(_ text: String, _ passage: String) -> (before: String, used: String, after: String)? {
        guard let r = SourceArticle.passageAt(text, passage) else { return nil }
        let ns = text as NSString
        return (ns.substring(to: r.location), ns.substring(with: r), ns.substring(from: r.location + r.length))
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let src = article.source {
                        Text(src)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if !splitDone {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if let split {
                        Label("The part BOAR used is marked.", systemImage: "highlighter")
                            .font(.subheadline)
                            .foregroundStyle(.tint)
                        part(split.before)
                        part(split.used)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.tint.opacity(0.10), in: .rect(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.tint.opacity(0.45)))
                            .id("used")
                        part(split.after)
                    } else {
                        part(article.text)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .task {
                split = Self.split(article.text, passage)
                splitDone = true
                guard split != nil else { return }
                // Once laid out, the marked passage comes into view, a little below the top.
                try? await Task.sleep(for: .milliseconds(250))
                withAnimation { proxy.scrollTo("used", anchor: UnitPoint(x: 0, y: 0.08)) }
            }
        }
    }

    @ViewBuilder
    private func part(_ text: String) -> some View {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            if article.markdown {
                MarkdownText(text: t, sourceCount: 0)
            } else {
                Text(t).textSelection(.enabled)
            }
        }
    }
}
