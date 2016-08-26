import KittenRunner
import KittenCompiler

print("Meow.")
var script: [UInt8] = [
    19,0,0,0, // undefined length now
    0x04 /*plain expression*/, 0x02 /*dynamic function call*/, 0x68 /*h*/, 0x65 /*e*/, 0x6c /*l*/, 0x6c /*l*/, 0x6f /*o*/, 0x00, /* String 'i' */ 0x69, 0x00, /*Value 'j'*/0x03, 0x01, 0x01, 0x00, 0x00, 0x00, 0x6a, 0x00 /*End of parameter list*/,
    0x00
]

var variablesTest: [UInt8] = [
    34, 0, 0, 0,
    0x03, 0x05, 0x00, 0x00, 0x00, 0x02, 0x68 /*h*/, 0x65 /*e*/, 0x6c /*l*/, 0x6c /*l*/, 0x6f /*o*/, 0x00, 0x00,
    0x04 /*plain expression*/, 0x02 /*dynamic function call*/, 0x68 /*h*/, 0x65 /*e*/, 0x6c /*l*/, 0x6c /*l*/, 0x6f /*o*/, 0x00, 0x69, 0x00, 0x04, 0x05, 0x00, 0x00, 0x00, 0x00,
    0x00
]

var variablesTest2: [UInt8] = [
    23, 0, 0, 0,
    0x04 /*plain expression*/, 0x02 /*dynamic function call*/, 0x68 /*h*/, 0x65 /*e*/, 0x6c /*l*/, 0x6c /*l*/, 0x6f /*o*/, 0x00, 0x69, 0x00, 0x02, 0x68 /*h*/, 0x65 /*e*/, 0x6c /*l*/, 0x6c /*l*/, 0x6f /*o*/, 0x00, 0x00,
    0x00
]

var functionsTest: [UInt8] = [
    35, 0, 0, 0,
    // var 4 = function() {
    0x03, 0x04, 0x00, 0x00, 0x00, 0x03, 0x04,
    // function Length
    23, 0, 0, 0,
    // hello()
     0x04, 0x02, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00, 0x69, 0x00, 0x02, 0x68, 0x65, 0x6c, 0x6c, 0x6f, 0x00, 0x00,
    // }
    0x00,
    // 4()
    0x04, 0x01, 0x04, 0x00, 0x00, 0x00, 0x00,
    0x00
]

//var uncompiled = "hello()\nwhatsup(    )    hello() hello() whatsup() hello()"
let uncompiled = "hello     ( )      hello            ()     whatsup(    )hello()hello()hello()hello()"

var script2 = try! compile(uncompiled)

//var script: [UInt8] = [
//    14,0,0,0, // undefined length now
//    0x04 /*plain expression*/, 0x02 /*dynamic function call*/, 0x68 /*h*/, 0x65 /*e*/, 0x6c /*l*/, 0x6c /*l*/, 0x6f /*o*/, 0x00, 0x00 /*empty parameter list*/,
//    0x00
//]

let runnableCode = Code()
runnableCode.code = script
runnableCode.context.functions["hello"] = { parameters, scope in
    print(parameters)
    print(scope.keys)
    print("hello")
    
    if case .literal(let variable) = parameters["i"] ?? .null {
        print(variable)
    }
    
    return Expression.literal(.double(3.14))
}

runnableCode.context.functions["whatsup"] = { parameters, scope in
    print("OMG IT ASKED ME WHAT'S UP THIS IS SO EXCIIIIITING")
    return .null
}

//try! runnableCode.run(inContext: [:])
//print("----------------------------")
//runnableCode.code = script2
//
//try! runnableCode.run(inContext: [:])
//
runnableCode.code = functionsTest

try! runnableCode.run(inScope: Scope())
