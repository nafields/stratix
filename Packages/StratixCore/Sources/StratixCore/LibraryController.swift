// LibraryController.swift
// Defines the library controller.
//

import DiagnosticsKit
import Foundation
import StratixModels
import Observation
import StreamingCore
import XCloudAPI
public enum HomeMerchandisingSessionSource: Sendable, Equatable {
    case none
    case cacheRestore
    case liveRecovery
}

@Observable
@MainActor
public final class LibraryController {
    struct CacheLocations: Sendable {
        let details: URL
        let sections: URL
        let repository: URL
        let homeMerchandising: URL

        init(
            details: URL,
            sections: URL,
            repository: URL? = nil,
            homeMerchandising: URL
        ) {
            self.details = details
            self.sections = sections
            self.repository = repository ?? sections.deletingPathExtension().appendingPathExtension("swiftdata")
            self.homeMerchandising = homeMerchandising
        }

        static var live: Self {
            Self(
                details: LibraryController.detailsCacheURL,
                sections: LibraryController.sectionsCacheURL,
                repository: LibraryController.libraryRepositoryStoreURL,
                homeMerchandising: LibraryController.homeMerchandisingCacheURL
            )
        }
    }

    public private(set) var state: LibraryState

    public var sections: [CloudLibrarySection] { state.sections }
    public var itemsByTitleID: [TitleID: CloudLibraryItem] { state.itemsByTitleID }
    public var itemsByProductID: [ProductID: CloudLibraryItem] { state.itemsByProductID }
    public var productDetails: [ProductID: CloudLibraryProductDetail] { state.productDetails }
    public var isLoading: Bool { state.isLoading }
    public var lastError: String? { state.lastError }
    public var needsReauth: Bool { state.needsReauth }
    public var lastHydratedAt: Date? { state.lastHydratedAt }
    public var cacheSavedAt: Date? { state.cacheSavedAt }
    public var isArtworkPrefetchThrottled: Bool { state.isArtworkPrefetchThrottled }
    public var homeMerchandising: HomeMerchandisingSnapshot? { state.homeMerchandising }
    public var discoveryEntries: [GamePassSiglDiscoveryEntry] { state.discoveryEntries }
    public var isHomeMerchandisingLoading: Bool { state.isHomeMerchandisingLoading }
    public var hasCompletedInitialHomeMerchandising: Bool { state.hasCompletedInitialHomeMerchandising }
    public var homeMerchandisingSessionSource: HomeMerchandisingSessionSource { state.homeMerchandisingSessionSource }
    public var hasRecoveredLiveHomeMerchandisingThisSession: Bool { state.hasRecoveredLiveHomeMerchandisingThisSession }
    public var catalogRevision: UInt64 { state.catalogRevision }
    public var detailRevision: UInt64 { state.detailRevision }
    public var homeRevision: UInt64 { state.homeRevision }
    public var sceneContentRevision: UInt64 { state.sceneContentRevision }

    enum TaskID {
        static let cloudLibraryLoad = "cloudLibraryLoad"
        static let postLibraryWarmup = "postLibraryWarmup"
    }

    enum TaskGroupID {
        static let cloudLibraryProductDetail = "cloudLibraryProductDetail"
    }

    struct HomeMerchandisingSIGLProvider {
        let discoverAliases: @Sendable () async throws -> GamePassSiglDiscoveryResult
        let fetchProductIDs: @Sendable (_ siglID: String, _ market: String, _ language: String) async throws -> [String]

        static let live = HomeMerchandisingSIGLProvider(
            discoverAliases: {
                let client = GamePassSiglClient()
                return try await client.discoverAliases()
            },
            fetchProductIDs: { siglID, market, language in
                let client = GamePassSiglClient()
                return try await client.fetchProductIDs(siglID: siglID, market: market, language: language)
            }
        )
    }

    @ObservationIgnored let taskRegistry = TaskRegistry()
    @ObservationIgnored weak var dependencies: (any LibraryControllerDependencies)?
    @ObservationIgnored let logger = GLogger(category: .auth)
    @ObservationIgnored let artworkPipeline: ArtworkPipeline
    @ObservationIgnored let homeMerchandisingSIGLProvider: HomeMerchandisingSIGLProvider
    @ObservationIgnored let cacheLocations: CacheLocations
    @ObservationIgnored let libraryRepository: any LibraryRepository
    @ObservationIgnored let hydrationPersistenceStore: LibraryHydrationPersistenceStore
    @ObservationIgnored let hydrationOrchestrator: any LibraryHydrationOrchestrating
    @ObservationIgnored let publicationCoordinator = LibraryHydrationPublicationCoordinator()
    @ObservationIgnored let artworkPrefetchCoordinator = LibraryArtworkPrefetchCoordinator()
    @ObservationIgnored let homeMerchandisingCoordinator = LibraryHomeMerchandisingCoordinator()
    @ObservationIgnored var productDetailsCacheScheduleTask: Task<Void, Never>?
    @ObservationIgnored var sectionsCacheScheduleTask: Task<Void, Never>?
    @ObservationIgnored let refreshWorkflow: (@MainActor (LibraryController, CloudLibraryRefreshReason, Bool) async -> Void)?
    @ObservationIgnored let detailWorkflow: (@MainActor (LibraryController, String, String, String) async -> Void)?
    @ObservationIgnored let hydrationPlanner: LibraryHydrationPlanner
    @ObservationIgnored let hydrationWorker: any LibraryHydrationWorking
    @ObservationIgnored private var runtimeState = LibraryRuntimeState()

    typealias CachedHomeMerchandisingDiscovery = HomeMerchandisingDiscoveryCachePayload

    var hasPerformedNetworkHydrationThisSession: Bool {
        get { runtimeState.hasPerformedNetworkHydrationThisSession }
        set { applyRuntime(.networkHydrationPerformedSet(newValue)) }
    }

    var hasLoadedProductDetailsCache: Bool {
        get { runtimeState.hasLoadedProductDetailsCache }
        set { applyRuntime(.loadedProductDetailsCacheSet(newValue)) }
    }

    var hasLoadedSectionsCache: Bool {
        get { runtimeState.hasLoadedSectionsCache }
        set { applyRuntime(.loadedSectionsCacheSet(newValue)) }
    }

    var isArtworkPrefetchDisabledForSession: Bool {
        get { runtimeState.isArtworkPrefetchDisabledForSession }
        set { applyRuntime(.artworkPrefetchDisabledForSessionSet(newValue)) }
    }

    var lastArtworkPrefetchStartedAt: Date? {
        get { runtimeState.lastArtworkPrefetchStartedAt }
        set { applyRuntime(.artworkPrefetchStartedAtSet(newValue)) }
    }

    var artworkPrefetchLastCompletedAtByURL: [String: Date] {
        get { runtimeState.artworkPrefetchLastCompletedAtByURL }
        set { applyRuntime(.artworkPrefetchLastCompletedAtByURLSet(newValue)) }
    }

    var hydrationIsSuspendedForStreaming: Bool {
        runtimeState.isSuspendedForStreaming
    }

    var isSuspendedForStreaming: Bool {
        get { runtimeState.isSuspendedForStreaming }
        set { applyRuntime(.suspendedForStreamingSet(newValue)) }
    }

    var cachedHomeMerchandisingDiscovery: CachedHomeMerchandisingDiscovery? {
        get { runtimeState.cachedHomeMerchandisingDiscovery }
        set { applyRuntime(.cachedHomeMerchandisingDiscoverySet(newValue)) }
    }

    init(
        refreshWorkflow: (@MainActor (LibraryController, CloudLibraryRefreshReason, Bool) async -> Void)? = nil,
        detailWorkflow: (@MainActor (LibraryController, String, String, String) async -> Void)? = nil,
        artworkPipeline: ArtworkPipeline = .shared,
        hydrationPlanner: LibraryHydrationPlanner = LibraryHydrationPlanner(),
        hydrationWorker: (any LibraryHydrationWorking)? = nil,
        hydrationOrchestrator: (any LibraryHydrationOrchestrating)? = nil,
        libraryRepository: (any LibraryRepository)? = nil,
        initialState: LibraryState = .empty,
        cacheLocations: CacheLocations = .live,
        homeMerchandisingSIGLProvider: HomeMerchandisingSIGLProvider = .live
    ) {
        self.state = initialState
        self.refreshWorkflow = refreshWorkflow
        self.detailWorkflow = detailWorkflow
        self.artworkPipeline = artworkPipeline
        self.hydrationPlanner = hydrationPlanner
        self.cacheLocations = cacheLocations
        let resolvedRepository = libraryRepository ?? {
            do {
                return try SwiftDataLibraryRepository(
                    storeURL: cacheLocations.repository
                )
            } catch {
                fatalError("Failed to initialize library repository: \(error)")
            }
        }()
        self.libraryRepository = resolvedRepository
        let resolvedWorker = hydrationWorker ?? LibraryHydrationWorker(
            detailsCacheURL: cacheLocations.details,
            repository: resolvedRepository
        )
        self.hydrationWorker = resolvedWorker
        let persistenceStore = LibraryHydrationPersistenceStore(
            detailsURL: cacheLocations.details,
            libraryRepository: resolvedRepository
        )
        self.hydrationPersistenceStore = persistenceStore
        self.homeMerchandisingSIGLProvider = homeMerchandisingSIGLProvider
        self.hydrationOrchestrator = hydrationOrchestrator ?? LibraryHydrationOrchestrator(
            planner: hydrationPlanner,
            worker: resolvedWorker,
            persistenceStore: persistenceStore,
            homeMerchandisingSIGLProvider: homeMerchandisingSIGLProvider
        )
    }

    func attach(_ dependencies: any LibraryControllerDependencies) {
        self.dependencies = dependencies
    }

    public func refresh(forceRefresh: Bool = false, reason: CloudLibraryRefreshReason = .manualUser) async {
        await refresh(
            forceRefresh: forceRefresh,
            reason: reason,
            deferInitialRoutePublication: false
        )
    }

    public func refresh(
        forceRefresh: Bool,
        reason: CloudLibraryRefreshReason,
        deferInitialRoutePublication: Bool
    ) async {
        guard !isSuspendedForStreaming else {
            logger.info("Cloud library load skipped: suspended for streaming")
            return
        }
        logger.info(
            "Cloud library request: reason=\(reason.rawValue) forceRefresh=\(forceRefresh) cacheAge=\(formattedCacheAge())"
        )

        guard forceRefresh || requiresUnifiedHydration else {
            logger.info(
                "Cloud library load skipped: reason=\(reason.rawValue) unified snapshot still fresh"
            )
            return
        }

        let (task, inserted) = await taskRegistry.taskOrRegister(id: TaskID.cloudLibraryLoad) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let refreshWorkflow = self.refreshWorkflow {
                    await refreshWorkflow(self, reason, deferInitialRoutePublication)
                } else {
                    await LibraryHydrationRefreshWorkflow().run(
                        controller: self,
                        reason: reason,
                        deferInitialRoutePublication: deferInitialRoutePublication
                    )
                }
            }
        }
        if !inserted {
            logger.info(
                "Cloud library load already in progress; reason=\(reason.rawValue) joining existing task"
            )
        }
        await task.value
        if inserted {
            await taskRegistry.remove(id: TaskID.cloudLibraryLoad)
        }
    }

    func makeHydrationRequest(
        trigger: LibraryHydrationTrigger,
        reason: CloudLibraryRefreshReason? = nil,
        deferInitialRoutePublication: Bool = false
    ) -> LibraryHydrationRequest {
        LibraryHydrationRequest(
            trigger: trigger,
            market: Self.hydrationConfig.market,
            language: Self.hydrationConfig.language,
            preferDeltaRefresh: trigger == .postStreamDelta,
            forceFullRefresh: false,
            allowCacheRestore: trigger == .startupRestore || trigger == .shellBoot,
            allowPersistenceWrite: trigger != .startupRestore,
            deferInitialRoutePublication: deferInitialRoutePublication,
            refreshReason: reason,
            sourceDescription: String(describing: trigger)
        )
    }

    func apply(_ action: LibraryAction) {
        state = LibraryReducer.reduce(state: state, action: action)
    }

    func apply(_ actions: [LibraryAction]) {
        for action in actions {
            state = LibraryReducer.reduce(state: state, action: action)
        }
    }

    /// Upserts an achievement summary into the matching product detail, then persists the change.
    /// Called by AchievementsController after a successful achievement fetch.
    func upsertAchievementSummary(_ summary: TitleAchievementSummary) {
        guard let item = item(titleID: TitleID(summary.titleId)) else { return }
        let normalizedProductID = ProductID(item.productId)
        guard !normalizedProductID.rawValue.isEmpty else { return }
        guard let current = state.productDetails[normalizedProductID] else { return }
        let updated = CloudLibraryProductDetail(
            productId: current.productId,
            title: current.title,
            publisherName: current.publisherName,
            shortDescription: current.shortDescription,
            longDescription: current.longDescription,
            developerName: current.developerName,
            releaseDate: current.releaseDate,
            capabilityLabels: current.capabilityLabels,
            genreLabels: current.genreLabels,
            mediaAssets: current.mediaAssets,
            galleryImageURLs: current.galleryImageURLs,
            trailers: current.trailers,
            achievementSummary: summary
        )
        if state.productDetails[normalizedProductID] != updated {
            var nextDetails = state.productDetails
            nextDetails[normalizedProductID] = updated
            apply(.productDetailsReplaced(nextDetails))
            saveProductDetailsCache()
        }
    }

    nonisolated static func makeIndexes(
        from sections: [CloudLibrarySection]
    ) -> (byTitleID: [TitleID: CloudLibraryItem], byProductID: [ProductID: CloudLibraryItem]) {
        LibraryIndexBuilder.makeIndexes(from: sections)
    }
}

struct LibraryHydrationConfig: Sendable {
    let defaultLibraryHost = "https://eus.core.gssv-play-prod.xboxlive.com"
    let canonicalF2PLibraryHost = "https://xgpuwebf2p.gssv-play-prod.xboxlive.com"
    let fallbackHosts = [
        "https://uks.core.gssv-play-prod.xboxlive.com",
        "https://weu.core.gssv-play-prod.xboxlive.com",
        "https://uks.core.gssv-play-prodxhome.xboxlive.com",
        "https://weu.core.gssv-play-prodxhome.xboxlive.com",
        "https://uks.core.gssv-play-prodxhome.xboxlive.com",
        "https://wus.core.gssv-play-prodxhome.xboxlive.com",
        "https://eus.core.gssv-play-prodxhome.xboxlive.com",
        "https://euw.core.gssv-play-prodxhome.xboxlive.com"
    ]
    let market = "US"
    let language = "en-US"
    let hydration = "RemoteHighSapphire0"
    let mruLimit = 25
    let maxExtraHomeCategories = 6
    let fixedHomeCategoryAliases = [
        "buy-and-stream",
        "recently-added",
        "leaving-soon",
        "popular",
        "action-adventure",
        "family-friendly",
        "fighters",
        "indies",
        "rpgs",
        "shooters",
        "simulations",
        "strategies",
        "ea-play",
        "free-to-play"
    ]
    let trailingHomeCategoryAliases = [
        "free-to-play"
    ]
    let excludedHomeCategoryAliases = Set([
        "touch",
        "mouse-and-keyboard",
        "all-games"
    ])
}

@MainActor
extension LibraryController {
    nonisolated static var detailsCacheURL: URL {
        MetadataCacheStore.url(for: "stratix.cloudLibraryDetails.v2.json")
    }

    nonisolated static var sectionsCacheURL: URL {
        MetadataCacheStore.url(for: "stratix.cloudLibrarySections.json")
    }

    nonisolated static var libraryRepositoryStoreURL: URL {
        MetadataCacheStore.cacheURL(for: "stratix.cloudLibrarySections.swiftdata")
    }

    nonisolated static var homeMerchandisingCacheURL: URL {
        MetadataCacheStore.url(for: "stratix.homeMerchandising.v1.json")
    }

    func applyRuntime(_ action: LibraryRuntimeAction) {
        runtimeState = LibraryRuntimeReducer.reduce(state: runtimeState, action: action)
    }

    // MARK: - Post-Load Warmup

    func warmProfileAndSocialAfterLibraryLoad() async {
        guard !isSuspendedForStreaming else {
            logger.info("Post-library warmup skipped: suspended for streaming")
            return
        }
        guard let dependencies else { return }
        await LibraryPostLoadWarmupCoordinator().warm(
            taskRegistry: taskRegistry,
            taskID: TaskID.postLibraryWarmup,
            environment: LibraryPostLoadWarmupEnvironment(
                loadCurrentUserProfile: { [dependencies] in
                    await dependencies.loadCurrentUserProfile()
                },
                loadSocialPeople: { [dependencies] maxItems in
                    await dependencies.loadSocialPeople(maxItems: maxItems)
                }
            ),
            isSuspendedForStreaming: { [weak self] in
                self?.isSuspendedForStreaming ?? true
            }
        )
    }

    static var hydrationConfig: LibraryHydrationConfig {
        LibraryHydrationConfig()
    }

    static var productDetailsCacheSizeLimit: Int {
        2_048
    }
}
