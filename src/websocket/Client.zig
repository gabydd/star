const std = @import("std");

var rng: ?std.Random.DefaultPrng = null;

stream: std.net.Stream,

pub fn connect(address: std.net.Address) !@This() {
    const client: @This() = .{
        .stream = try std.net.tcpConnectToAddress(address),
    };
    try client.sendHeader();
    return client;
}

fn initRandom() void {
    rng = std.Random.DefaultPrng.init(@intCast(std.time.milliTimestamp()));
}

fn sendHeader(client: @This()) !void {
    var buf: [16]u8 = undefined;
    if (rng == null) initRandom();
    rng.?.fill(&buf);
    for (&buf) |*c| {
        c.* = std.Random.limitRangeBiased(u8, c.*, 95) + 32;
    }
    var dest: [std.base64.standard.Encoder.calcSize(16)]u8 = undefined;
    const encoded = std.base64.standard.Encoder.encode(&dest, &buf);
    try std.fmt.format(client.stream.writer(), "GET / HTTP/1.1\r\nSec-WebSocket-Key: {s}\r\n\r\n", .{encoded});
}

fn read(client: @This()) !void {
    var rec_buf: [100]u8 = undefined;
    var total: usize = 0;
    while (true) {
        const amount = try client.stream.read(&rec_buf[total..]);
        if (amount == 0) break;
        total += amount;
        std.debug.print("{s}\n", .{rec_buf[amount..total]});
    }
}
