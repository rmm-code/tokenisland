import Foundation

struct DatabaseMigrator {
    func migrate(database: SQLiteDatabase) throws {
        try database.execute("""
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at REAL NOT NULL
        )
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS usage_events (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            provider TEXT NOT NULL,
            source_app TEXT NOT NULL,
            project_name TEXT,
            project_path TEXT,
            model TEXT NOT NULL,
            input_tokens INTEGER NOT NULL,
            output_tokens INTEGER NOT NULL,
            cache_read_tokens INTEGER NOT NULL,
            cache_write_tokens INTEGER NOT NULL,
            total_tokens INTEGER NOT NULL,
            estimated_cost_usd REAL NOT NULL,
            request_id TEXT,
            latency_ms INTEGER,
            session_id TEXT,
            raw_metadata_json TEXT
        )
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_usage_events_timestamp
        ON usage_events(timestamp DESC)
        """)

        try database.execute("""
        CREATE INDEX IF NOT EXISTS idx_usage_events_provider_model
        ON usage_events(provider, model)
        """)

        try database.execute("""
        CREATE TABLE IF NOT EXISTS daily_aggregates (
            day_start REAL NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            project_path TEXT,
            total_tokens INTEGER NOT NULL,
            estimated_cost_usd REAL NOT NULL,
            request_count INTEGER NOT NULL,
            PRIMARY KEY(day_start, provider, model, project_path)
        )
        """)

        try database.execute("""
        INSERT OR IGNORE INTO schema_migrations(version, applied_at)
        VALUES(1, ?)
        """, params: [.double(Date().timeIntervalSince1970)])
    }
}
