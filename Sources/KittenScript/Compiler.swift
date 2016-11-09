import Foundation

public enum CompilerError: Error {
    case invalidExpression, noParameterNameProvided
    case invalidCharacter(found: UInt8, expected: UInt8)
    case unexpectedCharacters(expected: [UInt8])
    case missingCharacter(expected: UInt8)
    case cannotLoadFile(atPath: String)
}

public class KittenScriptCompiler {
    enum Word: String {
        case `if`, `else`, `return`, `for`, `in`
        
        func makeBytes() -> [UInt8] {
            return [UInt8](self.rawValue.utf8)
        }
    }
    
    enum SpecialCharacters: UInt8 {
        case codeBlockOpen = 0x7b
        case codeBlockClose = 0x7d
        
        case arrayBlockOpen = 0x5b
        case arrayBlockClose = 0x5d
        
        case functionParametersOpen = 0x28
        case functionParametersClose = 0x29
        
        case comma = 0x2c
        case dot = 0x2e
        
        case colon = 0x3a
        
        case backslash = 0x5c
        
        case stringLiteralQuote = 0x22
    }
    
    static let wordCache: [Word] = [
        .if, .else, .return, .for, .in
    ]
    
    static let binaryWords: [(code: [UInt8], word: Word)] = wordCache.map {
        ($0.makeBytes(), $0)
    }
    
    public static func compile(atPath path: String) throws -> KittenScriptCode {
        guard let data = NSData(contentsOfFile: path) else {
            throw CompilerError.cannotLoadFile(atPath: path)
        }
        var bytes = [UInt8](repeating: 0, count: data.length)
        data.getBytes(&bytes, length: bytes.count)
        
        return KittenScriptCode(try compile(bytes))
    }
    
    static func compile(_ code: [UInt8]) throws -> [UInt8] {
        var position = 0
        
        let whitespace: [UInt8] = [0x20, 0x0a]
        let wordExcludedCharacters: [UInt8] = whitespace + [SpecialCharacters.comma.rawValue, SpecialCharacters.dot.rawValue, SpecialCharacters.arrayBlockOpen.rawValue, SpecialCharacters.arrayBlockClose.rawValue, SpecialCharacters.functionParametersOpen.rawValue, SpecialCharacters.functionParametersClose.rawValue, SpecialCharacters.colon.rawValue]
        var variables = [([UInt8], UInt32)]()
        var reservedVariables = [UInt32]()
        
        func skipWhitespace() {
            while position < code.count, whitespace.contains(code[position]) || (code[position] == 0x5c && code[position + 1] == 0x6e) {
                position += 1
            }
        }
        
        func makeWord() -> [UInt8] {
            var wordBuffer = [UInt8]()
            
            while position < code.count && !wordExcludedCharacters.contains(code[position]) {
                defer { position += 1 }
                
                wordBuffer.append(code[position])
            }
            
            return wordBuffer
        }
        
        func findWord(_ findCode: [UInt8]) throws {
            skipWhitespace()
            
            var codePosition = 0
            
            while codePosition < findCode.count && position < code.count {
                defer {
                    position += 1
                    codePosition += 1
                }
                
                guard findCode[codePosition] == code[position] else {
                    throw CompilerError.unexpectedCharacters(expected: findCode)
                }
            }
        }
        
        func compileArrayLiteral() throws -> [UInt8] {
            guard code[position] == SpecialCharacters.arrayBlockOpen.rawValue else {
                throw CompilerError.invalidCharacter(found: code[position], expected: SpecialCharacters.arrayBlockOpen.rawValue)
            }
            
            position += 1
            
            defer {
                position += 1
            }
            
            var array = [UInt8]()
            
            while position < code.count {
                skipWhitespace()
                let expression = try compileExpression()
                array.append(contentsOf: expression)
                
                skipWhitespace()
                
                if code[position] == SpecialCharacters.arrayBlockClose.rawValue {
                    return [0x05] + array + [0x00]
                } else if code[position] != SpecialCharacters.comma.rawValue {
                    throw CompilerError.invalidCharacter(found: code[position], expected: SpecialCharacters.comma.rawValue)
                }
                
                position += 1
                
                skipWhitespace()
            }
            
            throw CompilerError.missingCharacter(expected: SpecialCharacters.arrayBlockClose.rawValue)
        }
        
        func compileStringLiteral() throws -> [UInt8] {
            guard code[position] == SpecialCharacters.stringLiteralQuote.rawValue else {
                throw CompilerError.invalidCharacter(found: code[position], expected: SpecialCharacters.stringLiteralQuote.rawValue)
            }
            
            position += 1
            
            var stringLiteral = [UInt8]()
            
            while position < code.count {
                if code[position] == SpecialCharacters.stringLiteralQuote.rawValue && code[position - 1] != SpecialCharacters.backslash.rawValue {
                    position += 1
                    return [0x01] + UInt32(stringLiteral.count).bytes + stringLiteral
                } else if code[position] == SpecialCharacters.stringLiteralQuote.rawValue && code[position - 1] == SpecialCharacters.backslash.rawValue {
                    stringLiteral.removeLast()
                }
                
                stringLiteral.append(code[position])
                
                position += 1
            }
            
            throw CompilerError.missingCharacter(expected: SpecialCharacters.stringLiteralQuote.rawValue)
        }
        
        func compileLiteral() throws -> [UInt8]? {
            if code[position] == SpecialCharacters.arrayBlockOpen.rawValue {
                return try compileArrayLiteral()
            }
            
            if code[position] == SpecialCharacters.stringLiteralQuote.rawValue {
                return try compileStringLiteral()
            }
            
            if try scanWord("true") {
                return [0x03, 0x01]
            } else if try scanWord("false") {
                return [0x03, 0x00]
            } else if try scanWord("nil") {
                return [0x00]
            }
            
            return nil
        }
        
        func scanWord(_ word: String) throws -> Bool {
            return try scanBytes([UInt8](word.utf8))
        }
        
        func scanBytes(_ bytes: [UInt8]) throws -> Bool {
            var scanPosition = 0
            
            for byte in bytes {
                defer { scanPosition += 1 }
                
                guard position + scanPosition < code.count, code[position + scanPosition] == byte else {
                    return false
                }
            }
            
            position += scanPosition
            return true
        }
        
        func scanScope(_ scope: String) throws -> Bool {
            if try !scanWord(scope) {
                return false
            }
            
            guard code[position] == SpecialCharacters.dot.rawValue else {
                throw CompilerError.invalidCharacter(found: code[position], expected: SpecialCharacters.dot.rawValue)
            }
            
            position += 1
            
            return true
        }
        
        func makeParameter() throws -> [UInt8]? {
            guard try scanScope("Parameters") else {
                return nil
            }
            
            let word = makeWord() + [0x00]
            
            guard word.count > 0 else {
                throw CompilerError.noParameterNameProvided
            }
            
            return word
        }
        
        func compileExpression() throws -> [UInt8] {
            skipWhitespace()
            
            if let dynamicFunctionCall = try compileDynamicFunctionCall() {
                return [0x02] + dynamicFunctionCall
            }
            
            if let parameter = try makeParameter() {
                return [0x05] + parameter
            }
            
            if let literal = try compileLiteral() {
                return [0x03] + literal
            }
            
            for (variableName, variableId) in variables {
                if try scanBytes(variableName) {
                    return [0x04] + variableId.bytes
                }
            }
            
            throw CompilerError.invalidExpression
        }
        
        func compileDynamicFunctionCall() throws -> [UInt8]? {
            guard try scanScope("Swift") else {
                return nil
            }
            
            let functionNameBytes = makeWord() + [0x00]
            
            skipWhitespace()
            
            var parameters = [UInt8]()
            
            guard code[position] == SpecialCharacters.functionParametersOpen.rawValue else {
                throw CompilerError.invalidCharacter(found: code[position], expected: SpecialCharacters.functionParametersOpen.rawValue)
            }
            
            position += 1
            
            skipWhitespace()
            
            while position < code.count {
                skipWhitespace()
                
                if code[position] == SpecialCharacters.functionParametersClose.rawValue {
                    position += 1
                    return functionNameBytes + parameters + [0x00]
                } else if parameters.count > 0 && code[position] != SpecialCharacters.comma.rawValue {
                    throw CompilerError.invalidCharacter(found: code[position], expected: SpecialCharacters.comma.rawValue)
                } else if code[position] == SpecialCharacters.comma.rawValue {
                    position += 1
                }
                
                skipWhitespace()
                let word = makeWord()
                
                guard word.count > 0 else {
                    throw CompilerError.invalidExpression
                }
                
                parameters.append(contentsOf: word + [0x00])
                
                skipWhitespace()
                
                guard code[position] == SpecialCharacters.colon.rawValue else {
                    throw CompilerError.invalidCharacter(found: code[position], expected: SpecialCharacters.colon.rawValue)
                }
                
                position += 1
                
                skipWhitespace()
                
                parameters.append(contentsOf: try compileExpression())
                
                skipWhitespace()
            }
            
            throw CompilerError.missingCharacter(expected: SpecialCharacters.functionParametersClose.rawValue)
        }
        
        func compileStatement(fromData code: [UInt8], position: inout Int) throws -> [UInt8] {
            var binary = [UInt8]()
            
            let wordCode = makeWord()
            
            if let (_, word) = KittenScriptCompiler.binaryWords.first(where: { $0.code == wordCode }) {
                switch word {
                case .if:
                    binary.append(0x01)
                    binary.append(contentsOf: try compileExpression())
                    let ifBlock = try makeBlock(fromData: code, position: &position)
                    
                    skipWhitespace()
                    
                    if makeWord() == Word.else.makeBytes() {
                        let elseBlock = try makeBlock(fromData: code, position: &position)
                        
                        binary.append(contentsOf: UInt32(ifBlock.count).bytes)
                        binary.append(contentsOf: UInt32(elseBlock.count).bytes)
                        
                        binary.append(contentsOf: ifBlock)
                        binary.append(contentsOf: elseBlock)
                    } else {
                        binary.append(contentsOf: UInt32(ifBlock.count).bytes)
                        binary.append(contentsOf: UInt32(0).bytes)
                        
                        binary.append(contentsOf: ifBlock)
                    }
                case .return:
                    return [0x05] + (try compileExpression())
                case .for:
                    binary.append(0x02)
                    
                    skipWhitespace()
                    
                    let variableName = makeWord()
                    
                    guard variableName.count > 0 else {
                        throw CompilerError.invalidExpression
                    }
                    
                    let variableId = (reservedVariables.sorted().last ?? 0) + 1
                    variables.append((variableName, variableId))
                    
                    reservedVariables.append(variableId)
                    
                    binary.append(contentsOf: variableId.bytes)
                    
                    skipWhitespace()
                    
                    let wordBytes = makeWord()
                    
                    guard wordBytes == Word.in.makeBytes() else {
                        throw CompilerError.unexpectedCharacters(expected: Word.in.makeBytes())
                    }
                    
                    binary.append(contentsOf: try compileExpression())
                    
                    let block = try makeBlock(fromData: code, position: &position)
                    
                    binary.append(contentsOf: [0x03, 0x04])
                    binary.append(contentsOf: UInt32(block.count + 5).bytes)
                    binary.append(contentsOf: block)
                    binary.append(0x00)
                default:
                    throw CompilerError.invalidExpression
                }
            } else {
                position -= wordCode.count
                binary.append(contentsOf: [0x04] + (try compileExpression()))
            }
            
            return binary
        }
        
        func makeBlock(fromData code: [UInt8], position: inout Int) throws -> [UInt8] {
            skipWhitespace()
            
            guard code[position] == SpecialCharacters.codeBlockOpen.rawValue else {
                throw CompilerError.invalidCharacter(found: code[position], expected: SpecialCharacters.codeBlockOpen.rawValue)
            }
            
            position += 1
            
            var block = [UInt8]()
            
            while position < code.count {
                skipWhitespace()
                
                defer { position += 1 }
                
                if code[position] == SpecialCharacters.codeBlockClose.rawValue {
                    return block
                }
                
                let statement = try compileStatement(fromData: code, position: &position)
                block.append(contentsOf: statement)
            }
            
            throw CompilerError.missingCharacter(expected: SpecialCharacters.codeBlockClose.rawValue)
        }
        
        var binary = [UInt8]()
        
        while position < code.count {
            skipWhitespace()
            
            guard position < code.count else {
                return UInt32(binary.count + 5).bytes + binary + [0x00]
            }
            
            let statement = try compileStatement(fromData: code, position: &position)
            
            binary.append(contentsOf: statement)
        }
        
        return UInt32(binary.count + 5).bytes + binary + [0x00]
    }
}
