const std = @import("std");
const Word = @import("jix.zig").Word;
const ComptimeStringMap = std.ComptimeStringMap;
const AutoHashMap = std.AutoHashMap;

pub const InstType = enum {
    // stack
    push,
    dup,

    // arithmetics
    plus,
    minus,
    mult,
    div,
    eq,

    // misc
    jmp,
    jmp_if,
    halt,
};

pub const Inst = packed struct {
    @"type": InstType,
    operand: Word = undefined,
};

pub const InstFromString = ComptimeStringMap(InstType, .{
    // stack
    .{ "push", .push },
    .{ "dup", .dup },

    // arithmetics
    .{ "plus", .plus },
    .{ "minus", .minus },
    .{ "mult", .mult },
    .{ "div", .div },
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
    .{ "plus", false },
    .{ "minus", false },
    .{ "mult", false },
    .{ "div", false },
    .{ "eq", false },

    // misc
    .{ "jmp", true },
    .{ "jmp_if", true },
    .{ "halt", false },
});
