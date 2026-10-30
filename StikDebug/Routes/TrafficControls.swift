import CoreLocation
import Foundation

// MARK: - TrafficControls
//
// Real traffic lights, stop signs and yield signs along a route, from
// OpenStreetMap through Overpass. The query is the same one as the
// `openstreetmap.org/traffic-controls` endpoint in sitescrape-catalog, which
// locspoof uses on the PC; the phone cannot run sitescrape, so it asks
// Overpass itself.
//
// Results are cached by map tile (about 1 km) in Caches, so only tiles never
// seen before are fetched. A route through a familiar area needs no network,
// and a slow Overpass only costs the first time.
//
// nil from `along` means "unknown": the motion plan then guesses stops from
// junctions, as before.

struct TrafficControl: Codable, Hashable {
    let id: Int
    let lat: Double
    let lon: Double
    /// signal, stop, all_way_stop or give_way
    let kind: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

enum TrafficControls {
    /// Tile edge in degrees. About 1.1 km north-south.
    static let tileDegrees = 0.01
    /// Lights and signs rarely move. Refetch a tile after this long anyway.
    static let cacheLifetime: TimeInterval = 30 * 24 * 3600
    /// A sign within this distance of the route counts as on it. OSRM routes
    /// follow the same OSM ways, so anything wider catches side streets.
    static let nearDistance: CLLocationDistance = 8
    /// Tiles per Overpass query.
    private static let batch = 150

    /// Shared and often overloaded; which one is fast changes by the hour, so
    /// the query goes to all of them and the first good answer wins.
    private static let endpoints = [
        "https://overpass-api.de/api/interpreter",
        "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
        "https://overpass.private.coffee/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter"
    ]
    private static let userAgent = "locspoof-ios/1.0 (personal location simulator)"

    struct Tile: Hashable, Comparable {
        let y: Int
        let x: Int

        init(y: Int, x: Int) {
            self.y = y
            self.x = x
        }

        init(_ lat: Double, _ lon: Double) {
            y = Int((lat / TrafficControls.tileDegrees).rounded(.down))
            x = Int((lon / TrafficControls.tileDegrees).rounded(.down))
        }

        static func < (a: Tile, b: Tile) -> Bool { (a.y, a.x) < (b.y, b.x) }

        /// south, west, north, east
        var box: (Double, Double, Double, Double) {
            let s = Double(y) * TrafficControls.tileDegrees
            let w = Double(x) * TrafficControls.tileDegrees
            return (s, w, s + TrafficControls.tileDegrees, w + TrafficControls.tileDegrees)
        }
    }

    // MARK: - Public

    static func along(_ points: [CLLocationCoordinate2D]) async -> [TrafficControl]? {
        guard points.count >= 2 else { return nil }
        let tiles = tiles(for: points).sorted()
        let missing = tiles.filter { load($0) == nil }
        if !missing.isEmpty {
            LogManager.shared.addInfoLog("Traffic lights: fetching \(missing.count) of \(tiles.count) map tiles")
            var start = 0
            while start < missing.count {
                let chunk = Array(missing[start..<min(start + batch, missing.count)])
                guard let found = await fetch(chunk) else {
                    LogManager.shared.addInfoLog("Traffic lights: Overpass unavailable, guessing stops")
                    return nil
                }
                var byTile = Dictionary(uniqueKeysWithValues: chunk.map { ($0, [TrafficControl]()) })
                for control in found {
                    byTile[Tile(control.lat, control.lon), default: []].append(control)
                }
                // An empty tile is cached too: no lights there is an answer.
                for tile in chunk {
                    save(tile, byTile[tile] ?? [])
                }
                start += batch
            }
        }

        var all: [TrafficControl] = []
        for tile in tiles {
            guard let cached = load(tile) else { return nil }
            all += cached
        }
        return near(points, all)
    }

    // MARK: - Tiles

    /// Every tile the route passes through, sampling each segment finely
    /// enough that a diagonal cannot skip the corner of one.
    static func tiles(for points: [CLLocationCoordinate2D]) -> Set<Tile> {
        var tiles = Set<Tile>()
        let step = tileDegrees / 4
        for (a, b) in zip(points, points.dropFirst()) {
            let span = max(abs(b.latitude - a.latitude), abs(b.longitude - a.longitude))
            let n = max(1, Int(span / step) + 1)
            for i in 0...n {
                let f = Double(i) / Double(n)
                tiles.insert(Tile(a.latitude + (b.latitude - a.latitude) * f, a.longitude + (b.longitude - a.longitude) * f))
            }
        }
        return tiles
    }

    /// Controls within `maxDistance` of the route line. Segments are bucketed
    /// by tile so each control is only checked against the few around it.
    static func near(_ points: [CLLocationCoordinate2D], _ controls: [TrafficControl], maxDistance: CLLocationDistance = nearDistance) -> [TrafficControl] {
        guard points.count >= 2 else { return [] }
        var buckets: [Tile: [Int]] = [:]
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let lo = Tile(min(a.latitude, b.latitude), min(a.longitude, b.longitude))
            let hi = Tile(max(a.latitude, b.latitude), max(a.longitude, b.longitude))
            for y in lo.y...hi.y {
                for x in lo.x...hi.x {
                    buckets[Tile(y: y, x: x), default: []].append(i)
                }
            }
        }

        return controls.filter { control in
            // Metres per degree here; flat-earth is fine over a few metres.
            let my = 111_320.0
            let mx = 111_320.0 * cos(control.lat * .pi / 180)
            let home = Tile(control.lat, control.lon)
            var best = Double.infinity
            for dy in -1...1 {
                for dx in -1...1 {
                    for i in buckets[Tile(y: home.y + dy, x: home.x + dx)] ?? [] {
                        let a = points[i], b = points[i + 1]
                        let ax = (a.longitude - control.lon) * mx, ay = (a.latitude - control.lat) * my
                        let bx = (b.longitude - control.lon) * mx, by = (b.latitude - control.lat) * my
                        let vx = bx - ax, vy = by - ay
                        let length2 = vx * vx + vy * vy
                        let t = length2 == 0 ? 0 : max(0, min(1, -(ax * vx + ay * vy) / length2))
                        best = min(best, hypot(ax + vx * t, ay + vy * t))
                    }
                }
            }
            return best <= maxDistance
        }
    }

    // MARK: - Cache

    private struct CachedTile: Codable {
        let fetchedAt: Date
        let controls: [TrafficControl]
    }

    private static let cacheDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("osm-controls", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func cacheURL(_ tile: Tile) -> URL {
        cacheDirectory.appendingPathComponent("\(tile.y)_\(tile.x).json")
    }

    private static func load(_ tile: Tile) -> [TrafficControl]? {
        guard let data = try? Data(contentsOf: cacheURL(tile)),
              let cached = try? JSONDecoder().decode(CachedTile.self, from: data),
              Date().timeIntervalSince(cached.fetchedAt) < cacheLifetime else {
            return nil
        }
        return cached.controls
    }

    private static func save(_ tile: Tile, _ controls: [TrafficControl]) {
        guard let data = try? JSONEncoder().encode(CachedTile(fetchedAt: Date(), controls: controls)) else { return }
        try? data.write(to: cacheURL(tile), options: .atomic)
    }

    // MARK: - Overpass

    static func query(_ tiles: [Tile]) -> String {
        let clauses = tiles.map { tile -> String in
            let (s, w, n, e) = tile.box
            let box = [s, w, n, e].map { String(format: "%.6f", $0) }.joined(separator: ",")
            return "  node[\"highway\"~\"^(traffic_signals|stop|give_way)$\"](\(box));"
        }
        return "[out:json][timeout:60];\n(\n\(clauses.joined(separator: "\n"))\n);\nout body;"
    }

    static func classify(_ tags: [String: String]) -> String? {
        switch tags["highway"] {
        case "traffic_signals": return "signal"
        case "stop": return tags["stop"] == "all" ? "all_way_stop" : "stop"
        case "give_way": return "give_way"
        default: return nil
        }
    }

    private static func fetch(_ tiles: [Tile]) async -> [TrafficControl]? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard let encoded = query(tiles).addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        let body = Data("data=\(encoded)".utf8)

        return await withTaskGroup(of: [TrafficControl]?.self) { group in
            for endpoint in endpoints {
                group.addTask { await fetch(endpoint, body: body) }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }
    }

    private static func fetch(_ endpoint: String, body: Data) async -> [TrafficControl]? {
        guard let url = URL(string: endpoint) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // A query that runs out of time still comes back as 200, with the
        // reason in `remark`. That is a failure, not an empty road.
        if let remark = json["remark"] as? String, remark.localizedCaseInsensitiveContains("error") {
            return nil
        }
        var seen = Set<Int>()
        var controls: [TrafficControl] = []
        for element in json["elements"] as? [[String: Any]] ?? [] {
            guard element["type"] as? String == "node",
                  let id = (element["id"] as? NSNumber)?.intValue,
                  let lat = (element["lat"] as? NSNumber)?.doubleValue,
                  let lon = (element["lon"] as? NSNumber)?.doubleValue,
                  let kind = classify(element["tags"] as? [String: String] ?? [:]),
                  seen.insert(id).inserted else {
                continue
            }
            controls.append(TrafficControl(id: id, lat: lat, lon: lon, kind: kind))
        }
        return controls
    }
}
