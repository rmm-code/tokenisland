import Foundation
import SQLite3

enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
    case databaseNotOpen

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "Could not open database: \(message)"
        case .prepareFailed(let message):
            "Could not prepare SQL statement: \(message)"
        case .stepFailed(let message):
            "Could not execute SQL statement: \(message)"
        case .bindFailed(let message):
            "Could not bind SQL value: \(message)"
        case .databaseNotOpen:
            "Database is not open."
        }
    }
}

enum SQLiteValue: Sendable {
    case null
    case integer(Int64)
    case double(Double)
    case text(String)
}

struct SQLiteRow: Sendable {
    let values: [String: SQLiteValue]

    func string(_ key: String) -> String? {
        if case .text(let value)? = values[key] { return value }
        return nil
    }

    func int(_ key: String) -> Int? {
        if case .integer(let value)? = values[key] { return Int(value) }
        if case .double(let value)? = values[key] { return Int(value) }
        return nil
    }

    func int64(_ key: String) -> Int64? {
        if case .integer(let value)? = values[key] { return value }
        return nil
    }

    func double(_ key: String) -> Double? {
        if case .double(let value)? = values[key] { return value }
        if case .integer(let value)? = values[key] { return Double(value) }
        return nil
    }
}

final class SQLiteDatabase {
    private let url: URL
    private var handle: OpaquePointer?
    private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) {
        self.url = url
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func open() throws {
        guard handle == nil else { return }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteError.openFailed(message)
        }
        handle = database
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    func execute(_ sql: String, params: [SQLiteValue] = []) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(params, to: statement)

        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                return
            }
            if status == SQLITE_ROW {
                continue
            }
            throw SQLiteError.stepFailed(lastErrorMessage)
        }
    }

    func query(_ sql: String, params: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(params, to: statement)

        var rows: [SQLiteRow] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                break
            }
            guard status == SQLITE_ROW else {
                throw SQLiteError.stepFailed(lastErrorMessage)
            }
            rows.append(readRow(from: statement))
        }
        return rows
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let handle else { throw SQLiteError.databaseNotOpen }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepareFailed(lastErrorMessage)
        }
        return statement
    }

    private func bind(_ params: [SQLiteValue], to statement: OpaquePointer) throws {
        for (index, value) in params.enumerated() {
            let position = Int32(index + 1)
            let status: Int32
            switch value {
            case .null:
                status = sqlite3_bind_null(statement, position)
            case .integer(let value):
                status = sqlite3_bind_int64(statement, position, value)
            case .double(let value):
                status = sqlite3_bind_double(statement, position, value)
            case .text(let value):
                status = sqlite3_bind_text(statement, position, value, -1, transientDestructor)
            }
            guard status == SQLITE_OK else {
                throw SQLiteError.bindFailed(lastErrorMessage)
            }
        }
    }

    private func readRow(from statement: OpaquePointer) -> SQLiteRow {
        let count = sqlite3_column_count(statement)
        var values: [String: SQLiteValue] = [:]
        for index in 0..<count {
            let name = String(cString: sqlite3_column_name(statement, index))
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                values[name] = .integer(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                values[name] = .double(sqlite3_column_double(statement, index))
            case SQLITE_TEXT:
                let text = sqlite3_column_text(statement, index).map { String(cString: $0) }
                values[name] = text.map(SQLiteValue.text) ?? .null
            default:
                values[name] = .null
            }
        }
        return SQLiteRow(values: values)
    }

    private var lastErrorMessage: String {
        guard let handle else { return "database is not open" }
        return String(cString: sqlite3_errmsg(handle))
    }
}
