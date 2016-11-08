import CommonKitten

public func compile(_ s: String) {
    
}

public typealias DynamicFunction = (([String: [UInt8]])->[UInt8])

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

/// Runs the bitcode
///
/// The parameters are cString named parameters that contai a KittenScript literal
/// The context is the variable scope. It contains all stored variables as [id: literal].
/// The dynamicFunctions are the registered callbacks to Swift which are named with a cString.
///
/// This function can return a KittenScript Literal that needs to be parsed afterwards
public func run(code: [UInt8], withParameters: [String: [UInt8]] = [:], inContext context: [UInt32: [UInt8]] = [:], dynamicFunctions: [String: DynamicFunction] = [:]) throws -> [UInt8]? {
    var position = 0
    var val: [UInt8]? = nil
    var context = context
    var parameters = [String: [UInt8]]()
    
    /// Helper function that creates an ArraySlice of required amount of bytes from the current position
    ///
    /// Throws when there aren't enough bytes left
    func makeCodeRange(_ n: Int) throws -> ArraySlice<UInt8> {
        guard remaining() >= n else {
            throw RuntimeError.unexpectedEndOfScript(remaining: remaining(), required: n)
        }
        
        return code[position..<position + n]
    }
    
    /// Makes a cString from the current position and increments the position until the first byte after the String
    func makeCString() throws -> String {
        var stringBytes = [UInt8]()
        
        stringBuilder: while position < code.count {
            defer {
                position += 1
            }
            
            stringBytes.append(code[position])
            
            if code[position] == 0x00 {
                break stringBuilder
            }
        }
        
        return try String.instantiateFromCString(bytes: stringBytes)
    }
    
    /// Makes a KittenScript parameters object from it's binary form.
    /// Throws when unable to create the parameters according to spec
    func makeParameters(fromData code: [UInt8] = code, position: inout Int) throws -> [String: [UInt8]] {
        var parameters = [String: [UInt8]]()
        
        while position < code.count {
            if code[position] == 0x00 {
                position += 1
                return parameters
            }
            
            let parameterName = try makeCString()
            let expression = try makeExpression(fromData: code, position: &position)
            
            parameters[parameterName] = expression
        }
        
        return parameters
    }
    
    /// Makes a KittenScript literal at the current position, returns the bytes and advanced the position to the first byte after the literal
    func makeLiteral(fromData code: [UInt8] = code, position: inout Int) throws -> [UInt8] {
        let variableType = code[position]
        position += 1
        
        switch variableType {
        // Nil
        case 0x00:
            return [0x00]
        // String
        case 0x01:
            let length = Int(try fromBytes(try makeCodeRange(4)) as UInt32)
            
            defer {
                position += 4 + length
            }
            
            return [variableType] + Array(try makeCodeRange(4 + length))
        // Double
        case 0x02:
            defer {
                position += 8
            }
            
            return [variableType] + Array(try makeCodeRange(8))
        // Boolean
        case 0x03:
            defer {
                position += 1
            }
            
            return [variableType, code[position]]
        // Function
        case 0x04:
            let length = Int(try fromBytes(makeCodeRange(4)) as UInt32)
            
            defer { position += length }
            
            return [variableType] + Array(code[position..<position + length])
        // Array
        case 0x05:
            var literals = [UInt8]()
            
            while code[position] != 0x00 {
                literals.append(contentsOf: try makeExpression(fromData: code, position: &position))
            }
            
            position += 1
            
            return [variableType] + literals + [0x00]
        default: throw RuntimeError.invalidLiteralType(variableType)
        }
    }
    
    func makeExpression(fromData code: [UInt8] = code, position: inout Int) throws -> [UInt8] {
        let expressionType = code[position]
        position += 1
        
        switch expressionType {
        // Local function call to variableId
        case 0x01:
            let variableId: UInt32 = try fromBytes(code[position..<position + 4])
            guard var variable = context[variableId] else {
                throw RuntimeError.invalidVariable(variableId)
            }
            
            position += 4
            
            guard variable.count > 0 else {
                throw RuntimeError.unexpectedEndOfScript(remaining: 0, required: 1)
            }
            
            let type = variable.removeFirst()
            
            guard type == 0x04 else {
                throw RuntimeError.invalidVariableType(found: type, expected: 0x04)
            }
            
            let parameters = try makeParameters(fromData: code, position: &position)
            
            return try run(code: variable, withParameters: parameters, dynamicFunctions: dynamicFunctions) ?? [0x00]
        // Function call to registered native Swift closure
        case 0x02:
            let parameterName = try makeCString()
            
            let parameters = try makeParameters(fromData: code, position: &position)
            
            guard let dynamicFunc = dynamicFunctions[parameterName] else {
                throw RuntimeError.invalidDynamicFunction(named: parameterName)
            }
            
            return dynamicFunc(parameters)
        // Literal
        case 0x03:
            return try makeLiteral(fromData: code, position: &position)
        // Read the literal from a variable
        case 0x04:
            defer {
                position += 4
            }
            
            let variableId = try fromBytes(makeCodeRange(4)) as UInt32
            
            guard let variable = context[variableId] else {
                throw RuntimeError.invalidVariable(variableId)
            }
            
            return variable
        // Read the literal from a parameter
        case 0x05:
            let parameterName = try makeCString()
            
            guard let variable = parameters[parameterName] else {
                throw RuntimeError.invalidParameter(named: parameterName)
            }
            
            return variable
        default:
            throw RuntimeError.invalidExpressionType(expressionType)
        }
    }
    
    func makeLiteralArray(_ expression: [UInt8]) throws -> [[UInt8]] {
        var arrayPosition = 0
        var literals = [[UInt8]]()
        
        guard expression.count >= 2, expression[arrayPosition] == 0x05 else {
            throw RuntimeError.invalidArrayLiteral
        }
        
        arrayPosition += 1
        
        while arrayPosition < expression.count, expression[arrayPosition] != 0x00 {
            literals.append(try makeLiteral(fromData: expression, position: &arrayPosition))
        }
        
        return literals
    }
    
    func makeStatement() throws -> [UInt8]? {
        let statementType = code[position]
        position += 1
        
        switch statementType {
        case 0x01:
            let expression = try makeExpression(fromData: code, position: &position)
            
            guard expression.count == 2, expression[0] == 0x03 else {
                throw RuntimeError.invalidLiteralType(expression[0])
            }
            
            guard remaining(8) else {
                throw RuntimeError.unexpectedEndOfScript(remaining: remaining(), required: 8)
            }
            
            let trueStatementLength = Int(try fromBytes(makeCodeRange(4))as UInt32)
            
            position += 4
            
            let falseStatementLength = Int(try fromBytes(makeCodeRange(4)) as UInt32)
            
            position += 4
            
            guard remaining(trueStatementLength + falseStatementLength) else {
                throw RuntimeError.unexpectedEndOfScript(remaining: remaining(), required: trueStatementLength + falseStatementLength)
            }
            
            // true statement
            if expression[1] == 0x01 {
                val = try makeStatement()
                
                position += trueStatementLength + falseStatementLength
            // false statement
            } else if expression[1] == 0x00 {
                if falseStatementLength > 0 {
                    position += trueStatementLength
                    
                    defer {
                        position += falseStatementLength
                    }
                    
                    return try makeStatement()
                }
            } else {
                throw RuntimeError.invalidBoolean(value: expression[1])
            }
        case 0x02:
            let variableId = try fromBytes(makeCodeRange(4)) as UInt32
            position += 4
            
            let expression = try makeExpression(fromData: code, position: &position)
            
            var script = try makeExpression(fromData: code, position: &position)
            
            guard script.count >= 5 else {
                throw RuntimeError.unexpectedEndOfScript(remaining: script.count, required: 5)
            }
            
            let type = script.removeFirst()
            
            guard type == 0x04 else {
                throw RuntimeError.invalidLiteralType(type)
            }
            
            for literal in try makeLiteralArray(expression) {
                if let response = try run(code: script, withParameters: [:], inContext: [variableId: literal], dynamicFunctions: dynamicFunctions) {
                    return response
                }
            }
        case 0x03:
            let variableId = try fromBytes(makeCodeRange(4)) as UInt32
            
            position += 4
            
            let expression = try makeExpression(fromData: code, position: &position)
            
            context[variableId] = expression
        case 0x04:
            _ = try makeExpression(fromData: code, position: &position)
        case 0x05:
            return try makeExpression(fromData: code, position: &position)
        default: throw RuntimeError.invalidStatementType(statementType)
        }
        
        return nil
    }
    
    func remaining() -> Int {
        return code.count - position
    }
    
    func remaining(_ n: Int) -> Bool {
        return remaining() >= n
    }
    
    let headerCount = Int(try fromBytes(makeCodeRange(4)) as UInt32)
    
    guard code.count == headerCount else {
        throw RuntimeError.unexpectedEndOfScript(remaining: code.count, required: headerCount)
    }
    
    position += 4
    
    while position < code.count {
        if code[position] == 0x00 {
            return val
        }
        
        val = try makeStatement() ?? val
    }
    
    return val
}
