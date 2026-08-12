const std = @import("std");
const Io = std.Io;

const Word = struct { key: []const u8, freq: u32 };
const Doc = struct { sub_path: []const u8, word_map: std.StringHashMap(Word), length: u32, score: f32 = 0.0 };

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena: std.mem.Allocator = init.arena.allocator();

    const io = init.io;

    const args = try init.minimal.args.toSlice(arena);
    const search_keyword = if (args.len > 1) args[1] else std.process.exit(1);
    var lower_buffer: [1024]u8 = undefined;
    const search_keyword_lower = std.ascii.lowerString(&lower_buffer, search_keyword);
    var search_keyword_iter = std.mem.tokenizeAny(u8, search_keyword_lower, " ");

    const dir_path_arg = if (args.len > 2) args[2] else ".";

    const dir = try std.Io.Dir.cwd().openDir(io, dir_path_arg, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(gpa);
    defer walker.deinit();

    var doc_map: std.ArrayList(Doc) = .empty;
    defer {
        for (doc_map.items) |*i| {
            i.word_map.deinit();
        }
        doc_map.deinit(gpa);
    }

    var sum_length: u32 = 0;
    var doc_counter: u32 = 0;
    while (try walker.next(io)) |w| {
        if (w.kind == .file) {
            const path_copy = try arena.dupe(u8, w.path);
            try doc_map.append(gpa, .{ .sub_path = path_copy, .word_map = std.StringHashMap(Word).init(gpa), .length = 0 });

            try addWordsForAFile(arena, dir, io, w.path, &doc_map.items[doc_map.items.len - 1]);
            doc_counter += 1;
            sum_length += doc_map.items[doc_map.items.len - 1].length;
        } else {
            continue;
        }
    }
    const avgdl: f32 = @as(f32, @floatFromInt(sum_length)) / @as(f32, @floatFromInt(doc_counter));

    while (search_keyword_iter.next()) |keyword| {
        const idf = calculateIDF(doc_map, keyword);

        for (doc_map.items) |*i| {
            i.score += calculateScore(i, keyword, idf, avgdl);
        }
    }
    try printDocWithScoreSorted(&doc_map, dir_path_arg);
    return;
}

fn docScoreLessThan(q: void, a: Doc, c: Doc) bool {
    _ = q;
    if (a.score > c.score) {
        return true;
    }
    return false;
}

fn printDocWithScoreSorted(doc_map: *std.ArrayList(Doc), root_dir: []const u8) !void {
    std.mem.sort(Doc, doc_map.items, {}, docScoreLessThan);
    std.debug.print("----------------------------------------\n", .{});
    for (doc_map.items) |i| {
        if (i.score > 0) {
            if (root_dir[root_dir.len - 1] == '/') {
                std.debug.print("File: {s}{s}\n", .{ root_dir, i.sub_path });
            } else {
                std.debug.print("File: {s}/{s}\n", .{ root_dir, i.sub_path });
            }
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

fn addWordsForAFile(arena: std.mem.Allocator, dir: std.Io.Dir, io: std.Io, file_name: []const u8, doc: *Doc) !void {
    const f = try std.Io.Dir.openFile(dir, io, file_name, .{});
    defer f.close(io);

    var read_buffer: [4096]u8 = undefined;
    var reader = f.reader(io, &read_buffer);
    var counter: u32 = 0;

    while (reader.interface.takeDelimiter('\n')) |maybe_s| {
        const s = maybe_s orelse break;
        _ = std.ascii.lowerString(s, s);
        var map = &doc.word_map;
        var tokens = std.mem.tokenizeAny(u8, s, "!?{}<>[]*#&/-()\"\': ,.\n");
        while (tokens.next()) |tok| {
            counter += 1;
            if (map.contains(tok)) {
                map.getEntry(tok).?.value_ptr.freq += 1;
            } else {
                const tok_arena = try arena.dupe(u8, tok);
                try map.put(tok_arena, .{ .key = tok_arena, .freq = 1 });
            }
        }
    } else |err| {
        switch (err) {
            error.StreamTooLong => {
                //TODO: allocate on the heap.
            },
            error.ReadFailed => {
                std.debug.print("[ERROR] Failed to read file: {s}", .{file_name});
            },
        }
    }

    doc.length = counter;
}

const k1 = 1.5;
const b = 0.75;

fn calculateScore(doc: *Doc, word: []const u8, idf: f32, avgdl: f32) f32 {
    if (doc.word_map.get(word)) |in_doc_word| {
        const tf = @as(f32, @floatFromInt(in_doc_word.freq));
        return idf * (tf * (k1 + 1)) / (tf + (k1 * (1 - b + (b * (@as(f32, @floatFromInt(doc.length)) / avgdl)))));
    }
    return 0;
}

inline fn calculateIDF(doc_map: std.ArrayList(Doc), word: []const u8) f32 {
    var n: u32 = 0;
    const doc_counter = doc_map.items.len;
    for (doc_map.items) |i| {
        if (i.word_map.contains(word)) {
            n += 1;
        }
    }

    return @log(1 + (((@as(f32, @floatFromInt(doc_counter)) - @as(f32, @floatFromInt(n)) + 0.5) / (@as(f32, @floatFromInt(n)) + 0.5))));
}
