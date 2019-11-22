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
    MalList: std.TailQueue(MalType),
    MalString: []const u8,
    MalInteger: i64,
    MalBoolean: bool,
    MalSymbol: []const u8,
    MalVector: std.TailQueue(MalType),
    MalHashMap: std.StringHashMap(MalType),
    MalIntegerFunction: fn(x: i64, y: i64) i64,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        switch (self) {
            else => return,
        }
    }
};
