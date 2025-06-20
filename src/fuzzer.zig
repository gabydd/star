const star = @import("./root.zig");
const std = @import("std");

test "fuzz" {
    for (0..20) |i| {
        try fuzz(i, std.testing.allocator);
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
            const len: u32 = @intCast(doc[1].snapshot.items.len);
            const weight: f32 = if (len < 100) 0.65 else 0.35;
            if (len == 0 or random.float(f32) < weight) {
                const char = random.intRangeAtMost(u8, 'a', 'z');
                const pos = random.uintLessThan(u32, len + 1);
                try doc[1].insert(gpa, doc[0], pos, &.{char});
                try doc[1].replay(gpa);
            } else {
                const pos = random.uintLessThan(u32, len);
                try doc[1].delete(gpa, doc[0], pos, 1);
                try doc[1].replay(gpa);
            }
        }
        const a = &docs[random.uintLessThan(u32, docs.len)];
        const b = &docs[random.uintLessThan(u32, docs.len)];
        if (a != b) {
            try a[1].merge(gpa, b[1]);
            try a[1].replay(gpa);
            try b[1].merge(gpa, a[1]);
            try b[1].replay(gpa);
            try std.testing.expectEqual(a[1].frontier.items.len, b[1].frontier.items.len);
            try std.testing.expectEqual(a[1].version.get(a[0]), b[1].version.get(a[0]));
            try std.testing.expectEqual(a[1].version.get(b[0]), b[1].version.get(b[0]));
            try std.testing.expectEqualSlices(u8, a[1].snapshot.items, b[1].snapshot.items);
        }
    }
}
