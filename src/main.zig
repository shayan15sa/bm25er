const std = @import("std");
const Io = std.Io;

const Word = struct { key: []const u8, freq: u16 };
const Doc = struct { sub_path: []const u8, word_map: std.StringHashMap(Word) };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena: std.mem.Allocator = init.arena.allocator();

    const io = init.io;

    var map = std.StringHashMap(u16).init(gpa);
    defer map.deinit();

    const args = try init.minimal.args.toSlice(arena);
    const dir_path_arg = if (args.len > 1) args[1] else ".";

    const dir = try std.Io.Dir.cwd().openDir(io, dir_path_arg, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(gpa);
    defer walker.deinit();

    var doc_map = std.StringHashMap(Doc).init(gpa);
    defer {
        var iter = doc_map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.word_map.deinit();
        }
        doc_map.deinit();
    }

    while (try walker.next(io)) |w| {
        if (w.kind == .file) {
            const path_copy = try arena.dupe(u8, w.path);
            const doc = try doc_map.getOrPutValue(path_copy, .{ .sub_path = path_copy, .word_map = std.StringHashMap(Word).init(gpa) });
            try addWordsForAFile(gpa, arena, dir, io, w.path, &doc.value_ptr.*.word_map);
        } else {
            continue;
        }
    }

    var iter = doc_map.iterator();
    while (iter.next()) |i| {
        std.debug.print("File: {s}\n", .{i.key_ptr.*});
        var word_iter = i.value_ptr.word_map.iterator();
        while (word_iter.next()) |w_entry| {
            std.debug.print("  {s}: {d}\n", .{ w_entry.key_ptr.*, w_entry.value_ptr.freq });
        }
    }
    return;
}

fn addWordsForAFile(gpa: std.mem.Allocator, arena: std.mem.Allocator, dir: std.Io.Dir, io: std.Io, file_name: []const u8, map: *std.StringHashMap(Word)) !void {
    const f = std.Io.Dir.readFileAlloc(dir, io, file_name, gpa, .limited(1_000_000)) catch |err| {
        switch (err) {
            error.StreamTooLong => {
                std.debug.print("File {s} is too big abbas", .{file_name});
                return;
            },
            else => {
                return err;
            },
        }
    };
    defer gpa.free(f);

    var tokens = std.mem.tokenizeAny(u8, f, "[]*#&/-()\"\': ,.\n");
    while (tokens.next()) |tok| {
        const tok_copy = try arena.dupe(u8, tok);
        const entry = try map.getOrPut(tok_copy);
        entry.value_ptr.key = tok_copy;
        if (entry.found_existing) {
            entry.value_ptr.freq += 1;
        } else {
            entry.value_ptr.freq = 1;
        }
    }
}
