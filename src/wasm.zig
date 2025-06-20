const star = @import("star");
const std = @import("std");

const Wrapper = struct {
    graph: star.EventGraph,
    agent: star.Agent,
};

extern fn returnSlice(ptr: [*]u8, len: usize) void;
export fn createWrapper(agent: star.Agent) *Wrapper {
    const wrapper = std.heap.wasm_allocator.create(Wrapper) catch @panic("OOM");
    wrapper.* = .{
        .agent = agent,
        .graph = .empty,
    };
    return wrapper;
}

export fn destroyWrapper(wrapper: *Wrapper) void {
    std.heap.wasm_allocator.destroy(wrapper);
}

export fn snapshot(wrapper: *Wrapper) void {
    returnSlice(wrapper.graph.snapshot.items.ptr, wrapper.graph.snapshot.items.len);
}

export fn insert(wrapper: *Wrapper, pos: u32, text: [*]u8, text_len: usize) void {
    wrapper.graph.insert(std.heap.wasm_allocator, wrapper.agent, pos, text[0..text_len]) catch @panic("OOM");
}

export fn delete(wrapper: *Wrapper, pos: u32, count: u32) void {
    wrapper.graph.delete(std.heap.wasm_allocator, wrapper.agent, pos, count) catch @panic("OOM");
}

export fn toBytes(wrapper: *Wrapper) void {
    var buffer: std.ArrayListUnmanaged(u8) = .empty;
    wrapper.graph.toBytes(std.heap.wasm_allocator, &buffer) catch @panic("OOM");

    returnSlice(buffer.items.ptr, buffer.items.len);
}

export fn merge(wrapper: *Wrapper, bytes: [*]u8, len: usize) void {
    const other = star.EventGraph.fromBytes(std.heap.wasm_allocator, bytes[0..len]) catch @panic("OOM");
    wrapper.graph.merge(std.heap.wasm_allocator, other) catch @panic("OOM");
}
