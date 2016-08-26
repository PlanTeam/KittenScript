import Foundation
import CommonKitten

enum ParserError: Error {
    case unsupportedLiteralType(UInt8)
    case invalidCodeLength
    case invalidExpression
    case invalidStatement
    case invalidFunction(String)
    case invalidParameter(String)
}

/// The Script's Running Context
public class Context {
    /// A natively implemented function that's exposed in the Context
    public typealias NativeFunction = ((ParameterList, Scope) throws -> (Expression))
    
    public var functions = [String: NativeFunction]()
    public var variables = [String: Expression]()
}

public class Scope {
    internal var vars = [UInt32: Expression]()
    internal var superScope: Scope? = nil
    public let parameters: ParameterList
    
    public subscript(key: UInt32) -> Expression {
        get {
            if let value = superScope?.vars[key] {
                return value
            }
            
            if let value = vars[key] {
                return value
            }
            
            return .null
        }
        set {
            if superScope?.contains(key) == true {
               superScope?[key] = newValue
            } else {
                vars[key] = newValue
            }
        }
    }
    
    public func contains(_ key: UInt32) -> Bool {
        if superScope?.contains(key) == true {
            return true
        }
        
        return vars.keys.contains(key)
    }
    
    public var keys: [UInt32] {
        var response = Array(vars.keys)
        response.append(contentsOf: superScope?.keys ?? [])
        
        return response
    }
    
    public init(parameters: ParameterList = [:]) {
        self.parameters = parameters
    }
    
    internal init(subscopeOf scope: Scope, parameters: ParameterList = [:]) {
        self.superScope = scope
        self.parameters = parameters
    }
}

public class Code {
    /// The Code in binary form to execute
    public var code: [UInt8] = []
    
    /// The context to use for the execution
    public var context = Context()
    
    public init() {}
    
    /// Allows you to run the code within a given context
    public func run(inScope scope: Scope) throws {
        let length = Int(UnsafePointer<UInt32>(Array(code[0..<4])).pointee)
        
        guard code.count >= length else {
            throw ParserError.invalidCodeLength
        }
        
        let statement = try makeStatement(atPosition: 0, withType: 0x02, inScope: scope)
        
        guard let s = statement.statement else {
            throw ParserError.invalidStatement
        }
        
        try s.run(inContext: context, inScope: scope)
    }
    
    func makeStatement(atPosition position: Int, withType type: UInt8, inScope scope: Scope) throws -> (statement: Statement?, consumed: Int) {
        var consumed = position
        
        switch type {
        case 0x01:
            let type = code[consumed]
            
            consumed += 1
            
            let expressionResult = try makeExpression(fromPosition: consumed, withType: type, inScope: scope)
            
            guard let expression = expressionResult.expression else {
                throw ParserError.invalidExpression
            }
            
            let trueLength = Int(try UInt32.instantiate(bytes: Array(code[consumed..<consumed + 4])))
            
            consumed += 4
            
            let falseLength = Int(try UInt32.instantiate(bytes: Array(code[consumed..<consumed + 4])))
            
            consumed += 4
            
            let trueStatementResponse = try makeStatement(atPosition: consumed, withType: type, inScope: scope)
            
            guard let trueStatement = trueStatementResponse.statement else {
                throw ParserError.invalidStatement
            }
            
            consumed += trueLength
            
            if falseLength == 0 {
                return (Statement.ifStatement(expression: expression, trueStatement: trueStatement, falseStatement: nil), consumed - position)
            } else {
                let falseStatementResponse = try makeStatement(atPosition: consumed, withType: type, inScope: scope)
                
                consumed += falseLength
                
                return (Statement.ifStatement(expression: expression, trueStatement: trueStatement, falseStatement: falseStatementResponse.statement), consumed - position)
            }
        case 0x02:
            var statements = [Statement]()
            
            consumed += 4
            
            while consumed < code.count && code[consumed] != 0x00 {
                let type = code[consumed]
                consumed += 1
                
                let statementResponse = try makeStatement(atPosition: consumed, withType: type, inScope: scope)
                
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
            
            let expressionResult = try makeExpression(fromPosition: consumed, withType: type, inScope: scope)
            
            guard let expression = expressionResult.expression else {
                throw ParserError.invalidExpression
            }
            
            consumed += expressionResult.consumed
            
            return (Statement.assignment(id: varID, to: expression), consumed - position)
        case 0x04:
            let expressionType = code[position]
            
            consumed += 1
            
            let expressionResult = try makeExpression(fromPosition: consumed, withType: expressionType, inScope: scope)
            
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
    
    func makeExpression(fromPosition position: Int, withType type: UInt8, inScope scope: Scope) throws -> (expression: Expression?, consumed: Int) {
        switch type {
        case 0x01:
            var consumed = position
            
            let variableID = UnsafePointer<UInt32>(Array(code[consumed..<consumed + 4])).pointee
            
            consumed += 4
            
            let parametersResponse = try makeParameters(atPosition: consumed, inScope: scope)
            
            consumed += parametersResponse.consumed
            
            // TODO: Return values
            return (.localFunctionCall(id: variableID, parameterList: parametersResponse.parameters), consumed - position)
            
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
            let parametersResponse = try makeParameters(atPosition: consumed, inScope: scope)
            
            consumed += parametersResponse.consumed
            
            return (Expression.dynamicFunctionCall(name: name, ParameterList: parametersResponse.parameters), consumed - position)
        case 0x03:
            var consumed = position
            let type = code[consumed]
            
            consumed += 1
            
            let literalResponse = try makeLiteral(atPosition: consumed, withType: type, inScope: scope)
            
            consumed += literalResponse.consumed
            
            return (.literal(literalResponse.literal), consumed - position)
        case 0x04:
            let d = UnsafePointer<UInt32>(Array(code[position..<position + 4])).pointee
            
            return (.variable(d), 4)
        case 0x05:
            var consumed = position
            
            var key = [UInt8]()
            
            // Loop over string
            while code.count > consumed && code[consumed] != 0x00 {
                key.append(code[consumed])
                
                consumed += 1
            }
            
            // Null terminator
            consumed += 1
            
            guard  let keyString = String(bytes: key, encoding: .utf8) else {
                return (nil, consumed - position)
            }
            
            return (.parameter(keyString), consumed - position)
        default:
            return (nil, 0)
        }
    }
    
    func makeLiteral(atPosition position: Int, withType type: UInt8, inScope scope: Scope) throws -> (literal: Literal, consumed: Int) {
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
            var consumed = position
            
            let subscope = Scope(subscopeOf: scope)
            
            let statementResponse = try makeStatement(atPosition: consumed, withType: 0x02, inScope: subscope)
            
            guard let statement = statementResponse.statement, case .script(let statements) = statement else {
                throw ParserError.invalidStatement
            }
            
            consumed += statementResponse.consumed
            
            return (.script(statements), consumed - position)
        default:
            throw ParserError.unsupportedLiteralType(type)
        }
    }
    
    func makeParameters(atPosition position: Int, inScope scope: Scope) throws -> (parameters: ParameterList, consumed: Int) {
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
            
            let expressionResult = try makeExpression(fromPosition: consumed, withType: type, inScope: scope)
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
    
    func run(inContext context: Context, inScope scope: Scope) throws {
        switch self {
        case .script(let statements):
            for statement in statements {
                try statement.run(inContext: context, inScope: scope)
            }
        case .assignment(let id, let expression):
            scope[id] = try expression.run(inContext: context, inScope: scope)
        case .expression(let expression):
            _ = try expression.run(inContext: context, inScope: scope)
        case .ifStatement(let expression, let trueStatement, let falseStatement):
            let expression = try expression.run(inContext: context, inScope: scope)
            
            guard case Expression.literal(let literal) = expression, case .boolean(let bool) = literal else {
                throw ParserError.invalidExpression
            }
            
            let subscope = Scope(subscopeOf: scope)
            
            if bool {
                try trueStatement.run(inContext: context, inScope: subscope)
                
            } else if let falseStatement = falseStatement {
                try falseStatement.run(inContext: context, inScope: subscope)
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
    
    func run(inContext context: Context, inScope scope: Scope) throws -> Expression {
        switch self {
        case .localFunctionCall(let id, let parameterList):
            guard case .literal(let funcLiteral) = try scope[id].run(inContext: context, inScope: scope) else {
                throw ParserError.invalidExpression
            }
            
            guard case .script(let statements) = funcLiteral else {
                throw ParserError.invalidExpression
            }
            
            let subscope = Scope(subscopeOf: scope, parameters: parameterList)
            
            for statement in statements {
                try statement.run(inContext: context, inScope: subscope)
            }
            
            return .null
        case .dynamicFunctionCall(let name, let parameters):
            guard let function = context.functions[name] else {
                throw ParserError.invalidFunction(name)
            }
            
            var newParameters: ParameterList = [:]
            
            for parameter in parameters {
                newParameters[parameter.key] = try parameter.value.run(inContext: context, inScope: scope)
            }
            
            return try function(newParameters, scope)
        case .variable(let id):
            return scope[id]
        case .literal(_):
            return self
        case .parameter(let name):
            if let variable = scope.parameters[name] {
                return try variable.run(inContext: context, inScope: scope)
            }
            
            if let variable = context.variables[name] {
                return try variable.run(inContext: context, inScope: scope)
            }
            
            throw ParserError.invalidParameter(name)
        default:
            fatalError("unimplemented null")
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
