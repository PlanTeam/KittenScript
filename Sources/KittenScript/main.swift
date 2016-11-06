import Foundation
import ScriptUtils

enum Word: String {
    case `if`, `else`, `return`
    
    func makeBytes() -> [UInt8] {
        return [UInt8](self.rawValue.utf8)
    }
}

enum SpecialCharacters: UInt8 {
    case codeBlockOpen = 0x7b
    case codeBlockClose = 0x7d
}

let wordCache: [Word] = [
    .if, .else, .return
]

let binaryWords: [(code: [UInt8], word: Word)] = wordCache.map {
    ($0.makeBytes(), $0)
}

func compile(_ code: String) -> [UInt8] {
    let code = [UInt8](code.utf8)
    
    var position = 0
    
    let whitespace: [UInt8] = [0x20, 0x0a]
    
    func skipWhitespace() {
        while position < code.count, whitespace.contains(code[position]) || (code[position] == 0x5c && code[position + 1] == 0x6e) {
            position += 1
        }
    }
    
    func makeWord() -> [UInt8] {
        var wordBuffer = [UInt8]()
        
        while position < code.count && !whitespace.contains(code[position]) {
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
    
    func makeLiteral() -> [UInt8]? {
        let word = makeWord()
        
        if word == [UInt8]("true".utf8) {
            return [0x03, 0x01]
        } else if word == [UInt8]("false".utf8) {
            return [0x03, 0x00]
        }
        
        return nil
    }
    
    func makeExpression() -> [UInt8] {
        skipWhitespace()
        
        if let literal = makeLiteral() {
            return [0x03] + literal
        }
        
        fatalError("Invalid expression")
    }
    
    func makeStatement() -> [UInt8] {
        var binary = [UInt8]()
        
        let wordCode = makeWord()
        
        if let (_, word) = binaryWords.first(where: { $0.code == wordCode }) {
            switch word {
            case .if:
                binary.append(0x01)
                binary.append(contentsOf: makeExpression())
                let ifBlock = makeBlock()
                
                if makeWord() == Word.else.makeBytes() {
                    let elseBlock = makeBlock()
                    
                    binary.append(contentsOf: UInt32(ifBlock.count).bytes)
                    binary.append(contentsOf: UInt32(elseBlock.count).bytes)
                    
                    binary.append(contentsOf: ifBlock)
                    binary.append(contentsOf: elseBlock)
                } else {
                    binary.append(contentsOf: UInt32(ifBlock.count).bytes)
                    
                    binary.append(contentsOf: ifBlock)
                }
            case .return:
                return [0x05] + makeExpression()
            default:
                fatalError("Invalid usage of \(word)")
            }
        } else {
            
        }
        
        return binary
    }
    
    func makeBlock() -> [UInt8] {
        skipWhitespace()
        
        guard code[position] == SpecialCharacters.codeBlockOpen.rawValue else {
            fatalError("Invalid character \(code[position])")
        }
        
        position += 1
        
        defer {
            position += 1
        }
        
        var block = [UInt8]()
        
        while position < code.count {
            skipWhitespace()
            let statement = makeStatement()
            block.append(contentsOf: statement)
            
            defer { position += 1}
            
            skipWhitespace()
            
            if code[position] == SpecialCharacters.codeBlockClose.rawValue {
                return block
            }
        }
        
        fatalError("Unclosed code block. Missing `{`")
    }
    
    var binary = [UInt8]()
    
    while position < code.count {
        skipWhitespace()
        
        binary.append(contentsOf: makeStatement())
    }
    
    return UInt32(binary.count + 5).bytes + binary + [0x00]
}



print(run(code: [
    21, 0, 0, 0,
    0x01, 0x03, 0x03, 0x00, // if false {
    0x00, 0x00, 0x00, 0x00, // } else {
    0x04, 0x00, 0x00, 0x00, 0x05, 0x03, 0x03, 0x01,
    // }
    0
    ]) ?? [])

let code = try! String.init(contentsOfFile: "/Users/joannis/Desktop/code.swift")

print(run(code: compile(code)) ?? [])
