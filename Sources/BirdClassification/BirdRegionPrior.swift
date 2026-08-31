import Foundation

protocol BirdPriorWeighting: Sendable {
    func weight(for index: Int) -> Float
}

struct BirdRegionMatch: Equatable, Sendable {
    let code: String
    let name: String
}

final class BirdRegionPrior: BirdPriorWeighting, @unchecked Sendable {
    private struct Region: Sendable {
        let match: BirdRegionMatch
        let rings: [[CGPoint]]
    }

    private struct State {
        var region: BirdRegionMatch?
        var levels: [Int: [UInt8]]?
        var month: Int?
    }

    private let countryLevels: [Int: UInt8]
    private let regionTables: [String: [Int: [UInt8]]]
    private let regions: [Region]
    private let lock = NSLock()
    private var state = State()

    init(priorContents: String, polygonContents: String) throws {
        let parsedPrior = try Self.parsePrior(priorContents)
        countryLevels = parsedPrior.country
        regionTables = parsedPrior.regions
        regions = try Self.parseRegions(polygonContents)
    }

    var activeRegion: BirdRegionMatch? {
        lock.withLock { state.region }
    }

    func update(latitude: Double, longitude: Double, month: Int) {
        let region = resolveRegion(longitude: longitude, latitude: latitude)
        lock.withLock {
            state.region = region?.match
            state.levels = region.flatMap { regionTables[$0.match.code] }
            state.month = (1 ... 12).contains(month) ? month : nil
        }
    }

    func clear() {
        lock.withLock { state = State() }
    }

    func weight(for index: Int) -> Float {
        let snapshot = lock.withLock { state }
        guard let levels = snapshot.levels,
              let month = snapshot.month
        else { return 1 }

        guard let values = levels[index], values.count == 13 else {
            return countryLevels[index] == nil ? 0.05 : 0.15
        }
        let previousMonth = month == 1 ? 12 : month - 1
        let nextMonth = month == 12 ? 1 : month + 1
        let neighboringLevel = max(values[previousMonth], values[nextMonth])
        let blendedLevel = max(Float(values[month]), Float(neighboringLevel) * 0.5)
        if blendedLevel > 0 {
            return 1 + 6 * blendedLevel / 255
        }
        if values[0] > 0 {
            return 0.22
        }
        return countryLevels[index] == nil ? 0.05 : 0.15
    }

    static func loadBundled(bundle: Bundle = .main) throws -> BirdRegionPrior {
        guard let priorURL = bundle.url(forResource: "bird_region_prior", withExtension: "txt"),
              let polygonURL = bundle.url(forResource: "china_provinces_poly", withExtension: "txt")
        else { throw BirdRegionPriorError.resourcesMissing }
        return try BirdRegionPrior(
            priorContents: String(contentsOf: priorURL, encoding: .utf8),
            polygonContents: String(contentsOf: polygonURL, encoding: .utf8)
        )
    }

    private func resolveRegion(longitude: Double, latitude: Double) -> Region? {
        regions.first { region in
            region.rings.contains { Self.contains(longitude, latitude, ring: $0) }
        }
    }

    private static func contains(_ longitude: Double, _ latitude: Double, ring: [CGPoint]) -> Bool {
        guard ring.count >= 4 else { return false }
        let bounds = ring.reduce(into: CGRect.null) { result, point in
            result = result.union(CGRect(origin: point, size: .zero))
        }
        guard bounds.contains(CGPoint(x: longitude, y: latitude)) else { return false }

        var inside = false
        var previous = ring.count - 1
        for index in ring.indices {
            let currentPoint = ring[index]
            let previousPoint = ring[previous]
            if (currentPoint.y > latitude) != (previousPoint.y > latitude) {
                let intersection = (previousPoint.x - currentPoint.x)
                    * (latitude - currentPoint.y) / (previousPoint.y - currentPoint.y)
                    + currentPoint.x
                if longitude < intersection {
                    inside.toggle()
                }
            }
            previous = index
        }
        return inside
    }
}

private extension BirdRegionPrior {
    static func parsePrior(
        _ contents: String
    ) throws -> (country: [Int: UInt8], regions: [String: [Int: [UInt8]]]) {
        let lines = contents.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first?.hasPrefix("v1|") == true else {
            throw BirdRegionPriorError.invalidPriorHeader
        }
        var country: [Int: UInt8] = [:]
        var regionTables: [String: [Int: [UInt8]]] = [:]
        var index = 1
        while index < lines.count {
            let fields = lines[index].split(separator: "|", omittingEmptySubsequences: false)
            index += 1
            switch fields.first {
            case "C":
                country = try parseCountryBlock(lines, index: &index)
            case "R":
                let block = try parseRegionBlock(fields, lines: lines, index: &index)
                regionTables[block.code] = block.table
            default:
                continue
            }
        }
        return (country, regionTables)
    }

    static func parseCountryBlock(_ lines: [String], index: inout Int) throws -> [Int: UInt8] {
        guard index < lines.count, let count = Int(lines[index]) else {
            throw BirdRegionPriorError.invalidPriorRow
        }
        index += 1
        var country: [Int: UInt8] = [:]
        for _ in 0 ..< count {
            guard index < lines.count, let entry = parseCountryRow(lines[index]) else {
                throw BirdRegionPriorError.invalidPriorRow
            }
            country[entry.index] = entry.level
            index += 1
        }
        return country
    }

    static func parseRegionBlock(
        _ fields: [Substring],
        lines: [String],
        index: inout Int
    ) throws -> (code: String, table: [Int: [UInt8]]) {
        guard fields.count >= 4, let count = Int(fields[3]) else {
            throw BirdRegionPriorError.invalidPriorRow
        }
        var table: [Int: [UInt8]] = [:]
        for _ in 0 ..< count {
            guard index < lines.count, let entry = parseRegionRow(lines[index]) else {
                throw BirdRegionPriorError.invalidPriorRow
            }
            table[entry.index] = entry.levels
            index += 1
        }
        return (String(fields[1]), table)
    }

    private static func parseRegions(_ contents: String) throws -> [Region] {
        var regions: [Region] = []
        var currentMatch: BirdRegionMatch?
        var rings: [[CGPoint]] = []
        let finishRegion = {
            if let currentMatch, !rings.isEmpty {
                regions.append(Region(match: currentMatch, rings: rings))
            }
        }

        for line in contents.split(whereSeparator: \.isNewline).map(String.init) {
            if line == "v1" {
                continue
            }
            if line.hasPrefix("P|") {
                finishRegion()
                let fields = line.split(separator: "|", omittingEmptySubsequences: false)
                guard fields.count >= 3 else { throw BirdRegionPriorError.invalidPolygonRow }
                currentMatch = BirdRegionMatch(code: String(fields[1]), name: String(fields[2]))
                rings = []
            } else {
                let points = line.split(separator: ";").compactMap { pair -> CGPoint? in
                    let values = pair.split(separator: ",")
                    guard values.count == 2,
                          let longitude = Double(values[0]),
                          let latitude = Double(values[1])
                    else { return nil }
                    return CGPoint(x: longitude, y: latitude)
                }
                guard currentMatch != nil, points.count >= 4 else {
                    throw BirdRegionPriorError.invalidPolygonRow
                }
                rings.append(points)
            }
        }
        finishRegion()
        let priorityCodes = Set(["810000", "820000", "710000"])
        return regions.sorted { priorityCodes.contains($0.match.code) && !priorityCodes.contains($1.match.code) }
    }

    static func parseCountryRow(_ row: String) -> (index: Int, level: UInt8)? {
        let fields = row.split(separator: " ")
        guard fields.count == 2,
              let index = Int(fields[0]),
              let level = UInt8(fields[1], radix: 16)
        else { return nil }
        return (index, level)
    }

    static func parseRegionRow(_ row: String) -> (index: Int, levels: [UInt8])? {
        let fields = row.split(separator: " ")
        guard fields.count == 2, let index = Int(fields[0]), fields[1].count == 26 else { return nil }
        var levels: [UInt8] = []
        for offset in stride(from: 0, to: 26, by: 2) {
            let start = fields[1].index(fields[1].startIndex, offsetBy: offset)
            let end = fields[1].index(start, offsetBy: 2)
            guard let level = UInt8(fields[1][start ..< end], radix: 16) else { return nil }
            levels.append(level)
        }
        return (index, levels)
    }
}

enum BirdRegionPriorError: LocalizedError {
    case resourcesMissing
    case invalidPriorHeader
    case invalidPriorRow
    case invalidPolygonRow

    var errorDescription: String? {
        switch self {
        case .resourcesMissing: "鸟种地理先验资源未安装"
        case .invalidPriorHeader: "鸟种地理先验版本无效"
        case .invalidPriorRow: "鸟种地理先验数据损坏"
        case .invalidPolygonRow: "省界数据损坏"
        }
    }
}
