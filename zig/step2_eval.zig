const std = @import("std");
const Allocator = std.mem.Allocator;

const reader = @import("reader.zig");
const printer = @import("printer.zig");
const types = @import("types.zig");
const MalType = types.MalType;

pub const Env = std.StringHashMap(MalType);

pub const EvalError = std.mem.Allocator.Error || error{
    SymbolNotFound,
    ApplicationOfNonFunction,
    MissingOperands,
    NonIntegerOperands,
};

fn READ(s: []const u8, alloc: *Allocator) !MalType {
    return try reader.read_str(s, alloc);
}

fn EVAL(ast: MalType, env: Env, alloc: *Allocator) EvalError!MalType {
    switch (ast) {
        .MalList => |list| {
            if (list.len == 0) {
                return ast;
            } else {
                const evaluated = try eval_ast(ast, env, alloc);

                switch (evaluated) {
                    .MalList => |evaluated_list| {
                        if (evaluated_list.first) |first| {
                            switch (first.data) {
                                .MalIntegerFunction => |f| {
                                    const second = first.next orelse return error.MissingOperands;
                                    const third = second.next orelse return error.MissingOperands;

                                    if (second.data != .MalInteger) return error.NonIntegerOperands;
                                    if (third.data != .MalInteger) return error.NonIntegerOperands;

                                    const x = second.data.MalInteger;
                                    const y = third.data.MalInteger;

                                    return MalType{ .MalInteger = f(x, y) };
                                },
                                else => return error.ApplicationOfNonFunction,
                            }
                        } else {
                            // We can guarantee that the list is not empty
                            unreachable;
                        }
                    },
                    // We can guarantee that the expression is a list
                    else => unreachable,
                }
            }
        },
        else => return try eval_ast(ast, env, alloc),
    }
}

fn PRINT(x: MalType, alloc: *Allocator) ![]const u8 {
    return try printer.pr_str(x, alloc, true);
}

fn eval_ast(ast: MalType, env: Env, alloc: *Allocator) EvalError!MalType {
    switch (ast) {
        .MalSymbol => |name| if (env.get(name)) |kv| {
            return kv.value;
        } else {
            return error.SymbolNotFound;
        },
        .MalList, .MalVector => |list| {
            var result = std.TailQueue(MalType).init();

            var itm = list.first;
            while (true) {
                if (itm) |value| {
                    result.append(try result.createNode(try EVAL(value.data, env, alloc), alloc));
                    itm = value.next;
                } else {
                    break;
                }
            }

            return switch (ast) {
                .MalList => MalType{ .MalList = result },
                .MalVector => MalType{ .MalVector = result },
                else => unreachable,
            };
        },
        .MalHashMap => |map| {
            var result = std.StringHashMap(MalType).init(alloc);
            var iter = map.iterator();

            while (iter.next()) |kv| {
                _ = try result.put(kv.key, try EVAL(kv.value, env, alloc));
            }

            return MalType{ .MalHashMap = result };
        },
        else => return ast,
    }
}

fn rep(s: []const u8, env: Env, alloc: *Allocator) ![]const u8 {
    return try PRINT(try EVAL(try READ(s, alloc), env, alloc), alloc);
}

fn add(x: i64, y: i64) i64 { return x + y; }
fn sub(x: i64, y: i64) i64 { return x - y; }
fn mul(x: i64, y: i64) i64 { return x * y; }
fn div(x: i64, y: i64) i64 { return @divTrunc(x, y); }

pub fn main() !void {
    const stdout_file = std.io.getStdOut();
    const stdin_file = std.io.getStdIn();
    const stdin_stream = &stdin_file.inStream().stream;

    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    const allocator = &arena.allocator;

    // REPL environment
    var repl_env = Env.init(allocator);
    _ = try repl_env.put("+", MalType{ .MalIntegerFunction = add });
    _ = try repl_env.put("-", MalType{ .MalIntegerFunction = sub });
    _ = try repl_env.put("*", MalType{ .MalIntegerFunction = mul });
    _ = try repl_env.put("/", MalType{ .MalIntegerFunction = div });

    // Buffer for line reading
    var buf = try std.Buffer.initSize(allocator, std.mem.page_size);
    defer buf.deinit();

    while (true) {
        try stdout_file.write("user> ");

        if (std.io.readLineFrom(stdin_stream, &buf)) |line| {
            var result = rep(line, repl_env, allocator) catch |err| switch(err) {
                error.UnfinishedQuote => {
                    try stdout_file.write("error: unbalanced quote\n");
                    continue;
                },
                error.UnbalancedParenthesis => {
                    try stdout_file.write("error: unbalanced parenthesis\n");
                    continue;
                },
                error.Underflow => {
                    try stdout_file.write("error: underflow\n");
                    continue;
                },
                error.KeyIsNotString => {
                    try stdout_file.write("error: key is not a string\n");
                    continue;
                },
                error.UnevenHashMap => {
                    try stdout_file.write("error: odd number of elements in hashmap\n");
                    continue;
                },
                error.SymbolNotFound => {
                    try stdout_file.write("error: symbol not found\n");
                    continue;
                },
                error.ApplicationOfNonFunction => {
                    try stdout_file.write("error: trying to apply something else than a function\n");
                    continue;
                },
                error.MissingOperands => {
                    try stdout_file.write("error: missing operands\n");
                    continue;
                },
                 error.NonIntegerOperands => {
                    try stdout_file.write("error: integer functions expect integer arguments\n");
                    continue;
                },
                else => return err,
            };

            try stdout_file.write(result);
            try stdout_file.write("\n");
        } else |err| {
            switch (err) {
                error.EndOfStream => break,
                else => return err,
            }
        }
    }
}
