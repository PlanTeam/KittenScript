import Foundation
import ScriptUtils

let statementCode = [
    21, 0, 0, 0,
    0x01, 0x03, 0x03, 0x00, // if false {
    0x00, 0x00, 0x00, 0x00, // } else {
    0x04, 0x00, 0x00, 0x00, 0x05, 0x03, 0x03, 0x01, // return true
    // }
    0
] as [UInt8]

var functionTest: [UInt8] = [ 0x03, 1, 0, 0, 0, 0x03, 0x04 ] + statementCode + [
    0x01, 0x01, 1, 0, 0, 0, 0x00, // if statementCode() {
    0x04, 0x00, 0x00, 0x00,
    0x04, 0x00, 0x00, 0x00,
    0x05, 0x03, 0x03, 0x01, // { return true }
    0x05, 0x03, 0x03, 0x00, // else { return false }
    0x00
]

print(try! run(code: UInt32(functionTest.count + 4).bytes + functionTest) ?? [0x00])


var loopClosure: [UInt8] = [
    0x04, 0x02
]

loopClosure.append(contentsOf: "print".utf8)
loopClosure.append(0x00)
loopClosure.append(contentsOf: "var".utf8)
loopClosure.append(0x00)
loopClosure.append(contentsOf: [0x04, 2, 0, 0, 0])

var loopTest: [UInt8] = [ 0x03, 1, 0, 0, 0, 0x03, // var 1 =
                          0x05, 0x03, 0x03, 0x01, 0x03, 0x03, 0x01, 0x03, 0x03, 0x00, 0x03, 0x03, 0x00, 0x03, 0x03, 0x01, 0x00, // [true, true, false, false, true]
                          0x02, 2, 0, 0, 0, 0x04, 1, 0, 0, 0, 0x03, 0x04 // for (var 2) in (var 1) loopClosure()
] + UInt32(loopClosure.count + 4).bytes + loopClosure + [0x05, 0x03, 0x00, 0x00]

let functions: [String: DynamicFunction] = [
    "print": { parameters in
        print(parameters.keys)
        
        return [0x00]
    }
]

print(try! run(code: UInt32(loopTest.count + 4).bytes + loopTest, dynamicFunctions: functions) ?? [0x00])


let code = try! String.init(contentsOfFile: "/Users/joannis/Desktop/code.swift")

print("Compiled code:")

let compiledCode: [UInt8] = compile(code)

print(compiledCode)

print(try! run(code: compiledCode) ?? [])
