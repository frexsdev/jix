const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const JixError = @import("error.zig").JixError;

pub fn Array(comptime T: type) type {
    return struct {
        list: ArrayList(T),

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .list = ArrayList(T).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.list.deinit();
            self.* = undefined;
        }

        pub fn push(self: *Self, item: T) JixError!void {
            self.list.append(item) catch return JixError.StackOverflow;
        }

        pub fn pop(self: *Self) JixError!T {
            if (self.list.popOrNull()) |item|
                return item
            else
                return JixError.StackUnderflow;
        }

        pub fn size(self: Self) usize {
            return self.list.items.len;
        }

        pub fn items(self: Self) []T {
            return self.list.items;
        }

        pub fn get(self: Self, index: usize) T {
            return self.list.items[index];
        }

        pub fn reset(self: *Self) void {
            self.list.items.len = 0;
        }
    };
}
