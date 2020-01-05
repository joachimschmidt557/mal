const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const reader = @import("reader.zig");
const printer = @import("printer.zig");
const types = @import("types.zig");
const MalType = types.MalType;
const errMsg = types.errMsg;

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
                var evaluated = try eval_ast(ast, env, alloc);

                // We can guarantee that the expression is a list
                // We can guarantee that the list is not empty
                var l = evaluated.MalList;
                switch (l.at(0)) {
                    .MalBuiltinFunction => |f| {
                        _ = l.orderedRemove(0);

                        var result: MalType = undefined;
                        const return_val = try f(alloc, l);
                        result = return_val.*;
                        defer alloc.destroy(return_val);

                        return result;
                    },
                    else => return error.ApplicationOfNonFunction,
                }
            }
        },
        else => return try eval_ast(ast, env, alloc),
    }
}

/// Converts a mal value into a string
/// This takes ownership of the mal value
/// Caller gets ownership of the string
fn PRINT(x: MalType, alloc: *Allocator) ![]const u8 {
    return try printer.pr_str(x, alloc, true);
}

/// Recursive helper function for EVAL
fn eval_ast(ast: MalType, env: Env, alloc: *Allocator) EvalError!MalType {
    switch (ast) {
        .MalSymbol => |name| if (env.get(name)) |kv| {
            return kv.value;
        } else {
            return error.SymbolNotFound;
        },
        .MalList, .MalVector => |list| {
            for (list.toSlice()) |*value| {
                value.* = try EVAL(value.*, env, alloc);
            }

            return ast;
        },
        .MalHashMap => |map| {
            var iter = map.iterator();
            while (iter.next()) |*kv| {
                kv.*.value = try EVAL(kv.*.value, env, alloc);
            }

            return ast;
        },
        else => return ast,
    }
}

fn rep(s: []const u8, env: Env, alloc: *Allocator) ![]const u8 {
    return try PRINT(try EVAL(try READ(s, alloc), env, alloc), alloc);
}

pub fn add(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);

    if (args.len < 2) {
        result.* = try errMsg(alloc, "missing operands");
        return result;
    }
    const second = args.at(0);
    const third = args.at(1);

    if (second != .MalInteger or third != .MalInteger) {
        result.* = try errMsg(alloc, "expected integer operand");
        return result;
    }

    const x = second.MalInteger;
    const y = third.MalInteger;

    result.* = MalType{ .MalInteger = x + y };
    return result;
}

pub fn sub(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);

    if (args.len < 2) {
        result.* = try errMsg(alloc, "missing operands");
        return result;
    }
    const second = args.at(0);
    const third = args.at(1);

    if (second != .MalInteger or third != .MalInteger) {
        result.* = try errMsg(alloc, "expected integer operand");
        return result;
    }

    const x = second.MalInteger;
    const y = third.MalInteger;

    result.* = MalType{ .MalInteger = x - y };
    return result;
}

pub fn mul(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);

    if (args.len < 2) {
        result.* = try errMsg(alloc, "missing operands");
        return result;
    }
    const second = args.at(0);
    const third = args.at(1);

    if (second != .MalInteger or third != .MalInteger) {
        result.* = try errMsg(alloc, "expected integer operand");
        return result;
    }

    const x = second.MalInteger;
    const y = third.MalInteger;

    result.* = MalType{ .MalInteger = x * y };
    return result;
}

pub fn div(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);

    if (args.len < 2) {
        result.* = try errMsg(alloc, "missing operands");
        return result;
    }
    const second = args.at(0);
    const third = args.at(1);

    if (second != .MalInteger or third != .MalInteger) {
        result.* = try errMsg(alloc, "expected integer operand");
        return result;
    }

    const x = second.MalInteger;
    const y = third.MalInteger;

    result.* = MalType{ .MalInteger = @divTrunc(x, y) };
    return result;
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut();

    var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    const allocator = &arena.allocator;

    // REPL environment
    var repl_env = Env.init(allocator);
    _ = try repl_env.put("+", MalType{ .MalBuiltinFunction = add });
    _ = try repl_env.put("-", MalType{ .MalBuiltinFunction = sub });
    _ = try repl_env.put("*", MalType{ .MalBuiltinFunction = mul });
    _ = try repl_env.put("/", MalType{ .MalBuiltinFunction = div });

    // Buffer for line reading
    var buf = try std.Buffer.initSize(allocator, std.mem.page_size);
    defer buf.deinit();

    while (true) {
        try stdout_file.write("user> ");

        if (std.io.readLine(&buf)) |line| {
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
            defer allocator.free(result);

            try stdout_file.write(result);
            try stdout_file.write("\n");
        } else |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        }
    }
}
