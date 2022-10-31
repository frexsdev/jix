const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Word = @import("jix.zig").Word;
const Array = @import("array.zig").Array;

pub const Label = struct {
    name: []const u8,
    addr: usize,
};

pub const DeferredOperand = struct {
    addr: usize,
    label: []const u8,
};

pub const AsmContext = struct {
    labels: Array(Label),
    deferred_operands: Array(DeferredOperand),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .labels = Array(Label).init(allocator),
            .deferred_operands = Array(DeferredOperand).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.labels.deinit();
        self.deferred_operands.deinit();
        self.* = undefined;
    }

    pub fn find(self: Self, name: []const u8) ?usize {
        for (self.labels.items()) |label| {
            if (mem.eql(u8, label.name, name))
                return label.addr;
        }

        return null;
    }
};
