import KittenParser
import KittenRunner
import KittenCompiler

print("Meow.")
var script: [KittenCompiler.Statement] = [
    // 0x00 = function() {}
    .assignment(id: 0x00, to: .literal(.string("henk"))),
    .assignment(id: 0x01, to: .literal(.script([
        .ifStatement(expression: .parameter("a"), trueStatement: .script([
            .expression(.result(.literal(.boolean(false))))
            ]), falseStatement: .script([
                .expression(.result(.literal(.boolean(true))))
                ]))
        ]))),
    .ifStatement(expression: .localFunctionCall(id: 0x01, parameterList: ["a": .literal(.boolean(false))]), trueStatement: .script([
            .expression(.result(.variable(0x00)))
        ]), falseStatement: nil)
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
//runnableCode.code = script
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
let compiler = Compiler(code: script)

runnableCode.code = compiler.compile()

print(try! runnableCode.run(inScope: Scope()))
