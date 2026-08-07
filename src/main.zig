const std = @import("std");
const Io = std.Io;

const Word = struct { key: []const u8, freq: u16 };

pub fn main(init: std.process.Init) !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    const gpa = init.gpa;
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;
    var map = std.StringHashMap(u16).init(gpa);
    defer map.deinit();

    const args = try init.minimal.args.toSlice(arena);

    const f = try std.Io.Dir.cwd().readFileAlloc(io, args[1], gpa, .limited(1_000_000));
    defer gpa.free(f);
    var tokens = std.mem.tokenizeAny(u8, f, "*#&/-()\"\': ,.\n");
    while (tokens.next()) |tok| {
        const entry = try map.getOrPut(tok);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.value_ptr.* = 1;
        }
        std.debug.print("{s}\n", .{tok});
    }

    var map_it = map.iterator();
    var entries = try std.ArrayList(Word).initCapacity(gpa, 10);
    defer entries.deinit(gpa);

    while (map_it.next()) |item| {
        try entries.append(gpa, .{ .key = item.key_ptr.*, .freq = item.value_ptr.* });
    }

    var changed = true;
    while (changed) {
        changed = false;
        for (entries.items[0 .. entries.items.len - 1], 0..) |_, i| {
            if (entries.items[i].freq > entries.items[i + 1].freq) {
                std.mem.swap(Word, &entries.items[i], &entries.items[i + 1]);
                changed = true;
            }
        }
    }

    for (entries.items) |item| {
        std.debug.print("{s}: {d}\n", .{ item.key, item.freq });
    }
}
