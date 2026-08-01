import Foundation
import XCTest
@testable import MojiQuickLook

final class MojiQuickLookTests: XCTestCase {
    func testJapaneseWordTokenizerPreservesTextAndMarksWords() {
        let source = "「外国の地を踏む。」"
        let runs = JapaneseWordTokenizer.runs(in: source)

        XCTAssertEqual(runs.map(\.value).joined(), source)
        XCTAssertEqual(
            runs.filter(\.isLookup).map(\.value),
            ["外国", "の", "地", "を", "踏む"]
        )
        XCTAssertFalse(runs.first?.isLookup ?? true)
        XCTAssertFalse(runs.last?.isLookup ?? true)
    }

    func testSearchResponseFlattensSectionsInDisplayOrder() throws {
        let data = Data(
            """
            {
              "word": {"list": [{"targetId":"w1","targetType":102,"title":"辞書 | じしょ ①","excerpt":"[名] 辞典"}]},
              "grammar": {"list": [{"targetId":"g1","targetType":106,"title":"ことはない","excerpt":"用不着"}]},
              "example": {"list": [{"targetId":"e1","targetType":121,"title":"国語辞書。","excerpt":"国语词典。"}]},
              "examQuestion": {"list": [{"targetId":"q1","targetType":671,"title":"試験","excerpt":"2016年7月N3","levelTag":"N3"}]}
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        XCTAssertEqual(response.flattened.map(\.category), [.word, .grammar, .example, .exam])
        XCTAssertEqual(response.flattened.first?.targetId, "w1")
        XCTAssertEqual(response.flattened.last?.levelTag, "N3")
    }

    func testWordDetailPairsBilingualDefinitionsAndExamples() throws {
        let data = Data(
            """
            {
              "word": {"id":"w1","spell":"辞書","pron":"じしょ","accent":"①","romaji":"jisho","excerpt":"[名] 辞典","tags":"N2#N5"},
              "subdetails": [
                {"id":"s1","relaId":"r1","title":"辞典","lang":"zh-CN"},
                {"id":"s2","relaId":"r1","title":"言葉を集めた書。","lang":"ja"}
              ],
              "examples": [
                {"id":"e1","relaId":"x1","subdetailsId":"r1","title":"国語辞書。","lang":"ja"},
                {"id":"e2","relaId":"x1","subdetailsId":"r1","title":"国语词典。","lang":"zh-CN"}
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(WordDetailResponse.self, from: data)
        XCTAssertEqual(response.word?.tagList, ["N2", "N5"])
        XCTAssertEqual(response.word?.tagLine, "N2・N5")
        XCTAssertEqual(response.definitionGroups.first?.chinese, "辞典")
        XCTAssertEqual(response.definitionGroups.first?.japanese, "言葉を集めた書。")
        XCTAssertEqual(response.definitionGroups.first?.examples.first?.japanese, "国語辞書。")
        XCTAssertEqual(response.definitionGroups.first?.examples.first?.chinese, "国语词典。")
        XCTAssertTrue(response.unassignedExampleGroups.isEmpty)
    }

    func testWordDetailIgnoresNullExampleTranslation() throws {
        let data = Data(
            """
            {
              "word": {
                "id":"kana-word",
                "spell":"ほろ",
                "pron":"ほろ",
                "excerpt":"[副词] すこし"
              },
              "subdetails": [
                {
                  "id":"s1",
                  "relaId":"s1",
                  "title":"すこし、なんとなくなどの意を表す。",
                  "lang":"ja"
                }
              ],
              "examples": [
                {
                  "id":"e1",
                  "relaId":"pair1",
                  "subdetailsId":"s1",
                  "title":"ほろ酔い",
                  "lang":"ja"
                },
                {
                  "id":"e2",
                  "relaId":"pair1",
                  "subdetailsId":"s1",
                  "title":null,
                  "lang":"zh-CN"
                }
              ]
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(WordDetailResponse.self, from: data)
        let examples = try XCTUnwrap(response.definitionGroups.first?.examples)

        XCTAssertEqual(examples.count, 1)
        XCTAssertEqual(examples.first?.japanese, "ほろ酔い")
        XCTAssertNil(examples.first?.chinese)
    }

    func testRubySegmentationAnnotatesOnlyKanjiRuns() {
        XCTAssertEqual(
            RubySegmenter.segments(base: "踏む", reading: "ふむ"),
            [
                RubySegment(base: "踏", ruby: "ふ"),
                RubySegment(base: "む", ruby: nil)
            ]
        )
        XCTAssertEqual(
            RubySegmenter.segments(base: "取り戻す", reading: "とりもどす"),
            [
                RubySegment(base: "取", ruby: "と"),
                RubySegment(base: "り", ruby: nil),
                RubySegment(base: "戻", ruby: "もど"),
                RubySegment(base: "す", ruby: nil)
            ]
        )
        XCTAssertEqual(
            RubySegmenter.segments(base: "お祝い", reading: "おいわい"),
            [
                RubySegment(base: "お", ruby: nil),
                RubySegment(base: "祝", ruby: "いわ"),
                RubySegment(base: "い", ruby: nil)
            ]
        )
    }

    func testSidebarTitleRemovesAccentAndExcerpt() {
        let result = SearchResult(
            item: SearchItem(
                targetId: "w1",
                targetType: 102,
                title: "踏む | ふむ ⓪",
                excerpt: "不应显示",
                levelTag: "N1"
            ),
            category: .word
        )

        XCTAssertEqual(result.headword, "踏む")
        XCTAssertEqual(result.pronunciation, "ふむ")
        XCTAssertEqual(result.sidebarTitle, "踏む【ふむ】")
    }

    func testLookupHistoryMovesAndDropsForwardBranch() {
        let first = LookupPage(
            query: "踏む",
            filter: .word,
            selectedID: "word-102-w1"
        )
        let second = LookupPage(
            query: "辞書",
            filter: .word,
            selectedID: "word-102-w2"
        )
        let branch = LookupPage(
            query: "注ぐ",
            filter: .word,
            selectedID: "word-102-w3"
        )
        var history = LookupHistory()

        history.record(first)
        history.record(second)
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.goBack(), first)
        XCTAssertTrue(history.canGoForward)

        history.record(branch)
        XCTAssertEqual(history.pages, [first, branch])
        XCTAssertFalse(history.canGoForward)
    }

    func testSystemDictionaryURLPercentEncodesJapaneseTerm() throws {
        let url = try XCTUnwrap(
            ExternalLookupURL.systemDictionary(for: " 踏む ")
        )

        XCTAssertEqual(
            url.absoluteString,
            "dict://%E8%B8%8F%E3%82%80"
        )
    }

    func testSearchURLPreservesRepeatedTypeParameters() throws {
        let url = try MojiAPIClient.searchURL(for: "辞書")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let typeValues = components.queryItems?
            .filter { $0.name == "types" }
            .compactMap(\.value)

        XCTAssertEqual(typeValues, ["102", "106", "103", "671"])
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "text" })?.value,
            "辞書"
        )
    }

    func testEmailLoginRequestMatchesCapturedProtocol() throws {
        let request = try MojiAPIClient.loginRequest(
            email: "reader@example.com",
            password: "test-password",
            deviceID: "test-device-id"
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        let payload = try XCTUnwrap(json["authPayload"] as? [String: Any])

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(json["authName"] as? String, "PasswordAuth")
        XCTAssertEqual(payload["email"] as? String, "reader@example.com")
        XCTAssertEqual(payload["code"] as? String, "test-password")
        XCTAssertNil(payload["password"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-MOJI-OS"), "PCWeb")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-MOJI-APP-ID"),
            "com.mojitec.mojidict"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-MOJI-DEVICE-ID"),
            "test-device-id"
        )
    }

    func testRelatedWordRequestMatchesWebProtocol() throws {
        let request = try MojiAPIClient.wordRelatedRequest(
            id: "19894628",
            deviceID: "test-device-id"
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(json["wordIds"] as? [String], ["19894628"])
    }

    func testRelatedSubjectsWithSameWordIDHaveDistinctViewIdentity() {
        let lookingBack = RelatedSubject(
            title: "振り返る",
            trans: "回头看",
            relatedId: "198971081",
            relateId: "zTPM4MAUD4"
        )
        let reflecting = RelatedSubject(
            title: "振り返る",
            trans: "回顾",
            relatedId: "198971081",
            relateId: "zTPM4MAUD4"
        )

        XCTAssertNotEqual(lookingBack.id, reflecting.id)
    }

    func testLoginResponseDecodesCapturedShape() throws {
        let data = Data(
            """
            {
              "sessionToken": "session",
              "user": {
                "objectId": "user",
                "name": "Reader",
                "email": "reader@example.com"
              },
              "isNew": false,
              "needBindMobile": false
            }
            """.utf8
        )

        let response = try JSONDecoder().decode(LoginResponse.self, from: data)
        XCTAssertEqual(response.sessionToken, "session")
        XCTAssertEqual(response.user.name, "Reader")
        XCTAssertEqual(response.user.email, "reader@example.com")
        XCTAssertFalse(response.isNew ?? true)
    }

    func testPersistedAccountSessionRoundTrips() throws {
        let original = PersistedAccountSession(
            sessionToken: "session-token",
            deviceID: "device-id",
            displayName: "Reader",
            email: "reader@example.com"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersistedAccountSession.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDictionaryTypographyCompactsCJKPunctuationSpacing() {
        XCTAssertEqual(
            DictionaryTypography.compactedPunctuation(
                in: "踏 ，　踩， 践踏 ；　跺脚： 走上"
            ),
            "踏，踩，践踏；跺脚：走上"
        )
        XCTAssertEqual(
            DictionaryTypography.parts(in: "[名][五段] 辞典"),
            [
                DictionaryTextPart(value: "[名]", isMetadata: true),
                DictionaryTextPart(value: "[五段]", isMetadata: true),
                DictionaryTextPart(value: " 辞典", isMetadata: false)
            ]
        )
        XCTAssertEqual(
            DictionaryTypography.metadataSummary(
                in: "[他动・五段] 踩；实践；经历"
            ),
            "[他动・五段]"
        )
    }

    func testLiveSearchAndWordDetailWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MOJI_LIVE_TESTS"] == "1" else {
            throw XCTSkip("Set MOJI_LIVE_TESTS=1 to run the read-only live endpoint test.")
        }

        let client = MojiAPIClient()
        let search = try await client.search("踏む")
        let firstWord = try XCTUnwrap(search.word?.list?.first)
        XCTAssertEqual(firstWord.targetType, 102)

        let detail = try await client.wordDetail(id: firstWord.targetId)
        XCTAssertFalse(detail.word?.spell?.isEmpty ?? true)
        XCTAssertFalse(detail.definitionGroups.isEmpty)
        XCTAssertFalse(detail.definitionGroups.first?.examples.isEmpty ?? true)

        let related = try await client.wordRelated(id: firstWord.targetId)
        XCTAssertTrue(related?.hasContent ?? false)

        for query in ["ほろ", "全く"] {
            let response = try await client.search(query)
            let secondWord = try XCTUnwrap(response.word?.list?.dropFirst().first)
            let detail = try await client.wordDetail(id: secondWord.targetId)
            XCTAssertFalse(detail.word?.spell?.isEmpty ?? true)
            XCTAssertFalse(detail.definitionGroups.isEmpty)
        }
    }
}
