const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("types.zig");
const SequenceType = types.SequenceType;
const MalType = types.MalType;

pub const PrintError = error{ OutOfBounds, OutOfMemory };

/// Escapes a string
pub fn escape(s: []const u8, alloc: *Allocator) ![]const u8 {
    var result = std.ArrayList(u8).init(alloc);
    try result.appendSlice(s);

    // String
    var i: usize = 0;
    while (i < result.count()) : (i += 1) {
        switch (result.at(i)) {
            '\n' => {
                result.set(i, '\\');
                try result.insert(i + 1, 'n');
                i += 1;
            },
            '"' => {
                result.set(i, '\\');
                try result.insert(i + 1, '"');
                i += 1;
            },
            '\\' => {
                try result.insert(i + 1, '\\');
                i += 1;
            },
            else => continue,
        }
    }

    // Add double quotes
    try result.insert(0, '"');
    try result.append('"');

    return result.toSliceConst();
}

/// Formats all kinds of mal values
pub fn pr_str(x: MalType, alloc: *Allocator, print_readably: bool) PrintError![]const u8 {
    switch (x) {
        .MalNil => return "nil",
        .MalString => |value| {
            if (std.mem.startsWith(u8, value, "\u{29e}")) {
                return try pr_keyword(value, alloc);
            } else if (print_readably) {
                return try escape(value, alloc);
            } else {
                return value;
            }
         },
        .MalList => |list| return try pr_seq(list, alloc, SequenceType.List, print_readably),
        .MalVector => |list| return try pr_seq(list, alloc, SequenceType.Vector, print_readably),
        .MalHashMap => |map| return try pr_map(map, alloc, print_readably),
        .MalInteger => |value| return try std.fmt.allocPrint(alloc, "{}", value),
        .MalBoolean => |value| if (value) return "true" else return "false",
        .MalSymbol => |value| return value,
        .MalIntegerFunction => return "<builtin fn>",
    }
}

/// Formats keywords
fn pr_keyword(s: []const u8, alloc: *Allocator) ![]const u8 {
    return try std.fmt.allocPrint(alloc, ":{}", s[2..]);
}

/// Formats hash maps
fn pr_map(map: std.StringHashMap(MalType), alloc: *Allocator, print_readably: bool) PrintError![]const u8 {
    var result = std.ArrayList(u8).init(alloc);

    try result.append('{');

    // After the first element, prepend spaces to output
    // to make everything look nice
    var first_itm = true;
    var iter = map.iterator();
    while (iter.next()) |kv| {
        const key = MalType{ .MalString = kv.key };

        if (first_itm) {
            first_itm = false;
        } else {
            try result.append(' ');
        }

        try result.appendSlice(try pr_str(key, alloc, print_readably));
        try result.append(' ');
        try result.appendSlice(try pr_str(kv.value, alloc, print_readably));
    }
    try result.append('}');

    return result.toSliceConst();
}

/// Formats lists and vectors
fn pr_seq(list: std.ArrayList(MalType), alloc: *Allocator, seq_type: SequenceType, print_readably: bool) PrintError![]const u8 {
    var result = std.ArrayList(u8).init(alloc);

    try result.appendSlice(seq_type.startToken());
    var first_itm = true;
    var iter = list.iterator();
    while (iter.next()) |value| {
        if (first_itm) {
            first_itm = false;
        } else {
            try result.append(' ');
        }

        try result.appendSlice(try pr_str(value, alloc, print_readably));
    }
    try result.appendSlice(seq_type.endToken());

    return result.toSliceConst();
}
