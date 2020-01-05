const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const types = @import("types.zig");
const SequenceType = types.SequenceType;
const MalType = types.MalType;

pub const Env = struct {
    allocator: *Allocator,
    outer: ?*Self,
    data: StringHashMap(MalType),

    const Self = @This();

    /// Creates a new environment with an outer environment
    pub fn init(alloc: *Allocator, outer: ?*Self) Self {
        return Self{
            .allocator = alloc,
            .outer = outer,
            .data = StringHashMap(MalType).init(alloc),
        };
    }

    pub const BindsError = error{ WrongNumberOfBinds };

    /// Creates a new environment with these bindings
    pub fn initWithBinds(alloc: *Allocator, outer: ?*Self, binds: []const u8, exprs: []MalType) !Self {
        var new_env = Self.init(alloc, outer);

        if (binds.len != exprs.len) return error.WrongNumberOfBinds;
        for (binds) |i, sym| {
            try new_env.set(sym, exprs[i]);
        }

        return new_env;
    }

    /// Destroys this environment (but not outer environment(s))
    pub fn deinit(self: *Self) void {
        var iter = self.data.iterator();
        while (iter.next()) |kv| {
            kv.value.deinit(self.allocator);
        }
        self.data.deinit();
    }

    /// Adds or overwrites a definition in this environment
    /// This takes ownership of the key as well as the value
    pub fn set(self: *Self, key: []const u8, val: MalType) !void {
        _ = try self.data.put(key, val);
    }

    /// Finds the top-most environment containing this definition
    pub fn find(self: *Self, key: []const u8) ?*Self {
        if (self.data.get(key)) |_| {
            return self;
        } else {
            if (self.outer) |outer| {
                return outer.find(key);
            } else {
                return null;
            }
        }
    }

    /// Gets the value of this definition
    /// Caller gets ownership of the value
    pub fn get(self: *Self, alloc: *Allocator, key: []const u8) !?MalType {
        if (self.find(key)) |env| {
            return try env.data.get(key).?.value.copy(alloc);
        } else {
            return null;
        }
    }
};
