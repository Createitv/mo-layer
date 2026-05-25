import CoreGraphics
import CryptoKit
import Foundation

struct GesturePoint: Codable, Equatable {
    var x: Double
    var y: Double
    var t: Double
}

struct GestureMatchResult {
    let isMatch: Bool
    let score: Double
}

enum GestureCredentialService {
    private static let templateAccount = "vault.gesture.template"
    private static let backupKeyHashAccount = "vault.gesture.backup.hash"
    private static let backupKeySaltAccount = "vault.gesture.backup.salt"
    private static let legacyResetHashAccount = "vault.gesture.reset.hash"
    private static let legacyResetSaltAccount = "vault.gesture.reset.salt"
    private static let sampleCount = 64
    private static let unlockThreshold = 0.66
    private static let enrollmentThreshold = 0.68
    private static let minimumRawPathLength = 0.18
    private static let minimumRawSpan = 0.16

    static var hasTemplate: Bool {
        (try? KeychainService.read(account: templateAccount)) != nil
    }

    static func validateCandidate(_ points: [GesturePoint]) throws {
        let deduped = dedupe(points)
        guard deduped.count >= 12 else { throw GestureError.tooShort }

        let rawLength = pathLength(deduped)
        guard rawLength >= minimumRawPathLength else { throw GestureError.tooShort }

        let spanX = (deduped.map(\.x).max() ?? 0) - (deduped.map(\.x).min() ?? 0)
        let spanY = (deduped.map(\.y).max() ?? 0) - (deduped.map(\.y).min() ?? 0)
        guard max(spanX, spanY) >= minimumRawSpan else { throw GestureError.tooShort }

        let directDistance = distance(deduped.first!, deduped.last!)
        let maxTurn = turnProfile(normalize(deduped)).max() ?? 0
        if rawLength < directDistance * 1.08 && maxTurn < 0.06 {
            throw GestureError.tooSimple
        }
    }

    static func enroll(primary: [GesturePoint], confirmation: [GesturePoint], backupKey: String) throws -> GestureMatchResult {
        let first = try makeTemplate(from: primary)
        let second = try makeTemplate(from: confirmation)
        let result = match(first, second, threshold: enrollmentThreshold)
        guard result.isMatch else { return result }

        let salt = VaultCryptoService.randomData(count: 24)
        let hash = backupKeyHash(backupKey, salt: salt)
        let data = try JSONEncoder().encode(first)
        try KeychainService.save(data, account: templateAccount, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        try KeychainService.save(salt, account: backupKeySaltAccount, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        try KeychainService.save(hash, account: backupKeyHashAccount, accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        return result
    }

    static func verify(_ points: [GesturePoint]) throws -> GestureMatchResult {
        let storedData = try KeychainService.read(account: templateAccount)
        let stored = try JSONDecoder().decode(GestureTemplate.self, from: storedData)
        let candidate = try makeTemplate(from: points)
        return match(stored, candidate, threshold: unlockThreshold)
    }

    static func enrollmentMatchResult(primary: [GesturePoint], confirmation: [GesturePoint]) throws -> GestureMatchResult {
        let first = try makeTemplate(from: primary)
        let second = try makeTemplate(from: confirmation)
        return match(first, second, threshold: enrollmentThreshold)
    }

    static func reset(primary: [GesturePoint], confirmation: [GesturePoint], backupKey: String) throws -> GestureMatchResult {
        guard verifyBackupKey(backupKey) else {
            return GestureMatchResult(isMatch: false, score: 0)
        }
        return try enroll(primary: primary, confirmation: confirmation, backupKey: backupKey)
    }

    static func verifyBackupKey(_ key: String) -> Bool {
        if verifyBackupKey(key, saltAccount: backupKeySaltAccount, hashAccount: backupKeyHashAccount) {
            return true
        }
        return verifyBackupKey(key, saltAccount: legacyResetSaltAccount, hashAccount: legacyResetHashAccount)
    }

    private static func verifyBackupKey(_ key: String, saltAccount: String, hashAccount: String) -> Bool {
        guard let salt = try? KeychainService.read(account: saltAccount),
              let expected = try? KeychainService.read(account: hashAccount) else {
            return false
        }
        return backupKeyHash(key, salt: salt) == expected
    }

    private static func backupKeyHash(_ key: String, salt: Data) -> Data {
        let normalized = key
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        var data = Data(normalized.utf8)
        data.append(salt)
        return Data(SHA256.hash(data: data))
    }

    private static func makeTemplate(from rawPoints: [GesturePoint]) throws -> GestureTemplate {
        try validateCandidate(rawPoints)
        let points = normalize(rawPoints)
        let resampled = resample(points, count: sampleCount)
        let duration = max((rawPoints.last?.t ?? 0) - (rawPoints.first?.t ?? 0), 0.1)
        let length = pathLength(resampled)
        return GestureTemplate(
            points: resampled,
            duration: duration,
            pathLength: length,
            speedProfile: speedProfile(resampled),
            turnProfile: turnProfile(resampled),
            pauseRatio: pauseRatio(points)
        )
    }

    private static func dedupe(_ points: [GesturePoint]) -> [GesturePoint] {
        points.reduce(into: [GesturePoint]()) { result, point in
            guard let last = result.last else {
                result.append(point)
                return
            }
            let dx = point.x - last.x
            let dy = point.y - last.y
            if sqrt(dx * dx + dy * dy) > 0.006 {
                result.append(point)
            }
        }
    }

    private static func normalize(_ points: [GesturePoint]) -> [GesturePoint] {
        let deduped = dedupe(points)
        guard deduped.count >= 2 else { return deduped }

        let minX = deduped.map(\.x).min() ?? 0
        let maxX = deduped.map(\.x).max() ?? 1
        let minY = deduped.map(\.y).min() ?? 0
        let maxY = deduped.map(\.y).max() ?? 1
        let scale = max(maxX - minX, maxY - minY, 0.001)
        let startTime = deduped.first?.t ?? 0

        return deduped.map {
            GesturePoint(
                x: ($0.x - minX) / scale,
                y: ($0.y - minY) / scale,
                t: $0.t - startTime
            )
        }
    }

    private static func resample(_ points: [GesturePoint], count: Int) -> [GesturePoint] {
        guard points.count > 1 else { return points }
        let totalLength = max(pathLength(points), 0.001)
        let interval = totalLength / Double(count - 1)
        var result = [points[0]]
        var distanceSinceLast = 0.0
        var previous = points[0]
        var index = 1

        while index < points.count {
            let current = points[index]
            let segmentLength = distance(previous, current)
            if distanceSinceLast + segmentLength >= interval {
                let ratio = (interval - distanceSinceLast) / max(segmentLength, 0.001)
                let inserted = GesturePoint(
                    x: previous.x + ratio * (current.x - previous.x),
                    y: previous.y + ratio * (current.y - previous.y),
                    t: previous.t + ratio * (current.t - previous.t)
                )
                result.append(inserted)
                previous = inserted
                distanceSinceLast = 0
            } else {
                distanceSinceLast += segmentLength
                previous = current
                index += 1
            }
        }

        while result.count < count {
            result.append(points.last!)
        }
        return Array(result.prefix(count))
    }

    private static func match(_ stored: GestureTemplate, _ candidate: GestureTemplate, threshold: Double) -> GestureMatchResult {
        let count = min(stored.points.count, candidate.points.count)
        guard count > 8 else { return GestureMatchResult(isMatch: false, score: 0) }

        var squaredDistance = 0.0
        for index in 0..<count {
            let a = stored.points[index]
            let b = candidate.points[index]
            let dx = a.x - b.x
            let dy = a.y - b.y
            squaredDistance += dx * dx + dy * dy
        }

        let rmse = sqrt(squaredDistance / Double(count))
        let pointScore = max(0, 1 - rmse * 2.2)
        let pathScore = dynamicPathScore(stored.points, candidate.points)
        let shapeScore = max(pointScore, pathScore)
        let durationScore = ratioScore(stored.duration, candidate.duration)
        let lengthScore = ratioScore(stored.pathLength, candidate.pathLength)
        let speedScore = max(vectorScore(stored.speedProfile, candidate.speedProfile), 0.72)
        let turnScore = vectorScore(stored.turnProfile, candidate.turnProfile)
        let pauseScore = ratioScore(stored.pauseRatio + 0.05, candidate.pauseRatio + 0.05)
        let score = shapeScore * 0.66
            + durationScore * 0.08
            + lengthScore * 0.08
            + speedScore * 0.08
            + turnScore * 0.07
            + pauseScore * 0.03
        return GestureMatchResult(isMatch: score >= threshold, score: score)
    }

    private static func dynamicPathScore(_ first: [GesturePoint], _ second: [GesturePoint]) -> Double {
        guard !first.isEmpty, !second.isEmpty else { return 0 }

        let rows = first.count
        let columns = second.count
        var previous = Array(repeating: Double.infinity, count: columns + 1)
        var current = Array(repeating: Double.infinity, count: columns + 1)
        previous[0] = 0

        for row in 1...rows {
            current[0] = Double.infinity
            for column in 1...columns {
                let cost = distance(first[row - 1], second[column - 1])
                current[column] = cost + min(previous[column], current[column - 1], previous[column - 1])
            }
            swap(&previous, &current)
        }

        let normalized = previous[columns] / Double(rows + columns)
        return max(0, 1 - normalized * 3.0)
    }

    private static func ratioScore(_ a: Double, _ b: Double) -> Double {
        let larger = max(a, b, 0.001)
        let smaller = max(min(a, b), 0.001)
        return max(0, min(1, smaller / larger))
    }

    private static func pathLength(_ points: [GesturePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        return zip(points.dropFirst(), points).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    private static func speedProfile(_ points: [GesturePoint]) -> [Double] {
        guard points.count > 1 else { return [] }
        let speeds = zip(points.dropFirst(), points).map { current, previous in
            distance(current, previous) / max(current.t - previous.t, 0.001)
        }
        let maxSpeed = max(speeds.max() ?? 0.001, 0.001)
        return speeds.map { min($0 / maxSpeed, 1) }
    }

    private static func turnProfile(_ points: [GesturePoint]) -> [Double] {
        guard points.count > 2 else { return [] }
        return (1..<(points.count - 1)).map { index in
            let previous = points[index - 1]
            let current = points[index]
            let next = points[index + 1]
            let a = atan2(current.y - previous.y, current.x - previous.x)
            let b = atan2(next.y - current.y, next.x - current.x)
            let delta = abs(atan2(sin(b - a), cos(b - a)))
            return delta / .pi
        }
    }

    private static func pauseRatio(_ points: [GesturePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        let intervals = zip(points.dropFirst(), points).map { max($0.0.t - $0.1.t, 0) }
        let total = intervals.reduce(0, +)
        guard total > 0 else { return 0 }
        let pauses = intervals.filter { $0 >= 0.18 }.reduce(0, +)
        return pauses / total
    }

    private static func vectorScore(_ a: [Double], _ b: [Double]) -> Double {
        let count = min(a.count, b.count)
        guard count > 0 else { return 1 }
        var total = 0.0
        for index in 0..<count {
            total += abs(a[index] - b[index])
        }
        return max(0, 1 - total / Double(count))
    }

    private static func distance(_ a: GesturePoint, _ b: GesturePoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}

private struct GestureTemplate: Codable {
    var points: [GesturePoint]
    var duration: Double
    var pathLength: Double
    var speedProfile: [Double]
    var turnProfile: [Double]
    var pauseRatio: Double

    init(
        points: [GesturePoint],
        duration: Double,
        pathLength: Double,
        speedProfile: [Double],
        turnProfile: [Double],
        pauseRatio: Double
    ) {
        self.points = points
        self.duration = duration
        self.pathLength = pathLength
        self.speedProfile = speedProfile
        self.turnProfile = turnProfile
        self.pauseRatio = pauseRatio
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        points = try container.decode([GesturePoint].self, forKey: .points)
        duration = try container.decode(Double.self, forKey: .duration)
        pathLength = try container.decode(Double.self, forKey: .pathLength)
        speedProfile = try container.decodeIfPresent([Double].self, forKey: .speedProfile) ?? []
        turnProfile = try container.decodeIfPresent([Double].self, forKey: .turnProfile) ?? []
        pauseRatio = try container.decodeIfPresent(Double.self, forKey: .pauseRatio) ?? 0
    }
}

enum GestureError: Error, LocalizedError {
    case tooShort
    case tooSimple

    var errorDescription: String? {
        switch self {
        case .tooShort:
            L.string("Gesture is too short. Draw a longer continuous motion.")
        case .tooSimple:
            L.string("Gesture is too simple. Add a clear curve or turn so it can be recognized reliably.")
        }
    }
}
