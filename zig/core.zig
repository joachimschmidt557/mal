const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const types = @import("types.zig");
const BuiltinFunctionError = types.BuiltinFunctionError;
const MalType = types.MalType;
const errMsg = types.errMsg;

const printer = @import("printer.zig");
const pr_str = printer.pr_str;

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

pub fn lessThan(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
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

    result.* = MalType{ .MalBoolean = x < y };
    return result;
}

pub fn lessThanEq(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
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

    result.* = MalType{ .MalBoolean = x <= y };
    return result;
}

pub fn greaterThan(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
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

    result.* = MalType{ .MalBoolean = x > y };
    return result;
}

pub fn greaterThanEq(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
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

    result.* = MalType{ .MalBoolean = x >= y };
    return result;
}

/// Helper function for printing readably
fn readably(alloc: *Allocator, args: ArrayList(MalType)) ![]const u8 {
    defer args.deinit();
    var output = ArrayList(u8).init(alloc);

    for (args.toSlice()) |x, i| {
        try output.appendSlice(try pr_str(x, alloc, true));
        if (i != args.len - 1)
            try output.append(' ');
    }

    return output.toSliceConst();
}

/// Helper function for printing non-readably
fn nonReadably(alloc: *Allocator, args: ArrayList(MalType)) ![]const u8 {
    defer args.deinit();
    var output = ArrayList(u8).init(alloc);

    for (args.toSlice()) |x, i| {
        try output.appendSlice(try pr_str(x, alloc, false));
    }

    return output.toSliceConst();
}

/// Helper function for printing non-readably and joined with spaces
fn nonReadablyWithSpaces(alloc: *Allocator, args: ArrayList(MalType)) ![]const u8 {
    defer args.deinit();
    var output = ArrayList(u8).init(alloc);

    for (args.toSlice()) |x, i| {
        try output.appendSlice(try pr_str(x, alloc, false));
        if (i != args.len - 1)
            try output.append(' ');
    }

    return output.toSliceConst();
}

pub fn prStr(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);

    result.* = MalType{ .MalString = try readably(alloc, args) };
    return result;
}

pub fn str(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);

    result.* = MalType{ .MalString = try nonReadably(alloc, args) };
    return result;
}

pub fn prn(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);

    const output_stream = &std.io.getStdOut().outStream().stream;
    output_stream.print("{}\n", .{ try readably(alloc, args) }) catch {
        result.* = try errMsg(alloc, "input/output error");
        return result;
    };

    result.* = MalType.MalNil;
    return result;
}

pub fn printLn(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);

    const output_stream = &std.io.getStdOut().outStream().stream;
    output_stream.print("{}\n", .{ try nonReadablyWithSpaces(alloc, args) }) catch {
        result.* = try errMsg(alloc, "input/output error");
        return result;
    };

    result.* = MalType.MalNil;
    return result;
}

pub fn makeList(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);

    result.* = MalType{ .MalList = args };
    return result;
}

pub fn isList(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);
    defer {
        for (args.toSlice()) |x| x.deinit(alloc);
        args.deinit();
    }

    if (args.len != 1) {
        result.* = try errMsg(alloc, "list? expects 1 argument");
        return result;
    }

    const val = if (args.at(0) == .MalList) true else false;

    result.* = MalType{ .MalBoolean = val };
    return result;
}

pub fn isEmpty(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);
    defer {
        for (args.toSlice()) |x| x.deinit(alloc);
        args.deinit();
    }

    if (args.len != 1) {
        result.* = try errMsg(alloc, "empty? expects 1 argument");
        return result;
    }

    const val = switch (args.at(0)) {
        .MalList, .MalVector => |l| l.len == 0,
        else => {
            result.* = try errMsg(alloc, "empty? expects a list or vector");
            return result;
        },
    };

    result.* = MalType{ .MalBoolean = val };
    return result;
}

pub fn count(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);
    defer {
        for (args.toSlice()) |x| x.deinit(alloc);
        args.deinit();
    }

    if (args.len != 1) {
        result.* = try errMsg(alloc, "count expects 1 argument");
        return result;
    }

    const len = switch (args.at(0)) {
        .MalNil => @intCast(usize, 0),
        .MalList, .MalVector => |l| l.len,
        else => {
            result.* = try errMsg(alloc, "count expects a list or vector");
            return result;
        },
    };

    result.* = MalType{ .MalInteger = @intCast(i64, len) };
    return result;
}

pub fn eql(alloc: *Allocator, args: ArrayList(MalType)) !*MalType {
    const result = try alloc.create(MalType);
    defer {
        for (args.toSlice()) |x| x.deinit(alloc);
        args.deinit();
    }

    if (args.len != 2) {
        result.* = try errMsg(alloc, "= expects 2 arguments");
        return result;
    }

    result.* = MalType{ .MalBoolean = args.at(0).eql(args.at(1)) };
    return result;
}

pub const NamespaceItem = struct {
    name: []const u8,
    val: fn (alloc: *Allocator, args: ArrayList(MalType)) BuiltinFunctionError!*MalType,
};

pub const ns = [_]NamespaceItem{
    NamespaceItem{ .name = "+", .val = add },
    NamespaceItem{ .name = "-", .val = sub },
    NamespaceItem{ .name = "*", .val = mul },
    NamespaceItem{ .name = "/", .val = div },
    NamespaceItem{ .name = "<", .val = lessThan },
    NamespaceItem{ .name = "<=", .val = lessThanEq },
    NamespaceItem{ .name = ">", .val = greaterThan },
    NamespaceItem{ .name = ">=", .val = greaterThanEq },
    NamespaceItem{ .name = "list", .val = makeList },
    NamespaceItem{ .name = "list?", .val = isList },
    NamespaceItem{ .name = "empty?", .val = isEmpty },
    NamespaceItem{ .name = "empty?", .val = isEmpty },
    NamespaceItem{ .name = "count", .val = count },
    NamespaceItem{ .name = "=", .val = eql },
    NamespaceItem{ .name = "pr-str", .val = prStr },
    NamespaceItem{ .name = "str", .val = str },
    NamespaceItem{ .name = "prn", .val = prn },
    NamespaceItem{ .name = "println", .val = printLn },
};
