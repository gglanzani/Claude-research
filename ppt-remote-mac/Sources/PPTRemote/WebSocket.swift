import Foundation
import CryptoKit

func wsAcceptKey(_ clientKey: String) -> String {
    let raw = Data((clientKey + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)
    let digest = Insecure.SHA1.hash(data: raw)
    return Data(digest).base64EncodedString()
}

enum WSOpcode: UInt8 {
    case text = 1, binary = 2, close = 8, ping = 9, pong = 10
}

struct WSFrame {
    let opcode: WSOpcode
    let payload: Data
    let consumed: Int
}

func parseWSFrame(_ data: Data) -> WSFrame? {
    guard data.count >= 2 else { return nil }
    let i = data.startIndex
    let b0 = data[i], b1 = data[i + 1]
    guard let opcode = WSOpcode(rawValue: b0 & 0x0F) else { return nil }
    let masked = (b1 & 0x80) != 0
    var payloadLen = Int(b1 & 0x7F)
    var offset = 2

    if payloadLen == 126 {
        guard data.count >= 4 else { return nil }
        payloadLen = Int(data[i + 2]) << 8 | Int(data[i + 3])
        offset = 4
    } else if payloadLen == 127 {
        guard data.count >= 10 else { return nil }
        payloadLen = (0..<8).reduce(0) { acc, n in (acc << 8) | Int(data[i + 2 + n]) }
        offset = 10
    }

    let totalLen = offset + (masked ? 4 : 0) + payloadLen
    guard data.count >= totalLen else { return nil }

    let maskOffset = offset
    let payloadOffset = offset + (masked ? 4 : 0)
    var payload = data.subdata(in: (i + payloadOffset)..<(i + totalLen))
    if masked {
        let mask = data.subdata(in: (i + maskOffset)..<(i + maskOffset + 4))
        for j in 0..<payload.count { payload[j] ^= mask[j % 4] }
    }

    return WSFrame(opcode: opcode, payload: payload, consumed: totalLen)
}

func makeWSTextFrame(_ text: String) -> Data {
    let payload = Data(text.utf8)
    var frame = Data()
    frame.append(0x81)
    let len = payload.count
    if len < 126 {
        frame.append(UInt8(len))
    } else if len <= 0xFFFF {
        frame.append(126)
        frame.append(UInt8(len >> 8))
        frame.append(UInt8(len & 0xFF))
    } else {
        frame.append(127)
        for shift in stride(from: 56, through: 0, by: -8) { frame.append(UInt8((len >> shift) & 0xFF)) }
    }
    frame.append(contentsOf: payload)
    return frame
}

func makeWSPongFrame(_ payload: Data) -> Data {
    var f = Data([0x8A, UInt8(min(payload.count, 125))])
    f.append(payload.prefix(125))
    return f
}

let wsCloseFrame = Data([0x88, 0x00])
