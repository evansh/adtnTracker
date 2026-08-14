#if MANUAL_TEST_RUNNER
import XCTest

@main
enum ManualTestRunner {
    static func main() {
        let suite = XCTestSuite(name: "75Hard MVP Foundation")
        suite.addTest(XCTestSuite(forTestCaseClass: ChallengeSchedulerTests.self))
        suite.addTest(XCTestSuite(forTestCaseClass: RequirementEvaluatorTests.self))
        suite.addTest(XCTestSuite(forTestCaseClass: UseCaseTests.self))
        suite.addTest(XCTestSuite(forTestCaseClass: SecureFileChallengeRepositoryTests.self))
        suite.run()

        guard let run = suite.testRun else {
            fatalError("XCTest did not create a test run")
        }

        print("Executed \(run.executionCount) tests with \(run.totalFailureCount) failures")
        exit(run.totalFailureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
    }
}
#endif
