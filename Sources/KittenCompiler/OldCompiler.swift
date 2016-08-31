import CommonKitten

public enum ParseError : Error {
    case unexpectedEndOfScript
    case unexpectedCharacter
}

public func compile(_ script: String) throws -> [UInt8] {
    let characters = script.characters
    var position = characters.startIndex
    var bitcode = [UInt8]()
    typealias Expression = [UInt8]
    typealias Statement = [UInt8]
    
    // helper functions
    func advance() {
        position = characters.index(after: position)
    }
    
    @discardableResult func safetyBelt() throws -> Bool {
        guard characters.endIndex >= position else {
            throw ParseError.unexpectedEndOfScript
        }
        
        return true
    }
    
    let whitespace: [Character] = [" ", "\t", "\n", "\r"]
    func skipWhitespace() throws {
        while characters.endIndex > position && whitespace.contains(script.characters[position]) {
            advance()
        }
    }
    
    // Position aftwerwards: character AFTER word
    let identifierCharacterRanges = [
        0x41...0x5a, // A-Z
        0x61...0x7a  // a-z
    ]
    let identifierCharacters: [Character] = {
        var characters = [Character]()
        for range in identifierCharacterRanges {
            for unicodeValue in range {
                characters.append(Character(UnicodeScalar(unicodeValue)))
            }
        }
        return characters
    }()
    func getWord() throws -> String {
        try skipWhitespace()
        let startIndex = position
        
        while try safetyBelt() && identifierCharacters.contains(script.characters[position]) {
            advance()
        }
        
        let wordString = String(characters[startIndex..<position])
        
        return wordString
    }
    
    func makeDynamicFunctionCall(name: String) -> Expression {
        return [0x02] + [UInt8](name.utf8) + [0x00,0x00]
    }
    
    func makeStatement(expression: Expression) -> [UInt8] {
        return [0x04] + expression
    }
    
    func parseStatement() throws {
        // statements always start with an identifier for now
        let identifier = try getWord()
        
        // skip whitespace
        try skipWhitespace()
        
        let characterAfterIdentifier = characters[position]
        advance()
        
        switch characterAfterIdentifier {
        case "(":
            // function call
            try skipWhitespace()
            
            // dont support arguments now:
            guard characters[position] == ")" else {
                throw ParseError.unexpectedCharacter
            }
            
            advance()
            
            // append function call to bitcode:
            bitcode += makeStatement(expression: makeDynamicFunctionCall(name: identifier))
        default:
            throw ParseError.unexpectedCharacter
        }
    }
    
    while position < characters.endIndex {
        try parseStatement()
    }
    
    // prepend the length to the bitcode, and return it:
    let length = UInt32(bitcode.count + 5)
    
    return length.bytes + bitcode + [0x00]
}
