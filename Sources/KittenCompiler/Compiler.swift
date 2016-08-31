import CommonKitten
@_exported import ScriptUtils

public struct Definition {
    public var postfixOperators: [String: PostfixOperator]
    public var infixOperators: [String: InfixOperator]
    public var prefixOperators: [String: PrefixOperator]
}

public typealias PostfixOperator = ((lhs: Expression)->Expression)
public typealias InfixOperator = ((lhs: Expression, rhs: Expression)->Expression)
public typealias PrefixOperator = ((rhs: Expression)->Expression)

public typealias ParameterList = [String: Expression]
public typealias Script = [Statement]

extension Statement {
    func compile() -> [UInt8] {
        switch self {
        case .ifStatement(let expression, let trueStatement, let falseStatement):
            let trueStatement = trueStatement.compile()
            let falseStatement = falseStatement?.compile() ?? []
            let lengths = UInt32(trueStatement.count).bytes + UInt32(falseStatement.count).bytes
            
            return [0x01] + expression.compile() + lengths + trueStatement + falseStatement
        case .script(let statements):
            var statementsCode = [UInt8]()
            
            for statement in statements {
                statementsCode.append(contentsOf: statement.compile())
            }
            
            return [0x02] + UInt32(statementsCode.count + 5).bytes + statementsCode + [0x00]
        case .assignment(let variable, let expression):
            return [0x03] + variable.bytes + expression.compile()
        case .expression(let expression):
            return [0x04] + expression.compile()
        case .null:
            return [0x05]
        }
    }
}

func compileParameters(_ parameters: ParameterList) -> [UInt8] {
    var parameterCode = [UInt8]()
    
    for parameter in parameters {
        parameterCode += parameter.key.utf8 + [0x00] + parameter.value.compile()
    }
    
    return parameterCode + [0x00]
}

extension Expression {
    func compile() -> [UInt8] {
        switch self {
        case .localFunctionCall(let function, let parameters):
            return [0x01] + function.bytes + compileParameters(parameters)
        case .dynamicFunctionCall(let name, let parameters):
            return [0x02] + name.utf8 + compileParameters(parameters)
        case .literal(let literal):
            return [0x03] + literal.compile()
        case .variable(let id):
            return [0x04] + id.bytes
        case .parameter(let name):
            return [0x05] + name.utf8 + [0x00]
        case .result(let expression):
            return [0x06] + expression.compile()
        case .null:
            return [0x07]
        }
    }
}

extension Literal {
    func compile() -> [UInt8] {
        switch self {
        case .string(let s):
            return [0x01] + UInt32(s.utf8.count).bytes + [UInt8](s.utf8)
        case .double(var d):
            return [0x02] + withUnsafePointer(&d) {
                return Array(UnsafeBufferPointer(start: UnsafePointer<UInt8>($0), count: sizeof(Double.self)))
            }
        case .boolean(let bool):
            return [0x03] + (bool ? [0x01] : [0x00])
        case .script(let statements):
            var statementsCode = [UInt8]()
            
            for statement in statements {
                statementsCode.append(contentsOf: statement.compile())
            }
            
            return [0x04] + UInt32(statementsCode.count).bytes + statementsCode + [0x00]
        }
    }
}

public class Compiler {
    let code: Statement
    
    public init(code: Statement) {
        self.code = code
    }
    
    public init(code: Script) {
        self.code = .script(code)
    }
    
    public func compile() -> [UInt8] {
        var compiled = code.compile()
        compiled.removeFirst()
        return compiled
    }
}

class Interpreter {
    let definition: Definition
    
    init(definition: Definition) {
        self.definition = definition
    }
}
