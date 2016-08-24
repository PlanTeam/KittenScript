import KittenRunner
import KittenCompiler

//var uncompiled = "hello()\nwhatsup(    )    hello() hello() whatsup() hello()"
let uncompiled = "hello()hello()whatsup()hello()hello()hello()hello()"

var script = try! compile(uncompiled)

//var script: [UInt8] = [
//    14,0,0,0, // undefined length now
//    0x04 /*plain expression*/, 0x02 /*dynamic function call*/, 0x68 /*h*/, 0x65 /*e*/, 0x6c /*l*/, 0x6c /*l*/, 0x6f /*o*/, 0x00, 0x00 /*empty parameter list*/,
//    0x00
//]

let runnableCode = Code()
runnableCode.code = script
runnableCode.functions["hello"] = { parameters in
    print("hello")
    return .null
}
runnableCode.functions["whatsup"] = { parameters in
    print("OMG IT ASKED ME WHAT'S UP THIS IS SO EXCIIIIITING")
    return .null
    
}

try! runnableCode.run(inContext: [:])
