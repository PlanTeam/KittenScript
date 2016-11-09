import Foundation

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
    
    public static func compile(atPath path: String) -> KittenScriptCode {
        guard let data = NSData(contentsOfFile: path) else {
            fatalError("Error loading file at \(path)")
        }
        var bytes = [UInt8](repeating: 0, count: data.length)
        data.getBytes(&bytes, length: bytes.count)
        
        return KittenScriptCode(compile(bytes))
    }
    
    static func compile(_ code: [UInt8]) -> [UInt8] {
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
        
        func findWord(_ findCode: [UInt8]) {
            skipWhitespace()
            
            var codePosition = 0
            
            while codePosition < findCode.count && position < code.count {
                defer {
                    position += 1
                    codePosition += 1
                }
                
                guard findCode[codePosition] == code[position] else {
                    fatalError("Invalid code. Looking for \(findCode)")
                }
            }
        }
        
        func compileArrayLiteral() -> [UInt8] {
            guard code[position] == SpecialCharacters.arrayBlockOpen.rawValue else {
                fatalError("Invalid character \(code[position]), expected `[`")
            }
            
            position += 1
            
            defer {
                position += 1
            }
            
            var array = [UInt8]()
            
            while position < code.count {
                skipWhitespace()
                let expression = compileExpression()
                array.append(contentsOf: expression)
                
                skipWhitespace()
                
                if code[position] == SpecialCharacters.arrayBlockClose.rawValue {
                    return [0x05] + array + [0x00]
                } else if code[position] != SpecialCharacters.comma.rawValue {
                    fatalError("Unexpected character \(code[position]), expected `]`")
                }
                
                position += 1
            }
            
            fatalError("Unclosed array block. Missing `]`")
        }
        
        func compileStringLiteral() -> [UInt8] {
            guard code[position] == SpecialCharacters.stringLiteralQuote.rawValue else {
                fatalError("Invalid character \(code[position]), expected `\"`")
            }
            
            position += 1
            
            var stringLiteral = [UInt8]()
            
            while position < code.count {
                if code[position] == SpecialCharacters.stringLiteralQuote.rawValue && code[position - 1] != SpecialCharacters.backslash.rawValue {
                    return [0x02] + UInt32(stringLiteral.count).bytes + stringLiteral
                } else if code[position] == SpecialCharacters.stringLiteralQuote.rawValue && code[position - 1] == SpecialCharacters.backslash.rawValue {
                    stringLiteral.removeLast()
                }
                
                stringLiteral.append(code[position])
                
                position += 1
            }
            
            fatalError("Unclosed String literal. Missing `\"`")
        }
        
        func compileLiteral() -> [UInt8]? {
            if code[position] == SpecialCharacters.arrayBlockOpen.rawValue {
                return compileArrayLiteral()
            }
            
            if code[position] == SpecialCharacters.stringLiteralQuote.rawValue {
                return compileStringLiteral()
            }
            
            let word = makeWord()
            
            if word == [UInt8]("true".utf8) {
                return [0x03, 0x01]
            } else if word == [UInt8]("false".utf8) {
                return [0x03, 0x00]
            }
            
            return nil
        }
        
        func scanScope(_ scope: String) -> Bool {
            var scanPosition = 0
            
            for character in [UInt8](scope.utf8) {
                defer { scanPosition += 1 }
                
                guard position + scanPosition < code.count, code[position + scanPosition] == character else {
                    return false
                }
            }
            
            position += scanPosition
            
            guard code[position] == SpecialCharacters.dot.rawValue else {
                fatalError("Unexpected character \(code[position]) after `Parameters` scope entry")
            }
            
            position += 1
            
            return true
        }
        
        func makeParameter() -> [UInt8]? {
            guard scanScope("Parameters") else {
                return nil
            }
            
            let word = makeWord() + [0x00]
            
            guard word.count > 0 else {
                fatalError("No parametername provided after `Parameter.` scope entry")
            }
            
            return word
        }
        
        func compileExpression() -> [UInt8] {
            skipWhitespace()
            
            if let dynamicFunctionCall = compileDynamicFunctionCall() {
                return [0x03] + dynamicFunctionCall
            }
            
            if let parameter = makeParameter() {
                return [0x05] + parameter
            }
            
            if let literal = compileLiteral() {
                return [0x03] + literal
            }
            
            fatalError("Invalid expression")
        }
        
        func compileDynamicFunctionCall() -> [UInt8]? {
            guard scanScope("Swift") else {
                return nil
            }
            
            let functionNameBytes = makeWord() + [0x00]
            
            skipWhitespace()
            
            var parameters = [UInt8]()
            
            guard code[position] == SpecialCharacters.functionParametersOpen.rawValue else {
                fatalError("Expected `(` to open function call. Found `\(code[position])`")
            }
            
            position += 1
            
            skipWhitespace()
            
            while position < code.count {
                defer { position += 1 }
                
                if code[position] == SpecialCharacters.functionParametersClose.rawValue {
                    return [0x02] + functionNameBytes + parameters + [0x00]
                } else if parameters.count > 0 && code[position] != SpecialCharacters.comma.rawValue {
                    fatalError("Unexpected character \(code[position])")
                }
                
                skipWhitespace()
                parameters.append(contentsOf: makeWord() + [0x00])
                
                skipWhitespace()
                
                guard code[position] == SpecialCharacters.colon.rawValue else {
                    fatalError("Expected `:` to open function call. Found `\(code[position])`")
                }
                
                position += 1
                
                skipWhitespace()
                
                parameters.append(contentsOf: compileExpression())
                
                skipWhitespace()
            }
            
            fatalError("Unclosed function parameters. Missing `)`")
        }
        
        func compileStatement(fromData code: [UInt8], position: inout Int, exposingVariables variables: [([UInt8], UInt32)]) -> [UInt8] {
            var binary = [UInt8]()
            
            let wordCode = makeWord()
            
            if let (_, word) = KittenScriptCompiler.binaryWords.first(where: { $0.code == wordCode }) {
                switch word {
                case .if:
                    binary.append(0x01)
                    binary.append(contentsOf: compileExpression())
                    let ifBlock = makeBlock(fromData: code, position: &position, exposingVariables: variables)
                    
                    skipWhitespace()
                    
                    if makeWord() == Word.else.makeBytes() {
                        let elseBlock = makeBlock(fromData: code, position: &position, exposingVariables: variables)
                        
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
                    return [0x05] + compileExpression()
                case .for:
                    binary.append(0x02)
                    
                    skipWhitespace()
                    
                    let variableName = makeWord()
                    
                    guard variableName.count > 0 else {
                        fatalError("Empty variable name")
                    }
                    
                    let variableId = (reservedVariables.sorted().last ?? 0) + 1
                    
                    reservedVariables.append(variableId)
                    
                    binary.append(contentsOf: variableId.bytes)
                    
                    skipWhitespace()
                    
                    let wordBytes = makeWord()
                    
                    guard wordBytes == Word.in.makeBytes() else {
                        fatalError("Invalid word \(wordBytes)")
                    }
                    
                    binary.append(contentsOf: compileExpression())
                    
                    let block = makeBlock(fromData: code, position: &position, exposingVariables: variables + [(variableName, variableId)])
                    
                    binary.append(contentsOf: [0x03, 0x04])
                    binary.append(contentsOf: UInt32(block.count + 5).bytes)
                    binary.append(contentsOf: block)
                    binary.append(0x00)
                default:
                    fatalError("Invalid usage of \(word)")
                }
            } else {
                position -= wordCode.count
                binary.append(contentsOf: [0x04] + compileExpression())
            }
            
            return binary
        }
        
        func makeBlock(fromData code: [UInt8], position: inout Int, exposingVariables: [([UInt8], UInt32)]) -> [UInt8] {
            skipWhitespace()
            
            guard code[position] == SpecialCharacters.codeBlockOpen.rawValue else {
                fatalError("Invalid character \(code[position])")
            }
            
            position += 1
            
            var block = [UInt8]()
            
            while position < code.count {
                skipWhitespace()
                
                defer { position += 1}
                
                if code[position] == SpecialCharacters.codeBlockClose.rawValue {
                    return block
                }
                
                let statement = compileStatement(fromData: code, position: &position, exposingVariables: exposingVariables)
                block.append(contentsOf: statement)
            }
            
            fatalError("Unclosed code block. Missing `}`")
        }
        
        var binary = [UInt8]()
        
        while position < code.count {
            skipWhitespace()
            
            guard position < code.count else {
                return UInt32(binary.count + 5).bytes + binary + [0x00]
            }
            
            let statement = compileStatement(fromData: code, position: &position, exposingVariables: variables)
            
            binary.append(contentsOf: statement)
        }
        
        return UInt32(binary.count + 5).bytes + binary + [0x00]
    }
}
