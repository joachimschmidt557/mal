const std = @import("std");
const Allocator = std.mem.Allocator;

const reader = @import("reader.zig");
const printer = @import("printer.zig");
const types = @import("types.zig");
const MalType = types.MalType;

const Env = @import("env.zig").Env;

pub const EvalError = std.mem.Allocator.Error;

pub const err_application_of_non_function = MalType{
    .MalErrorStr = "trying to apply something else than a function",
};
pub const err_missing_operands = MalType{
    .MalErrorStr = "missing operands",
};
pub const err_non_int_operand = MalType{
    .MalErrorStr = "integer functions expect integer arguments",
};
pub const err_defining_non_symbol = MalType{
    .MalErrorStr = "def! expects a symbol",
};
pub const err_let_binding_non_list = MalType{
    .MalErrorStr = "let* bindings expect a list",
};
pub const err_let_binding_odd = MalType{
    .MalErrorStr = "let* bindings need an even number of arguments",
};

fn errSymbolNotFound(name: []const u8, alloc: *Allocator) !MalType {
    const msg = try std.fmt.allocPrint(alloc, "{} not found", name);
    return MalType{ .MalErrorStr = msg };
}

/// Parses this string into a mal value
/// This takes ownership of the string
/// Caller gets ownership of the mal value
fn READ(s: []const u8, alloc: *Allocator) !MalType {
    return try reader.read_str(s, alloc);
}

/// Evaluates a mal value
/// This takes ownership of the mal value
/// Caller recieves ownership of the result
fn EVAL(ast: MalType, env: *Env, alloc: *Allocator) EvalError!MalType {
    switch (ast) {
        .MalErrorStr => return ast,
        .MalList => |list| {
            if (list.len == 0) {
                return ast;
            } else {
                // Special symbols such as let* and def!
                if (list.at(0) == .MalSymbol) {
                    const symbol = list.at(0).MalSymbol;
                    if (std.mem.eql(u8, symbol, "def!")) {
                        // Change current environment
                        if (list.len < 3) return try err_missing_operands.copy(alloc);
                        const second = list.at(1);
                        const third = list.at(2);

                        if (second != .MalSymbol) return try err_defining_non_symbol.copy(alloc);

                        const key = second.MalSymbol;
                        const value = try EVAL(third, env, alloc);
                        if (value.isError()) return value;

                        try env.set(key, try value.copy(alloc));
                        return value;
                    } else if (std.mem.eql(u8, symbol, "let*")) {
                        // New environment
                        if (list.len < 3) return try err_missing_operands.copy(alloc);
                        const second = list.at(1);
                        const third = list.at(2);

                        const new_bindings = switch (second) {
                            .MalList, .MalVector => |l| l,
                            else => return try err_let_binding_non_list.copy(alloc),
                        };
                        const new_env = &Env.init(env, alloc);
                        defer new_env.deinit();

                        // Reading in two stages: First read key, then read value
                        var key: ?[]const u8 = null;
                        var iter = new_bindings.iterator();
                        while (iter.next()) |itm| {
                            if (key) |ky| {
                                // Key was already read
                                const value = try EVAL(itm, new_env, alloc);
                                // TODO: memory management after error
                                if (value.isError()) return value;

                                try new_env.set(ky, value);
                                key = null;
                            } else {
                                // Read key
                                if (itm != .MalSymbol) return try err_defining_non_symbol.copy(alloc);
                                key = itm.MalSymbol;
                            }
                        }
                        if (key != null) return try err_let_binding_odd.copy(alloc);

                        return try EVAL(third, new_env, alloc);
                    }
                }

                // Evaluate list
                const evaluated = try eval_ast(ast, env, alloc);
                if (evaluated.isError()) return evaluated;

                // We can guarantee that the expression is a list
                // We can guarantee that the list is not empty
                const l = evaluated.MalList;
                switch (l.at(0)) {
                    .MalIntegerFunction => |f| {
                        if (l.len < 3) return try err_missing_operands.copy(alloc);
                        const second = l.at(1);
                        const third = l.at(2);

                        if (second != .MalInteger) return try err_non_int_operand.copy(alloc);
                        if (third != .MalInteger) return try err_non_int_operand.copy(alloc);

                        const x = second.MalInteger;
                        const y = third.MalInteger;

                        return MalType{ .MalInteger = f(x, y) };
                    },
                    else => return try err_application_of_non_function.copy(alloc),
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
fn eval_ast(ast: MalType, env: *Env, alloc: *Allocator) EvalError!MalType {
    switch (ast) {
        .MalErrorStr => return ast,
        .MalSymbol => |name| {
            if (try env.get(alloc, name)) |val| {
                return val;
            } else {
                return try errSymbolNotFound(name, alloc);
            }
        },
        .MalList, .MalVector => |list| {
            var result = std.ArrayList(MalType).init(alloc);

            var iter = list.iterator();
            while (iter.next()) |value| {
                const itm = try EVAL(value, env, alloc);
                if (itm.isError()) {
                    var deinit_iter = result.iterator();
                    while (deinit_iter.next()) |x| x.deinit(alloc);
                    result.deinit();
                    return itm;
                }

                try result.append(itm);
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
                const itm = try EVAL(kv.value, env, alloc);
                if (itm.isError()) {
                    var deinit_iter = result.iterator();
                    while (deinit_iter.next()) |deinit_kv| {
                        deinit_kv.value.deinit(alloc);
                    }
                    result.deinit();
                    return itm;
                }

                _ = try result.put(kv.key, itm);
            }

            return MalType{ .MalHashMap = result };
        },
        else => return ast,
    }
}

fn rep(s: []const u8, env: *Env, alloc: *Allocator) ![]const u8 {
    return try PRINT(try EVAL(try READ(s, alloc), env, alloc), alloc);
}

fn add(x: i64, y: i64) i64 { return x + y; }
fn sub(x: i64, y: i64) i64 { return x - y; }
fn mul(x: i64, y: i64) i64 { return x * y; }
fn div(x: i64, y: i64) i64 { return @divTrunc(x, y); }

pub fn main() !void {
    const stdout_file = std.io.getStdOut();

    //var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    //const allocator = &arena.allocator;
    const allocator = std.heap.page_allocator;

    // REPL environment
    const repl_env = &Env.init(null, allocator);
    try repl_env.set("+", MalType{ .MalIntegerFunction = add });
    try repl_env.set("-", MalType{ .MalIntegerFunction = sub });
    try repl_env.set("*", MalType{ .MalIntegerFunction = mul });
    try repl_env.set("/", MalType{ .MalIntegerFunction = div });
    defer repl_env.deinit();

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
                else => return err,
            };
            defer allocator.free(result);

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
