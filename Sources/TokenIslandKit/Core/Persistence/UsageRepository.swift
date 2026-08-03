import Foundation

actor UsageRepository {
    private let database: SQLiteDatabase
    private let migrator: DatabaseMigrator
    private let aggregator = UsageAggregator()
    private var isPrepared = false

    init(databaseURL: URL, migrator: DatabaseMigrator = DatabaseMigrator()) {
        self.database = SQLiteDatabase(url: databaseURL)
        self.migrator = migrator
    }

    func prepare() throws {
        guard !isPrepared else { return }
        try database.open()
        try migrator.migrate(database: database)
        isPrepared = true
    }

    func insert(_ event: UsageEvent) throws {
        try insert([event])
    }

    func insert(_ events: [UsageEvent]) throws {
        guard !events.isEmpty else { return }
        try prepare()
        try database.execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for event in events {
                try database.execute("""
                INSERT OR REPLACE INTO usage_events (
                    id, timestamp, provider, source_app, project_name, project_path, model,
                    input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, total_tokens,
                    estimated_cost_usd, request_id, latency_ms, session_id, raw_metadata_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, params: [
                    .text(event.id.uuidString),
                    .double(event.timestamp.timeIntervalSince1970),
                    .text(event.provider.rawValue),
                    .text(event.sourceApp),
                    event.projectName.map(SQLiteValue.text) ?? .null,
                    event.projectPath.map(SQLiteValue.text) ?? .null,
                    .text(event.model),
                    .integer(Int64(event.inputTokens)),
                    .integer(Int64(event.outputTokens)),
                    .integer(Int64(event.cacheReadTokens)),
                    .integer(Int64(event.cacheWriteTokens)),
                    .integer(Int64(event.totalTokens)),
                    .double((event.estimatedCostUSD as NSDecimalNumber).doubleValue),
                    event.requestID.map(SQLiteValue.text) ?? .null,
                    event.latencyMS.map { .integer(Int64($0)) } ?? .null,
                    event.sessionID.map(SQLiteValue.text) ?? .null,
                    event.rawMetadataJSON.map(SQLiteValue.text) ?? .null
                ])
            }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    func recent(limit: Int = 30) throws -> [UsageEvent] {
        try prepare()
        let rows = try database.query("""
        SELECT * FROM usage_events
        ORDER BY timestamp DESC
        LIMIT ?
        """, params: [.integer(Int64(limit))])
        return rows.compactMap(Self.event(from:))
    }

    func events(since date: Date) throws -> [UsageEvent] {
        try prepare()
        let rows = try database.query("""
        SELECT * FROM usage_events
        WHERE timestamp >= ?
        ORDER BY timestamp DESC
        """, params: [.double(date.timeIntervalSince1970)])
        return rows.compactMap(Self.event(from:))
    }

    func summary(now: Date = Date(), calendar: Calendar = .current) throws -> UsageSummary {
        let startOfDay = calendar.startOfDay(for: now)
        let events = try events(since: startOfDay)
        let recentEvents = try recent(limit: 24)
        return aggregator.makeSummary(events: events, recentRequests: recentEvents, now: now, calendar: calendar)
    }

    func deleteAllUsage() throws {
        try prepare()
        try database.execute("DELETE FROM usage_events")
        try database.execute("DELETE FROM daily_aggregates")
    }

    func exportEventsJSON() throws -> Data {
        let events = try recent(limit: 10_000)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(events)
    }

    private static func event(from row: SQLiteRow) -> UsageEvent? {
        guard
            let idString = row.string("id"),
            let id = UUID(uuidString: idString),
            let timestamp = row.double("timestamp"),
            let providerRaw = row.string("provider"),
            let provider = AIProvider(rawValue: providerRaw),
            let sourceApp = row.string("source_app"),
            let model = row.string("model")
        else {
            return nil
        }

        return UsageEvent(
            id: id,
            timestamp: Date(timeIntervalSince1970: timestamp),
            provider: provider,
            sourceApp: sourceApp,
            projectName: row.string("project_name"),
            projectPath: row.string("project_path"),
            model: model,
            inputTokens: row.int("input_tokens") ?? 0,
            outputTokens: row.int("output_tokens") ?? 0,
            cacheReadTokens: row.int("cache_read_tokens") ?? 0,
            cacheWriteTokens: row.int("cache_write_tokens") ?? 0,
            estimatedCostUSD: Decimal(row.double("estimated_cost_usd") ?? 0),
            requestID: row.string("request_id"),
            latencyMS: row.int("latency_ms"),
            sessionID: row.string("session_id"),
            rawMetadataJSON: row.string("raw_metadata_json")
        )
    }
}
