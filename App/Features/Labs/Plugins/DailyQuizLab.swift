import BoarRAG
import SwiftUI

/// Boar Labs' Daily Quiz (android labs/plugins/dailyQuiz, Oct 24): five questions a day from BOAR's built-in library,
/// offline and without the model (BoarRAG `DailyQuiz`, the same draw as Android's for the same date and library). It
/// stays behind its classified tile: leaking the tile (the Labs easter egg) unlocks it, as on Android's normal builds.
/// Today's answers are kept, so leaving resumes the quiz and replaying counts nothing more. Right answers and the days
/// played count for Boar Avatars (knight, elder), as on Android; the copy says so again once the avatars have a screen.
struct DailyQuizLab: LabPlugin {
    let id = "dailyQuiz"
    let order = 80
    let emoji = "❔"
    let art: String? = "lab_daily_quiz"
    let status = LabStatus.alpha
    var title: String { String(localized: "Daily Quiz") }
    var body: String { String(localized: "A short daily quiz from BOAR's library, offline.") }

    func content() -> AnyView { AnyView(DailyQuizSections()) }
}

private struct DailyQuizSections: View {
    @Environment(AppModel.self) private var model
    /// Articles the day's quiz draws from (a sample of the library, by the date).
    private static let pool = 400
    private static let dayKey = "labs.dailyQuiz.day"
    /// Today's picks, one per answered question ("2,0,3").
    private static let picksKey = "labs.dailyQuiz.picks"

    @State private var today = DailyQuiz.epochDay(.now)
    @State private var quiz: [DailyQuiz.Question]?
    @State private var picks: [Int] = []
    /// The question on screen after an answer, until Next: picks.count counts answered ones.
    @State private var showing: Int?

    var body: some View {
        Group {
            if let q = quiz {
                if q.isEmpty {
                    Section { Text("The library isn't ready yet: finish setup, then come back.").foregroundStyle(.boar(.muted)) }
                } else if showing == nil && picks.count >= q.count {
                    let right = q.indices.filter { $0 < picks.count && picks[$0] == q[$0].answer }.count
                    Section {
                        Text("\(right) of \(q.count) right today.").font(.boar("ui.title"))
                        Text("A new quiz tomorrow.").foregroundStyle(.boar(.muted))
                    }
                } else {
                    question(q, showing ?? picks.count)
                }
            } else {
                Section { Text("Picking today's questions…").foregroundStyle(.boar(.muted)) }
            }
        }
        // Again once the engine is open: a page shown before that would stay on "not ready".
        .task(id: model.services != nil) { await load() }
    }

    @ViewBuilder private func question(_ q: [DailyQuiz.Question], _ i: Int) -> some View {
        let question = q[i]
        let picked = i < picks.count ? picks[i] : nil
        Section {
            Text(verbatim: question.clue)
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Question \(i + 1) of \(q.count)").font(.boar("mono.xs").bold()).foregroundStyle(.boar(.success))
                Text("Which article does this come from?").font(.boar("ui.title")).foregroundStyle(.boar(.heading)).textCase(nil)
            }
        }
        Section {
            ForEach(question.options.indices, id: \.self) { o in
                Button {
                    pick(o, at: i, right: o == question.answer)
                } label: {
                    HStack {
                        Text(verbatim: question.options[o]).foregroundStyle(.boar(.primary))
                        Spacer()
                        if picked != nil && o == question.answer {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.boar(.success))
                        } else if picked == o {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.boar(.danger))
                        }
                    }
                }
                .disabled(picked != nil)
            }
        } footer: {
            BoarFooter {
                // Android: a right pick in textAccentEmerald, a wrong one in textSecondary (DailyQuizLab.kt).
                if let picked {
                    if picked == question.answer {
                        Text("Right!").foregroundStyle(.boar(.success))
                    } else {
                        Text("Not this time: it was \(question.options[question.answer]).").foregroundStyle(.boar(.secondary))
                    }
                }
            }
        }
        if picked != nil {
            Section {
                Button("Next") { showing = nil }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func pick(_ o: Int, at i: Int, right: Bool) {
        // A second tap before the screen updates finds this question answered already.
        if picks.count > i { return }
        // Kept before anything else: a second tap, or the app closing here, can't count it twice.
        picks.append(o)
        AppPaths.defaults.set(String(today), forKey: Self.dayKey)
        AppPaths.defaults.set(picks.map(String.init).joined(separator: ","), forKey: Self.picksKey)
        showing = i
        model.services?.vault.quizAnswered(right: right, epochDay: today)
    }

    private func load() async {
        let day = today
        picks = AppPaths.defaults.string(forKey: Self.dayKey) == String(day)
            ? (AppPaths.defaults.string(forKey: Self.picksKey) ?? "").split(separator: ",").compactMap { Int($0) } : []
        guard let kb = model.services?.knowledgeBase else { quiz = []; return }
        let pool = Self.pool
        quiz = await Task.detached(priority: .userInitiated) {
            (try? DailyQuiz.daily(kb.seedArticles(seed: day, limit: pool), epochDay: day)) ?? []
        }.value
    }
}
