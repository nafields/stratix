// AchievementModels.swift
// Defines the achievement models.
//

import Foundation

public struct TitleAchievementSummary: Sendable, Equatable, Hashable, Codable {
    public let titleId: String
    public let titleName: String?
    public let totalAchievements: Int
    public let unlockedAchievements: Int
    public let totalGamerscore: Int?
    public let unlockedGamerscore: Int?
    public let lastUpdated: Date

    public init(
        titleId: String,
        titleName: String? = nil,
        totalAchievements: Int,
        unlockedAchievements: Int,
        totalGamerscore: Int? = nil,
        unlockedGamerscore: Int? = nil,
        lastUpdated: Date = Date()
    ) {
        self.titleId = titleId
        self.titleName = titleName
        self.totalAchievements = totalAchievements
        self.unlockedAchievements = unlockedAchievements
        self.totalGamerscore = totalGamerscore
        self.unlockedGamerscore = unlockedGamerscore
        self.lastUpdated = lastUpdated
    }

    public var unlockPercent: Int {
        guard totalAchievements > 0 else { return 0 }
        let value = Double(unlockedAchievements) / Double(totalAchievements)
        return max(0, min(100, Int((value * 100).rounded())))
    }
}

public struct AchievementProgressItem: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: String
    public let name: String
    public let detail: String?
    public let unlocked: Bool
    public let percentComplete: Int?
    public let gamerscore: Int?
    public let unlockedAt: Date?

    public init(
        id: String,
        name: String,
        detail: String? = nil,
        unlocked: Bool,
        percentComplete: Int? = nil,
        gamerscore: Int? = nil,
        unlockedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.unlocked = unlocked
        self.percentComplete = percentComplete
        self.gamerscore = gamerscore
        self.unlockedAt = unlockedAt
    }
}

public struct TitleAchievementSnapshot: Sendable, Equatable, Hashable, Codable {
    public let titleId: String
    public let fetchedAt: Date
    public let summary: TitleAchievementSummary
    public let achievements: [AchievementProgressItem]

    public init(
        titleId: String,
        fetchedAt: Date = Date(),
        summary: TitleAchievementSummary,
        achievements: [AchievementProgressItem]
    ) {
        self.titleId = titleId
        self.fetchedAt = fetchedAt
        self.summary = summary
        self.achievements = achievements
    }
}
