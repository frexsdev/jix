const std = @import("std");
const Jix = @import("jix.zig").Jix;
const JixError = @import("error.zig").JixError;

pub const natives = [_]JixNative{
    jixAlloc,
    jixFree,
};

pub const JixNative = *const fn (*Jix) JixError!void;

pub fn jixAlloc(jix: *Jix) JixError!void {
    const a = (try jix.stack.pop()).as_u64;
    try jix.stack.push(.{ .as_ptr = std.c.malloc(a) });
}

pub fn jixFree(jix: *Jix) JixError!void {
    const a = (try jix.stack.pop()).as_ptr;
    std.c.free(a);
}
