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

fn ping(server: @This()) !void {
    var header: [2]u8 = .{ 0, 0 };
    header[0] |= 0b10000000;
    header[0] |= 0b00001001;
    header[1] |= 0b00000100;
    _ = try server.conn.stream.write(&header);
    _ = try server.conn.stream.write("ping");
}
const Opcode = std.http.WebSocket.Opcode;
pub fn write(server: @This(), message: []const u8) !void {
    var header: [2]u8 = .{ 0, 0 };
    header[0] |= 0b10000000;
    header[0] |= @intFromEnum(Opcode.binary);
    if (message.len > (1 << 16) - 1) {
        header[1] |= 127;
        const len = std.mem.nativeToBig(u64, @intCast(message.len));
        _ = try server.conn.stream.writeAll(&header);
        _ = try server.conn.stream.writeAll(std.mem.asBytes(&len));
    } else if (message.len > 125) {
        header[1] |= 126;
        const len = std.mem.nativeToBig(u16, @intCast(message.len));
        _ = try server.conn.stream.writeAll(&header);
        _ = try server.conn.stream.writeAll(std.mem.asBytes(&len));
    } else {
        header[1] |= @truncate(message.len);
        _ = try server.conn.stream.writeAll(&header);
    }
    _ = try server.conn.stream.writeAll(message);
}
