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
}

public typealias NativeFunction = ((ParameterList)->(Expression))

public class Code {
    public var code: [UInt8] = []
    
    public var functions = [String: NativeFunction]()
    
    public init() {}
    
    public func run(inContext: [String: Expression]) throws {
        let length = Int(UnsafePointer<UInt32>(Array(code[0..<4])).pointee)
        
        guard code.count >= length else {
            throw ParserError.invalidCodeLength
        }
        
        var position = 4
        
        while position < length {
            let statementType = code[position]
            position += 1
            
            switch statementType {
            case 0x01:
                fatalError("0x01")
            case 0x02:
                fatalError("0x02")
            case 0x03:
                fatalError("0x03")
            case 0x04:
                let expressionType = code[position]
                
                position += 1
                
                let expressionResult = try makeExpression(fromPosition: position, withType: expressionType)
                
                guard let expression = expressionResult.expression else {
                    throw ParserError.invalidExpression
                }
                
                print(expression)
                
                position += expressionResult.consumed
            default:
                break
            }
        }
    }
    
    func makeExpression(fromPosition position: Int, withType type: UInt8) throws -> (expression: Expression?, consumed: Int) {
        switch type {
        case 0x01:
            fatalError("0x01")
        case 0x02:
            var consumed = position
            
            var key = [UInt8]()
            
            while code.count > consumed && code[consumed] != 0x00 {
                key.append(code[consumed])
                
                consumed += 1
            }
            
            guard let name = String.init(bytes: key, encoding: .utf8) else {
                return (nil, consumed)
            }
            
            guard let function = self.functions[name] else {
                return (nil, consumed)
            }
            
            guard let parametersResponse = parseParameters(fromPosition: position + consumed) else {
                return (nil, consumed)
            }
            
            consumed += parametersResponse.consumed
            
            let expression = function(parametersResponse.parameters)
            
            return (expression, consumed)
        case 0x03:
            fatalError("0x03")
        case 0x04:
            fatalError("0x04")
        case 0x05:
            fatalError("0x05")
        default:
            return (nil, 0)
        }
    }
    
    func parseParameters(fromPosition position: Int) -> (parameters: ParameterList, consumed: Int)? {
        return ([:], 0)
    }
}

public typealias Script = [Statement]

public indirect enum Statement {
    case ifStatement(expression: Expression, trueStatement: Statement, falseStatement: Statement?)
    case script(Script)
    case assignment(id: UInt32, to: Expression)
    case expression(Expression)
    case null
}

public typealias ParameterList = [String: Expression]

public enum Expression {
    case localFunctionCall(id: UInt32, parameterList: ParameterList)
    case dynamicFunctionCall(name: String, ParameterList: ParameterList)
    case literal(Literal)
    case variable(UInt32)
    case parameter(String)
    case null
}

public enum Literal {
    case string(String)
    case double(Double)
    case boolean(Bool)
    case script(Script)
}
