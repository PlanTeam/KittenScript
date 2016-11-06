import CommonKitten

public func compile(_ s: String) {
    
}

public func run(code: [UInt8], withParameters: [String: [UInt8]] = [:]) -> [UInt8]? {
    var position = 0
    var val: [UInt8]? = nil
    var context = [UInt32: [UInt8]]()
    var parameters = [String: [UInt8]]()
    
    func makeCodeRange(_ n: Int) -> ArraySlice<UInt8> {
        guard remaining() >= n else {
            fatalError("Not enough remaining bytes")
        }
        
        return code[position..<position + n]
    }
    
    func makeCString() -> String {
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
        
        guard let string = try? String.instantiateFromCString(bytes: stringBytes) else {
            fatalError("Invalid CString")
        }
        
        return string
    }
    
    func makeParameters() -> [String: [UInt8]] {
        var parameters = [String: [UInt8]]()
        
        while position < code.count {
            defer {
                position += 1
            }
            
            if code[position] == 0x00 {
                return parameters
            }
            
            let parameterName = makeCString()
            let expression = makeExpression()
            
            parameters[parameterName] = expression
        }
        
        return parameters
    }
    
    func makeLiteral() -> [UInt8] {
        let variableType = code[position]
        position += 1
        
        switch variableType {
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
            
            var oldPosition = position
            
            position += 4
            
            scriptLoop: while position < code.count {
                position += 1
                
                if code[position] == 0x00 {
                    break scriptLoop
                }
            }
            
            defer {
                position += 1
            }
            
            return [variableType] + Array(code[oldPosition..<position])
        case 0x05:
            var literals = [UInt8]()
            
            while code[position] != 0x00 {
                literals.append(contentsOf: makeLiteral())
            }
            
            position += 1
            
            return [variableType] + literals + [0x00]
        default: fatalError("Invalid variable type")
        }
    }
    
    func makeExpression() -> [UInt8] {
        let expressionType = code[position]
        position += 1
        
        switch expressionType {
        case 0x01:
            let variableId: UInt32 = try! fromBytes(code[position..<position + 4])
            guard var variable = context[variableId] else {
                fatalError("Non-existing variable")
            }
            
            guard variable.count > 0, variable.removeFirst() == 0x04 else {
                fatalError("Invalid variable type being executed")
            }
            
            let parameters = makeParameters()
            
            return run(code: variable, withParameters: parameters) ?? [0x00]
        case 0x02:
            let parameterName = makeCString()
            
            guard var variable = parameters[parameterName] else {
                fatalError("Non-existing parameter")
            }
            
            guard variable.count > 0, variable.removeFirst() == 0x04 else {
                fatalError("Invalid variable type being executed")
            }
            
            let parameters = makeParameters()
            
            return run(code: variable, withParameters: parameters) ?? [0x00]
        case 0x03:
            return makeLiteral()
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
        
        while arrayPosition < expression.count, expression[arrayPosition] != 0x00 {
            let literalType = expression[arrayPosition]
            
            arrayPosition += 1
            
            switch literalType {
            case 0x01:
                let stringLength = Int(try! fromBytes(makeCodeRange(4)) as UInt32)
                defer { arrayPosition += 4 }
                
                guard stringLength < expression.count - arrayPosition else {
                    fatalError("Invalid remaining bytes")
                }
                
                literals.append([literalType] + Array(expression[arrayPosition + 4..<arrayPosition + 4 + stringLength]))
            case 0x02:
                guard arrayPosition + 8 < expression.count else {
                    fatalError("Invalid remaining bytes")
                }
                
                defer { arrayPosition += 8 }
                
                literals.append([literalType] + Array(expression[arrayPosition..<arrayPosition + 8]))
            case 0x03:
                guard expression[arrayPosition] == 0x00 || expression[arrayPosition] == 0x01 else {
                    fatalError("Invalid boolean case")
                }
                
                defer { arrayPosition += 1 }
                
                literals.append([literalType, expression[arrayPosition]])
            case 0x04:
                fatalError("Unsupported in array -- for now")
            case 0x05:
                return makeLiteralArray(<#T##expression: [UInt8]##[UInt8]#>)
            default:
                fatalError("Unsupported literal type")
            }
        }
        
        return literals
    }
    
    func makeStatement() -> [UInt8]? {
        let statementType = code[position]
        position += 1
        
        switch statementType {
        case 0x01:
            let expression = makeExpression()
            
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
                fatalError("Unexpected end of script")
            }
            
            guard expression[0] == 0x03 else {
                fatalError("Unexpected type \(expression[0]) is not a boolean")
            }
            
            if expression[1] == 0x01 {
                val = makeStatement()
                
                position += trueStatementLength + falseStatementLength
            } else if expression[1] == 0x00 {
                position += trueStatementLength
                
                val = makeStatement()
                
                position += falseStatementLength
            } else {
                fatalError("Impossible boolean")
            }
        case 0x02:
            let variableId = try! fromBytes(makeCodeRange(4)) as UInt32
            position += 4
            
            let expression = makeExpression()
            
            let scriptLength = Int(try! fromBytes(makeCodeRange(4)) as UInt32)
            
            for literal in makeLiteralArray(expression) {
                
            }
        case 0x03:
            let variableId = try! fromBytes(makeCodeRange(4)) as UInt32
            
            position += 4
            
            context[variableId] = makeExpression()
        case 0x04:
            _ = makeExpression()
        case 0x05:
            return makeExpression()
        default: fatalError("Invalid Statement Type")
        }
        
        return nil
    }
    
    func remaining() -> Int {
        return code.count - position
    }
    
    func remaining(_ n: Int) -> Bool {
        return remaining() > n
    }
    
    guard code.count == Int(try! fromBytes(makeCodeRange(4)) as UInt32) else {
        fatalError("Invalid script length")
    }
    
    position += 4
    
    while position < code.count {
        defer {
            position += 1
        }
        
        if code[position] == 0x00 {
            return val
        }
        
        val = makeStatement() ?? val
    }
    
    return val
}
