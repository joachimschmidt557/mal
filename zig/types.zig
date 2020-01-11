const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const env = @import("env.zig");
const Env = env.Env;

pub const SequenceType = enum {
    List,
    Vector,

    const Self = @This();

    pub fn startToken(x: Self) []const u8 {
        return switch (x) {
            .List => "(",
            .Vector => "[",
        };
    }

    pub fn endToken(x: Self) []const u8 {
        return switch (x) {
            .List => ")",
            .Vector => "]",
        };
    }
};

pub const MalClosure = struct {
    param_list: ArrayList([]const u8),
    body: MalType,
    env: *Env,

    const Self = @This();

    pub fn hasVarArgs(self: Self) bool {
        return (self.param_list.len >= 2) and
            (std.mem.eql(u8, "&", self.param_list.at(self.param_list.len - 2)));
    }

    pub fn numberOfArgsValid(self: Self, num: usize) bool {
        if (self.hasVarArgs()) {
            return num >= self.param_list.len - 2;
        } else {
            return num == self.param_list.len;
        }
    }
};

pub const BuiltinFunctionError = Allocator.Error;

pub const MalType = union(enum) {
    MalNil: void,
    MalErrorStr: []const u8,
    MalList: ArrayList(MalType),
    MalString: []const u8,
    MalInteger: i64,
    MalBoolean: bool,
    MalSymbol: []const u8,
    MalVector: ArrayList(MalType),
    MalHashMap: StringHashMap(MalType),
    MalBuiltinFunction: fn(alloc: *Allocator, args: ArrayList(MalType)) BuiltinFunctionError!*MalType,
    MalFunction: *MalClosure,

    const Self = @This();

    /// Recursively deinitializes this mal value
    /// Basically the opposite to copy
    pub fn deinit(self: Self, alloc: *Allocator) void {
        switch (self) {
            .MalErrorStr, .MalString, .MalSymbol => |s| alloc.free(s),
            .MalList, .MalVector => |list| {
                for (list.toSlice()) |x| x.deinit(alloc);
                list.deinit();
            },
            .MalHashMap => |map| {
                var iter = map.iterator();
                while (iter.next()) |kv| {
                    alloc.free(kv.key);
                    kv.value.deinit(alloc);
                }
                map.deinit();
            },
            .MalFunction => |closure| {
                for (closure.param_list.toSlice()) |p|
                    alloc.free(p);
                closure.param_list.deinit();
                closure.body.deinit(alloc);

                alloc.destroy(closure);
            },
            .MalNil, .MalBoolean, .MalInteger,
            .MalBuiltinFunction => {},
        }
    }

    pub const CopyError = Allocator.Error;

    /// Performs a "deep copy" or recursive copy of this mal
    /// value if applicable
    /// Basically the opposite to deinit
    pub fn copy(self: Self, alloc: *Allocator) CopyError!Self {
        return switch (self) {
            .MalErrorStr => |s| MalType{ .MalErrorStr = try std.mem.dupe(alloc, u8, s) },
            .MalString => |s| MalType{ .MalString = try std.mem.dupe(alloc, u8, s) },
            .MalSymbol => |s| MalType{ .MalSymbol = try std.mem.dupe(alloc, u8, s) },
            .MalList, .MalVector => |l| blk: {
                var result = ArrayList(MalType).init(alloc);

                for (l.toSlice()) |x| {
                    try result.append(try x.copy(alloc));
                }

                break :blk switch(self) {
                    .MalList => MalType{ .MalList = result },
                    .MalVector => MalType{ .MalVector = result },
                    else => unreachable,
                };
            },
            .MalHashMap => |map| blk: {
                var result = StringHashMap(MalType).init(alloc);

                var iter = map.iterator();
                while (iter.next()) |kv| {
                    const key = try std.mem.dupe(alloc, u8, kv.key);
                    const value = try kv.value.copy(alloc);
                    _ = try result.put(key, value);
                }

                break :blk MalType{ .MalHashMap = result };
            },
            .MalFunction => |closure| blk: {
                var param_list = ArrayList([]const u8).init(alloc);

                for (closure.param_list.toSlice()) |p| {
                    try param_list.append(try std.mem.dupe(alloc, u8, p));
                }

                const result = try alloc.create(MalClosure);
                result.* = MalClosure{
                    .param_list = param_list,
                    .env = closure.env,
                    .body = try closure.body.copy(alloc),
                };

                break :blk MalType{ .MalFunction = result };
            },
            .MalNil, .MalBoolean, .MalInteger,
            .MalBuiltinFunction => self,
        };
    }

    pub fn eql(self: Self, other: Self) bool {
        return switch (self) {
            .MalNil => other == .MalNil,
            .MalBoolean => |val| switch (other) {
                .MalBoolean => |b| b == val,
                else => false,
            },
            .MalInteger => |val| switch (other) {
                .MalInteger => |b| b == val,
                else => false,
            },
            .MalBuiltinFunction => |val| switch (other) {
                .MalBuiltinFunction => |f| f == val,
                else => false,
            },
            .MalString => |val| switch (other) {
                .MalString => |s| std.mem.eql(u8, val, s),
                else => false,
            },
            .MalErrorStr => |val| switch (other) {
                .MalErrorStr => |s| std.mem.eql(u8, val, s),
                else => false,
            },
            .MalSymbol => |val| switch (other) {
                .MalSymbol => |s| std.mem.eql(u8, val, s),
                else => false,
            },
            .MalList, .MalVector => |val| switch (other) {
                .MalList, .MalVector => |l| blk: {
                    if (val.len == l.len) {
                        for (val.toSlice()) |x, i| {
                            if (!x.eql(l.at(i))) {
                                break :blk false;
                            }
                        }
                        break :blk true;
                    } else {
                        break :blk false;
                    }
                },
                else => false,
            },
            .MalHashMap => |val| switch (other) {
                .MalHashMap => |map| blk: {
                    break :blk false;
                },
                else => false,
            },
            .MalFunction => false,
        };
    }

    /// Returns whether this mal value represents
    /// an error value
    pub fn isError(self: Self) bool {
        return switch (self) {
            .MalErrorStr => true,
            else => false,
        };
    }
};

pub fn errMsg(alloc: *Allocator, msg: []const u8) !MalType {
    const msg_copy = try std.mem.dupe(alloc, u8, msg);
    return MalType{ .MalErrorStr = msg_copy };
}

pub fn errSymbolNotFound(name: []const u8, alloc: *Allocator) !MalType {
    const msg = try std.fmt.allocPrint(alloc, "{} not found", .{ name });
    return MalType{ .MalErrorStr = msg };
}
