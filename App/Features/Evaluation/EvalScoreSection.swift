import BoarAnswer
import SwiftUI

/// Each model's score v1 (android ScoreSection: speed 60 %, reliability 25 %, sources found 15 %) from the answers so
/// far, live while the run goes: a ring with the score and a bar per part. Speed and reliability on this phone, not
/// whether the answers are right.
struct EvalScoreSection: View {
    let controller: EvaluationController

    var body: some View {
        let scores = controller.scores
        let done = controller.rows.count
        let total = controller.expectedAnswers
        Section {
            ForEach(scores) { score in
                ScoreRow(score: score, name: controller.name(configId: score.configId, label: score.modelLabel ?? score.configId).plain)
            }
        } header: {
            BoarHeader {
                HStack {
                    Text("Score")
                    Spacer()
                    Group {
                        if controller.running {
                            Text("Running · \(done)/\(total) answers")
                                .foregroundStyle(.boar(.link))
                        } else {
                            Text("\(done)/\(total) answers")
                                .foregroundStyle(.boar(.muted))
                        }
                    }
                    .boarText("mono.xs")
                    .monospacedDigit()
                }
            }
        } footer: {
            if !scores.isEmpty {
                BoarFooter {
                    Text("Speed 60 %, reliability 25 %, sources found 15 %, measured on this \(Platform.deviceNoun). It doesn't say whether the answers are right.")
                }
            }
        }
    }
}

private struct ScoreRow: View {
    let score: EvalScore.ModelScore
    let name: String
    @Environment(\.palette) private var palette

    /// Real traffic-light colors for the ring only, as Android: a theme's "emerald" is gold in some themes, so a 96 would
    /// look like a warning.
    private var tone: Color {
        score.score >= 70 ? Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)
            : score.score >= 40 ? Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
            : Color(red: 0xEF / 255, green: 0x44 / 255, blue: 0x44 / 255)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(palette.borderDefault), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: Double(score.score) / 100)
                    .stroke(tone, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(score.score, format: .number)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.boar(.heading))
            }
            .frame(width: 64, height: 64)
            .padding(3)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: name)
                    .font(.boar("ui.subtext").weight(.semibold))
                    .lineLimit(1)
                PartBar(label: "Speed", fraction: score.speed, value: EvalFormat.tokensPerSecond(score.medianTokPerSec),
                        color: Color(palette.cyan400))
                PartBar(label: "Reliability", fraction: score.reliability,
                        value: String(localized: "\(score.completed)/\(score.answers) answered"), color: Color(palette.emerald400))
                PartBar(label: "Sources found", fraction: score.retrieval ?? 0,
                        value: score.retrieval == nil ? String(localized: "none expected")
                            : String(localized: "\(score.retrievalHits)/\(score.retrievalQuestions) found"),
                        color: Color(palette.amber400))
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PartBar: View {
    let label: LocalizedStringKey
    let fraction: Double
    let value: String
    let color: Color
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .foregroundStyle(.boar(.muted))
                Spacer()
                Text(verbatim: value)
                    .foregroundStyle(.boar(.primary))
                    .monospacedDigit()
            }
            .boarText("mono.xs")
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Color(palette.borderDefault)
                    color.frame(width: g.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 5)
            .clipShape(.rect(cornerRadius: 3))
        }
    }
}
