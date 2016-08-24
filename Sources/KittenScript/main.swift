import KittenRunner
import KittenCompiler

print("Meow.")
var script: [UInt8] = [
    19,0,0,0, // undefined length now
    0x04 /*plain expression*/, 0x02 /*dynamic function call*/, 0x68 /*h*/, 0x65 /*e*/, 0x6c /*l*/, 0x6c /*l*/, 0x6f /*o*/, 0x00, /* String 'i' */ 0x69, 0x00, /*Value 'j'*/0x03, 0x01, 0x01, 0x00, 0x00, 0x00, 0x6a, 0x00 /*End of parameter list*/,
    0x00
]

var variablesTest: [UInt8] = [
    13, 0, 0, 0,
    0x03, 0x05, 0x00, 0x00, 0x00, 0x03, 0x03, 0x01,
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
runnableCode.context.functions["hello"] = { parameters in
    print(parameters)
    print("hello")
    return .null
}
runnableCode.context.functions["whatsup"] = { parameters in
    print("OMG IT ASKED ME WHAT'S UP THIS IS SO EXCIIIIITING")
    return .null
    
}

//try! runnableCode.run(inContext: [:])
//print("----------------------------")
//runnableCode.code = script2
//
//try! runnableCode.run(inContext: [:])
//
runnableCode.code = variablesTest

try! runnableCode.run(inContext: [:])
print(runnableCode.context.variables)
