const std = @import("std");
const Word = @import("jix.zig").Word;
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const ComptimeStringMap = std.ComptimeStringMap;

pub const InstType = enum {
    // stack
    push,
    dup,
    swap,
    drop,

    // arithmetics
    plusi,
    plusf,

    minusi,
    minusf,

    multi,
    multf,

    divi,
    divf,

    eqi,
    eqf,

    gei,
    gef,

    // misc
    jmp,
    jmp_if,
    call,
    ret,
    native,
    halt,

    const Self = @This();

    pub fn fromString(str: []const u8) ?Self {
        for (std.enums.values(Self)) |inst| {
            if (std.mem.eql(u8, @tagName(inst), str))
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

    const Self = @This();

    pub fn toString(self: Self, allocator: Allocator) ![]const u8 {
        const inst_name = @tagName(self.@"type");
        if (InstType.hasOperand(self.@"type"))
            return switch (self.operand) {
                .as_u64 => |w| try std.fmt.allocPrint(allocator, "{s} {}", .{ inst_name, w }),
                .as_i64 => |w| try std.fmt.allocPrint(allocator, "{s} {}", .{ inst_name, w }),
                .as_f64 => |w| try std.fmt.allocPrint(allocator, "{s} {d}", .{ inst_name, w }),
                .as_ptr => |w| try std.fmt.allocPrint(allocator, "{s} {*}", .{ inst_name, w }),
            }
        else
            return try std.fmt.allocPrint(allocator, "{s}", .{inst_name});
    }
};
