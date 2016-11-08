import KittenScript
import Foundation

let code = try! String.init(contentsOfFile: "/Users/joannis/Desktop/code.swift")

print("Compiled code:")

let compiledCode = KittenScriptCompiler.compile(code)

print(compiledCode)

print(try! KittenScriptRuntime.run(code: compiledCode, withParameters: [:], inContext: [:], dynamicFunctions: [:]) ?? [])
