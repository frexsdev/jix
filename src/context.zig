const std = @import("std");
const Allocator = std.mem.Allocator;
const Array = @import("array.zig").Array;

usingnamespace @import("jix.zig");

const Global = @This();

pub const Label = struct {
    name: []const u8,
    addr: Global.InstAddr,
};

pub const DeferredOperand = struct {
    addr: Global.InstAddr,
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

    pub fn find(self: Self, name: []const u8) ?Global.InstAddr {
        for (self.labels.items()) |label| {
            if (std.mem.eql(u8, label.name, name))
                return label.addr;
        }

        return null;
    }
};
