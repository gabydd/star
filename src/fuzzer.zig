const star = @import("./root.zig");
const std = @import("std");

test "fuzz" {
    for (0..10) |i| {
        try fuzz(i);
    }
}

fn fuzz(seed: u64) !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const alloc = gpa.allocator();
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    var docs: [3]struct { star.Agent, star.EventGraph } = undefined;
    for (&docs, 0..) |*doc, i| {
        doc.* = .{ i, .empty };
    }

    for (0..100) |_| {
        for (0..docs.len) |_| {
            const doc = &docs[random.uintLessThan(u32, docs.len)];
            const len: u32 = @intCast(doc[1].snapshot.items.len);
            const weight: f32 = if (len < 100) 0.65 else 0.35;
            if (len == 0 or random.float(f32) < weight) {
                const char = random.intRangeAtMost(u8, 'a', 'z');
                const pos = random.uintLessThan(u32, len + 1);
                try doc[1].insert(alloc, doc[0], pos, &.{char});
                try doc[1].replay(alloc);
            } else {
                const pos = random.uintLessThan(u32, len);
                try doc[1].delete(alloc, doc[0], pos, 1);
                try doc[1].replay(alloc);
            }
        }
        const a = &docs[random.uintLessThan(u32, docs.len)];
        const b = &docs[random.uintLessThan(u32, docs.len)];
        if (a != b) {
            try a[1].merge(alloc, b[1]);
            try a[1].replay(alloc);
            try b[1].merge(alloc, a[1]);
            try b[1].replay(alloc);
            try std.testing.expectEqual(a[1].frontier.items.len, b[1].frontier.items.len);
            try std.testing.expectEqual(a[1].version.get(a[0]), b[1].version.get(a[0]));
            try std.testing.expectEqual(a[1].version.get(b[0]), b[1].version.get(b[0]));
            try std.testing.expectEqualSlices(u8, a[1].snapshot.items, b[1].snapshot.items);
        }
    }
}
