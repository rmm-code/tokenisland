import XCTest
@testable import TokenIslandKit

final class UsagePipelineTests: XCTestCase {
    func testAggregatorBuildsProviderPercentages() {
        let events = [
            UsageEvent(
                provider: .claude,
                sourceApp: "Claude Code",
                model: "claude-sonnet",
                inputTokens: 600,
                outputTokens: 100,
                estimatedCostUSD: 0.01
            ),
            UsageEvent(
                provider: .gpt,
                sourceApp: "Codex CLI",
                model: "gpt-4.1",
                inputTokens: 250,
                outputTokens: 50,
                estimatedCostUSD: 0.01
            )
        ]

        let summary = UsageAggregator().makeSummary(
            events: events,
            recentRequests: events,
            now: Date(),
            calendar: .current
        )

        XCTAssertEqual(summary.totalTokensToday, 1_000)
        XCTAssertEqual(summary.provider(.claude).totalTokens, 700)
        XCTAssertEqual(summary.provider(.gpt).totalTokens, 300)
        XCTAssertEqual(summary.provider(.claude).percentage, 0.7, accuracy: 0.001)
        XCTAssertEqual(summary.provider(.gpt).percentage, 0.3, accuracy: 0.001)
    }

    func testOTLPNormalizerReadsSpanAttributes() throws {
        let payload = """
        {
          "resourceSpans": [{
            "resource": {
              "attributes": [
                {"key": "service.name", "value": {"stringValue": "Claude Code"}}
              ]
            },
            "scopeSpans": [{
              "spans": [{
                "traceId": "abc",
                "spanId": "def",
                "timeUnixNano": "1710000000000000000",
                "attributes": [
                  {"key": "gen_ai.system", "value": {"stringValue": "anthropic"}},
                  {"key": "gen_ai.request.model", "value": {"stringValue": "claude-3-5-sonnet"}},
                  {"key": "gen_ai.usage.input_tokens", "value": {"intValue": "1200"}},
                  {"key": "gen_ai.usage.output_tokens", "value": {"intValue": "400"}},
                  {"key": "project.path", "value": {"stringValue": "/tmp/project"}}
                ]
              }]
            }]
          }]
        }
        """.data(using: .utf8)!

        let events = try OTLPNormalizer().events(
            from: payload,
            defaultSource: "Local OTLP",
            storePromptText: false
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].provider, .claude)
        XCTAssertEqual(events[0].sourceApp, "Claude Code")
        XCTAssertEqual(events[0].model, "claude-3-5-sonnet")
        XCTAssertEqual(events[0].inputTokens, 1_200)
        XCTAssertEqual(events[0].outputTokens, 400)
        XCTAssertEqual(events[0].projectPath, "/tmp/project")
    }

    func testOTLPNormalizerHonorsMetadataStorageOptions() throws {
        let payload = """
        {
          "input_tokens": 10,
          "output_tokens": 5,
          "model": "claude-3-5-sonnet",
          "service.name": "Claude Code",
          "project.path": "/Users/example/private-project",
          "prompt": "private prompt text"
        }
        """.data(using: .utf8)!

        let events = try OTLPNormalizer().events(
            from: payload,
            defaultSource: "Local OTLP",
            storageOptions: UsageMetadataStorageOptions(
                storePromptText: false,
                storeSourceApp: false,
                storeProjectPath: false,
                storeRawMetadataJSON: false
            )
        )

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].sourceApp, "Source hidden")
        XCTAssertNil(events[0].projectPath)
        XCTAssertNil(events[0].rawMetadataJSON)

        let debugEvents = try OTLPNormalizer().events(
            from: payload,
            defaultSource: "Local OTLP",
            storageOptions: UsageMetadataStorageOptions(
                storePromptText: false,
                storeSourceApp: true,
                storeProjectPath: true,
                storeRawMetadataJSON: true
            )
        )

        XCTAssertEqual(debugEvents[0].sourceApp, "Claude Code")
        XCTAssertEqual(debugEvents[0].projectPath, "/Users/example/private-project")
        XCTAssertTrue(debugEvents[0].rawMetadataJSON?.contains("[redacted]") == true)
        XCTAssertFalse(debugEvents[0].rawMetadataJSON?.contains("private prompt text") == true)
    }

    func testOTLPNormalizerReadsCurrentProviderAttributeAndModelFallback() throws {
        let geminiPayload = """
        {
          "gen_ai.provider.name": "gcp.gemini",
          "gen_ai.request.model": "gemini-3.5-flash",
          "gen_ai.usage.input_tokens": 10,
          "gen_ai.usage.output_tokens": 5
        }
        """.data(using: .utf8)!
        let bedrockPayload = """
        {
          "gen_ai.provider.name": "aws.bedrock",
          "gen_ai.request.model": "anthropic.claude-sonnet-5",
          "gen_ai.usage.input_tokens": 10,
          "gen_ai.usage.output_tokens": 5
        }
        """.data(using: .utf8)!

        let gemini = try OTLPNormalizer().events(from: geminiPayload, defaultSource: "", storePromptText: false)
        let bedrock = try OTLPNormalizer().events(from: bedrockPayload, defaultSource: "", storePromptText: false)

        XCTAssertEqual(gemini.first?.provider, .gemini)
        XCTAssertEqual(bedrock.first?.provider, .claude)
    }

    func testCurrentModelRatesAndUnknownModelsDoNotFabricateCost() {
        let estimator = TokenCostEstimator()
        XCTAssertEqual(
            estimator.estimate(
                provider: .gpt,
                model: "gpt-5.6-sol",
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheReadTokens: 0,
                cacheWriteTokens: 0
            ),
            35
        )
        XCTAssertEqual(
            estimator.estimate(
                provider: .gpt,
                model: "gpt-5.3-codex",
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheReadTokens: 0,
                cacheWriteTokens: 0
            ),
            15.75
        )
        XCTAssertEqual(
            estimator.estimate(
                provider: .unknown,
                model: "new-vendor-model",
                inputTokens: 1_000_000,
                outputTokens: 1_000_000,
                cacheReadTokens: 0,
                cacheWriteTokens: 0
            ),
            0
        )
    }
}
