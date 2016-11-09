import Foundation

public enum TemplateError: Error {
    case emptyStartOrEndTag
}

public struct KittenScriptTemplate {
    public typealias Metadata = (templateCodeStart: String, templateCodeEnd: String)
    
    var code: KittenScriptCode
    
    public init?(atPath path: String, withMetadata metadata: Metadata = ("{{>", "<}}")) throws {
        guard let data = NSData(contentsOfFile: path) else {
            throw CompilerError.cannotLoadFile(atPath: path)
        }
        var bytes = [UInt8](repeating: 0, count: data.length)
        data.getBytes(&bytes, length: bytes.count)
        
        self.code = try KittenScriptTemplate.compile(bytes, withMetadata: metadata)
    }
    
    private static func compile(_ bytes: [UInt8], withMetadata metadata: Metadata) throws -> KittenScriptCode {
        let codeStartBytes = [UInt8](metadata.templateCodeStart.utf8)
        let codeEndBytes = [UInt8](metadata.templateCodeEnd.utf8)
        
        guard codeStartBytes.count > 0 && codeEndBytes.count > 0 else {
            throw TemplateError.emptyStartOrEndTag
        }
        
        var code = bytes
        var position = 0
        var stringBuilderPosition = 0
        
        var kittenCode = [UInt8]()
        
        func appendString(offset: Int = 0) {
            if position - offset > stringBuilderPosition {
                let string = Array(code[stringBuilderPosition..<position - offset])
                
                kittenCode.append(contentsOf: [0x04, 0x02])
                kittenCode.append(contentsOf: "render".utf8)
                kittenCode.append(0x00)
                kittenCode.append(contentsOf: "string".utf8)
                kittenCode.append(contentsOf: [0x00, 0x03, 0x01])
                kittenCode.append(contentsOf: UInt32(string.count).bytes + string)
                kittenCode.append(0x00)
            }
        }
        
        while position < code.count {
            startDetector: if code[position] == codeStartBytes.first {
                var offset = 1
                
                startMatcher: while position + offset < code.count {
                    defer { offset += 1 }
                    
                    guard offset < codeStartBytes.count && code[position + offset] == codeStartBytes[offset] else {
                        defer { position += offset }
                        
                        if offset == codeStartBytes.count {
                            break startMatcher
                        }
                        
                        break startDetector
                    }
                }
                
                appendString(offset: offset)
                
                let codeStartPosition = position
                
                while position < code.count {
                    endDetector: if code[position] == codeEndBytes.first {
                        var offset = 1
                        
                        endMatcher: while position + offset < code.count {
                            defer { offset += 1 }
                            
                            guard offset < codeEndBytes.count && code[position + offset] == codeEndBytes[offset] else {
                                defer { position += offset }
                                
                                if offset == codeEndBytes.count {
                                    break endMatcher
                                }
                                
                                break endDetector
                            }
                        }
                        
                        let compiledCode = try KittenScriptCompiler.compile(Array(code[codeStartPosition..<position - offset]))
                        
                        kittenCode.append(contentsOf: [0x04, 0x01, 0x03, 0x04])
                        kittenCode.append(contentsOf: compiledCode)
                        kittenCode.append(contentsOf: [0x00])
                        
                        stringBuilderPosition = position
                    } else {
                        position += 1
                    }
                }
            } else {
                position += 1
            }
        }
        
        appendString()
        
        return KittenScriptCode(UInt32(kittenCode.count + 5).bytes + kittenCode + [0x00])
    }
    
    public func run(withParameters parameters: [String: KittenScriptValue], inContext context: [UInt32: [UInt8]], dynamicFunctions: [String: DynamicFunction]) throws -> String {
        var dynamicFunctions = dynamicFunctions
        
        var rendered = ""
        
        dynamicFunctions["render"] = { parameters in
            if let string = parameters["string"]?.stringValue {
                rendered.append(string)
            }
            
            return nil
        }
        
        _ = try code.run(withParameters: parameters, inContext: context, dynamicFunctions: dynamicFunctions)
        
        return rendered
    }
}
