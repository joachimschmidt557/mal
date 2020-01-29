const std = @import("std");
const Allocator = std.mem.Allocator;

const reader = @import("reader.zig");
const printer = @import("printer.zig");
const types = @import("types.zig");

fn READ(s: []const u8, alloc: *Allocator) !types.MalType {
    return try reader.read_str(s, alloc);
}

fn EVAL(x: types.MalType) types.MalType {
    return x;
}

fn PRINT(x: types.MalType, alloc: *Allocator) ![]const u8 {
    return try printer.pr_str(x, alloc, true);
}

fn rep(s: []const u8, alloc: *Allocator) ![]const u8 {
    return try PRINT(EVAL(try READ(s, alloc)), alloc);
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut();

    const allocator = std.heap.c_allocator;

    // Buffer for line reading
    var buf = try std.Buffer.initSize(allocator, std.mem.page_size);
    defer buf.deinit();

    while (true) {
        try stdout_file.write("user> ");

        if (std.io.readLine(&buf)) |line| {
            const result = rep(line, allocator) catch |err| {
                const msg = switch (err) {
                    error.UnfinishedQuote => "error: unbalanced quote\n",
                    error.UnbalancedParenthesis => "error: unbalanced parenthesis\n",
                    error.Underflow => "error: underflow\n",
                    error.KeyIsNotString => "error: key is not a string\n",
                    error.UnevenHashMap => "error: odd number of elements in hashmap\n",
                    else => return err,
                };
                try stdout_file.write(msg);
                continue;
            };
            defer allocator.free(result);

            try stdout_file.write(result);
            try stdout_file.write("\n");
        } else |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        }
    }
}
