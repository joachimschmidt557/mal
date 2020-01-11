const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn Rc(comptime T: type) type {
    return struct {
        alloc: *Allocator,
        p: *T,
        refs: usize,
        destructor: ?(fn (x: *T) void),

        const Self = @This();

        pub fn initEmpty(alloc: *Allocator) !*Self {
            const result = try alloc.create(Self);

            result.* = Self{
                .alloc = alloc,
                .p = try alloc.create(T),
                .refs = 1,
                .destructor = null,
            };

            return result;
        }

        pub fn copy(self: *Self) *Self {
            self.refs += 1;
            return self;
        }

        pub fn close(self: *Self) void {
            self.refs -= 1;

            if (self.refs == 0) {
                if (self.destructor) |fun| {
                    fun(self.p);
                }

                self.alloc.destroy(self.p);
                self.alloc.destroy(self);
            }
        }
    };
}
