const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

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
    param_list: ArrayList(MalType),
    body: MalType,
};

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
    MalIntegerFunction: fn(x: i64, y: i64) i64,

    const Self = @This();

    /// Recursively deinitializes this mal value
    /// Basically the opposite to copy
    pub fn deinit(self: Self, alloc: *Allocator) void {
        switch (self) {
            .MalErrorStr, .MalString, .MalSymbol => |s| alloc.free(s),
            .MalList, .MalVector => |list| {
                for (list.toSlice()) |*x| x.deinit(alloc);
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
            else => {},
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
            else => self,
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

pub fn errSymbolNotFound(name: []const u8, alloc: *Allocator) !MalType {
    const msg = try std.fmt.allocPrint(alloc, "{} not found", .{ name });
    return MalType{ .MalErrorStr = msg };
}
