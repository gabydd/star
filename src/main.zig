const star = @import("star");
const vaxis = @import("vaxis");
const std = @import("std");
pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const alloc = gpa.allocator();
    var random = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
    const agent = random.next();
    var graph: star.EventGraph = .empty;

    const socket_addr = try std.net.Address.initUnix("/home/gaby/temp/conn");

    // var buffer1: star.TextBuffer = .empty;
    // var buffer2: star.TextBuffer = .empty;
    // var graph1: star.EventGraph = .empty;
    // const agent1 = 0;
    // var graph2: star.EventGraph = .empty;
    // const agent2 = 1;
    // try graph1.insert(alloc, agent1, 0, "hi");
    // try graph2.insert(alloc, agent2, 0, "yooooo");
    // try graph1.merge(alloc, graph2);
    // try graph2.merge(alloc, graph1);
    // try graph2.delete(alloc, agent2, 1, 1);
    // try graph1.merge(alloc, graph2);
    // try graph1.replay(alloc, &buffer1);
    // std.debug.print("{s}\n", .{buffer1.items});
    // try graph2.replay(alloc, &buffer2);
    // std.debug.print("{s}\n", .{buffer2.items});

    var tty = try vaxis.Tty.init();
    defer tty.deinit();
    var vx = try vaxis.init(alloc, .{});
    var stream: ?std.net.Stream = null;
    defer vx.deinit(alloc, tty.anyWriter());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();
    if (std.fs.accessAbsolute("/home/gaby/temp/conn", .{})) {
        const socket = try std.net.connectUnixSocket("/home/gaby/temp/conn");
        const thread = try std.Thread.spawn(.{}, pollSocket, .{ socket, &loop });
        stream = socket;
        _ = thread;
    } else |_| {
        var server = try socket_addr.listen(.{});
        const thread = try std.Thread.spawn(.{}, pollSocketServer, .{ &server, &loop, &stream });
        _ = thread;
    }

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());

    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_ms);

    var cursor: u32 = 0;
    while (true) {
        var event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key.matches(vaxis.Key.backspace, .{})) {
                    if (cursor > 0) {
                        try graph.delete(alloc, agent, cursor - 1, 1);
                        cursor -= 1;
                        if (stream) |s| try writeSocket(alloc, s, graph);
                    }
                } else if (key.matches(vaxis.Key.left, .{})) {
                    cursor = @intCast(std.math.clamp(cursor - 1, 0, graph.snapshot.items.len));
                } else if (key.matches(vaxis.Key.right, .{})) {
                    cursor = @intCast(std.math.clamp(cursor + 1, 0, graph.snapshot.items.len));
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    try graph.insert(alloc, agent, cursor, "\n");
                    cursor += 1;
                    if (stream) |s| try writeSocket(alloc, s, graph);
                } else {
                    if (key.text) |text| {
                        try graph.insert(alloc, agent, cursor, text);
                        cursor += @intCast(text.len);
                        if (stream) |s| try writeSocket(alloc, s, graph);
                    }
                }
            },
            .winsize => |ws| try vx.resize(alloc, tty.anyWriter(), ws),
            .graph => |*other| {
                try graph.merge(alloc, other.*);
                cursor = @intCast(std.math.clamp(cursor, 0, graph.snapshot.items.len));
            },
        }
        const win = vx.window();
        win.clear();
        var col: u16 = 0;
        var line: u16 = 0;
        for (graph.snapshot.items, 0..) |*c, i| {
            if (c.* == '\n') {
                const cell: vaxis.Cell = .{
                    .char = .{ .grapheme = "⏎" },
                    .style = .{ .bg = if (i == cursor) .{ .rgb = .{ 120, 120, 120 } } else .default },
                };
                win.writeCell(col, line, cell);
                col = 0;
                line += 1;
            } else {
                const cell: vaxis.Cell = .{
                    .char = .{ .grapheme = c[0..1] },
                    .style = .{ .bg = if (i == cursor) .{ .rgb = .{ 120, 120, 120 } } else .default },
                };
                win.writeCell(col, line, cell);

                col += 1;
            }
        }
        try vx.render(tty.anyWriter());
    }
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    graph: star.EventGraph,
};

fn writeTo(T: type, buffer: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, value: T) !void {
    const bytes = @divExact(@typeInfo(T).int.bits, 8);
    const val: [bytes]u8 = @bitCast(value);
    try buffer.appendSlice(alloc, &val);
}

fn writeSocket(alloc: std.mem.Allocator, stream: std.net.Stream, graph: star.EventGraph) !void {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(alloc);
    try graph.toBytes(alloc, &buffer);
    try stream.writeAll(buffer.items);
}

fn pollSocketServer(server: *std.net.Server, loop: *vaxis.Loop(Event), stream: *?std.net.Stream) !void {
    const peer = try server.accept();
    stream.* = peer.stream;
    try pollSocket(peer.stream, loop);
}

fn pollSocket(stream: std.net.Stream, loop: *vaxis.Loop(Event)) !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const alloc = gpa.allocator();
    const buffer = try alloc.alloc(u8, 1024 * 1024);
    while (true) {
        const size = try stream.read(buffer);
        loop.postEvent(.{ .graph = try .fromBytes(alloc, buffer[0..size]) });
    }
}

const ByteReader = struct {
    bytes: []const u8,
    offset: u32,
    pub fn read(reader: *ByteReader, T: type) T {
        const bytes = @divExact(@typeInfo(T).int.bits, 8);
        const val: T = @bitCast(reader.bytes[reader.offset..][0..bytes].*);
        reader.offset += bytes;
        return val;
    }
    pub fn readFrom(reader: *ByteReader, T: type, offset: u32) T {
        reader.skip(offset);
        return reader.read(T);
    }
    pub fn skip(reader: *ByteReader, offset: u32) void {
        reader.offset += offset;
    }
    pub fn reset(reader: *ByteReader, offset: u32) void {
        reader.offset = offset;
    }
};
