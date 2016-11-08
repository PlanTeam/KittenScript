import CommonKitten

public func compile(_ s: String) {
    
}

public typealias DynamicFunction = (([String: [UInt8]])->[UInt8])

public enum RuntimeError: Error {
    case unexpectedEndOfScript(remaining: Int, required: Int)
}

/// Runs the bitcode
///
/// The parameters are cString named parameters that contai a KittenScript literal
/// The context is the variable scope. It contains all stored variables as [id: literal].
/// The dynamicFunctions are the registered callbacks to Swift which are named with a cString.
///
/// This function can return a KittenScript Literal that needs to be parsed afterwards
public func run(code: [UInt8], withParameters: [String: [UInt8]] = [:], inContext context: [UInt32: [UInt8]] = [:], dynamicFunctions: [String: DynamicFunction] = [:]) -> [UInt8]? {
    var position = 0
    var val: [UInt8]? = nil
    var context = context
    var parameters = [String: [UInt8]]()
    
    /// Helper function that creates an ArraySlice of required amount of bytes from the current position
    func makeCodeRange(_ n: Int) throws -> ArraySlice<UInt8> {
        guard remaining() >= n else {
            throw RuntimeError.unexpectedEndOfScript(remaining: remaining(), required: n)
        }
        
        return code[position..<position + n]
    }
    
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
    
    func makeParameters(fromData code: [UInt8] = code, position: inout Int) -> [String: [UInt8]] {
        var parameters = [String: [UInt8]]()
        
        while position < code.count {
            if code[position] == 0x00 {
                position += 1
                return parameters
            }
            
            let parameterName = makeCString()
            let expression = makeExpression(fromData: code, position: &position)
            
            parameters[parameterName] = expression
        }
        
        return parameters
    }
    
    func makeLiteral(fromData code: [UInt8] = code, position: inout Int) -> [UInt8] {
        let variableType = code[position]
        position += 1
        
        switch variableType {
        case 0x00:
            return [0x00]
        case 0x01:
            let length = Int(try! fromBytes(makeCodeRange(4)) as UInt32)
            
            defer {
                position += 4 + length
            }
            
            return [variableType] + Array(makeCodeRange(4 + length))
        case 0x02:
            defer {
                position += 8
            }
            
            return [variableType] + Array(makeCodeRange(8))
        case 0x03:
            defer {
                position += 1
            }
            
            return [variableType, code[position]]
        case 0x04:
            let length = Int(try! fromBytes(makeCodeRange(4)) as UInt32)
            
            defer { position += length }
            
            return [variableType] + Array(code[position..<position + length])
        case 0x05:
            var literals = [UInt8]()
            
            while code[position] != 0x00 {
                literals.append(contentsOf: makeExpression(fromData: code, position: &position))
            }
            
            position += 1
            
            return [variableType] + literals + [0x00]
        default: fatalError("Invalid variable type")
        }
    }
    
    func makeExpression(fromData code: [UInt8] = code, position: inout Int) -> [UInt8] {
        let expressionType = code[position]
        position += 1
        
        switch expressionType {
        case 0x01:
            let variableId: UInt32 = try! fromBytes(code[position..<position + 4])
            guard var variable = context[variableId] else {
                fatalError("Non-existing variable")
            }
            
            position += 4
            
            guard variable.count > 0, variable.removeFirst() == 0x04 else {
                fatalError("Invalid variable type being executed")
            }
            
            let parameters = makeParameters(fromData: code, position: &position)
            
            return run(code: variable, withParameters: parameters, dynamicFunctions: dynamicFunctions) ?? [0x00]
        case 0x02:
            let parameterName = makeCString()
            
            let parameters = makeParameters(fromData: code, position: &position)
            
            return dynamicFunctions[parameterName]!(parameters)
        case 0x03:
            return makeLiteral(fromData: code, position: &position)
        case 0x04:
            defer {
                position += 4
            }
            
            let variableId = try! fromBytes(makeCodeRange(4)) as UInt32
            
            guard let variable = context[variableId] else {
                fatalError("Non-existing variable")
            }
            
            return variable
        case 0x05:
            let parameterName = makeCString()
            
            guard let variable = parameters[parameterName] else {
                fatalError("Non-existing parameter")
            }
            
            return variable
        default: fatalError("Invalid expression type")
        }
    }
    
    func makeLiteralArray(_ expression: [UInt8]) -> [[UInt8]] {
        var arrayPosition = 0
        var literals = [[UInt8]]()
        
        guard expression.count >= 2, expression[arrayPosition] == 0x05 else {
            fatalError("Invalid array")
        }
        
        arrayPosition += 1
        
        while arrayPosition < expression.count, expression[arrayPosition] != 0x00 {
            literals.append(makeLiteral(fromData: expression, position: &arrayPosition))
        }
        
        return literals
    }
    
    func makeStatement() -> [UInt8]? {
        let statementType = code[position]
        position += 1
        
        switch statementType {
        case 0x01:
            let expression = makeExpression(fromData: code, position: &position)
            
            guard expression.count == 2, expression[0] == 0x03 else {
                fatalError("Not a boolean in if-statement")
            }
            
            guard remaining(8) else {
                fatalError("Unexpected end of script")
            }
            
            let trueStatementLength = Int(try! fromBytes(makeCodeRange(4))as UInt32)
            
            position += 4
            
            let falseStatementLength = Int(try! fromBytes(makeCodeRange(4)) as UInt32)
            
            position += 4
            
            guard remaining(trueStatementLength + falseStatementLength) else {
                fatalError("Unexpected end of block")
            }
            
            guard expression[0] == 0x03 else {
                fatalError("Unexpected type \(expression[0]) is not a boolean")
            }
            
            if expression[1] == 0x01 {
                val = makeStatement()
                
                position += trueStatementLength + falseStatementLength
            } else if expression[1] == 0x00 {
                position += trueStatementLength
                
                defer {
                    position += falseStatementLength
                }
                
                return makeStatement()
            } else {
                fatalError("Impossible boolean")
            }
        case 0x02:
            let variableId = try! fromBytes(makeCodeRange(4)) as UInt32
            position += 4
            
            let expression = makeExpression(fromData: code, position: &position)
            
            var script = makeExpression(fromData: code, position: &position)
            
            guard script.count >= 5, script.removeFirst() == 0x04 else {
                fatalError("Invalid script")
            }
            
            for literal in makeLiteralArray(expression) {
                if let response = run(code: script, withParameters: [:], inContext: [variableId: literal], dynamicFunctions: dynamicFunctions) {
                    return response
                }
            }
        case 0x03:
            let variableId = try! fromBytes(makeCodeRange(4)) as UInt32
            
            position += 4
            
            let expression = makeExpression(fromData: code, position: &position)
            
            context[variableId] = expression
        case 0x04:
            _ = makeExpression(fromData: code, position: &position)
        case 0x05:
            return makeExpression(fromData: code, position: &position)
        default: fatalError("Invalid Statement Type")
        }
        
        return nil
    }
    
    func remaining() -> Int {
        return code.count - position
    }
    
    func remaining(_ n: Int) -> Bool {
        return remaining() >= n
    }
    
    guard code.count == Int(try! fromBytes(makeCodeRange(4)) as UInt32) else {
        fatalError("Invalid script length")
    }
    
    position += 4
    
    while position < code.count {
        if code[position] == 0x00 {
            return val
        }
        
        val = makeStatement() ?? val
    }
    
    return val
}
