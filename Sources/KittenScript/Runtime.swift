public enum RuntimeError: Error {
    case unexpectedEndOfScript(remaining: Int, required: Int)
    case invalidVariable(UInt32)
    case invalidDynamicFunction(named: String)
    case invalidArrayLiteral
    case invalidLiteralType(UInt8)
    case invalidExpressionType(UInt8)
    case invalidStatementType(UInt8)
    case invalidParameter(named: String)
    case invalidVariableType(found: UInt8, expected: UInt8)
    case invalidBoolean(value: UInt8)
}

public struct KittenScriptValue: ExpressibleByBooleanLiteral, ExpressibleByStringLiteral, ExpressibleByNilLiteral {
    var binary: [UInt8]
    
    public init(nilLiteral: ()) {
        self.binary = [0x00]
    }
    
    public init(booleanLiteral value: Bool) {
        self.binary = value ? [0x03, 0x01] : [0x03, 0x00]
    }
    
    public init(stringLiteral value: String) {
        self.binary = UInt32(value.characters.count).bytes + [UInt8](value.utf8)
    }
    
    public init(unicodeScalarLiteral value: String) {
        self.binary = UInt32(value.characters.count).bytes + [UInt8](value.utf8)
    }
    
    public init(extendedGraphemeClusterLiteral value: String) {
        self.binary = UInt32(value.characters.count).bytes + [UInt8](value.utf8)
    }
    
    init(binary: [UInt8]) {
        self.binary = binary
    }
    
    var value: Any? {
        switch self.binary[0] {
        case 0x00:
            return nil
        case 0x01:
            return String(bytes: self.binary[5..<self.binary.count], encoding: .utf8)
        case 0x02:
            return try? fromBytes(self.binary[1..<9]) as Double
        case 0x03:
            return self.binary[1] == 0x01
        case 0x04:
            return KittenScriptCode(Array(self.binary[1..<self.binary.count]))
        case 0x05:
            return KittenScriptArray(Array(self.binary[1..<self.binary.count]))
        default:
            return nil
        }
    }
}

public typealias DynamicFunction = (([String: KittenScriptValue])->KittenScriptValue)

public struct KittenScriptCode {
    var bytes: [UInt8]
    
    init(_ bytes: [UInt8]) {
        self.bytes = bytes
    }
    
    public func run(withParameters parameters: [String: KittenScriptValue], inContext context: [UInt32: [UInt8]], dynamicFunctions: [String: DynamicFunction]) throws -> KittenScriptValue {
        return try KittenScriptRuntime.run(context: RuntimeContext(code: bytes, withParameters: parameters, inContext: context, dynamicFunctions: dynamicFunctions))
    }
}

public struct KittenScriptArray: Sequence {
    var code: [UInt8]
    
    init(_ code: [UInt8]) {
        self.code = code
    }
    
    public func makeIterator() -> AnyIterator<KittenScriptValue> {
        let context = RuntimeContext(code: code, withParameters: [:], inContext: [:], dynamicFunctions: [:])
        
        return AnyIterator {
            return try? makeLiteral(context: context)
        }
    }
}

class RuntimeContext {
    var code: [UInt8]
    var position = 0
    var context: [UInt32: [UInt8]]
    var parameters: [String: KittenScriptValue]
    var dynamicFunctions: [String: DynamicFunction]
    
    init(code: [UInt8], withParameters parameters: [String: KittenScriptValue], inContext context: [UInt32: [UInt8]], dynamicFunctions: [String: DynamicFunction]) {
        self.code = code
        self.parameters = parameters
        self.context = context
        self.dynamicFunctions = dynamicFunctions
    }
}

class KittenScriptRuntime {
    /// Runs the bitcode
    ///
    /// The parameters are cString named parameters that contai a KittenScript literal
    /// The context is the variable scope. It contains all stored variables as [id: literal].
    /// The dynamicFunctions are the registered callbacks to Swift which are named with a cString.
    ///
    /// This function can return a KittenScript Literal that needs to be parsed afterwards
    static func run(context: RuntimeContext) throws -> KittenScriptValue {
        let headerCount = Int(try fromBytes(makeCodeRange(4, context: context)) as UInt32)
        
        guard context.code.count == headerCount else {
            throw RuntimeError.unexpectedEndOfScript(remaining: context.code.count, required: headerCount)
        }
        
        context.position += 4
        
        while context.position < context.code.count {
            if context.code[context.position] == 0x00 {
                return nil
            }
            
            let val = try makeStatement(context: context)
            
            if val.binary != [0x00] {
                return val
            }
        }
        
        return nil
    }
}

/// Helper function that creates an ArraySlice of required amount of bytes from the current context.position
///
/// Throws when there aren't enough bytes left
func makeCodeRange(_ n: Int, context: RuntimeContext) throws -> ArraySlice<UInt8> {
    guard remaining(context: context) >= n else {
        throw RuntimeError.unexpectedEndOfScript(remaining: remaining(context: context), required: n)
    }
    
    return context.code[context.position..<context.position + n]
}

/// Makes a cString from the current context.position and increments the context.position until the first byte after the String
func makeCString(context: RuntimeContext) throws -> String {
    var stringBytes = [UInt8]()
    
    stringBuilder: while context.position < context.code.count {
        defer {
            context.position += 1
        }
        
        stringBytes.append(context.code[context.position])
        
        if context.code[context.position] == 0x00 {
            break stringBuilder
        }
    }
    
    return try String.instantiateFromCString(bytes: stringBytes)
}

func remaining(context: RuntimeContext) -> Int {
    return context.code.count - context.position
}

func remaining(_ n: Int, context: RuntimeContext) -> Bool {
    return remaining(context: context) >= n
}

/// Makes a KittenScript parameters object from it's binary form.
/// Throws when unable to create the parameters according to spec
func makeParameters(context: RuntimeContext) throws -> [String: KittenScriptValue] {
    var parameters = [String: KittenScriptValue]()
    
    while context.position < context.code.count {
        if context.code[context.position] == 0x00 {
            context.position += 1
            return parameters
        }
        
        let parameterName = try makeCString(context: context)
        let expression = try makeExpression(context: context)
        
        parameters[parameterName] = KittenScriptValue(binary: expression.binary)
    }
    
    return parameters
}

/// Makes a KittenScript literal at the current context.position, returns the bytes and advanced the context.position to the first byte after the literal
func makeLiteral(context: RuntimeContext) throws -> KittenScriptValue {
    let variableType = context.code[context.position]
    context.position += 1
    
    switch variableType {
    // Nil
    case 0x00:
        return KittenScriptValue(binary: [0x00])
    // String
    case 0x01:
        let length = Int(try fromBytes(try makeCodeRange(4, context: context)) as UInt32)
        
        defer {
            context.position += 4 + length
        }
        
        return KittenScriptValue(binary: [variableType] + Array(try makeCodeRange(4 + length, context: context)))
    // Double
    case 0x02:
        defer {
            context.position += 8
        }
        
        return KittenScriptValue(binary: [variableType] + Array(try makeCodeRange(8, context: context)))
    // Boolean
    case 0x03:
        defer {
            context.position += 1
        }
        
        return KittenScriptValue(binary: [variableType, context.code[context.position]])
    // Function
    case 0x04:
        let length = Int(try fromBytes(makeCodeRange(4, context: context)) as UInt32)
        
        defer { context.position += length }
        
        return KittenScriptValue(binary: [variableType] + Array(context.code[context.position..<context.position + length]))
    // Array
    case 0x05:
        var literals = [UInt8]()
        
        while context.code[context.position] != 0x00 {
            literals.append(contentsOf: try makeExpression(context: context).binary)
        }
        
        context.position += 1
        
        return KittenScriptValue(binary: [variableType] + literals + [0x00])
    default: throw RuntimeError.invalidLiteralType(variableType)
    }
}

func makeExpression(context: RuntimeContext) throws -> KittenScriptValue {
    let expressionType = context.code[context.position]
    context.position += 1
    
    switch expressionType {
    // Local function call to variableId
    case 0x01:
        let variableId: UInt32 = try fromBytes(context.code[context.position..<context.position + 4])
        guard var variable = context.context[variableId] else {
            throw RuntimeError.invalidVariable(variableId)
        }
        
        context.position += 4
        
        guard variable.count > 0 else {
            throw RuntimeError.unexpectedEndOfScript(remaining: 0, required: 1)
        }
        
        let type = variable.removeFirst()
        
        guard type == 0x04 else {
            throw RuntimeError.invalidVariableType(found: type, expected: 0x04)
        }
        
        let parameters = try makeParameters(context: context)
        
        return try KittenScriptRuntime.run(context: context)
    // Function call to registered native Swift closure
    case 0x02:
        let parameterName = try makeCString(context: context)
        
        let parameters = try makeParameters(context: context)
        
        guard let dynamicFunc = context.dynamicFunctions[parameterName] else {
            throw RuntimeError.invalidDynamicFunction(named: parameterName)
        }
        
        return dynamicFunc(parameters)
    // Literal
    case 0x03:
        return try makeLiteral(context: context)
    // Read the literal from a variable
    case 0x04:
        defer {
            context.position += 4
        }
        
        let variableId = try fromBytes(makeCodeRange(4, context: context)) as UInt32
        
        guard let variable = context.context[variableId] else {
            throw RuntimeError.invalidVariable(variableId)
        }
        
        return KittenScriptValue(binary: variable)
    // Read the literal from a parameter
    case 0x05:
        let parameterName = try makeCString(context: context)
        
        guard let variable = context.parameters[parameterName] else {
            throw RuntimeError.invalidParameter(named: parameterName)
        }
        
        return variable
    default:
        throw RuntimeError.invalidExpressionType(expressionType)
    }
}

func makeLiteralArray(_ expression: [UInt8], context: RuntimeContext) throws -> [[UInt8]] {
    var literals = [[UInt8]]()
    
    let subcontext = RuntimeContext(code: expression, withParameters: context.parameters, inContext: context.context, dynamicFunctions: context.dynamicFunctions)
    
    guard subcontext.code.count >= 2, subcontext.code[subcontext.position] == 0x05 else {
        throw RuntimeError.invalidArrayLiteral
    }
    
    subcontext.position += 1
    
    while subcontext.position < subcontext.code.count, subcontext.code[subcontext.position] != 0x00 {
        literals.append(try makeLiteral(context: subcontext).binary)
    }
    
    return literals
}

func makeStatement(context: RuntimeContext) throws -> KittenScriptValue {
    let statementType = context.code[context.position]
    context.position += 1
    
    switch statementType {
    case 0x01:
        let expression = try makeExpression(context: context).binary
        
        guard expression.count == 2, expression[0] == 0x03 else {
            throw RuntimeError.invalidLiteralType(expression[0])
        }
        
        guard remaining(8, context: context) else {
            throw RuntimeError.unexpectedEndOfScript(remaining: remaining(context: context), required: 8)
        }
        
        let trueStatementLength = Int(try fromBytes(makeCodeRange(4, context: context))as UInt32)
        
        context.position += 4
        
        let falseStatementLength = Int(try fromBytes(makeCodeRange(4, context: context)) as UInt32)
        
        context.position += 4
        
        guard remaining(trueStatementLength + falseStatementLength, context: context) else {
            throw RuntimeError.unexpectedEndOfScript(remaining: remaining(context: context), required: trueStatementLength + falseStatementLength)
        }
        
        // true statement
        if expression[1] == 0x01 {
            let val = try makeStatement(context: context)
            
            context.position += trueStatementLength + falseStatementLength
            
            return val
            // false statement
        } else if expression[1] == 0x00 {
            if falseStatementLength > 0 {
                context.position += trueStatementLength
                
                defer {
                    context.position += falseStatementLength
                }
                
                return try makeStatement(context: context)
            }
        } else {
            throw RuntimeError.invalidBoolean(value: expression[1])
        }
    case 0x02:
        let variableId = try fromBytes(makeCodeRange(4, context: context)) as UInt32
        context.position += 4
        
        let expression = try makeExpression(context: context)
        
        var script = try makeExpression(context: context).binary
        
        guard script.count >= 5 else {
            throw RuntimeError.unexpectedEndOfScript(remaining: script.count, required: 5)
        }
        
        let type = script.removeFirst()
        
        guard type == 0x04 else {
            throw RuntimeError.invalidLiteralType(type)
        }
        
        for literal in try makeLiteralArray(expression.binary, context: context) {
            var newVariableContext = context.context
            newVariableContext[variableId] = literal
            
            let subcontext = RuntimeContext(code: script, withParameters: context.parameters, inContext: newVariableContext, dynamicFunctions: context.dynamicFunctions)
            
            let response = try KittenScriptRuntime.run(context: subcontext)
            
            if response.binary != [0x00] {
                return response
            }
        }
    case 0x03:
        let variableId = try fromBytes(makeCodeRange(4, context: context)) as UInt32
        
        context.position += 4
        
        let expression = try makeExpression(context: context)
        
        context.context[variableId] = expression.binary
    case 0x04:
        _ = try makeExpression(context: context)
    case 0x05:
        return try makeExpression(context: context)
    default: throw RuntimeError.invalidStatementType(statementType)
    }
    
    return nil
}
