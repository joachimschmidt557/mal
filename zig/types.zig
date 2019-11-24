const std = @import("std");

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

pub const MalType = union(enum) {
    MalNil: void,
    MalErrorStr: []const u8,
    MalList: std.ArrayList(MalType),
    MalString: []const u8,
    MalInteger: i64,
    MalBoolean: bool,
    MalSymbol: []const u8,
    MalVector: std.ArrayList(MalType),
    MalHashMap: std.StringHashMap(MalType),
    MalIntegerFunction: fn(x: i64, y: i64) i64,

    const Self = @This();

    pub fn deinit(self: Self) void {
        switch (self) {
            .MalList, .MalVector => |list| {
                var iter = list.iterator();
                while (iter.next()) |x| x.deinit();
                list.deinit();
            },
            .MalHashMap => |map| {
                var iter = map.iterator();
                while (iter.next()) |kv| kv.value.deinit();
                map.deinit();
            },
            else => {},
        }
    }

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            MalNil => "nil",
            MalList => "list",
            MalString => "string",
            MalInteger => "int",
            MalBoolean => "bool",
            MalSymbol => "symbol",
            MalVector => "vector",
            MalHashMap => "hashmap",
            MalIntegerFunction => "builtin_fn",
        };
    }
};
