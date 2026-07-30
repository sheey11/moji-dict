import AppKit
import Foundation
import SwiftUI

struct DictionaryTextPart: Equatable {
    let value: String
    let isMetadata: Bool
}

enum DictionaryTypography {
    private static let punctuation: Set<Character> = ["，", "、", "；", "："]

    static func compactedPunctuation(in value: String) -> String {
        value.replacingOccurrences(
            of: #"[ \x{3000}]*([，、；：])[ \x{3000}]*"#,
            with: "$1",
            options: .regularExpression
        )
    }

    static func attributed(_ value: String) -> AttributedString {
        var output = AttributedString(compactedPunctuation(in: value))
        var index = output.characters.startIndex

        while index < output.characters.endIndex {
            let nextIndex = output.characters.index(after: index)
            if punctuation.contains(output.characters[index]) {
                output[index..<nextIndex].appKit.kern = -5
            }
            index = nextIndex
        }
        return output
    }

    static func parts(in value: String) -> [DictionaryTextPart] {
        let value = compactedPunctuation(in: value)
        var output: [DictionaryTextPart] = []
        var cursor = value.startIndex

        while
            let opening = value[cursor...].firstIndex(of: "["),
            let closing = value[opening...].firstIndex(of: "]")
        {
            if cursor < opening {
                output.append(
                    DictionaryTextPart(
                        value: String(value[cursor..<opening]),
                        isMetadata: false
                    )
                )
            }
            let afterClosing = value.index(after: closing)
            output.append(
                DictionaryTextPart(
                    value: String(value[opening..<afterClosing]),
                    isMetadata: true
                )
            )
            cursor = afterClosing
        }

        if cursor < value.endIndex {
            output.append(
                DictionaryTextPart(
                    value: String(value[cursor...]),
                    isMetadata: false
                )
            )
        }
        return output
    }

    static func metadataSummary(in value: String) -> String {
        parts(in: value)
            .filter(\.isMetadata)
            .map(\.value)
            .joined(separator: " ")
    }
}

struct DictionaryRichText: View {
    let value: String
    let pointSize: CGFloat
    let weight: Font.Weight
    let color: Color

    init(
        _ value: String,
        pointSize: CGFloat,
        weight: Font.Weight = .regular,
        color: Color = .primary
    ) {
        self.value = value
        self.pointSize = pointSize
        self.weight = weight
        self.color = color
    }

    var body: some View {
        composedText
    }

    private var composedText: Text {
        DictionaryTypography.parts(in: value).reduce(Text("")) { output, part in
            let fragment: Text
            if part.isMetadata {
                fragment = Text(part.value)
                    .font(.system(size: pointSize, weight: .regular, design: .default))
                    .foregroundColor(.secondary)
            } else {
                fragment = Text(DictionaryTypography.attributed(part.value))
                    .font(.system(size: pointSize, weight: weight, design: .serif))
                    .foregroundColor(color)
            }
            return output + fragment
        }
    }
}
