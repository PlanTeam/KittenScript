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
    "01-basic-functioncall.kitten", "02-if-statement.kitten", "03-single-expression-script.kitten", "04-multi-expression-result-script.kitten", "05-swift-code.kitten"
]

for resource in resources {
    let compiledCode = KittenScriptCompiler.compile(atPath: workDir + resource)
    
    print(compiledCode)
    
    print(try! compiledCode.run(withParameters: ["sample": true], inContext: [:], dynamicFunctions: [
        "hello": { parameters in
            print("hello")
            return nil
        },
        "debug": { parameters in
            print(parameters["message"])
            return nil
        }
    ]))
}

let compiledCode = KittenScriptCompiler.compile(atPath: "/Users/joannis/Desktop/code.swift")
print(try! compiledCode.run(withParameters: [:], inContext: [:], dynamicFunctions: [
    "hello": { parameters in
        print("hello")
        return nil
    }
]))
