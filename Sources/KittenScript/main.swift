import KittenRunner
import KittenCompiler

print("Meow.")
var script: [UInt8] = [
    14,0,0,0, // undefined length now
    0x04 /*plain expression*/, 0x02 /*dynamic function call*/, 0x68 /*h*/, 0x65 /*e*/, 0x6c /*l*/, 0x6c /*l*/, 0x6f /*o*/, 0x00, /* String 'i' */ 0x69, 0x00, /*Value 'j'*/0x03, 0x01, 0x01, 0x00, 0x00, 0x00, 0x6a, 0x00 /*End of parameter list*/,
    0x00
]

let runnableCode = Code()
runnableCode.code = script
runnableCode.functions["hello"] = { parameters in
    print(parameters)
    print("hello")
    return .null
}
try! runnableCode.run(inContext: [:])
