import XCTest
@testable import TokenIslandKit

final class SQLiteDatabaseTests: XCTestCase {
    func testExecuteDrainsStatementsThatReturnRows() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenIsland-\(UUID().uuidString).sqlite")
        let database = SQLiteDatabase(url: url)

        try database.open()
        try database.execute("PRAGMA journal_mode = WAL")
        try database.execute("SELECT 1")

        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }
}
