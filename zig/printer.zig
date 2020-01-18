const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("types.zig");
const SequenceType = types.SequenceType;
const MalType = types.MalType;

pub const PrintError = Allocator.Error;

/// Escapes a string
pub fn escape(s: []const u8, alloc: *Allocator) ![]const u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();
    try result.appendSlice(s);

    // String
    var i: usize = 0;
    while (i < result.len) : (i += 1) {
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
/// After the conversion process of mal value to string, the mal value will
/// be deinitialized
pub fn pr_str(x: MalType, alloc: *Allocator, print_readably: bool) PrintError![]const u8 {
    // We deinitialize the value after printing as it
    // is of no use anymore
    defer x.deinit(alloc);

    switch (x) {
        .MalNil => return try std.fmt.allocPrint(alloc, "nil", .{}),
        .MalErrorStr => |err_str| return try pr_errorstr(err_str, alloc),
        .MalString => |value| {
            if (std.mem.startsWith(u8, value, "\u{29e}")) {
                return try pr_keyword(value, alloc);
            } else if (print_readably) {
                return try escape(value, alloc);
            } else {
                return try std.fmt.allocPrint(alloc, "{}", .{ value });
            }
         },
        .MalList => |list| return try pr_seq(list, alloc, SequenceType.List, print_readably),
        .MalVector => |list| return try pr_seq(list, alloc, SequenceType.Vector, print_readably),
        .MalHashMap => |map| return try pr_map(map, alloc, print_readably),
        .MalInteger => |value| return try std.fmt.allocPrint(alloc, "{}", .{ value }),
        .MalBoolean => |value| if (value) return try std.fmt.allocPrint(alloc, "true", .{}) else return try std.fmt.allocPrint(alloc, "false", .{}),
        .MalSymbol => |value| return try std.fmt.allocPrint(alloc, "{}", .{ value }),
        .MalBuiltinFunction => return try std.fmt.allocPrint(alloc, "#<builtin fn>", .{}),
        .MalFunction => return try std.fmt.allocPrint(alloc, "#<function>", .{}),
    }
}

/// Formats an error
fn pr_errorstr(s: []const u8, alloc: *Allocator) ![]const u8 {
    return try std.fmt.allocPrint(alloc, "error: {}", .{ s });
}

/// Formats keywords
fn pr_keyword(s: []const u8, alloc: *Allocator) ![]const u8 {
    return try std.fmt.allocPrint(alloc, ":{}", .{ s[2..] });
}

/// Formats hash maps
fn pr_map(map: std.StringHashMap(MalType), alloc: *Allocator, print_readably: bool) PrintError![]const u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();

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

        // Copying of key and value necessary because pr_str will
        // deinit the value after printing
        const key_cpy = try pr_str(try key.copy(alloc), alloc, print_readably);
        defer alloc.free(key_cpy);

        const val_cpy = try pr_str(try kv.value.copy(alloc), alloc, print_readably);
        defer alloc.free(val_cpy);

        try result.appendSlice(key_cpy);
        try result.append(' ');
        try result.appendSlice(val_cpy);
    }
    try result.append('}');

    return result.toSliceConst();
}

/// Formats lists and vectors
fn pr_seq(list: std.ArrayList(MalType), alloc: *Allocator, seq_type: SequenceType, print_readably: bool) PrintError![]const u8 {
    var result = std.ArrayList(u8).init(alloc);
    errdefer result.deinit();

    try result.appendSlice(seq_type.startToken());
    var first_itm = true;
    for (list.toSlice()) |value| {
        if (first_itm) {
            first_itm = false;
        } else {
            try result.append(' ');
        }

        // Copying of value necessary because pr_str will
        // deinit the value after printing
        const cpy = try pr_str(try value.copy(alloc), alloc, print_readably);
        defer alloc.free(cpy);

        try result.appendSlice(cpy);
    }
    try result.appendSlice(seq_type.endToken());

    return result.toSliceConst();
}
