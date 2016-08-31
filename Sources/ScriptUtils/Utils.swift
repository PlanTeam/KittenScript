public indirect enum Statement {
    case ifStatement(expression: Expression, trueStatement: Statement, falseStatement: Statement?)
    case script(Script)
    case assignment(id: UInt32, to: Expression)
    case expression(Expression)
    case null
}

public indirect enum Expression {
    case localFunctionCall(id: UInt32, parameterList: ParameterList)
    case dynamicFunctionCall(name: String, ParameterList: ParameterList)
    case literal(Literal)
    case variable(UInt32)
    case parameter(String)
    case result(Expression)
    case null
}

public enum Literal {
    case string(String)
    case double(Double)
    case boolean(Bool)
    case script(Script)
}

public typealias Script = [Statement]
public typealias ParameterList = [String: Expression]

public protocol Parser {
    func parseStatement(_ code: String) throws -> Statement
    func parseExpression(_ code: String) throws -> Expression
    func parseLiteral(_ code: String) throws -> Literal
}

extension Literal: Equatable {
    public static func ==(lhs: Literal, rhs: Literal) -> Bool {
        if case .string(let s0) = lhs, case .string(let s1) = rhs {
            return s0 == s1
        }
        
        if case .double(let d0) = lhs, case .double(let d1) = rhs {
            return d0 == d1
        }
        
        if case .boolean(let b0) = lhs, case .boolean(let b1) = rhs {
            return b0 == b1
        }
        
        return false
    }
}
