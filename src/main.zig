const std = @import("std");
const Io = std.Io;

const Word = struct { key: []const u8, freq: u16 };
const Doc = struct { sub_path: []const u8, word_map: std.StringHashMap(Word), score: u16 = 0 };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena: std.mem.Allocator = init.arena.allocator();

    const io = init.io;

    var map = std.StringHashMap(u16).init(gpa);
    defer map.deinit();

    const args = try init.minimal.args.toSlice(arena);
    const search_keyword = if (args.len > 1) args[1] else std.process.exit(1);
    const dir_path_arg = if (args.len > 2) args[2] else ".";

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
        var docs_iter = doc_map.iterator();
        i.value_ptr.score = calculateScore(&docs_iter, i.value_ptr, search_keyword);
    }
    try printDocWithScoreSorted(doc_map, gpa);
    return;
}

fn printDocWithScoreSorted(doc_map: std.hash_map.StringHashMap(Doc), gpa: std.mem.Allocator) !void {
    var doc_list: std.ArrayList(*Doc) = .empty;
    defer doc_list.deinit(gpa);
    var iter = doc_map.iterator();
    while (iter.next()) |i| {
        try doc_list.append(gpa, i.value_ptr);
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (doc_list.items[0 .. doc_list.items.len - 1], 0..) |_, i| {
            if (doc_list.items[i].*.score > doc_list.items[i + 1].*.score) {
                std.mem.swap(*Doc, &doc_list.items[i], &doc_list.items[i + 1]);
                changed = true;
            }
        }
    }
    for (doc_list.items) |i| {
        std.debug.print("----------------------------------------\n", .{});
        std.debug.print("File: {s}\n", .{i.sub_path});
        std.debug.print("score: {d}\n", .{i.score});
        std.debug.print("----------------------------------------\n", .{});
    }
}

fn printDocWithWords(doc_map: std.hash_map.StringHashMap(Doc)) void {
    var iter = doc_map.iterator();
    while (iter.next()) |i| {
        std.debug.print("----------------------------------------\n", .{});
        std.debug.print("File: {s}\n", .{i.key_ptr.*});
        var word_iter = i.value_ptr.word_map.iterator();
        while (word_iter.next()) |w_entry| {
            std.debug.print("  {s}: {d}\n", .{ w_entry.key_ptr.*, w_entry.value_ptr.freq });
        }
        std.debug.print("----------------------------------------\n", .{});
    }
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
        // const tok_copy = try arena.dupe(u8, std.ascii.low);
        const tok_copy = try arena.alloc(u8, tok.len);
        _ = std.ascii.lowerString(tok_copy, tok);
        const entry = try map.getOrPut(tok_copy);
        entry.value_ptr.key = tok_copy;
        if (entry.found_existing) {
            entry.value_ptr.freq += 1;
        } else {
            entry.value_ptr.freq = 1;
        }
    }
}

fn calculateScore(docs_iter: anytype, doc: *Doc, word: []const u8) u16 {
    if (doc.word_map.get(word)) |in_doc_word| {
        const tf = in_doc_word.freq;
        var idf: u16 = 0;
        while (docs_iter.next()) |i| {
            if (i.value_ptr.word_map.get(word)) |v| {
                idf += v.freq;
            }
        }
        return tf * idf;
    }
    return 0;
}
