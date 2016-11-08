import Foundation

public enum InstantiationError : Error {
    case notEnoughData
}

/// All errors that can occur when (de)serializing
public enum DeserializationError : Error {
    /// The instantiating went wrong because the element has an invalid size
    case InvalidElementSize
    
    /// The contents of the BSON binary data was invalid
    case InvalidElementContents
    
    /// The lsat element of the Binary Array was invalid
    case InvalidLastElement
    
    /// Something went wrong with parsing (yeah.. very specific)
    case ParseError
    
    /// This operation was invalid
    case InvalidOperation
}

public protocol BSONBytesProtocol {}
extension Int : BSONBytesProtocol {}
extension Int64 : BSONBytesProtocol {}
extension Int32 : BSONBytesProtocol {}
extension Int16 : BSONBytesProtocol {}
extension Int8 : BSONBytesProtocol {}
extension UInt : BSONBytesProtocol {}
extension UInt64 : BSONBytesProtocol {}
extension UInt32 : BSONBytesProtocol {}
extension UInt16 : BSONBytesProtocol {}
extension UInt8 : BSONBytesProtocol {}
extension Double : BSONBytesProtocol {}
extension BSONBytesProtocol {
    /// The bytes in `Self`
    public var bytes : [UInt8] {
        var integer = self
        return withUnsafePointer(to: &integer) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<Self>.size) {
                Array(UnsafeBufferPointer(start: $0, count: MemoryLayout<Self>.size))
            }
        }
    }
}

public func fromBytes<T, S : Collection>(_ bytes: S) throws -> T where S.Iterator.Element == UInt8, S.IndexDistance == Int {
    guard bytes.count >= MemoryLayout<T>.size else {
        throw DeserializationError.InvalidElementSize
    }
    
    return UnsafeRawPointer([UInt8](bytes)).assumingMemoryBound(to: T.self).pointee
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
        let length: Int32 = try fromBytes(Array(data[0...3]))
        
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
