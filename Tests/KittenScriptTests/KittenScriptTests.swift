import KittenScript
import XCTest

#if Xcode
    private var workDir: String {
        let parent = #file.characters.split(separator: "/").map(String.init).dropLast().joined(separator: "/")
        let path = "/\(parent)/../../Resources/"
        return path
    }
#else
    private let workDir = "./Resources/"
#endif


class KittenScriptTests: XCTestCase {
    func testHelloWorldPerformance() throws {
        let template = try KittenScriptTemplate(atPath: workDir + "template-02.kitten")!
        let expectation = "Hello,World!"
        
        measure {
            try! (1...500).forEach { _ in
                let result = try! template.run(withParameters: [
                        "name": "World"
                    ], inContext: [:], dynamicFunctions: [:]) ?? ""
                XCTAssertEqual(result.trimmingCharacters(in: ["\n", "\t"]), expectation)
            }
        }
    }
    
    func testPerformance() throws {
        let compiledCode = try KittenScriptTemplate(atPath: workDir + "template-01.kitten")
        
        measure {
            let result = try! compiledCode?.run(withParameters: [
                "sample": true,
                "otherSample": true
                ], inContext: [:], dynamicFunctions: [
                    "hello": { parameters in
                        print("hello")
                        return nil
                    },
                    "debug": { parameters in
                        let message = parameters["message"]?.value as? String
                        print(message ?? "")
                        return nil
                    },
                    "print": { parameters in
                        for parameter in parameters {
                            print(parameter.key)
                            print(parameter.value.value)
                        }
                        print()
                        return nil
                    },
                    "helloString": { parameters in
                        let dict: [String: String] = [
                            "bob": "Hoi Bob, jij bent niet klaas.",
                            "klaas": "Hoi Klaas, jij bent niet bob."
                        ]
                        
                        if let key = parameters["forKey"]?.value as? String {
                            print(dict[key])
                        }
                        
                        return nil
                    }
            ]) ?? ""
            
            XCTAssert(result.contains("Hello! WORLD"))
            XCTAssert(result.contains("honthoi"))
            XCTAssert(result.contains("WAUW"))
        }
    }
    
    static var allTests : [(String, (KittenScriptTests) -> () throws -> Void)] {
        return [
            ("testPerformance", testPerformance),
        ]
    }
}
