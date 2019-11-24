const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;

const types = @import("types.zig");
const SequenceType = types.SequenceType;
const MalType = types.MalType;

pub const Env = struct {
    outer: ?*Self,
    data: StringHashMap(MalType),

    const Self = @This();

    /// Creates a new environment with an outer environment
    pub fn init(outer: ?*Self, alloc: *Allocator) Self {
        return Self{
            .outer = outer,
            .data = StringHashMap(MalType).init(alloc),
        };
    }

    /// Destroys this environment (but not outer environment(s))
    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }

    /// Adds or overwrites a definition in this environment
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
    pub fn get(self: *Self, key: []const u8) ?MalType {
        if (self.find(key)) |env| {
            return env.data.get(key).?.value;
        } else {
            return null;
        }
    }
};
