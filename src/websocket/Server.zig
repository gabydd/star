const std = @import("std");

conn: std.net.Server.Connection,

const State = enum {
    head,
    seen_r,
    seen_rn,
    seen_rnr,
    seen_colon,
    seen_space,
};

pub fn acceptSocket(server: @This()) !void {
    var buffer: [100]u8 = undefined;
    var key: [100]u8 = undefined;
    var key_len: usize = 0;
    var value: [200]u8 = undefined;
    var value_len: usize = 0;
    var state: State = .head;
    var found_key = false;
    blk: while (true) {
        const size = try server.conn.stream.read(&buffer);
        for (buffer[0..size]) |ch| {
            switch (state) {
                .head => {
                    if (ch == '\r') state = .seen_r;
                },
                .seen_r => {
                    if (ch == '\n') state = .seen_rn;
                },
                .seen_rn => {
                    if (ch == '\r') {
                        state = .seen_rnr;
                    } else if (ch == ':') {
                        state = .seen_colon;
                    } else {
                        key[key_len] = ch;
                        key_len += 1;
                    }
                },
                .seen_rnr => {
                    if (ch == '\n') break :blk;
                },
                .seen_colon => {
                    if (ch == ' ') state = .seen_space;
                },
                .seen_space => {
                    if (ch == '\r') {
                        state = .seen_r;
                        if (std.mem.eql(u8, key[0..key_len], "Sec-WebSocket-Key")) {
                            found_key = true;
                        }
                        if (!found_key) {
                            value_len = 0;
                        }
                        key_len = 0;
                    } else if (!found_key) {
                        value[value_len] = ch;
                        value_len += 1;
                    }
                },
            }
        }
    }
    var hash_out: [20]u8 = undefined;
    const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    std.mem.copyForwards(u8, value[value_len..], magic);
    std.crypto.hash.Sha1.hash(value[0 .. value_len + magic.len], &hash_out, .{});
    var dest: [std.base64.standard.Encoder.calcSize(20)]u8 = undefined;
    const encoded = std.base64.standard.Encoder.encode(&dest, hash_out[0..20]);
    try std.fmt.format(server.conn.stream.writer(), "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{encoded});
    try ping(server);
}

pub fn ping(server: @This()) !void {
    try server.write("ping", .ping);
}

pub fn pong(server: @This()) !void {
    try server.write("pong", .pong);
}

const Opcode = std.http.WebSocket.Opcode;

pub fn write(server: @This(), message: []const u8, opcode: Opcode) !void {
    var header: [2]u8 = .{ 0, 0 };
    header[0] |= 0b10000000;
    header[0] |= @intFromEnum(opcode);
    if (message.len > (1 << 16) - 1) {
        header[1] |= 127;
        const len = std.mem.nativeToBig(u64, @intCast(message.len));
        try server.conn.stream.writeAll(&header);
        try server.conn.stream.writeAll(std.mem.asBytes(&len));
    } else if (message.len > 125) {
        header[1] |= 126;
        const len = std.mem.nativeToBig(u16, @intCast(message.len));
        try server.conn.stream.writeAll(&header);
        try server.conn.stream.writeAll(std.mem.asBytes(&len));
    } else {
        header[1] |= @truncate(message.len);
        try server.conn.stream.writeAll(&header);
    }
    try server.conn.stream.writeAll(message);
}

pub fn read(server: @This(), gpa: std.mem.Allocator, buffer: *std.ArrayListUnmanaged(u8)) !Opcode {
    const reader = server.conn.stream.reader();
    const byte = try reader.readByte();
    const opcode: Opcode = @enumFromInt(@as(u4, @truncate(byte)));
    const byte2 = try reader.readByte();
    const masked = (byte2 >> 7) == 1;
    var length: u64 = byte2 & 0b01111111;
    if (length == 126) {
        length = try reader.readInt(u16, .big);
    } else if (length == 127) {
        length = try reader.readInt(u64, .big);
    }
    const mask = if (masked) try reader.readBytesNoEof(4) else .{ 0, 0, 0, 0 };
    try buffer.ensureTotalCapacity(gpa, length);
    for (0..length) |i| {
        buffer.appendAssumeCapacity(try reader.readByte() ^ mask[i % 4]);
    }
    return opcode;
}
