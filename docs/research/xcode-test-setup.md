# Running the iOS tests from the terminal

Research date: 2026-10-16. Installed tools: Xcode 27.0 (27A266a), iOS 27.0 simulator runtime, xcresulttool version 25115 (`xcodebuild -version`, `xcrun simctl list runtimes`, `xcrun xcresulttool --version`).

The question is which parts of `ios/scripts/test.sh` Xcode already does, and which parts a tool could do. Some claims below rest on a probe. The probe is a small Swift package in a scratch folder, tested with `xcodebuild test -destination 'platform=macOS'`. It is not the iOS simulator, so those results are marked "probe, macOS".

## 1. xcodebuild flags

All flags below exist in the installed Xcode (`xcodebuild -help`, `man xcodebuild`).

- **Time limits.** `-test-timeouts-enabled YES` turns on per-test limits, and it overrides the test plan (`man xcodebuild`). `-default-test-execution-time-allowance` sets the limit for each test. `-maximum-test-execution-time-allowance` caps it, even for a test that asks for more. The smallest value is 60 seconds, and Xcode rounds up to whole minutes ([Organizing tests](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback), [executionTimeAllowance](https://developer.apple.com/documentation/xctest/xctestcase/executiontimeallowance)).
- **Do the limits apply to Swift Testing?** Apple's pages talk only about XCTest. The probe shows that they do apply. A Swift Testing test that slept 150 seconds failed after 60 seconds with "Time limit was exceeded: 60.000 seconds". The other tests still passed. The result bundle named the test, `Slow/hangs()`, with "Test exceeded execution time allowance of 1 minute" (probe, macOS). Swift Testing has its own `.timeLimit` trait. The library uses the shortest of all limits, rounds to one minute, and can take a maximum from its configuration ([Limiting execution time](https://developer.apple.com/documentation/testing/limitingexecutiontime), `adjustedTimeLimit` in [TimeLimitTrait.swift](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Traits/TimeLimitTrait.swift)). The way Xcode passes its allowance into that configuration is not public (unconfirmed). On a timeout, the library cancels the test's task ([Limiting execution time](https://developer.apple.com/documentation/testing/limitingexecutiontime)). A test that ignores cancellation may need Xcode to kill the process. The log then said "Restarting after unexpected exit, crash, or test timeout" (probe, macOS).
- **Hangs outside a test.** No flag limits the whole run. `-destination-timeout` only limits the search for the device, and its default is 30 seconds (`man xcodebuild`). macOS has no `timeout` command (`which timeout` finds nothing).
- **Parallel testing.** `-parallel-testing-enabled YES|NO` overrides the scheme. `-parallel-testing-worker-count` sets the exact number of test runners (`man xcodebuild`). Swift Testing runs tests in parallel with task groups, and they generally run in one process ([Parallelization](https://developer.apple.com/documentation/testing/parallelization)). An Apple engineer wrote in July 2026 that "xcodebuild and Swift Testing do not currently support multi-process parallelization" ([forum thread 838772](https://developer.apple.com/forums/thread/838772)). So worker count and simulator clones only matter for XCTest, which means the UI tests here. In the probe, `-parallel-testing-enabled NO` ran the Swift Testing tests one after another (4.1 s instead of 2.1 s). With `YES`, the console output changed to a different format: `Test case 'Par/b()' passed on 'My Mac - xctest (56278)'` (probe, macOS).
- **Diagnostics.** `-collect-test-diagnostics on-failure|never` overrides the test plan (`man xcodebuild`). The test plan can also set this ([Organizing tests](https://developer.apple.com/documentation/xcode/organizing-tests-to-improve-feedback)).
- **Selecting tests.** `-only-testing` and `-skip-testing` take `Target/Suite/function()` for Swift Testing ([Running tests](https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results)). The probe confirmed `-only-testing:ProbeTests/Slow/quick()`. `-enumerate-tests -test-enumeration-style flat` prints these identifiers without running anything (probe, macOS).- **Repeats.** `-test-iterations`, `-retry-tests-on-failure` and `-run-tests-until-failure` exist (`xcodebuild -help`). In Xcode 27, repetition repeats single Swift Testing tests, and no longer the whole plan ([Xcode 27 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes)). Retrying on failure hides flaky tests, so it suits a hunt for flakes, not the normal run.
- **`-quiet`.** It prints only warnings and errors (`man xcodebuild`). In the probe it still printed `IDETestOperationsObserverDebug` lines and a "Please file a bug" warning, so it does not make a clean summary.
- **`-resultBundlePath`.** It writes a `.xcresult` bundle to a known path. Without it, the bundle lands in `DerivedData/Logs/Test` (probe).

## 2. Result bundles instead of grep

`xcrun xcresulttool get test-results summary --path X.xcresult` returns JSON. It holds the counts and a `testFailures` list, and each failure has `testIdentifierString` and `failureText` (`xcrun xcresulttool get test-results summary --schema`). `get test-results tests` returns the tree of tests, with a result and a source location for each failure. `get build-results` returns the build errors as JSON with `issueType`, `message` and `sourceURL` (`xcrun xcresulttool get build-results --help`).

The probe added a `#require` without `try`. The log showed `macro expansion #require:1:1: error:`, which the script's grep `^/.*: error: ` misses. `get build-results` reported it as a "Swift Compiler Error" with the message (probe, macOS). Its `sourceURL` points to the generated macro file, not to the test file.

The log is a weak base for parsing. Swift Testing prints SF Symbols characters on macOS and Unicode marks elsewhere (`Event.Symbol.swift` in [swift-testing](https://github.com/swiftlang/swift-testing/blob/main/Sources/Testing/Events/Recorder/Event.Symbol.swift)). The format also changes when parallel testing is on (probe, macOS). The result bundle does not have these problems.

## 3. Formatters

- **xcbeautify** is maintained. Release 3.2.1 came out on 2026-04-04, with commits in August 2026 (`gh api repos/cpisciotta/xcbeautify`). It installs with `brew install xcbeautify` (`brew info xcbeautify`). It parses Swift Testing output: its source has capture groups such as `SwiftTestingTestFailedCaptureGroup` ([CaptureGroups.swift](https://github.com/cpisciotta/xcbeautify/blob/main/Sources/XcbeautifyLib/CaptureGroups.swift)). It also writes JUnit ([README](https://github.com/cpisciotta/xcbeautify)). It still reads the log, so it has the same weakness as grep.
- **xcpretty** had its last release, v0.4.1, in March 2025 (`gh api repos/xcpretty/xcpretty/tags`). Swift Testing support is unconfirmed. Do not use it.

## 4. Simulators for parallel checkouts

- `simctl create` and `simctl clone <device> <new name>` make a new device (`xcrun simctl help clone`). One device per worktree means runs never share a test host. Then the lock is not needed. The memory cost of several booted simulators is unconfirmed.
- Parallel XCTest clones a simulator. Xcode makes the clones and deletes them, and the original only serves as a template ([WWDC18 session 403](https://developer.apple.com/videos/play/wwdc2018/403/); only confirmed through [notes on the session](https://wwdcnotes.com/notes/wwdc18/403)). This does not help Swift Testing, because it does not run in several processes (see section 1).
- **"Timed out waiting for AX loaded notification".** Apple has not answered the forum threads ([656364](https://developer.apple.com/forums/thread/656364), [818427](https://developer.apple.com/forums/thread/818427)). The cause is unconfirmed. One user suspected a timeout on a busy build machine ([fastlane issue 11469](https://github.com/fastlane/fastlane/issues/11469)). Other reports blame a simulator that another tool uses at the same time, or stale simulator state (unconfirmed, secondary sources). A safe setup is a separate simulator for UI tests, erased and booted before the run, with parallel testing off. This setup is untested here.

## 5. Swift Testing parallelism

Tests run in parallel by default ([Parallelization](https://developer.apple.com/documentation/testing/parallelization)). `.serialized` on a suite runs that suite's tests one after another. It does not change how they run next to unrelated tests (same page). Apple advises refactoring tests before you serialize them. WWDC24 shows a shared global variable as code that is "not concurrency-safe" ([Go further with Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10195/)). The test plan value `swiftTestingOnly` runs only the Swift Testing tests in parallel. Tuist's source describes the three values ([TestableTarget.swift](https://github.com/tuist/tuist/blob/main/cli/Sources/ProjectDescription/TestableTarget.swift)). Apple does not document them (unconfirmed). Swift Testing has no lock that spans suites, so state shared across suites needs isolation in the code. In this repo, `SupabaseServerTests.swift` has `nonisolated(unsafe) static var count`, which is worth a look.

## 6. Existing tools

- **fastlane `run_tests` (scan).** It is maintained, with release 2.241.1 on 2026-10-15 (`gh api repos/fastlane/fastlane`). It wraps xcodebuild and adds retries, JUnit/HTML reports and simulator reset ([docs](https://docs.fastlane.tools/actions/run_tests/)). It uses xcbeautify when installed, and xcpretty otherwise (`scan/lib/scan/options.rb`). It needs Ruby and a gem install. It has no lock across checkouts. It adds little here.
- **Tuist.** `tuist xcodebuild test` adds selective testing, which reruns only targets whose hash changed. It needs a Tuist account and project (Tuist docs, `server/priv/docs/es/guides/features/selective-testing/xcode-project.md` in [tuist/tuist](https://github.com/tuist/tuist)). This repo has a single unit test target, so selection by target saves nothing.
- **XcodeBuildMCP**, now **MobileBuildMCP** (`getsentry/MobileBuildMCP`). It is maintained, with v2.7.1 on 2026-09-23. It installs through Homebrew or npm and needs Node 18 when installed through npm ([README](https://github.com/getsentry/MobileBuildMCP)). It offers an MCP server and a CLI for agents, it reads result bundles (`src/utils/xcresult-test-failures.ts`), and it sends error telemetry to Sentry. It does not stop two checkouts from sharing a simulator (unconfirmed).
- **Apple's own.** Xcode ships `xcrun mcpbridge` and `xcrun mcp-server` (`xcrun mcpbridge --help`). They need Xcode open with the project, and the setting "Allow external agents to use Xcode tools" turned on ([Giving external agents access to Xcode](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode)). The test tool names and the behaviour with several worktrees are unconfirmed. No Apple tool replaces a terminal script for headless runs in parallel.

## 7. Recommendation

Keep a short script, because no tool covers the per-checkout simulator. Lean it on built-in features.

**Keep**
- `build-for-testing` and then `test-without-building`, with `ios/DerivedData` per checkout.
- A dedicated simulator, chosen by UDID.
- `-collect-test-diagnostics never`.
- Test names as arguments, passed as `-only-testing:gassipassTests/<id>`.

**Replace**
- Replace the polling timeout and the Python parser of unfinished tests with `-test-timeouts-enabled YES -default-test-execution-time-allowance 60 -maximum-test-execution-time-allowance 120`. A hung test then fails and is named in the result bundle. Keep one coarse outer limit, for example 600 s, only for install and launch hangs.
- Replace all `grep` lines with `-resultBundlePath "$derived/Test-<timestamp>.xcresult"`. Print the failures from `xcresulttool get build-results` and `get test-results summary` with a few lines of `python3` or `jq`. This fixes the missing macro errors.
- Replace the shared «GassiPass Tests» simulator and `lockf` with one simulator per worktree. Name it after the worktree folder, make it with `simctl clone` from a template device, and delete it when the worktree goes away. If memory gets tight, keep the lock instead.

**Drop**
- The `◇`/`✘` log parsing.
- Plans for fastlane or Tuist.
- xcpretty.
- MobileBuildMCP is optional: add it only if agents want structured MCP tools.

**Separately**
- Run the UI tests with their own scheme on their own simulator. Erase and boot it first, and turn parallel testing off.
- Leave `swiftTestingOnly` as it is. Fix shared state in the tests. Use `-parallel-testing-enabled NO` as a one-off check when a test seems to depend on another.

## 8. What the project did (2026-10-16)

- `ios/scripts/test.sh` gives each test a time limit with `-test-timeouts-enabled YES`, keeps an outer limit of 600 s for hangs outside the tests, and reads the errors and failures from the result bundles (`ios/scripts/report.py`). The log is read only for two things the bundles do not hold: the place in the test file of an error in a macro, and a test over its time limit that Xcode lost when it restarted the test process. Both showed up in a probe on the iOS 27 simulator.
- The unit tests keep one shared simulator with the lock, and do not clone one per worktree. Several booted simulators cost memory, and clones need cleanup when a worktree goes away.
- `ios/scripts/screenshots.sh` runs the UI test on its own simulator, which it erases and boots first, with parallel testing off. On that simulator the AX loaded timeout did not come back.
