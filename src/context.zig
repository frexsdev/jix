const std = @import("std");
const Allocator = std.mem.Allocator;
const Array = @import("array.zig").Array;
const String = @import("string.zig").String;
const JixError = @import("error.zig").JixError;

usingnamespace @import("jix.zig");

const Global = @This();

pub const Label = struct {
    name: String,
    word: Global.Word,
};

pub const DeferredOperand = struct {
    addr: Global.InstAddr,
    label: String,
    line_number: usize,
};

pub const AsmContext = struct {
    file_path: String,
    labels: Array(Label),
    deferred_operands: Array(DeferredOperand),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .file_path = String.init(allocator),
            .labels = Array(Label).init(allocator),
            .deferred_operands = Array(DeferredOperand).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.file_path.deinit();
        self.labels.deinit();
        self.deferred_operands.deinit();
        self.* = undefined;
    }

    pub fn resolve(self: Self, name: String) ?Global.Word {
        for (self.labels.items()) |label| {
            if (std.mem.eql(u8, label.name.str(), name.str()))
                return label.word;
        }

        return null;
    }

    pub fn bindLabel(self: *Self, name: String, word: Global.Word) JixError!void {
        try self.labels.push(.{ .name = name, .word = word });
    }
};
