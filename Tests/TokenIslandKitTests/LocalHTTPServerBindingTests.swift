import Network
import XCTest
@testable import TokenIslandKit

/// The hook receiver accepts session events and parks approval prompts that the
/// user then answers from the notch. Reachable off-loopback, that is a way for
/// anyone on the same Wi-Fi to forge those prompts — so the binding is a
/// security property, not a detail.
final class LocalHTTPServerBindingTests: XCTestCase {
    func testListenerParametersAreLoopbackOnly() {
        let parameters = LocalHTTPServer.loopbackParameters()
        XCTAssertEqual(
            parameters.requiredInterfaceType, .loopback,
            "plain NWParameters.tcp binds every interface — the LAN included"
        )
    }

    /// End-to-end: a real listener must serve 127.0.0.1 and refuse this Mac's
    /// own LAN address. Skips when the machine has no non-loopback IPv4.
    func testServerServesLoopbackAndRefusesLANAddress() throws {
        let port: UInt16 = 47_913
        let server = LocalHTTPServer(name: "BindingTest", port: port) { _ in
            HTTPResponse.text("ok")
        }
        try server.start()
        defer { server.stop() }
        // Give NWListener a moment to come up before probing it.
        Thread.sleep(forTimeInterval: 0.4)

        XCTAssertTrue(canConnect(host: "127.0.0.1", port: port), "loopback must work")

        let lanAddress = try XCTUnwrap(Self.primaryLANAddress(), "no LAN address to test against")
        try XCTSkipIf(lanAddress.hasPrefix("127."))
        XCTAssertFalse(
            canConnect(host: lanAddress, port: port),
            "\(lanAddress):\(port) accepted a connection — the server is on the LAN"
        )
    }

    // MARK: - Helpers

    private func canConnect(host: String, port: UInt16, timeout: TimeInterval = 2) -> Bool {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        let ready = expectation(description: "connect \(host)")
        // .ready is often followed by .cancelled on teardown — both fulfil.
        ready.assertForOverFulfill = false
        let succeeded = ConnectionOutcome()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                succeeded.value = true
                ready.fulfill()
            case .failed, .cancelled:
                ready.fulfill()
            default:
                break
            }
        }
        connection.start(queue: .global())
        _ = XCTWaiter().wait(for: [ready], timeout: timeout)
        connection.cancel()
        return succeeded.value
    }

    /// `stateUpdateHandler` runs off this thread, so the flag needs a box.
    private final class ConnectionOutcome: @unchecked Sendable {
        var value = false
    }

    /// This Mac's own non-loopback IPv4, which a LAN peer would use to reach it.
    private static func primaryLANAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard let address = pointer.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address, socklen_t(address.pointee.sa_len),
                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
            ) == 0 else { continue }
            let text = String(cString: host)
            if !text.isEmpty, !text.hasPrefix("127.") { return text }
        }
        return nil
    }
}
