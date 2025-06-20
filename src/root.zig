const std = @import("std");

pub const OpType = enum(u8) {
    ins,
    del,
};

pub const Op = union(OpType) {
    ins: struct {
        pos: u32,
        content: u8,
    },
    del: struct {
        pos: u32,
    },
};

pub const EventId = u32;

const Event = struct {
    agent: Agent,
    seq: u32,
    parents: []EventId,
    op: Op,
};

const PrepareState = enum(usize) {
    not_yet_inserted,
    inserted,
    _,
    fn deleted(state: PrepareState) usize {
        return @intFromEnum(state) - 2;
    }
    fn advance(state: *PrepareState) void {
        state.* = @enumFromInt(@intFromEnum(state.*) + 1);
    }
    fn retreat(state: *PrepareState) void {
        state.* = @enumFromInt(@intFromEnum(state.*) - 1);
    }
};

const CRDTItem = struct {
    id: EventId,
    prepare_state: PrepareState,
    origin_left: ?EventId,
    origin_right: ?EventId,
    deleted: bool,
};

const CRDTState = struct {
    items: std.ArrayListUnmanaged(*CRDTItem),
    current: std.ArrayListUnmanaged(EventId),
    delete_map: std.AutoArrayHashMapUnmanaged(EventId, EventId),
    id_to_items: std.AutoArrayHashMapUnmanaged(EventId, *CRDTItem),
    pub fn clear(state: *CRDTState, gpa: std.mem.Allocator) void {
        for (state.items.items) |item| {
            gpa.destroy(item);
        }
        state.items.clearRetainingCapacity();
        state.current.clearRetainingCapacity();
        state.delete_map.clearRetainingCapacity();
        state.id_to_items.clearRetainingCapacity();
    }
    pub fn deinit(state: *CRDTState, gpa: std.mem.Allocator) void {
        for (state.items.items) |item| {
            gpa.destroy(item);
        }
        state.items.deinit(gpa);
        state.current.deinit(gpa);
        state.delete_map.deinit(gpa);
        state.id_to_items.deinit(gpa);
    }
    const empty: CRDTState = .{
        .items = .empty,
        .current = .empty,
        .delete_map = .empty,
        .id_to_items = .empty,
    };
};

pub const Agent = u64;

pub const TextBuffer = std.ArrayListUnmanaged(u8);
pub const EventGraph = struct {
    events: std.ArrayListUnmanaged(Event),
    frontier: std.ArrayListUnmanaged(EventId),
    version: std.AutoArrayHashMapUnmanaged(Agent, u32),
    snapshot: TextBuffer,
    state: CRDTState,

    pub const empty: EventGraph = .{
        .events = .empty,
        .frontier = .empty,
        .version = .empty,
        .snapshot = .empty,
        .state = .empty,
    };

    pub fn deinit(graph: *EventGraph, gpa: std.mem.Allocator) void {
        for (graph.events.items) |event| {
            gpa.free(event.parents);
        }
        graph.events.deinit(gpa);
        graph.frontier.deinit(gpa);
        graph.version.deinit(gpa);
        graph.snapshot.deinit(gpa);
        graph.state.deinit(gpa);
    }

    pub fn addLocalOp(graph: *EventGraph, gpa: std.mem.Allocator, agent: Agent, op: Op) !void {
        try graph.version.ensureUnusedCapacity(gpa, 1);
        try graph.events.ensureUnusedCapacity(gpa, 1);
        try graph.frontier.ensureTotalCapacity(gpa, 1);
        const dupe = try gpa.dupe(EventId, graph.frontier.items);
        graph.frontier.clearRetainingCapacity();

        const version = graph.version.getOrPutAssumeCapacity(agent);
        if (!version.found_existing) {
            version.value_ptr.* = 0;
        } else {
            version.value_ptr.* += 1;
        }
        const seq = version.value_ptr.*;
        const lv = graph.events.items.len;
        graph.events.appendAssumeCapacity(.{ .seq = seq, .agent = agent, .op = op, .parents = dupe });
        graph.frontier.appendAssumeCapacity(@intCast(lv));
    }

    pub fn insert(graph: *EventGraph, gpa: std.mem.Allocator, agent: Agent, pos: u32, text: []const u8) !void {
        var p = pos;
        for (text) |c| {
            try graph.addLocalOp(gpa, agent, .{ .ins = .{ .pos = p, .content = c } });
            p += 1;
        }
        try graph.snapshot.insertSlice(gpa, pos, text);
    }

    pub fn delete(graph: *EventGraph, gpa: std.mem.Allocator, agent: Agent, pos: u32, len: u32) !void {
        for (0..len) |_| {
            try graph.addLocalOp(gpa, agent, .{ .del = .{ .pos = pos } });
            _ = graph.snapshot.orderedRemove(pos);
        }
    }

    pub fn merge(graph: *EventGraph, gpa: std.mem.Allocator, remote: EventGraph) !void {
        const frontier = try gpa.dupe(EventId, graph.frontier.items);
        defer gpa.free(frontier);
        for (remote.events.items) |event| {
            if (graph.version.get(event.agent)) |seq| {
                if (seq >= event.seq) continue;
            }
            try graph.version.ensureUnusedCapacity(gpa, 1);
            try graph.events.ensureUnusedCapacity(gpa, 1);
            try graph.frontier.ensureUnusedCapacity(gpa, 1);
            const parents = try gpa.dupe(EventId, event.parents);

            const lv = graph.events.items.len;
            for (parents) |*id| {
                const parentEvent = remote.events.items[id.*];
                for (graph.events.items, 0..) |e, i| {
                    if (e.agent == parentEvent.agent and e.seq == parentEvent.seq) {
                        id.* = @intCast(i);
                        break;
                    }
                }
            }
            std.mem.sortUnstable(EventId, parents, {}, struct {
                fn sort(_: void, a: EventId, b: EventId) bool {
                    return a < b;
                }
            }.sort);
            graph.events.appendAssumeCapacity(.{ .seq = event.seq, .op = event.op, .agent = event.agent, .parents = parents });
            const localEvent = graph.events.items[lv];
            var i: usize = 0;
            var nextI: u32 = 0;
            for (graph.frontier.items) |id| {
                var seen = false;
                while (i < localEvent.parents.len) {
                    if (id < localEvent.parents[i]) break;
                    seen = id == localEvent.parents[i];
                    i += 1;
                    if (seen) {
                        break;
                    }
                }
                if (!seen) {
                    graph.frontier.items[nextI] = id;
                    nextI += 1;
                }
            }
            graph.frontier.items.len = nextI;
            graph.frontier.appendAssumeCapacity(@intCast(lv));
            graph.version.putAssumeCapacity(event.agent, event.seq);
        }
        try graph.replay(gpa, frontier);
    }

    fn indexOf(items: []*CRDTItem, id: EventId) ?usize {
        for (items, 0..) |item, i| {
            if (item.id == id) return i;
        }
        return null;
    }

    fn ltNull(T: type, a: ?T, b: ?T) bool {
        if (a) |a1| {
            if (b) |b1| {
                return a1 < b1;
            }
            return false;
        } else {
            return b != null;
        }
    }
    fn integrate(graph: *EventGraph, state: *CRDTState, gpa: std.mem.Allocator, item: *CRDTItem, i: usize, end_pos: usize, snapshot: ?*TextBuffer) !void {
        var idx = i;
        var end = end_pos;

        var scan_idx = idx;
        var scan_end = end;

        const left = if (scan_idx == 0) null else scan_idx - 1;
        const right = if (item.origin_right) |origin_right| indexOf(state.items.items, origin_right).? else state.items.items.len;

        var scanning = false;
        while (scan_idx < right) {
            const other = state.items.items[scan_idx];
            if (other.prepare_state != .not_yet_inserted) break;

            const oleft = if (other.origin_left) |origin_left| indexOf(state.items.items, origin_left).? else null;
            const oright = if (other.origin_right) |origin_right| indexOf(state.items.items, origin_right).? else state.items.items.len;

            if (ltNull(usize, oleft, left) or (oleft == left and oright == right and graph.events.items[item.id].agent < graph.events.items[other.id].agent)) {
                break;
            }
            if (oleft == left) scanning = ltNull(usize, oright, right);
            if (!other.deleted) scan_end += 1;
            scan_idx += 1;
            if (!scanning) {
                idx = scan_idx;
                end = scan_end;
            }
        }

        try state.items.insert(gpa, idx, item);

        if (snapshot) |snap| try snap.insert(gpa, end, graph.events.items[item.id].op.ins.content);
    }

    pub fn debugEvents(graph: *EventGraph) void {
        for (graph.events.items, 0..) |event, i| {
            std.debug.print("{} : {}-{} {s} {c} {} {any}\n", .{ i, event.agent, event.seq, if (event.op == .ins) "ins" else "del", switch (event.op) {
                .ins => |ins| ins.content,
                .del => ' ',
            }, switch (event.op) {
                .ins => |ins| ins.pos,
                .del => |del| del.pos,
            }, event.parents });
        }
    }

    const DiffFlag = enum { a, b, shared };
    const FlagMap = std.AutoArrayHashMapUnmanaged(EventId, DiffFlag);
    const EventQueue = std.PriorityQueue(EventId, void, struct {
        fn compare(_: void, a: EventId, b: EventId) std.math.Order {
            return std.math.order(b, a);
        }
    }.compare);

    fn enque(gpa: std.mem.Allocator, queue: *EventQueue, flags: *FlagMap, id: EventId, flag: DiffFlag, num_shared: *usize) !void {
        const stored_flag = try flags.getOrPut(gpa, id);
        if (stored_flag.found_existing) {
            if (stored_flag.value_ptr.* != flag and stored_flag.value_ptr.* != .shared) {
                stored_flag.value_ptr.* = .shared;
                num_shared.* += 1;
            }
        } else {
            stored_flag.value_ptr.* = flag;
            try queue.add(id);
            if (flag == .shared) {
                num_shared.* += 1;
            }
        }
    }

    pub fn diff(graph: *EventGraph, gpa: std.mem.Allocator, a: []EventId, b: []EventId) !struct { std.ArrayListUnmanaged(EventId), std.ArrayListUnmanaged(EventId) } {
        var flags: FlagMap = .empty;
        defer flags.deinit(gpa);
        var num_shared: usize = 0;

        var queue: EventQueue = .init(gpa, {});
        defer queue.deinit();
        for (a) |id| {
            try enque(gpa, &queue, &flags, id, .a, &num_shared);
        }
        for (b) |id| {
            try enque(gpa, &queue, &flags, id, .b, &num_shared);
        }
        var a_only: std.ArrayListUnmanaged(EventId) = .empty;
        var b_only: std.ArrayListUnmanaged(EventId) = .empty;

        while (queue.items.len > num_shared) {
            const id = queue.remove();
            const flag = flags.get(id).?;
            switch (flag) {
                .shared => num_shared -= 1,
                .a => try a_only.append(gpa, id),
                .b => try b_only.append(gpa, id),
            }
            const event = graph.events.items[id];
            for (event.parents) |parent| try enque(gpa, &queue, &flags, parent, flag, &num_shared);
        }
        return .{ a_only, b_only };
    }

    pub fn replayEvent(graph: *EventGraph, gpa: std.mem.Allocator, i: EventId, snapshot: ?*TextBuffer) !void {
        const event = graph.events.items[i];
        var a_only, var b_only = try graph.diff(gpa, graph.state.current.items, event.parents);
        defer a_only.deinit(gpa);
        defer b_only.deinit(gpa);

        for (a_only.items) |id| {
            const op = graph.events.items[id].op;
            const target_id = if (op == .ins) id else graph.state.delete_map.get(id).?;
            const target = graph.state.id_to_items.get(target_id).?;
            target.prepare_state.retreat();
        }

        for (b_only.items) |id| {
            const op = graph.events.items[id].op;
            const target_id = if (op == .ins) id else graph.state.delete_map.get(id).?;
            const target = graph.state.id_to_items.get(target_id).?;
            target.prepare_state.advance();
        }

        switch (event.op) {
            .ins => |ins| {
                var cur_pos: usize = 0;
                var idx: usize = 0;
                var end_pos: usize = 0;
                while (cur_pos < ins.pos) {
                    if (graph.state.items.items.len == 0) break;
                    const item = graph.state.items.items[idx];
                    if (item.prepare_state == .inserted) cur_pos += 1;
                    if (!item.deleted) end_pos += 1;
                    idx += 1;
                }
                var origin_right: ?EventId = null;
                for (idx..graph.state.items.items.len) |j| {
                    const item = graph.state.items.items[j];
                    if (item.prepare_state != .not_yet_inserted) {
                        origin_right = item.id;
                        break;
                    }
                }
                const item: *CRDTItem = try gpa.create(CRDTItem);
                const origin_left = if (idx != 0 and graph.state.items.items.len != 0) graph.state.items.items[idx - 1].id else null;
                item.* = .{
                    .id = i,
                    .deleted = false,
                    .prepare_state = .inserted,
                    .origin_left = origin_left,
                    .origin_right = origin_right,
                };
                try graph.integrate(&graph.state, gpa, item, idx, end_pos, snapshot);
                try graph.state.id_to_items.put(gpa, i, item);
            },
            .del => |del| {
                var cur_pos: usize = 0;
                var idx: usize = 0;
                var end_pos: usize = 0;
                while (cur_pos < del.pos or graph.state.items.items[idx].prepare_state != .inserted) {
                    const item = graph.state.items.items[idx];
                    if (item.prepare_state == .inserted) cur_pos += 1;
                    if (!item.deleted) end_pos += 1;
                    idx += 1;
                }
                const item = graph.state.items.items[idx];
                if (!item.deleted) {
                    item.deleted = true;
                    if (snapshot) |snap| _ = snap.orderedRemove(end_pos);
                }
                item.prepare_state = @enumFromInt(2);
                try graph.state.delete_map.put(gpa, i, item.id);
            },
        }
        graph.state.current.clearRetainingCapacity();
        try graph.state.current.ensureTotalCapacity(gpa, 1);
        graph.state.current.appendAssumeCapacity(i);
    }

    pub fn replay(graph: *EventGraph, gpa: std.mem.Allocator, frontier: []EventId) !void {
        graph.state.clear(gpa);
        var a_only, var b_only, var version = try graph.partial(gpa, frontier, graph.frontier.items);
        defer a_only.deinit(gpa);
        defer b_only.deinit(gpa);
        defer version.deinit(gpa);

        for (0..version.items.len) |i| {
            try graph.state.current.append(gpa, version.items[version.items.len - i - 1]);
        }

        const placeholder_len = if (frontier.len == 0) 1 else std.mem.max(EventId, frontier) + 1;
        for (0..placeholder_len) |i| {
            const item = try gpa.create(CRDTItem);
            item.* = .{
                .id = @intCast(i + 1000000000),
                .origin_left = null,
                .origin_right = null,
                .deleted = false,
                .prepare_state = .inserted,
            };
            try graph.state.items.append(gpa, item);
            try graph.state.id_to_items.put(gpa, item.id, item);
        }

        for (0..a_only.items.len) |i| {
            const id = a_only.items[a_only.items.len - i - 1];
            try graph.replayEvent(gpa, id, null);
        }

        for (0..b_only.items.len) |i| {
            const id = b_only.items[b_only.items.len - i - 1];
            try graph.replayEvent(gpa, id, &graph.snapshot);
        }
    }

    const PartialFlag = enum { a, b, shared };
    const PartialFlagMap = std.AutoArrayHashMapUnmanaged(EventId, PartialFlag);

    fn enquePartial(gpa: std.mem.Allocator, queue: *EventQueue, flags: *PartialFlagMap, id: EventId, flag: PartialFlag, num_versions: *u32) !void {
        const stored_flag = try flags.getOrPut(gpa, id);
        if (stored_flag.found_existing) {
            if (stored_flag.value_ptr.* != flag and stored_flag.value_ptr.* != .shared) {
                stored_flag.value_ptr.* = .shared;
                num_versions.* += 1;
            }
        } else {
            stored_flag.value_ptr.* = flag;
            try queue.add(id);
            if (flag == .shared) {
                num_versions.* += 1;
            }
        }
    }

    pub fn partial(graph: *EventGraph, gpa: std.mem.Allocator, a: []EventId, b: []EventId) !struct { std.ArrayListUnmanaged(EventId), std.ArrayListUnmanaged(EventId), std.ArrayListUnmanaged(EventId) } {
        var flags: PartialFlagMap = .empty;
        defer flags.deinit(gpa);

        var num_versions: u32 = 0;
        var queue: EventQueue = .init(gpa, {});
        defer queue.deinit();
        for (a) |id| {
            try enquePartial(gpa, &queue, &flags, id, .a, &num_versions);
        }
        for (b) |id| {
            if (!std.mem.containsAtLeastScalar(EventId, a, 1, id)) {
                try enquePartial(gpa, &queue, &flags, id, .b, &num_versions);
            }
        }
        var a_only: std.ArrayListUnmanaged(EventId) = .empty;
        var b_only: std.ArrayListUnmanaged(EventId) = .empty;
        var version: std.ArrayListUnmanaged(EventId) = .empty;

        var ended: bool = false;
        while (queue.removeOrNull()) |id| {
            const flag = flags.get(id).?;
            switch (flag) {
                .shared => {
                    if ((num_versions > queue.items.len + 1 or queue.peek() == null) and !ended) {
                        try version.append(gpa, id);
                        continue;
                    } else {
                        num_versions -= 1;
                        try a_only.append(gpa, id);
                    }
                },
                .a => try a_only.append(gpa, id),
                .b => try b_only.append(gpa, id),
            }
            const event = graph.events.items[id];
            for (event.parents) |parent| try enquePartial(gpa, &queue, &flags, parent, flag, &num_versions);
            if (event.parents.len == 0) {
                ended = true;
            }
        }
        return .{ a_only, b_only, version };
    }

    pub fn fromBytes(gpa: std.mem.Allocator, buffer: []const u8) !EventGraph {
        var reader: ByteReader = .{ .bytes = buffer, .offset = 0 };
        var graph: EventGraph = .empty;
        const len = reader.read(u32);
        for (0..len) |_| {
            const agent = reader.read(Agent);
            const seq = reader.read(u32);
            const num_parents = reader.read(u32);
            const parents = try gpa.alloc(EventId, num_parents);
            for (0..num_parents) |i| {
                parents[i] = reader.read(EventId);
            }
            const op_type: OpType = @enumFromInt(reader.read(u8));
            const pos = reader.read(u32);
            const op: Op = switch (op_type) {
                .del => .{ .del = .{ .pos = pos } },
                .ins => .{ .ins = .{ .pos = pos, .content = reader.read(u8) } },
            };
            try graph.events.append(gpa, .{ .agent = agent, .seq = seq, .parents = parents, .op = op });
        }
        return graph;
    }

    pub fn toBytes(graph: EventGraph, gpa: std.mem.Allocator, buffer: *std.ArrayListUnmanaged(u8)) !void {
        try writeTo(u32, buffer, gpa, @intCast(graph.events.items.len));
        for (graph.events.items) |event| {
            try writeTo(Agent, buffer, gpa, event.agent);
            try writeTo(u32, buffer, gpa, event.seq);
            try writeTo(u32, buffer, gpa, @intCast(event.parents.len));
            for (event.parents) |parent| {
                try writeTo(EventId, buffer, gpa, parent);
            }
            switch (event.op) {
                .del => |del| {
                    try writeTo(u8, buffer, gpa, @intFromEnum(OpType.del));
                    try writeTo(u32, buffer, gpa, del.pos);
                },
                .ins => |ins| {
                    try writeTo(u8, buffer, gpa, @intFromEnum(OpType.ins));
                    try writeTo(u32, buffer, gpa, ins.pos);
                    try writeTo(u8, buffer, gpa, ins.content);
                },
            }
        }
    }
};

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

fn writeTo(T: type, buffer: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, value: T) !void {
    const bytes = @divExact(@typeInfo(T).int.bits, 8);
    const val: [bytes]u8 = @bitCast(value);
    try buffer.appendSlice(alloc, &val);
}

comptime {
    _ = @import("./fuzzer.zig");
}
