import Foundation

struct LookupPage: Equatable, Sendable {
    let query: String
    let filter: ResultFilter
    let selectedID: SearchResult.ID
}

struct LookupHistory: Equatable, Sendable {
    private(set) var pages: [LookupPage] = []
    private(set) var currentIndex: Int?

    var canGoBack: Bool {
        guard let currentIndex else { return false }
        return currentIndex > pages.startIndex
    }

    var canGoForward: Bool {
        guard let currentIndex else { return false }
        return pages.indices.contains(currentIndex + 1)
    }

    mutating func record(_ page: LookupPage) {
        if let currentIndex, pages[currentIndex] == page {
            return
        }

        if
            let currentIndex,
            pages.indices.contains(currentIndex + 1)
        {
            pages.removeSubrange((currentIndex + 1)...)
        }

        pages.append(page)
        currentIndex = pages.index(before: pages.endIndex)
    }

    mutating func goBack() -> LookupPage? {
        guard canGoBack, let currentIndex else { return nil }
        let destination = pages.index(before: currentIndex)
        self.currentIndex = destination
        return pages[destination]
    }

    mutating func goForward() -> LookupPage? {
        guard canGoForward, let currentIndex else { return nil }
        let destination = pages.index(after: currentIndex)
        self.currentIndex = destination
        return pages[destination]
    }
}

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            cancelPendingNavigationIfNeeded()
            scheduleSearch()
        }
    }

    @Published var filter: ResultFilter = .word {
        didSet {
            guard filter != oldValue else { return }
            cancelPendingNavigationIfNeeded()
            keepSelectionVisible()
        }
    }

    @Published var selectedID: SearchResult.ID? {
        didSet {
            guard selectedID != oldValue else { return }
            loadSelectedDetail()
        }
    }

    @Published private(set) var results: [SearchResult] = []
    @Published private(set) var detail: WordDetailResponse?
    @Published private(set) var related: WordRelatedGroup?
    @Published private(set) var forvoAudio: ForvoWordAudio?
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingDetail = false
    @Published private(set) var searchError: String?
    @Published private(set) var detailError: String?
    @Published private(set) var lastLatencyMilliseconds: Int?
    @Published private(set) var navigationHistory = LookupHistory()

    private let api: MojiAPIClient
    private let forvoClient: ForvoClient
    private var searchTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var forvoTask: Task<Void, Never>?
    private var pendingHistoryPage: LookupPage?
    private var isNavigatingHistory = false
    private var isApplyingHistoryPage = false

    init(
        api: MojiAPIClient = .shared,
        forvoClient: ForvoClient = .shared
    ) {
        self.api = api
        self.forvoClient = forvoClient
    }

    deinit {
        searchTask?.cancel()
        detailTask?.cancel()
        forvoTask?.cancel()
    }

    var visibleResults: [SearchResult] {
        guard let category = filter.category else { return results }
        return results.filter { $0.category == category }
    }

    var selectedResult: SearchResult? {
        results.first { $0.id == selectedID }
    }

    var canGoBack: Bool {
        navigationHistory.canGoBack
    }

    var canGoForward: Bool {
        navigationHistory.canGoForward
    }

    func searchImmediately() {
        scheduleSearch(delay: nil)
    }

    func goBack() {
        guard let page = navigationHistory.goBack() else { return }
        navigate(to: page)
    }

    func goForward() {
        guard let page = navigationHistory.goForward() else { return }
        navigate(to: page)
    }

    func retryDetail() {
        guard let selectedResult, selectedResult.category == .word else { return }
        requestDetail(for: selectedResult, forceRefresh: true)
        requestForvo(for: selectedResult, forceRefresh: true)
    }

    func clear() {
        query = ""
        results = []
        selectedID = nil
        detail = nil
        related = nil
        forvoAudio = nil
        searchError = nil
        detailError = nil
        lastLatencyMilliseconds = nil
        pendingHistoryPage = nil
        isNavigatingHistory = false
    }

    private func scheduleSearch(delay: Duration? = .milliseconds(180)) {
        searchTask?.cancel()
        detailTask?.cancel()
        forvoTask?.cancel()
        forvoAudio = nil

        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            results = []
            selectedID = nil
            detail = nil
            related = nil
            forvoAudio = nil
            searchError = nil
            detailError = nil
            isSearching = false
            isLoadingDetail = false
            lastLatencyMilliseconds = nil
            return
        }

        isSearching = true
        searchError = nil

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                if let delay {
                    try await Task.sleep(for: delay)
                }
                let startedAt = ContinuousClock.now
                let response = try await api.search(text)
                try Task.checkCancellation()
                let elapsed = startedAt.duration(to: .now)
                lastLatencyMilliseconds = Int(
                    Double(elapsed.components.seconds) * 1_000
                        + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
                )
                results = response.flattened
                isSearching = false

                if let pendingHistoryPage {
                    restoreHistoryPage(pendingHistoryPage)
                    return
                }

                let preferred = visibleResults.first(where: { $0.category == .word })
                    ?? visibleResults.first
                    ?? results.first
                selectedID = preferred?.id
                recordCurrentPage()
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                selectedID = nil
                detail = nil
                related = nil
                forvoAudio = nil
                isSearching = false
                searchError = error.localizedDescription
                pendingHistoryPage = nil
                isNavigatingHistory = false
            }
        }
    }

    private func keepSelectionVisible() {
        let currentIsVisible = visibleResults.contains { $0.id == selectedID }
        if !currentIsVisible {
            selectedID = visibleResults.first?.id
        }
    }

    private func loadSelectedDetail() {
        detailTask?.cancel()
        forvoTask?.cancel()
        detail = nil
        related = nil
        forvoAudio = nil
        detailError = nil
        recordCurrentPage()

        guard let selectedResult else {
            isLoadingDetail = false
            return
        }
        guard selectedResult.category == .word else {
            isLoadingDetail = false
            return
        }
        requestDetail(for: selectedResult)
        requestForvo(for: selectedResult)
    }

    private func requestForvo(
        for result: SearchResult,
        forceRefresh: Bool = false
    ) {
        forvoTask?.cancel()
        let word = result.headword

        forvoTask = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await forvoClient.pronunciations(
                    for: word,
                    forceRefresh: forceRefresh
                )
                try Task.checkCancellation()
                guard selectedID == result.id else { return }
                forvoAudio = response
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, selectedID == result.id else { return }
                forvoAudio = nil
            }
        }
    }

    private func requestDetail(for result: SearchResult, forceRefresh: Bool = false) {
        detailTask?.cancel()
        isLoadingDetail = true
        detailError = nil

        detailTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let detailRequest = api.wordDetail(
                    id: result.targetId,
                    forceRefresh: forceRefresh
                )
                async let relatedRequest = api.wordRelated(
                    id: result.targetId,
                    forceRefresh: forceRefresh
                )
                let response = try await detailRequest
                let relatedResponse = try? await relatedRequest
                try Task.checkCancellation()
                guard selectedID == result.id else { return }
                detail = response
                related = relatedResponse
                isLoadingDetail = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, selectedID == result.id else { return }
                detail = nil
                related = nil
                isLoadingDetail = false
                detailError = error.localizedDescription
            }
        }
    }

    private func recordCurrentPage() {
        guard
            !isNavigatingHistory,
            let selectedResult
        else {
            return
        }

        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        navigationHistory.record(
            LookupPage(
                query: text,
                filter: filter,
                selectedID: selectedResult.id
            )
        )
    }

    private func navigate(to page: LookupPage) {
        isNavigatingHistory = true
        pendingHistoryPage = page
        let needsSearch = query != page.query

        isApplyingHistoryPage = true
        filter = page.filter
        query = page.query
        isApplyingHistoryPage = false

        if !needsSearch {
            restoreHistoryPage(page)
        }
    }

    private func restoreHistoryPage(_ page: LookupPage) {
        pendingHistoryPage = nil
        filter = page.filter

        let destination = results.first(where: { $0.id == page.selectedID })
            ?? visibleResults.first
            ?? results.first
        selectedID = destination?.id
        isNavigatingHistory = false
    }

    private func cancelPendingNavigationIfNeeded() {
        guard !isApplyingHistoryPage else { return }
        guard let pendingHistoryPage else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            text != pendingHistoryPage.query
                || filter != pendingHistoryPage.filter
        else {
            return
        }

        self.pendingHistoryPage = nil
        isNavigatingHistory = false
    }
}
