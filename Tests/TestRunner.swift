import Foundation

// Minimal test runner — no XCTest dependency
var passed = 0
var failed = 0

func check(_ desc: String, _ condition: Bool, file: String = #file, line: Int = #line) {
    if condition {
        print("  ✓ \(desc)")
        passed += 1
    } else {
        let f = URL(fileURLWithPath: file).lastPathComponent
        print("  ✗ \(desc)  [\(f):\(line)]")
        failed += 1
    }
}

func suite(_ name: String, _ body: () -> Void) {
    print("\n\(name)")
    body()
}

func summarise() -> Never {
    print("\n\(passed + failed) tests: \(passed) passed, \(failed) failed")
    exit(failed > 0 ? 1 : 0)
}
