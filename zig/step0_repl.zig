const std = @import("std");

fn READ(s: []const u8) []const u8 {
    return s;
}

fn EVAL(s: []const u8) []const u8 {
    return s;
}

fn PRINT(s: []const u8) []const u8 {
    return s;
}

fn rep(s: []const u8) []const u8 {
    return PRINT(EVAL(READ(s)));
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut();

    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    const allocator = &arena.allocator;

    var buf = try std.Buffer.initSize(allocator, std.mem.page_size);
    defer buf.deinit();

    while (true) {
        try stdout_file.write("user> ");

        if (std.io.readLine(&buf)) |line| {
            try stdout_file.write(rep(line));
            try stdout_file.write("\n");
        } else |err| {
            switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        }
    }
}
