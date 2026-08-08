const std = @import("std");
const Io = std.Io;

const Word = struct { key: []const u8, freq: u16 };
const Doc = struct { sub_path: []const u8, word_map: std.StringHashMap(Word), lenght: u32, score: f32 = 0.0 };

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
    var sum_length: u32 = 0;
    var doc_counter: u32 = 0;
    while (try walker.next(io)) |w| {
        if (w.kind == .file) {
            const path_copy = try arena.dupe(u8, w.path);
            const doc = try doc_map.getOrPutValue(path_copy, .{ .sub_path = path_copy, .word_map = std.StringHashMap(Word).init(gpa), .lenght = 0 });
            try addWordsForAFile(gpa, arena, dir, io, w.path, doc.value_ptr);
            doc_counter += 1;
            sum_length += doc.value_ptr.lenght;
        } else {
            continue;
        }
    }
    const avgdl: f32 = @as(f32, @floatFromInt(sum_length)) / @as(f32, @floatFromInt(doc_counter));

    var docs_iter = doc_map.iterator();
    const idf = calculateIDF(&docs_iter, search_keyword);

    var iter = doc_map.iterator();
    while (iter.next()) |i| {
        i.value_ptr.score = calculateScore(i.value_ptr, search_keyword, idf, avgdl);
    }
    try printDocWithScoreSorted(doc_map, gpa);
    return;
}

fn docScoreLessThan(q: void, a: *Doc, c: *Doc) bool {
    _ = q;
    if (a.score > c.score) {
        return true;
    }
    return false;
}

fn printDocWithScoreSorted(doc_map: std.hash_map.StringHashMap(Doc), gpa: std.mem.Allocator) !void {
    var doc_list: std.ArrayList(*Doc) = .empty;
    defer doc_list.deinit(gpa);
    var iter = doc_map.iterator();
    while (iter.next()) |i| {
        try doc_list.append(gpa, i.value_ptr);
    }
    std.mem.sort(*Doc, doc_list.items, {}, docScoreLessThan);
    for (doc_list.items) |i| {
        if (i.score > 0) {
            std.debug.print("----------------------------------------\n", .{});
            std.debug.print("File: {s}\n", .{i.sub_path});
            std.debug.print("score: {d}\n", .{i.score});
            std.debug.print("----------------------------------------\n", .{});
        }
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

fn addWordsForAFile(gpa: std.mem.Allocator, arena: std.mem.Allocator, dir: std.Io.Dir, io: std.Io, file_name: []const u8, doc: *Doc) !void {
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

    var map = &doc.word_map;
    var tokens = std.mem.tokenizeAny(u8, f, "[]*#&/-()\"\': ,.\n");
    var counter: u32 = 0;
    while (tokens.next()) |tok| {
        counter += 1;
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
    doc.lenght = counter;
}

const k1 = 1.5;
const b = 0.75;

fn calculateScore(doc: *Doc, word: []const u8, idf: f32, avgdl: f32) f32 {
    if (doc.word_map.get(word)) |in_doc_word| {
        const tf = @as(f32, @floatFromInt(in_doc_word.freq));
        return idf * (tf * (k1 + 1)) / (tf + (k1 * (1 - b + (b * (@as(f32, @floatFromInt(doc.lenght)) / avgdl)))));
    }
    return 0;
}

inline fn calculateIDF(docs_iter: anytype, word: []const u8) f32 {
    var n: u32 = 0;
    var doc_counter: u32 = 0;
    while (docs_iter.next()) |i| {
        if (i.value_ptr.word_map.contains(word)) {
            n += 1;
        }
        doc_counter += 1;
    }
    return @log(1 + (((@as(f32, @floatFromInt(doc_counter)) - @as(f32, @floatFromInt(n)) + 0.5) / (@as(f32, @floatFromInt(n)) + 0.5))));
}
