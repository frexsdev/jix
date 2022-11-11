const std = @import("std");
const Word = @import("jix.zig").Word;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const String = @import("string.zig").String;
const ComptimeStringMap = std.ComptimeStringMap;

pub const InstType = enum {
    // stack
    push,
    dup,
    swap,
    drop,

    // arithmetics
    add,
    sub,
    mult,
    div,
    not,

    // comparison
    eq,
    gt,
    get,
    lt,
    let,

    // bitwise
    andb,
    orb,
    xor,
    shr,
    shl,
    notb,

    // misc
    jmp,
    jmp_if,
    call,
    ret,
    native,
    halt,

    const Self = @This();

    pub fn fromString(str: String) ?Self {
        for (std.enums.values(Self)) |inst| {
            if (str.cmp(@tagName(inst)))
                return inst;
        }

        return null;
    }

    pub fn hasOperand(self: Self) bool {
        return switch (self) {
            // stack
            .push => true,
            .dup => true,
            .swap => true,

            // arithmetics

            // misc
            .jmp => true,
            .jmp_if => true,
            .call => true,
            .native => true,
            else => false,
        };
    }
};

pub const Inst = struct {
    @"type": InstType,
    operand: Word = undefined,
    line_number: usize,

    const Self = @This();

    pub fn toString(self: Self, allocator: Allocator) !String {
        var result = String.init(allocator);
        try result.concat(@tagName(self.@"type"));

        if (InstType.hasOperand(self.@"type"))
            switch (self.operand) {
                .as_u64 => |w| {
                    var word = try std.fmt.allocPrint(allocator, " {}", .{w});
                    defer allocator.free(word);

                    try result.concat(word);
                },
                .as_i64 => |w| {
                    var word = try std.fmt.allocPrint(allocator, " {}", .{w});
                    defer allocator.free(word);

                    try result.concat(word);
                },
                .as_f64 => |w| {
                    var word = try std.fmt.allocPrint(allocator, " {d}", .{w});
                    defer allocator.free(word);

                    try result.concat(word);
                },
                .as_ptr => |w| {
                    var word = try std.fmt.allocPrint(allocator, " {*}", .{w});
                    defer allocator.free(word);

                    try result.concat(word);
                },
            };

        return result;
    }
};
