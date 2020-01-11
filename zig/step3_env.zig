const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const reader = @import("reader.zig");
const printer = @import("printer.zig");
const types = @import("types.zig");
const MalType = types.MalType;
const errMsg = types.errMsg;
const errSymbolNotFound = types.errSymbolNotFound;

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
                        defer ast.deinit(alloc);
                        if (list.len != 3) return try err_missing_operands.copy(alloc);
                        const second = try list.at(1).copy(alloc);
                        const third = try list.at(2).copy(alloc);

                        const key = switch (second) {
                            .MalSymbol => |sym| sym,
                             else => return try err_defining_non_symbol.copy(alloc),
                        };

                        const value = try EVAL(third, env, alloc);
                        if (value.isError()) {
                            second.deinit(alloc);
                        } else {
                            try env.set(key, try value.copy(alloc));
                        }

                        return value;
                    } else if (std.mem.eql(u8, symbol, "let*")) {
                        // New environment
                        defer ast.deinit(alloc);
                        if (list.len != 3) return try err_missing_operands.copy(alloc);
                        const second = try list.at(1).copy(alloc);
                        const third = try list.at(2).copy(alloc);

                        const new_bindings = switch (second) {
                            .MalList, .MalVector => |l| l,
                            else => return try err_let_binding_non_list.copy(alloc),
                        };
                        defer new_bindings.deinit();
                        var new_env = Env.init(alloc, env);
                        defer new_env.deinit();

                        if (new_bindings.len % 2 != 0)
                            return try err_let_binding_odd.copy(alloc);

                        var i: usize = 0;
                        while (i < new_bindings.len) : (i += 2) {
                            const key = switch (new_bindings.at(i)) {
                                .MalSymbol => |str| str,
                                else => return try err_defining_non_symbol.copy(alloc),
                            };
                            const value = try EVAL(new_bindings.at(i + 1), &new_env, alloc);
                            if (value.isError()) return value;

                            try new_env.set(key, value);
                        }

                        return try EVAL(third, &new_env, alloc);
                    }
                }

                // Evaluate list
                var evaluated = try eval_ast(ast, env, alloc);
                if (evaluated.isError()) return evaluated;

                // We can guarantee that the expression is a list
                // We can guarantee that the list is not empty
                var l = evaluated.MalList;
                switch (l.orderedRemove(0)) {
                    .MalBuiltinFunction => |f| {
                        var result: MalType = undefined;
                        const return_val = try f(alloc, l);
                        result = return_val.*;
                        defer alloc.destroy(return_val);

                        return result;
                    },
                    else => |x| {
                        x.deinit(alloc);

                        // Free parameters
                        for (l.toSlice()) |y| y.deinit(alloc);
                        l.deinit();

                        return try err_application_of_non_function.copy(alloc);
                    },
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
            defer ast.deinit(alloc);
            if (try env.get(alloc, name)) |val| {
                return val;
            } else {
                return try errSymbolNotFound(name, alloc);
            }
        },
        .MalList, .MalVector => |list| {
            for (list.toSlice()) |*value| {
                const itm = try EVAL(value.*, env, alloc);
                value.* = itm;
                if (itm.isError()) {
                    defer ast.deinit(alloc);
                    return itm.copy(alloc);
                }
            }

            return ast;
        },
        .MalHashMap => |map| {
            var iter = map.iterator();
            while (iter.next()) |*kv| {
                const itm = try EVAL(kv.*.value, env, alloc);
                kv.*.value = itm;
                if (itm.isError()) {
                    defer ast.deinit(alloc);
                    return itm.copy(alloc);
                }
            }

            return ast;
        },
        else => return ast,
    }
}

fn rep(s: []const u8, env: *Env, alloc: *Allocator) ![]const u8 {
    return try PRINT(try EVAL(try READ(s, alloc), env, alloc), alloc);
}

pub fn add(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);
    defer {
        for (args.toSlice()) |x| x.deinit(alloc);
        args.deinit();
    }

    if (args.len != 2) {
        result.* = try errMsg(alloc, "missing operands");
        return result;
    }

    const x = switch (args.at(0)) {
        .MalInteger => |val| val,
        else => {
            result.* = try errMsg(alloc, "expected integer operand");
            return result;
        },
    };
    const y = switch (args.at(1)) {
        .MalInteger => |val| val,
        else => {
            result.* = try errMsg(alloc, "expected integer operand");
            return result;
        },
    };

    result.* = MalType{ .MalInteger = x + y };
    return result;
}

pub fn sub(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);
    defer {
        for (args.toSlice()) |x| x.deinit(alloc);
        args.deinit();
    }

    if (args.len != 2) {
        result.* = try errMsg(alloc, "missing operands");
        return result;
    }

    const x = switch (args.at(0)) {
        .MalInteger => |val| val,
        else => {
            result.* = try errMsg(alloc, "expected integer operand");
            return result;
        },
    };
    const y = switch (args.at(1)) {
        .MalInteger => |val| val,
        else => {
            result.* = try errMsg(alloc, "expected integer operand");
            return result;
        },
    };

    result.* = MalType{ .MalInteger = x - y };
    return result;
}

pub fn mul(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);
    defer {
        for (args.toSlice()) |x| x.deinit(alloc);
        args.deinit();
    }

    if (args.len != 2) {
        result.* = try errMsg(alloc, "missing operands");
        return result;
    }

    const x = switch (args.at(0)) {
        .MalInteger => |val| val,
        else => {
            result.* = try errMsg(alloc, "expected integer operand");
            return result;
        },
    };
    const y = switch (args.at(1)) {
        .MalInteger => |val| val,
        else => {
            result.* = try errMsg(alloc, "expected integer operand");
            return result;
        },
    };

    result.* = MalType{ .MalInteger = x * y };
    return result;
}

pub fn div(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);
    defer {
        for (args.toSlice()) |x| x.deinit(alloc);
        args.deinit();
    }

    if (args.len != 2) {
        result.* = try errMsg(alloc, "missing operands");
        return result;
    }

    const x = switch (args.at(0)) {
        .MalInteger => |val| val,
        else => {
            result.* = try errMsg(alloc, "expected integer operand");
            return result;
        },
    };
    const y = switch (args.at(1)) {
        .MalInteger => |val| val,
        else => {
            result.* = try errMsg(alloc, "expected integer operand");
            return result;
        },
    };

    result.* = MalType{ .MalInteger = @divTrunc(x, y) };
    return result;
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut();

    //var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    //const allocator = &arena.allocator;
    const allocator = std.heap.page_allocator;

    // REPL environment
    const repl_env = &Env.init(allocator, null);
    try repl_env.set("+", MalType{ .MalBuiltinFunction = add });
    try repl_env.set("-", MalType{ .MalBuiltinFunction = sub });
    try repl_env.set("*", MalType{ .MalBuiltinFunction = mul });
    try repl_env.set("/", MalType{ .MalBuiltinFunction = div });
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
        } else |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        }
    }
}
