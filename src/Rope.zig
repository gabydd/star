const Rope = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;

const PAGES = 4;
const MAX_BYTES = 1024 - 32;
const CHILDREN = 5;
state: *State,
root: Index,
const Page = struct {
    memory: []align(std.mem.page_size) u8,
    capacity: usize,
    fn init(capacity: usize) !Page {
        const memory = try std.os.mmap(null, capacity, std.os.PROT.READ | std.os.PROT.WRITE, .{ .TYPE = .PRIVATE, .ANONYMOUS = true }, -1, 0);
        errdefer std.os.munmap(memory);
        return .{
            .memory = memory,
            .capacity = capacity,
        };
    }
    fn deinit(page: Page) void {
        std.os.munmap(page.memory);
    }
};
fn PageList(comptime T: type) type {
    return struct {
        const Self = @This();
        const Item = struct {
            index: usize,
            ptr: *T,
        };
        const Node = struct {
            page: Page,
            next: ?*Self.Node,
        };
        first: *Self.Node,
        last: *Self.Node,
        left: usize,
        items: usize = 0,
        alloc: Allocator,
        fn init(a: Allocator) !Self {
            const page = try Page.init(std.mem.page_size * PAGES);
            const first = try a.create(Self.Node);
            first.* = .{ .next = null, .page = page };
            return .{
                .left = page.capacity,
                .first = first,
                .last = first,
                .alloc = a,
            };
        }

        fn addPage(self: *Self) !void {
            const page = try Page.init(self.last.page.capacity * 2);
            const last = try self.alloc.create(Self.Node);
            last.* = .{ .next = null, .page = page };
            self.last.next = last;
            self.last = last;
            self.left = page.capacity;
        }
        fn get(self: Self, index: usize) *T {
            var page = self.first;
            var i = index;
            while (page.page.capacity <= i) {
                i -= page.page.capacity;
                page = page.next.?;
            }
            const ptr: []align(8) u8 = @alignCast(page.page.memory[i..]);
            return @ptrCast(ptr);
        }
        fn create(self: *Self) !Self.Item {
            if (self.left == 0) {
                try self.addPage();
            }
            const index = self.items * @sizeOf(T);
            const last = self.last.page;
            const ptr: []align(8) u8 = @alignCast(last.memory[last.capacity - self.left ..]);
            self.left -= @sizeOf(T);
            self.items += 1;
            return .{ .index = index, .ptr = @ptrCast(ptr) };
        }

        fn deinit(self: *Self) void {
            var page = self.pages.first;
            while (page != null) {
                page.?.data.deinit();
                page = page.?.next;
            }
        }
    };
}
const State = struct {
    leafs: PageList(Leaf),
    nodes: std.ArrayList(Node),
    items: usize,
    fn init(alloc: Allocator) !*State {
        const state = try alloc.create(State);
        state.* = .{
            .leafs = try PageList(Leaf).init(alloc),
            .nodes = std.ArrayList(Node).init(alloc),
            .items = 0,
        };
        return state;
    }

    fn addLeaf(state: *State) !LeafItem {
        const item = try state.leafs.create();
        item.ptr.init();
        state.items += 1;
        return .{ .index = .{ .i = item.index, .leaf = true }, .ptr = item.ptr };
    }

    fn getLeaf(state: State, index: Index) *Leaf {
        return state.leafs.get(index.i);
    }

    fn getLeafWrite(state: *State, index: Index) !LeafItem {
        const leaf = state.leafs.get(index.i);
        if (leaf.refs == 1) {
            return .{ .index = index, .ptr = leaf };
        } else {
            const item = try state.leafs.create();
            leaf.refs -= 1;
            item.ptr.init();
            item.ptr.copy(leaf);
            state.items += 1;
            return .{ .index = .{ .i = item.index, .leaf = true }, .ptr = item.ptr };
        }
    }

    fn addNode(state: *State) !Index {
        const node = try state.nodes.addOne();
        const i = state.nodes.items.len - 1;
        node.init();
        state.items += 1;
        return .{ .i = i, .leaf = false };
    }

    fn getNode(state: State, index: Index) *Node {
        return &state.nodes.items[index.i];
    }

    fn getNodeWrite(state: *State, index: Index) !NodeItem {
        const node: *Node = &state.nodes.items[index.i];
        if (node.refs == 1) {
            return .{ .index = index, .ptr = node };
        } else {
            const item: *Node = try state.nodes.addOne();
            const i = state.nodes.items.len - 1;
            node.refs -= 1;
            item.init();
            item.copy(node);
            state.items += 1;
            return .{ .index = .{ .i = i, .leaf = false }, .ptr = item };
        }
    }

    fn copy(state: State, index: Index) void {
        const node = state.getNode(index);
        node.refs += 1;
        for (node.children[0..node.len]) |child| {
            if (child.leaf) {
                state.getLeaf(child).refs += 1;
            } else {
                state.copy(child);
            }
        }
    }

    fn drop(state: State, index: Index) void {
        dropInternal(state, index);
        if (state.items == 0) {
            state.deinit();
        }
    }

    fn dropInternal(state: State, index: Index) void {
        const node = state.getNode(index);
        node.refs -= 1;
        if (node.refs == 0) {
            state.items -= 1;
        }
        for (node.children) |child| {
            if (child.leaf) {
                var leaf = state.getLeaf(child);
                leaf.refs -= 1;
                if (leaf.refs == 0) {
                    state.items -= 1;
                }
            } else {
                state.dropInternal(child);
            }
        }
    }

    fn deinit(state: State) void {
        state.leafs.deinit();
        state.nodes.deinit();
    }
};

const LeafItem = struct {
    index: Index,
    ptr: *Leaf,
};

const NodeItem = struct {
    index: Index,
    ptr: *Node,
};

const Index = struct {
    i: usize,
    leaf: bool,
};

const Info = struct {
    breaks: usize,
    bytes: usize,
};
const Node = struct {
    children: [CHILDREN]Index,
    info: [CHILDREN]Info,
    parent: usize,
    len: usize,
    refs: usize,

    fn init(node: *Node) void {
        node.refs = 1;
        node.len = 0;
    }

    fn getInfo(node: *Node) Info {
        var info: Info = .{
            .breaks = 0,
            .bytes = 0,
        };
        for (0..node.len) |i| {
            info.breaks += node.info[i].breaks;
            info.bytes += node.info[i].bytes;
        }
        return info;
    }
    fn toString(node: *Node, state: *State, write: *Write) void {
        var buf: [MAX_BYTES]u8 = undefined;
        for (0..node.len) |i| {
            const index = node.children[i];
            if (index.leaf) {
                const offset = node.info[i].bytes;
                @memcpy(write.buffer[write.offset .. write.offset + offset], state.getLeaf(index).toString(&buf));
                write.offset += offset;
            } else {
                state.getNode(index).toString(state, write);
            }
        }
    }

    fn insert(node: *Node, state: *State, index: usize, str: []const u8) !void {
        var acc: usize = 0;
        var i: usize = 0;
        while (acc + node.info[i].bytes < index) {
            acc += node.info[i].bytes;
            i += 1;
        }
        const pos = index - acc;
        if (node.children[i].leaf) {
            const leaf = try state.getLeafWrite(node.children[i]);
            leaf.ptr.insert(pos, str);
            node.info[i] = leaf.ptr.getInfo();
            node.children[i] = leaf.index;
        } else {
            const item = try state.getNodeWrite(node.children[i]);
            try item.ptr.insert(state, pos, str);
            node.info[i] = item.ptr.getInfo();
            node.children[i] = item.index;
        }
    }

    fn copy(node: *Node, other: *Node) void {
        node.parent = other.parent;
        node.len = other.len;
        @memcpy(node.children[0..], other.children[0..]);
        @memcpy(node.info[0..], other.info[0..]);
    }
};

fn breaks(str: []const u8) usize {
    var b: usize = 0;
    for (str) |char| {
        if (char == '\n') {
            b += 1;
        }
    }
    return b;
}
const Leaf = struct {
    buffer: [MAX_BYTES]u8,
    breaks: usize,
    left_len: usize,
    right_len: usize,
    refs: usize,
    fn init(leaf: *Leaf) void {
        leaf.breaks = 0;
        leaf.left_len = 0;
        leaf.right_len = 0;
        leaf.refs = 1;
    }
    fn insert(leaf: *Leaf, pos: usize, str: []const u8) void {
        leaf.move_gap(pos);
        @memcpy(leaf.buffer[leaf.left_len .. leaf.left_len + str.len], str);
        leaf.left_len += str.len;
        leaf.breaks += breaks(str);
    }
    fn move_gap(leaf: *Leaf, pos: usize) void {
        if (pos > leaf.left_len) {
            @memcpy(leaf.buffer[leaf.left_len..pos], leaf.buffer[MAX_BYTES - leaf.right_len .. pos + leaf.gap_size()]);
            leaf.right_len -= pos - leaf.left_len;
            leaf.left_len = pos;
        } else if (pos < leaf.left_len) {
            @memcpy(leaf.buffer[pos + leaf.gap_size() .. MAX_BYTES - leaf.right_len], leaf.buffer[pos..leaf.left_len]);
            leaf.right_len += leaf.left_len - pos;
            leaf.left_len = pos;
        }
    }
    fn remove(leaf: *Leaf, pos: usize, len: usize) void {
        if (pos < leaf.left_len) {
            leaf.move_gap(pos + len);
            leaf.breaks -= breaks(leaf.buffer[pos..leaf.left_len]);
            leaf.left_len = pos;
        } else {
            leaf.move_gap(pos);
            leaf.breaks -= breaks(leaf.buffer[leaf.right_len .. leaf.right_len + len]);
            leaf.right_len -= len;
        }
    }
    inline fn gap_size(leaf: Leaf) usize {
        return MAX_BYTES - leaf.left_len - leaf.right_len;
    }
    inline fn bytes(leaf: Leaf) usize {
        return leaf.left_len + leaf.right_len;
    }
    fn toString(leaf: *Leaf, buf: *[MAX_BYTES]u8) []u8 {
        @memcpy(buf[0..leaf.left_len], leaf.buffer[0..leaf.left_len]);
        @memcpy(buf[leaf.left_len .. leaf.left_len + leaf.right_len], leaf.buffer[MAX_BYTES - leaf.right_len .. MAX_BYTES]);
        return buf[0 .. leaf.left_len + leaf.right_len];
    }

    fn getInfo(leaf: *Leaf) Info {
        return .{
            .bytes = leaf.bytes(),
            .breaks = leaf.breaks,
        };
    }

    fn copy(leaf: *Leaf, other: *Leaf) void {
        leaf.breaks = other.breaks;
        leaf.left_len = other.left_len;
        leaf.right_len = other.right_len;
        @memcpy(leaf.buffer[0..], other.buffer[0..]);
    }
};

fn fromString(str: []const u8, alloc: Allocator) !Rope {
    const state = try State.init(alloc);
    const root = try state.addNode();
    const node = state.getNode(root);
    const leaf = try state.addLeaf();
    leaf.ptr.insert(0, str);
    node.children[0] = leaf.index;
    node.info[0] = leaf.ptr.getInfo();
    node.len += 1;
    return .{
        .state = state,
        .root = root,
    };
}

const Write = struct {
    buffer: []u8,
    offset: usize,
};

fn toString(rope: Rope, alloc: Allocator) ![]u8 {
    const root = rope.state.getNode(rope.root);
    const buffer = try alloc.alloc(u8, root.getInfo().bytes);
    const write = try alloc.create(Write);
    write.* = .{ .offset = 0, .buffer = buffer };
    root.toString(rope.state, write);
    return buffer;
}

fn copy(rope: Rope) Rope {
    rope.state.copy(rope.root);
    return rope;
}

fn insert(rope: *Rope, index: usize, str: []const u8) !void {
    const root = try rope.state.getNodeWrite(rope.root);
    try root.ptr.insert(rope.state, index, str);
    rope.root = root.index;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var rope = try Rope.fromString("hello world\n", arena.allocator());
    var rope2 = rope.copy();
    try rope.insert(5, "no");
    try rope2.insert(3, "no");
    std.debug.print("{s}", .{try rope.toString(arena.allocator())});
    std.debug.print("{s}, {}", .{ try rope2.toString(arena.allocator()), rope2.root });
}
