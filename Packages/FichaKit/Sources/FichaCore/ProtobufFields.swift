import Foundation

/// The fields of a protobuf message, read by hand from its wire format, as
/// protobuf's encoding guide describes it (protobuf.dev/programming-guides/
/// encoding): a key, the field's number and its wire type, before each
/// value. Anki's packages hold a few messages, of which Ficha reads only a
/// handful of fields, so it reads them here rather than through a protobuf
/// library and the messages' definitions. Fields it doesn't ask for are
/// skipped by their wire type, and a field left out reads as protobuf's
/// default, as proto3 leaves out a field that holds it.
public struct ProtobufFields: Sendable {
    /// The varint fields' values, by their numbers: the last one when a
    /// field comes more than once, as protobuf reads it.
    private var varints: [UInt64: UInt64] = [:]
    /// The length-delimited fields' values, by their numbers, in order: a
    /// string, bytes, an embedded message, or a repeated field's elements.
    private var lengthDelimited: [UInt64: [Data]] = [:]

    /// The fields `message` holds, or why it isn't a protobuf message.
    public init(_ message: Data) throws(ProtobufProblem) {
        var bytes = message[...]
        while !bytes.isEmpty {
            let key = try popVarint(from: &bytes)
            let number = key >> 3
            guard number > 0 else {
                throw ProtobufProblem("A protobuf message has a field numbered 0")
            }
            switch key & 7 {
            case 0:
                varints[number] = try popVarint(from: &bytes)
            case 1:
                try skip(8, of: &bytes)
            case 2:
                let length = try popVarint(from: &bytes)
                guard length <= UInt64(bytes.count) else {
                    throw ProtobufProblem("A protobuf message ends in the middle of field \(number)")
                }
                lengthDelimited[number, default: []].append(Data(bytes.prefix(Int(length))))
                bytes = bytes.dropFirst(Int(length))
            case 5:
                try skip(4, of: &bytes)
            default:
                throw ProtobufProblem("A protobuf message's field \(number) has the wire type \(key & 7)")
            }
        }
    }

    /// The integer, enum or bool field `number` holds, or 0 without it.
    public func varint(_ number: UInt64) -> UInt64 {
        varints[number] ?? 0
    }

    /// The string field `number` holds, or an empty string without it.
    public func string(_ number: UInt64) throws(ProtobufProblem) -> String {
        guard let bytes = lengthDelimited[number]?.last else {
            return ""
        }
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw ProtobufProblem("A protobuf message's field \(number) isn't UTF-8 text")
        }
        return string
    }

    /// Each value of the repeated field `number`, in order, as the bytes of
    /// each element, such as an embedded message: none without it.
    public func repeated(_ number: UInt64) -> [Data] {
        lengthDelimited[number] ?? []
    }
}

/// Why bytes can't be read as a protobuf message: they're damaged, or not
/// one.
public struct ProtobufProblem: Error, Equatable, CustomStringConvertible {
    public let description: String

    init(_ description: String) {
        self.description = description
    }
}

/// The varint at the start of `bytes`, which it drops: seven bits a byte,
/// the lowest first, until a byte without its top bit.
private func popVarint(from bytes: inout Data.SubSequence) throws(ProtobufProblem) -> UInt64 {
    var value: UInt64 = 0
    var shift: UInt64 = 0
    while shift < 64, let byte = bytes.popFirst() {
        value |= UInt64(byte & 0x7F) << shift
        if byte & 0x80 == 0 {
            return value
        }
        shift += 7
    }
    throw ProtobufProblem("A protobuf message has a number cut short, or longer than 64 bits")
}

/// Drops `count` bytes from the start of `bytes`, a fixed-size field's
/// value.
private func skip(_ count: Int, of bytes: inout Data.SubSequence) throws(ProtobufProblem) {
    guard bytes.count >= count else {
        throw ProtobufProblem("A protobuf message ends in the middle of a field")
    }
    bytes = bytes.dropFirst(count)
}
