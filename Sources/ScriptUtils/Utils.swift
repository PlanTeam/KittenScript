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
