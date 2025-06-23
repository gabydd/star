const star = @import("./root.zig");
const std = @import("std");
const builtin = @import("builtin");

test "fuzz" {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const gpa = if (builtin.mode == .Debug)
        debug_allocator.allocator()
    else
        std.heap.smp_allocator;
    defer {
        if (builtin.mode == .Debug) _ = debug_allocator.deinit();
    }

    for (0..1000) |i| {
        try fuzz(i, gpa);
    }
}

fn fuzz(seed: u64, gpa: std.mem.Allocator) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    var docs: [3]struct { star.Agent, star.EventGraph } = undefined;
    defer {
        for (&docs) |*doc| {
            doc[1].deinit(gpa);
        }
    }
    for (&docs, 0..) |*doc, i| {
        doc.* = .{ i, .empty };
    }

    for (0..100) |_| {
        for (0..docs.len) |_| {
            const doc = &docs[random.uintLessThan(u32, docs.len)];
            const len: u32 = @intCast(doc[1].snapshot.size());
            const weight: f32 = if (len < 100) 0.65 else 0.35;
            if (len == 0 or random.float(f32) < weight) {
                const char = random.intRangeAtMost(u8, 'a', 'z');
                const pos = random.uintLessThan(u32, len + 1);
                try doc[1].insert(gpa, doc[0], pos, &.{char});
            } else {
                const pos = random.uintLessThan(u32, len);
                try doc[1].delete(gpa, doc[0], pos, 1);
            }
        }
        const a = &docs[random.uintLessThan(u32, docs.len)];
        const b = &docs[random.uintLessThan(u32, docs.len)];
        if (a != b) {
            try a[1].merge(gpa, b[1]);
            try b[1].merge(gpa, a[1]);
            try std.testing.expectEqualSlices(u8, a[1].snapshot.slice(), b[1].snapshot.slice());
        }
    }
}
