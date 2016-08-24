import Foundation


/// All errors that can occur when (de)serializing BSON
public enum DeserializationError : Error {
    /// The Document doesn't have a valid length
    case InvalidDocumentLength
    
    /// The instantiating went wrong because the element has an invalid size
    case InvalidElementSize
    
    /// The contents of the BSON binary data was invalid
    case InvalidElementContents
    
    /// The BSON Element type was unknown
    case UnknownElementType
    
    /// The lsat element of the BSON Binary Array was invalid
    case InvalidLastElement
    
    /// Something went wrong with parsing (yeah.. very specific)
    case ParseError
    
    /// This operation was invalid
    case InvalidOperation
    
    case unsupportedLiteralType(UInt8)
}

public extension String {
    /// This `String` as c-string
    public var cStringBytes : [UInt8] {
        var byteArray = self.utf8.filter{$0 != 0x00}
        byteArray.append(0x00)
        
        return byteArray
    }
    
    /// Instantiate a string from BSON (UTF8) data, including the length of the string.
    public static func instantiate(bytes data: [UInt8]) throws -> String {
        var 🖕 = 0
        
        return try instantiate(bytes: data, consumedBytes: &🖕)
    }
    
    /// Instantiate a string from BSON (UTF8) data, including the length of the string.
    public static func instantiate(bytes data: [UInt8], consumedBytes: inout Int) throws -> String {
        let res = try _instant(bytes: data)
        consumedBytes = res.0
        return res.1
    }
    
    private static func _instant(bytes data: [UInt8]) throws -> (Int, String) {
        // Check for null-termination and at least 5 bytes (length spec + terminator)
        guard data.count >= 5 && data.last == 0x00 else {
            throw DeserializationError.InvalidLastElement
        }
        
        // Get the length
        let length = try Int32.instantiate(bytes: Array(data[0...3]))
        
        // Check if the data is at least the right size
        guard data.count >= Int(length) + 4 else {
            throw DeserializationError.ParseError
        }
        
        // Empty string
        if length == 1 {
            return (5, "")
        }
        
        guard length > 0 else {
            throw DeserializationError.ParseError
        }
        
        var stringData = Array(data[4..<Int(length + 3)])
        
        guard let string = String(bytesNoCopy: &stringData, length: stringData.count, encoding: String.Encoding.utf8, freeWhenDone: false) else {
            throw DeserializationError.ParseError
        }
        
        return (Int(length + 4), string)
    }
    
    /// Instantiate a String from a CString (a null terminated string of UTF8 characters, not containing null)
    public static func instantiateFromCString(bytes data: [UInt8]) throws -> String {
        var 🖕 = 0
        
        return try instantiateFromCString(bytes: data, consumedBytes: &🖕)
    }
    
    /// Instantiate a String from a CString (a null terminated string of UTF8 characters, not containing null)
    public static func instantiateFromCString(bytes data: [UInt8], consumedBytes: inout Int) throws -> String {
        let res = try _cInstant(bytes: data)
        consumedBytes = res.0
        return res.1
    }
    
    private static func _cInstant(bytes data: [UInt8]) throws -> (Int, String) {
        guard data.contains(0x00) else {
            throw DeserializationError.ParseError
        }
        
        guard let stringData = data.split(separator: 0x00, maxSplits: 1, omittingEmptySubsequences: false).first else {
            throw DeserializationError.ParseError
        }
        
        guard let string = String(bytes: stringData, encoding: String.Encoding.utf8) else {
            throw DeserializationError.ParseError
        }
        
        return (stringData.count+1, string)
    }
}

extension Integer {
    public static var size: Int {
        return sizeof(Self.self)
    }
    
    public var bytes : [UInt8] {
        var integer = self
        return withUnsafePointer(&integer) {
            Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>($0), count: Self.size))
        }
    }
    
    public static func instantiate(bytes data: [UInt8]) throws -> Self {
        guard data.count >= self.size else {
            throw DeserializationError.InvalidElementSize
        }
        
        return UnsafePointer<Self>(data).pointee
    }
}

enum ParserError: Error {
    case invalidCodeLength
    case invalidExpression
    case invalidStatement
    case invalidFunction(String)
}

public typealias NativeFunction = ((ParameterList)->(Expression))

public class Context {
    public var functions = [String: NativeFunction]()
    public var variables = [UInt32: Expression]()
}

public class Code {
    public var code: [UInt8] = []
    public var context = Context()
    
    public init() {}
    
    public func run(inContext: [String: Expression]) throws {
        let length = Int(UnsafePointer<UInt32>(Array(code[0..<4])).pointee)
        
        guard code.count >= length else {
            throw ParserError.invalidCodeLength
        }
        
        let statement = try makeStatement(atPosition: 0, withType: 0x02)
        
        guard let s = statement.statement else {
            throw ParserError.invalidStatement
        }
        
        try s.run(inContext: context)
    }
    
    func makeStatement(atPosition position: Int, withType type: UInt8) throws -> (statement: Statement?, consumed: Int) {
        var consumed = position
        
        switch type {
        case 0x01:
            let type = code[consumed]
            
            consumed += 1
            
            let expressionResult = try makeExpression(fromPosition: consumed, withType: type)
            
            guard let expression = expressionResult.expression else {
                throw ParserError.invalidExpression
            }
            
            let trueLength = Int(try UInt32.instantiate(bytes: Array(code[consumed..<consumed + 4])))
            
            consumed += 4
            
            let falseLength = Int(try UInt32.instantiate(bytes: Array(code[consumed..<consumed + 4])))
            
            consumed += 4
            
            let trueStatementResponse = try makeStatement(atPosition: consumed, withType: type)
            
            guard let trueStatement = trueStatementResponse.statement else {
                throw ParserError.invalidStatement
            }
            
            consumed += trueLength
            
            if falseLength == 0 {
                return (Statement.ifStatement(expression: expression, trueStatement: trueStatement, falseStatement: nil), consumed - position)
            } else {
                let falseStatementResponse = try makeStatement(atPosition: consumed, withType: type)
                
                consumed += falseLength
                
                return (Statement.ifStatement(expression: expression, trueStatement: trueStatement, falseStatement: falseStatementResponse.statement), consumed - position)
            }
        case 0x02:
            var statements = [Statement]()
            
            consumed += 4
            
            while consumed < code.count && code[consumed] != 0x00 {
                let type = code[consumed]
                consumed += 1
                
                let statementResponse = try makeStatement(atPosition: consumed, withType: type)
                
                consumed += statementResponse.consumed
                
                guard let statement = statementResponse.statement else {
                    throw ParserError.invalidStatement
                }
                
                statements.append(statement)
            }
            
            return (Statement.script(statements), consumed - position)
        case 0x03:
            let varID = try UInt32.instantiate(bytes: Array(code[position..<position + 4]))
            
            consumed += 4
            
            let type = code[consumed]
            
            consumed += 1
            
            let expressionResult = try makeExpression(fromPosition: consumed, withType: type)
            
            guard let expression = expressionResult.expression else {
                throw ParserError.invalidExpression
            }
            
            consumed += expressionResult.consumed
            
            return (Statement.assignment(id: varID, to: expression), consumed - position)
        case 0x04:
            let expressionType = code[position]
            
            consumed += 1
            
            let expressionResult = try makeExpression(fromPosition: consumed, withType: expressionType)
            
            guard let expression = expressionResult.expression else {
                throw ParserError.invalidExpression
            }
            
            print("Return value: \(expression)")
            
            consumed += expressionResult.consumed
            
            return (.expression(expression), consumed - position)
        default:
            return (.null, 0)
        }
    }
    
    func makeExpression(fromPosition position: Int, withType type: UInt8) throws -> (expression: Expression?, consumed: Int) {
        switch type {
        case 0x01:
            fatalError("0x01")
        case 0x02:
            var consumed = position
            
            var key = [UInt8]()
            
            // Loop over string
            while code.count > consumed && code[consumed] != 0x00 {
                key.append(code[consumed])
                
                consumed += 1
            }
            
            // Null terminator
            consumed += 1
            
            // Transform key into name string
            guard let name = String.init(bytes: key, encoding: .utf8) else {
                return (nil, consumed - position)
            }
            
            // Make the parameters
            let parametersResponse = try makeParameters(atPosition: consumed)
            
            consumed += parametersResponse.consumed
            
            return (Expression.dynamicFunctionCall(name: name, ParameterList: parametersResponse.parameters), consumed - position)
        case 0x03:
            var consumed = position
            let type = code[consumed]
            
            consumed += 1
            
            let literalResponse = try makeLiteral(atPosition: consumed, withType: type)
            
            consumed += literalResponse.consumed
            
            return (.literal(literalResponse.literal), consumed - position)
        case 0x04:
            let d = UnsafePointer<UInt32>(Array(code[position..<position + 4])).pointee
            
            return (context.variables[d], 4)
        case 0x05:
            fatalError("0x05")
        default:
            return (nil, 0)
        }
    }
    
    func makeLiteral(atPosition position: Int, withType type: UInt8) throws -> (literal: Literal, consumed: Int) {
        var consumed = position
        
        switch type {
        case 0x01:
            var text = [UInt8]()
            let textLength = try UInt32.instantiate(bytes: Array(code[consumed..<consumed + 4]))
            
            consumed += 4
            
            guard position + Int(textLength) < code.count else {
                throw DeserializationError.InvalidElementSize
            }
            
            var keyPos = 0
            
            while keyPos < Int(textLength) && keyPos + consumed < code.count {
                text.append(code[consumed + keyPos])
                keyPos += 1
            }
            
            consumed += keyPos
            
            guard let string = String(bytes: text, encoding: .utf8) else {
                throw DeserializationError.InvalidElementContents
            }
            
            return (.string(string), consumed - position)
        case 0x02:
            fatalError("Double")
        case 0x03:
            if code[consumed] == 0x00 {
                consumed += 1
                return (.boolean(false), consumed - position)
            }
            consumed += 1
            
            return (.boolean(true), consumed - position)
        case 0x04:
            fatalError("Script")
        default:
            throw DeserializationError.unsupportedLiteralType(type)
        }
    }
    
    func makeParameters(atPosition position: Int) throws -> (parameters: ParameterList, consumed: Int) {
        var consumed = position
        var parameters = ParameterList()
        
        while code.count > consumed && code[consumed] != 0x00 {
            var key = [UInt8]()
            
            while code.count > consumed && code[consumed] != 0x00 {
                key.append(code[consumed])
                
                consumed += 1
            }
            
            consumed += 1
            
            guard let name = String.init(bytes: key, encoding: .utf8) else {
                return (parameters, consumed - position)
            }
            
            let type = code[consumed]
            
            consumed += 1
            
            let expressionResult = try makeExpression(fromPosition: consumed, withType: type)
            consumed += expressionResult.consumed
            
            parameters[name] = expressionResult.expression
        }
        
        // Add one for the null terminator
        consumed += 1
        
        return (parameters, consumed - position)
    }
}

public typealias Script = [Statement]

public indirect enum Statement {
    case ifStatement(expression: Expression, trueStatement: Statement, falseStatement: Statement?)
    case script(Script)
    case assignment(id: UInt32, to: Expression)
    case expression(Expression)
    case null
    
    func run(inContext context: Context) throws {
        switch self {
        case .script(let statements):
            for statement in statements {
                try statement.run(inContext: context)
            }
        case .assignment(let id, let expression):
            context.variables[id] = try expression.run(inContext: context)
        case .expression(let expression):
            _ = try expression.run(inContext: context)
        case .ifStatement(let expression, let trueStatement, let falseStatement):
            guard let expression = try expression.run(inContext: context) else {
                throw ParserError.invalidExpression
            }
            
            guard case Expression.literal(let literal) = expression, case .boolean(let bool) = literal else {
                throw ParserError.invalidExpression
            }
            
            if bool {
                try trueStatement.run(inContext: context)
                
            } else if let falseStatement = falseStatement {
                try falseStatement.run(inContext: context)
            }
        case .null:
            break
        }
    }
}

public typealias ParameterList = [String: Expression]

public enum Expression {
    case localFunctionCall(id: UInt32, parameterList: ParameterList)
    case dynamicFunctionCall(name: String, ParameterList: ParameterList)
    case literal(Literal)
    case variable(UInt32)
    case parameter(String)
    case null
    
    func run(inContext context: Context) throws -> Expression? {
        switch self {
        case .dynamicFunctionCall(let name, let parameters):
            guard let function = context.functions[name] else {
                throw ParserError.invalidFunction(name)
            }
            
            return function(parameters)
        case .variable(let id):
            return context.variables[id]
        case .literal(_):
            return self
        default:
            fatalError("unimplemented")
        }
        // Find the function
        
    }
}

public enum Literal {
    case string(String)
    case double(Double)
    case boolean(Bool)
    case script(Script)
}
