const std = @import("std");
const Word = @import("jix.zig").Word;
const ComptimeStringMap = std.ComptimeStringMap;
const AutoHashMap = std.AutoHashMap;

pub const InstType = enum {
    // stack
    push,
    dup,

    // arithmetics
    plusi,
    plusf,

    minusi,
    minusf,

    multi,
    multf,

    divi,
    divf,

    eq,

    // misc
    jmp,
    jmp_if,
    halt,
};

pub const Inst = struct {
    @"type": InstType,
    operand: Word = undefined,
};

pub const InstFromString = ComptimeStringMap(InstType, .{
    // stack
    .{ "push", .push },
    .{ "dup", .dup },

    // arithmetics
    .{ "plusi", .plusi },
    .{ "plusf", .plusf },

    .{ "minusi", .minusi },
    .{ "minusf", .minusf },

    .{ "multi", .multi },
    .{ "multf", .multf },

    .{ "divi", .divi },
    .{ "divf", .divf },

    .{ "eq", .eq },

    // misc
    .{ "jmp", .jmp },
    .{ "jmp_if", .jmp_if },
    .{ "halt", .halt },
});

pub const InstHasOperand = ComptimeStringMap(bool, .{
    // stack
    .{ "push", true },
    .{ "dup", true },

    // arithmetics
    .{ "plusi", false },
    .{ "plusf", false },

    .{ "minusi", false },
    .{ "minusf", false },

    .{ "multi", false },
    .{ "multf", false },

    .{ "divi", false },
    .{ "divf", false },

    .{ "eq", false },

    // misc
    .{ "jmp", true },
    .{ "jmp_if", true },
    .{ "halt", false },
});
