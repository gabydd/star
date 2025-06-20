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
};

pub const Agent = u64;

pub const TextBuffer = std.ArrayListUnmanaged(u8);
pub const EventGraph = struct {
    events: std.ArrayListUnmanaged(Event),
    frontier: std.ArrayListUnmanaged(EventId),
    version: std.AutoArrayHashMapUnmanaged(Agent, u32),
    snapshot: TextBuffer,

    pub const empty: EventGraph = .{
        .events = .empty,
        .frontier = .empty,
        .version = .empty,
        .snapshot = .empty,
    };

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
    }

    pub fn delete(graph: *EventGraph, gpa: std.mem.Allocator, agent: Agent, pos: u32, len: u32) !void {
        var p = pos;
        for (0..len) |_| {
            try graph.addLocalOp(gpa, agent, .{ .del = .{ .pos = pos } });
            p += 1;
        }
    }

    pub fn merge(graph: *EventGraph, gpa: std.mem.Allocator, remote: EventGraph) !void {
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
    fn integrate(graph: *EventGraph, state: *CRDTState, gpa: std.mem.Allocator, item: *CRDTItem, i: usize, end_pos: usize) !void {
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

        try graph.snapshot.insert(gpa, end, graph.events.items[item.id].op.ins.content);
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

    pub fn replay(graph: *EventGraph, gpa: std.mem.Allocator) !void {
        graph.snapshot.clearRetainingCapacity();
        var state: CRDTState = .{ .current = .empty, .delete_map = .empty, .id_to_items = .empty, .items = .empty };
        for (graph.events.items, 0..) |event, i| {
            var old: std.AutoArrayHashMapUnmanaged(EventId, void) = .empty;
            var new: std.AutoArrayHashMapUnmanaged(EventId, void) = .empty;
            var queue: std.ArrayListUnmanaged(EventId) = .empty;
            try queue.appendSlice(gpa, state.current.items);

            while (queue.pop()) |id| {
                if (old.contains(id)) continue;
                try old.put(gpa, id, {});
                try queue.appendSlice(gpa, graph.events.items[id].parents);
            }

            queue.clearRetainingCapacity();
            try queue.appendSlice(gpa, event.parents);

            while (queue.pop()) |id| {
                if (new.contains(id)) continue;
                try new.put(gpa, id, {});
                try queue.appendSlice(gpa, graph.events.items[id].parents);
            }

            for (old.entries.items(.key)) |id| {
                if (!new.contains(id)) {
                    const op = graph.events.items[id].op;
                    const target_id = if (op == .ins) id else state.delete_map.get(id).?;
                    const target = state.id_to_items.get(target_id).?;
                    target.prepare_state.retreat();
                }
            }

            for (new.entries.items(.key)) |id| {
                if (!old.contains(id)) {
                    const op = graph.events.items[id].op;
                    const target_id = if (op == .ins) id else state.delete_map.get(id).?;
                    const target = state.id_to_items.get(target_id).?;
                    target.prepare_state.advance();
                }
            }

            switch (event.op) {
                .ins => |ins| {
                    var cur_pos: usize = 0;
                    var idx: usize = 0;
                    var end_pos: usize = 0;
                    while (cur_pos < ins.pos) {
                        if (state.items.items.len == 0) break;
                        const item = state.items.items[idx];
                        if (item.prepare_state == .inserted) cur_pos += 1;
                        if (!item.deleted) end_pos += 1;
                        idx += 1;
                    }
                    var origin_right: ?EventId = null;
                    for (idx..state.items.items.len) |j| {
                        const item = state.items.items[j];
                        if (item.prepare_state != .not_yet_inserted) {
                            origin_right = item.id;
                            break;
                        }
                    }
                    const item: *CRDTItem = try gpa.create(CRDTItem);
                    const origin_left = if (idx != 0 and state.items.items.len != 0) state.items.items[idx - 1].id else null;
                    item.* = .{
                        .id = @intCast(i),
                        .deleted = false,
                        .prepare_state = .inserted,
                        .origin_left = origin_left,
                        .origin_right = origin_right,
                    };
                    try graph.integrate(&state, gpa, item, idx, end_pos);
                    try state.id_to_items.put(gpa, @intCast(i), item);
                },
                .del => |del| {
                    var cur_pos: usize = 0;
                    var idx: usize = 0;
                    var end_pos: usize = 0;
                    while (cur_pos < del.pos or state.items.items[idx].prepare_state != .inserted) {
                        const item = state.items.items[idx];
                        if (item.prepare_state == .inserted) cur_pos += 1;
                        if (!item.deleted) end_pos += 1;
                        idx += 1;
                    }
                    const item = state.items.items[idx];
                    if (!item.deleted) {
                        item.deleted = true;
                        _ = graph.snapshot.orderedRemove(end_pos);
                    }
                    item.prepare_state = @enumFromInt(2);
                    try state.delete_map.put(gpa, @intCast(i), item.id);
                },
            }
            state.current.clearRetainingCapacity();
            try state.current.ensureTotalCapacity(gpa, 1);
            state.current.appendAssumeCapacity(@intCast(i));
        }
    }
};

comptime {
    _ = @import("./fuzzer.zig");
}
