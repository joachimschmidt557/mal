const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StringHashMap = std.StringHashMap;

const Rc = @import("rc.zig").Rc;

const types = @import("types.zig");
const SequenceType = types.SequenceType;
const MalType = types.MalType;

pub const Env = struct {
    allocator: *Allocator,
    outer: ?*Rc(Self),
    data: StringHashMap(MalType),

    const Self = @This();

    /// Creates a new environment with an outer environment
    pub fn init(alloc: *Allocator, outer: ?*Rc(Self)) Self {
        return Self{
            .allocator = alloc,
            .outer = outer,
            .data = StringHashMap(MalType).init(alloc),
        };
    }

    /// Creates a new environment with these bindings
    /// Does not take ownership of the bindings
    /// Takes ownership of the expressions
    pub fn initWithBinds(alloc: *Allocator, outer: ?*Rc(Self), binds: [][]const u8, exprs: []MalType) !Self {
        var new_env = Self.init(alloc, outer);

        for (binds) |name, i| {
            if (std.mem.eql(u8, "&", name)) {
                var l = ArrayList(MalType).init(alloc);

                for (exprs[i..]) |x| {
                    try l.append(x);
                }

                // When creating closures, we always check for correct varargs
                const varargs_param_name = try std.mem.dupe(alloc, u8, binds[i + 1]);
                try new_env.set(varargs_param_name, MalType{ .MalList = l });

                break;
            } else {
                const name_copy = try std.mem.dupe(alloc, u8, name);
                const expr_copy = exprs[i];
                try new_env.set(name_copy, expr_copy);
            }
        }

        return new_env;
    }

    /// Destroys this environment (but not outer environment(s))
    pub fn deinit(self: *Self) void {
        if (self.outer) |env|
            env.close();

        var iter = self.data.iterator();
        while (iter.next()) |kv| {
            self.allocator.free(kv.key);
            kv.value.deinit(self.allocator);
        }
        self.data.deinit();
    }

    /// Adds or overwrites a definition in this environment
    /// This takes ownership of the key as well as the value
    pub fn set(self: *Self, key: []const u8, val: MalType) !void {
        // If we are overwriting an existing entry, discard that entry
        if (try self.data.put(key, val)) |kv| {
            self.allocator.free(kv.key);
            kv.value.deinit(self.allocator);
        }
    }

    /// Finds the top-most environment containing this definition
    pub fn find(self: *Self, key: []const u8) ?*Self {
        if (self.data.get(key)) |_| {
            return self;
        } else {
            if (self.outer) |outer| {
                return outer.p.find(key);
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
