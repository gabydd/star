const star = @import("star");
const vaxis = @import("vaxis");
const std = @import("std");
const builtin = @import("builtin");
const SocketServer = @import("websocket/Server.zig");

var done: std.atomic.Value(bool) = .init(false);
pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const gpa = if (builtin.mode == .Debug)
        debug_allocator.allocator()
    else
        std.heap.smp_allocator;
    defer {
        if (builtin.mode == .Debug) _ = debug_allocator.deinit();
    }

    var random = std.Random.DefaultPrng.init(@bitCast(std.time.microTimestamp()));
    const agent = random.next();
    var graph: star.EventGraph = .empty;
    defer graph.deinit(gpa);

    const socket_addr = try std.net.Address.initUnix("/home/gaby/temp/conn");

    var tty = try vaxis.Tty.init();
    defer tty.deinit();
    var vx = try vaxis.init(gpa, .{});
    defer vx.deinit(gpa, tty.anyWriter());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();
    if (std.fs.accessAbsolute("/home/gaby/temp/conn", .{})) {
        const socket = try std.net.connectUnixSocket("/home/gaby/temp/conn");
        const thread = try std.Thread.spawn(.{}, pollSocket, .{ gpa, socket, &loop, &graph.events });
        _ = thread;
    } else |_| {
        var server = try socket_addr.listen(.{});
        const thread = try std.Thread.spawn(.{}, pollWebSocketServer, .{ gpa, &loop, &graph.events });
        const thread2 = try std.Thread.spawn(.{}, pollSocketServer, .{ gpa, &server, &loop, &graph.events });
        _ = thread;
        _ = thread2;
    }

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.anyWriter());

    try vx.queryTerminal(tty.anyWriter(), 1 * std.time.ns_per_ms);

    while (true) {
        var event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    try std.fs.deleteFileAbsolute("/home/gaby/temp/conn");
                    break;
                } else if (key.matches(vaxis.Key.backspace, .{})) {
                    if (graph.snapshot.cursor > 0) {
                        try graph.delete(gpa, agent, graph.snapshot.cursor - 1, 1);
                    }
                } else if (key.matches(vaxis.Key.left, .{})) {
                    graph.snapshot.left();
                } else if (key.matches(vaxis.Key.right, .{})) {
                    graph.snapshot.right();
                } else if (key.matches(vaxis.Key.enter, .{})) {
                    try graph.insert(gpa, agent, graph.snapshot.cursor, "\n");
                } else {
                    if (key.text) |text| {
                        try graph.insert(gpa, agent, graph.snapshot.cursor, text);
                    }
                }
            },
            .winsize => |ws| try vx.resize(gpa, tty.anyWriter(), ws),
            .graph => |*other| {
                try graph.merge(gpa, other.*);
                other.deinit(gpa);
            },
        }
        const win = vx.window();
        win.clear();
        var col: u16 = 0;
        var line: u16 = 0;
        for (graph.snapshot.slice(), 0..) |*c, i| {
            if (c.* == '\n') {
                const cell: vaxis.Cell = .{
                    .char = .{ .grapheme = "⏎" },
                    .style = .{ .bg = if (i == graph.snapshot.cursor) .{ .rgb = .{ 120, 120, 120 } } else .default },
                };
                win.writeCell(col, line, cell);
                col = 0;
                line += 1;
            } else {
                const cell: vaxis.Cell = .{
                    .char = .{ .grapheme = c[0..1] },
                    .style = .{ .bg = if (i == graph.snapshot.cursor) .{ .rgb = .{ 120, 120, 120 } } else .default },
                };
                win.writeCell(col, line, cell);

                col += 1;
            }
        }
        try vx.render(tty.anyWriter());
    }
    done.store(true, .release);
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    graph: star.EventGraph,
};

fn accept(gpa: std.mem.Allocator, conn: std.net.Server.Connection, loop: *vaxis.Loop(Event), events: *std.ArrayListUnmanaged(star.Event)) !void {
    var len: usize = 0;
    var polls: [1]std.posix.pollfd = .{.{ .fd = conn.stream.handle, .events = std.posix.POLL.IN, .revents = undefined }};
    const socket: SocketServer = .{ .conn = conn };
    try socket.acceptSocket();
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    defer buffer.deinit(gpa);
    while (true) {
        // poll socket
        const s = try std.posix.poll(&polls, 0);
        if (done.load(.acquire)) {
            return;
        }
        if (s > 0) {
            if (polls[0].revents == std.posix.POLL.IN) {
                const opcode = socket.read(gpa, &buffer) catch |err| switch (err) {
                    error.EndOfStream => return,
                    else => return err,
                };
                defer buffer.clearRetainingCapacity();
                switch (opcode) {
                    .binary => {
                        loop.postEvent(.{ .graph = try .fromBytes(gpa, buffer.items) });
                    },
                    .ping => {
                        try socket.pong();
                    },
                    else => {},
                }
            } else if (polls[0].revents == 0) {} else {
                return;
            }
        }
        if (done.load(.acquire)) {
            return;
        }
        if (events.items.len > len) {
            try star.eventsToBytes(events.*, gpa, &buffer);
            try socket.write(buffer.items, .binary);
            len = events.items.len;
            buffer.clearRetainingCapacity();
        }
    }
}

fn pollWebSocketServer(gpa: std.mem.Allocator, loop: *vaxis.Loop(Event), events: *std.ArrayListUnmanaged(star.Event)) !void {
    const address = try std.net.Address.resolveIp("0.0.0.0", 1999);
    var web = try address.listen(.{ .reuse_address = true });
    while (true) {
        const conn = try web.accept();
        const thread = try std.Thread.spawn(.{}, accept, .{
            gpa,
            conn,
            loop,
            events,
        });
        _ = thread;
    }
}

fn pollSocketServer(gpa: std.mem.Allocator, server: *std.net.Server, loop: *vaxis.Loop(Event), events: *std.ArrayListUnmanaged(star.Event)) !void {
    const peer = try server.accept();
    try pollSocket(gpa, peer.stream, loop, events);
}

fn pollSocket(gpa: std.mem.Allocator, stream: std.net.Stream, loop: *vaxis.Loop(Event), events: *std.ArrayListUnmanaged(star.Event)) !void {
    const buffer = try gpa.alloc(u8, 1024 * 1024);
    defer gpa.free(buffer);
    var len: usize = 0;
    var polls: [1]std.posix.pollfd = .{.{ .fd = stream.handle, .events = std.posix.POLL.IN, .revents = undefined }};
    var buf: std.ArrayListUnmanaged(u8) = .empty;
    defer buf.deinit(gpa);
    while (true) {
        const s = try std.posix.poll(&polls, 0);
        if (done.load(.acquire)) {
            return;
        }
        if (s > 0) {
            if (polls[0].revents == std.posix.POLL.IN) {
                const size = try stream.read(buffer);
                loop.postEvent(.{ .graph = try .fromBytes(gpa, buffer[0..size]) });
            } else if (polls[0].revents == 0) {} else {
                return;
            }
        }
        if (done.load(.acquire)) {
            return;
        }
        if (events.items.len > len) {
            try star.eventsToBytes(events.*, gpa, &buf);
            try stream.writeAll(buf.items);
            len = events.items.len;
            buf.clearRetainingCapacity();
        }
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
