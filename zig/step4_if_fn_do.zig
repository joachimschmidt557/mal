const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Rc = @import("rc.zig").Rc;

const reader = @import("reader.zig");
const printer = @import("printer.zig");
const types = @import("types.zig");
const MalType = types.MalType;
const MalClosure = types.MalClosure;
const errMsg = types.errMsg;
const errSymbolNotFound = types.errSymbolNotFound;

const Env = @import("env.zig").Env;

const core = @import("core.zig");
const ns = core.ns;

pub const EvalError = Allocator.Error;

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
fn EVAL(ast: MalType, env: *Rc(Env), alloc: *Allocator) EvalError!MalType {
    defer env.close();

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

                        const value = try EVAL(third, env.copy(), alloc);
                        if (value.isError()) {
                            second.deinit(alloc);
                        } else {
                            try env.p.set(key, try value.copy(alloc));
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

                        const new_env = try Rc(Env).initEmpty(alloc);
                        new_env.destructor = Env.deinit;
                        new_env.p.* = Env.init(alloc, env.copy());
                        defer new_env.close();

                        if (new_bindings.len % 2 != 0)
                            return try err_let_binding_odd.copy(alloc);

                        var i: usize = 0;
                        while (i < new_bindings.len) : (i += 2) {
                            const key = switch (new_bindings.at(i)) {
                                .MalSymbol => |str| str,
                                else => return try err_defining_non_symbol.copy(alloc),
                            };
                            const value = try EVAL(new_bindings.at(i + 1), new_env.copy(), alloc);
                            if (value.isError()) return value;

                            try new_env.p.set(key, value);
                        }

                        return try EVAL(third, new_env.copy(), alloc);
                    } else if (std.mem.eql(u8, symbol, "do")) {
                        // Do block
                        defer ast.deinit(alloc);
                        if (list.len < 2) return try errMsg(alloc, "do requires at least one item");
                        var body = try ast.copy(alloc);

                        // Remove the "do" symbol
                        body.MalList.at(0).deinit(alloc);
                        _ = body.MalList.orderedRemove(0);

                        // Evaluate and return
                        const result = try eval_ast(body, env.copy(), alloc);
                        if (result.isError()) return result;

                        defer result.deinit(alloc);
                        const last_i = result.MalList.len - 1;
                        return try result.MalList.at(last_i).copy(alloc);
                    } else if (std.mem.eql(u8, symbol, "if")) {
                        // if condition
                        defer ast.deinit(alloc);
                        if (list.len != 3 and list.len != 4) return try err_missing_operands.copy(alloc);
                        const second = try list.at(1).copy(alloc);

                        // Evaluate condition
                        const cond = try EVAL(second, env.copy(), alloc);
                        if (cond.isError()) return cond;

                        const cond_false = (cond == .MalNil) or (cond == .MalBoolean and
                                                                     cond.MalBoolean == false);
                        if (!cond_false) {
                            const third = try list.at(2).copy(alloc);
                            return try EVAL(third, env.copy(), alloc);
                        } else {
                            if (list.len == 3) {
                                return MalType.MalNil;
                            } else {
                                const fourth = try list.at(3).copy(alloc);
                                return try EVAL(fourth, env.copy(), alloc);
                            }
                        }
                    } else if (std.mem.eql(u8, symbol, "fn*")) {
                        // function closure
                        defer ast.deinit(alloc);
                        if (list.len != 3) return try err_missing_operands.copy(alloc);
                        const second = try list.at(1).copy(alloc);
                        const third = try list.at(2).copy(alloc);

                        defer second.deinit(alloc);

                        const params = switch (second) {
                            .MalList, .MalVector => |l| l,
                            else => return try errMsg(alloc, "function parameters must be a list"),
                        };

                        var param_list = ArrayList([]const u8).init(alloc);
                        for (params.toSlice()) |p, i| {
                            if (p != .MalSymbol) {
                                return try errMsg(alloc, "function parameter must be a symbol");
                            }
                            if (std.mem.eql(u8, "&", p.MalSymbol) and i != params.len - 2) {
                                return try errMsg(alloc, "function varargs must be at the last position of the parameter list");
                            }

                            try param_list.append((try p.copy(alloc)).MalSymbol);
                        }

                        const closure = try alloc.create(MalClosure);
                        closure.* = MalClosure{
                            .param_list = param_list,
                            .body = third,
                            .env = env.copy(),
                        };

                        return MalType{ .MalFunction = closure };
                    }
                }

                // Evaluate list
                var evaluated = try eval_ast(ast, env.copy(), alloc);
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
                    .MalFunction => |closure| {
                        defer (MalType{ .MalFunction = closure }).deinit(alloc);
                        defer {
                            // Free parameters
                            for (l.toSlice()) |y| y.deinit(alloc);
                            l.deinit();
                        }

                        if (!closure.numberOfArgsValid(l.len))
                            return try errMsg(alloc, "wrong number of parameters");

                        const new_env = try Rc(Env).initEmpty(alloc);
                        new_env.destructor = Env.deinit;
                        new_env.p.* = try Env.initWithBinds(alloc,
                                                            closure.env.copy(),
                                                            closure.param_list.toSlice(),
                                                            l.toSlice());
                        defer new_env.close();

                        return try EVAL(try closure.body.copy(alloc),
                                        new_env.copy(), alloc);
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
        else => return try eval_ast(ast, env.copy(), alloc),
    }
}

/// Converts a mal value into a string
/// This takes ownership of the mal value
/// Caller gets ownership of the string
fn PRINT(x: MalType, alloc: *Allocator) ![]const u8 {
    return try printer.pr_str(x, alloc, true);
}

/// Recursive helper function for EVAL
fn eval_ast(ast: MalType, env: *Rc(Env), alloc: *Allocator) EvalError!MalType {
    defer env.close();

    switch (ast) {
        .MalErrorStr => return ast,
        .MalSymbol => |name| {
            defer ast.deinit(alloc);
            if (try env.p.get(alloc, name)) |val| {
                return val;
            } else {
                return try errSymbolNotFound(name, alloc);
            }
        },
        .MalList, .MalVector => |list| {
            for (list.toSlice()) |*value| {
                const itm = try EVAL(value.*, env.copy(), alloc);
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
                const itm = try EVAL(kv.*.value, env.copy(), alloc);
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

fn rep(s: []const u8, env: *Rc(Env), alloc: *Allocator) ![]const u8 {
    return try PRINT(try EVAL(try READ(s, alloc), env, alloc), alloc);
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut();

    //var arena = std.heap.ArenaAllocator.init(std.heap.direct_allocator);
    //const allocator = &arena.allocator;
    const allocator = std.heap.page_allocator;

    // REPL environment
    const repl_env = try Rc(Env).initEmpty(allocator);
    repl_env.destructor = Env.deinit;
    repl_env.p.* = Env.init(allocator, null);
    for (core.ns) |itm| {
        try repl_env.p.set(try std.mem.dupe(allocator, u8, itm.name),
                         MalType{ .MalBuiltinFunction = itm.val });
    }
    defer repl_env.close();

    // Initialization
    _ = try rep("(def! not (fn* (a) (if a false true)))", repl_env.copy(), allocator);

    // Buffer for line reading
    var buf = try std.Buffer.initSize(allocator, std.mem.page_size);
    defer buf.deinit();

    while (true) {
        try stdout_file.write("user> ");

        if (std.io.readLine(&buf)) |line| {
            var result = rep(line, repl_env.copy(), allocator) catch |err| {
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
