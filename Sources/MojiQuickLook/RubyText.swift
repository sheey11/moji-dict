import SwiftUI

struct RubyText: View {
    let base: String
    let reading: String

    private let pointSize: CGFloat = 30
    private let rubyPointSize: CGFloat = 11

    static func canSegment(base: String, reading: String) -> Bool {
        RubySegmenter.segments(base: base, reading: reading) != nil
    }

    var body: some View {
        if let segments = RubySegmenter.segments(base: base, reading: reading) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    if let ruby = segment.ruby {
                        VStack(spacing: -3) {
                            Text(ruby)
                                .font(.system(size: rubyPointSize, design: .serif))
                                .fontWeight(.regular)
                            Text(segment.base)
                                .font(.system(
                                    size: pointSize,
                                    weight: .semibold,
                                    design: .serif
                                ))
                        }
                    } else {
                        Text(segment.base)
                            .font(.system(
                                size: pointSize,
                                weight: .semibold,
                                design: .serif
                            ))
                    }
                }
            }
            .fixedSize()
            .textSelection(.enabled)
        } else {
            Text(base)
                .font(.system(size: pointSize, weight: .semibold, design: .serif))
                .textSelection(.enabled)
        }
    }
}

struct RubySegment: Equatable, Sendable {
    let base: String
    let ruby: String?
}

enum RubySegmenter {
    static func segments(base: String, reading: String) -> [RubySegment]? {
        guard base.containsKanji, !reading.isEmpty else { return nil }

        let baseRuns = makeBaseRuns(base)
        return solve(
            runs: baseRuns,
            runIndex: 0,
            reading: reading,
            readingCursor: reading.startIndex
        )
    }

    private struct BaseRun {
        let text: String
        let isKanji: Bool
    }

    private static func makeBaseRuns(_ base: String) -> [BaseRun] {
        var output: [BaseRun] = []

        for character in base {
            let text = String(character)
            let isKanji = text.unicodeScalars.contains(where: \.isKanji)

            if let last = output.last, last.isKanji == isKanji {
                output[output.count - 1] = BaseRun(
                    text: last.text + text,
                    isKanji: isKanji
                )
            } else {
                output.append(BaseRun(text: text, isKanji: isKanji))
            }
        }
        return output
    }

    private static func solve(
        runs: [BaseRun],
        runIndex: Int,
        reading: String,
        readingCursor: String.Index
    ) -> [RubySegment]? {
        guard runIndex < runs.count else {
            return readingCursor == reading.endIndex ? [] : nil
        }

        let run = runs[runIndex]
        if !run.isKanji {
            guard reading[readingCursor...].hasPrefix(run.text) else {
                return nil
            }
            let nextCursor = reading.index(readingCursor, offsetBy: run.text.count)
            guard let tail = solve(
                runs: runs,
                runIndex: runIndex + 1,
                reading: reading,
                readingCursor: nextCursor
            ) else {
                return nil
            }
            return [RubySegment(base: run.text, ruby: nil)] + tail
        }

        guard runIndex + 1 < runs.count else {
            let ruby = String(reading[readingCursor...])
            guard !ruby.isEmpty else { return nil }
            return [RubySegment(base: run.text, ruby: ruby)]
        }

        let anchor = runs[runIndex + 1].text
        var searchStart = readingCursor
        while let range = reading.range(
            of: anchor,
            range: searchStart..<reading.endIndex
        ) {
            if range.lowerBound > readingCursor {
                let ruby = String(reading[readingCursor..<range.lowerBound])
                if let tail = solve(
                    runs: runs,
                    runIndex: runIndex + 1,
                    reading: reading,
                    readingCursor: range.lowerBound
                ) {
                    return [RubySegment(base: run.text, ruby: ruby)] + tail
                }
            }

            guard range.lowerBound < reading.endIndex else { break }
            searchStart = reading.index(after: range.lowerBound)
        }
        return nil
    }
}

extension String {
    var containsKanji: Bool {
        unicodeScalars.contains(where: \.isKanji)
    }
}

private extension Unicode.Scalar {
    var isKanji: Bool {
        switch value {
        case 0x3005, 0x3007, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            true
        default:
            false
        }
    }
}
