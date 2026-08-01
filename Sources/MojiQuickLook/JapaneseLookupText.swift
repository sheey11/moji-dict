import NaturalLanguage
import SwiftUI

struct JapaneseTextRun: Equatable {
    let value: String
    let isLookup: Bool
    let canBreakBefore: Bool
}

enum JapaneseWordTokenizer {
    private static let openingPunctuation: Set<Character> = [
        "（", "「", "『", "【", "〔", "〈", "《", "“", "‘"
    ]
    private static let closingPunctuation: Set<Character> = [
        "、", "。", "，", "；", "：", "！", "？",
        "）", "」", "』", "】", "〕", "〉", "》", "”", "’", "…"
    ]

    static func runs(in value: String) -> [JapaneseTextRun] {
        guard !value.isEmpty else { return [] }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = value
        tokenizer.setLanguage(.japanese)

        var output: [JapaneseTextRun] = []
        var cursor = value.startIndex

        tokenizer.enumerateTokens(in: value.startIndex..<value.endIndex) { range, _ in
            appendPlainText(value[cursor..<range.lowerBound], to: &output)

            let followsOpeningPunctuation = output.last.map {
                $0.value.count == 1
                    && $0.value.first.map(openingPunctuation.contains) == true
            } ?? false
            output.append(
                JapaneseTextRun(
                    value: String(value[range]),
                    isLookup: true,
                    canBreakBefore: !followsOpeningPunctuation
                )
            )
            cursor = range.upperBound
            return true
        }

        appendPlainText(value[cursor..<value.endIndex], to: &output)
        return output
    }

    private static func appendPlainText(
        _ text: Substring,
        to output: inout [JapaneseTextRun]
    ) {
        for character in text {
            output.append(
                JapaneseTextRun(
                    value: String(character),
                    isLookup: false,
                    canBreakBefore: !closingPunctuation.contains(character)
                )
            )
        }
    }
}

struct JapaneseLookupText: View {
    let value: String
    let pointSize: CGFloat
    let weight: Font.Weight
    let color: Color
    let selectWord: (String) -> Void

    init(
        _ value: String,
        pointSize: CGFloat,
        weight: Font.Weight = .regular,
        color: Color = .primary,
        selectWord: @escaping (String) -> Void
    ) {
        self.value = value
        self.pointSize = pointSize
        self.weight = weight
        self.color = color
        self.selectWord = selectWord
    }

    var body: some View {
        InlineTokenLayout(lineSpacing: 2) {
            ForEach(
                Array(JapaneseWordTokenizer.runs(in: value).enumerated()),
                id: \.offset
            ) { _, run in
                if run.isLookup {
                    Button {
                        selectWord(run.value)
                    } label: {
                        PointerHoverLabel { isHovering in
                            styledText(run.value)
                                .underline(isHovering)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("查询“\(run.value)”")
                    .accessibilityLabel("查询“\(run.value)”")
                    .fixedSize()
                    .layoutValue(
                        key: InlineCanBreakBeforeKey.self,
                        value: run.canBreakBefore
                    )
                } else {
                    styledText(run.value)
                        .fixedSize()
                        .layoutValue(
                            key: InlineCanBreakBeforeKey.self,
                            value: run.canBreakBefore
                        )
                }
            }
        }
    }

    private func styledText(_ value: String) -> Text {
        Text(DictionaryTypography.attributed(value))
            .font(.system(size: pointSize, weight: weight, design: .serif))
            .foregroundColor(color)
    }
}

private struct InlineCanBreakBeforeKey: LayoutValueKey {
    static let defaultValue = true
}

private struct InlineTokenLayout: Layout {
    let lineSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = rows(for: subviews, width: widthLimit(for: proposal))
        return CGSize(
            width: rows.map(\.width).max() ?? 0,
            height: rows.reduce(0) { $0 + $1.height }
                + lineSpacing * CGFloat(max(rows.count - 1, 0))
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = rows(for: subviews, width: bounds.width)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(
                        x: x,
                        y: y + row.baseline - item.baseline
                    ),
                    proposal: .unspecified
                )
                x += item.size.width
            }
            y += row.height + lineSpacing
        }
    }

    private func widthLimit(for proposal: ProposedViewSize) -> CGFloat {
        guard let width = proposal.width, width > 0 else {
            return .greatestFiniteMagnitude
        }
        return width
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [InlineRow] {
        let items = subviews.indices.map { index in
            let dimensions = subviews[index].dimensions(in: .unspecified)
            return InlineItem(
                index: index,
                size: CGSize(width: dimensions.width, height: dimensions.height),
                baseline: dimensions[.firstTextBaseline],
                canBreakBefore: subviews[index][InlineCanBreakBeforeKey.self]
            )
        }

        var groups: [[InlineItem]] = []
        for item in items {
            if groups.isEmpty || item.canBreakBefore {
                groups.append([item])
            } else {
                groups[groups.index(before: groups.endIndex)].append(item)
            }
        }

        var rows: [InlineRow] = []
        var row = InlineRow()
        for group in groups {
            let groupWidth = group.reduce(0) { $0 + $1.size.width }
            if !row.items.isEmpty, row.width + groupWidth > width {
                rows.append(row)
                row = InlineRow()
            }
            for item in group {
                row.append(item)
            }
        }
        if !row.items.isEmpty {
            rows.append(row)
        }
        return rows
    }
}

private struct InlineItem {
    let index: Int
    let size: CGSize
    let baseline: CGFloat
    let canBreakBefore: Bool
}

private struct InlineRow {
    var items: [InlineItem] = []
    var width: CGFloat = 0
    var baseline: CGFloat = 0
    var descent: CGFloat = 0

    var height: CGFloat {
        baseline + descent
    }

    mutating func append(_ item: InlineItem) {
        items.append(item)
        width += item.size.width
        baseline = max(baseline, item.baseline)
        descent = max(descent, item.size.height - item.baseline)
    }
}
