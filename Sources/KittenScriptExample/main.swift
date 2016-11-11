import KittenScript
import Foundation

print("Compiled code:")

#if Xcode
    private var workDir: String {
        let parent = #file.characters.split(separator: "/").map(String.init).dropLast().joined(separator: "/")
        let path = "/\(parent)/../../Resources/"
        return path
    }
#else
    private let workDir = "./Resources/"
#endif

let resources = [
   // "01-basic-functioncall.kitten", "02-if-statement.kitten", "03-single-expression-script.kitten", "04-multi-expression-result-script.kitten", "05-swift-code.kitten", "06-complex-example.kitten"
] as [String]

for resource in resources {
    let compiledCode = try KittenScriptCompiler.compile(atPath: workDir + resource)
    
    print(compiledCode)
    
    print(try! compiledCode.run(withParameters: [
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
    ]))
}

let template = try KittenScriptTemplate(atPath: workDir + "template-02.kitten")!

let result = try! template.run(withParameters: [
    "name": "World"
    ], inContext: [:], dynamicFunctions: [:]) ?? ""

print(result)
