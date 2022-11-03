const std = @import("std");
const Allocator = std.mem.Allocator;

pub const String = struct {
    allocator: Allocator,
    buffer: ?[]u8,
    size: usize,

    const Self = @This();

    pub const StringError = error{
        OutOfMemory,
        InvalidRange,
    };

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .buffer = null,
            .size = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.buffer) |buffer|
            self.allocator.free(buffer);

        self.* = undefined;
    }

    pub fn capacity(self: Self) usize {
        if (self.buffer) |buffer|
            return buffer.len;
        return 0;
    }

    pub fn allocate(self: *Self, bytes: usize) StringError!void {
        if (self.buffer) |buffer| {
            if (bytes < self.size) self.size = bytes;
            self.buffer = self.allocator.realloc(buffer, bytes) catch {
                return StringError.OutOfMemory;
            };
        } else {
            self.buffer = self.allocator.alloc(u8, bytes) catch {
                return StringError.OutOfMemory;
            };
        }
    }

    pub fn truncate(self: *Self) StringError!void {
        try self.allocate(self.size);
    }

    pub fn concat(self: *Self, char: []const u8) StringError!void {
        try self.insert(char, self.len());
    }

    pub fn insert(self: *Self, literal: []const u8, index: usize) StringError!void {
        if (self.buffer) |buffer| {
            if (self.size + literal.len > buffer.len) {
                try self.allocate((self.size + literal.len) * 2);
            }
        } else {
            try self.allocate((literal.len) * 2);
        }

        const buffer = self.buffer.?;

        if (index == self.len()) {
            var i: usize = 0;
            while (i < literal.len) : (i += 1) {
                buffer[self.size + i] = literal[i];
            }
        } else {
            if (Self.getIndex(buffer, index, true)) |k| {
                var i: usize = buffer.len - 1;
                while (i >= k) : (i -= 1) {
                    if (i + literal.len < buffer.len) {
                        buffer[i + literal.len] = buffer[i];
                    }

                    if (i == 0) break;
                }

                i = 0;
                while (i < literal.len) : (i += 1) {
                    buffer[index + i] = literal[i];
                }
            }
        }

        self.size += literal.len;
    }

    pub fn pop(self: *Self) ?[]const u8 {
        if (self.size == 0) return null;

        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = Self.getUTF8Size(buffer[i]);
                if (i + size >= self.size) break;
                i += size;
            }

            const ret = buffer[i..self.size];
            self.size -= (self.size - i);
            return ret;
        }

        return null;
    }

    pub fn cmp(self: Self, literal: []const u8) bool {
        if (self.buffer) |buffer| {
            return std.mem.eql(u8, buffer[0..self.size], literal);
        }
        return false;
    }

    pub fn str(self: Self) []const u8 {
        if (self.buffer) |buffer| return buffer[0..self.size];
        return "";
    }

    pub fn toOwned(self: Self) StringError!?[]u8 {
        if (self.buffer != null) {
            const string = self.str();
            if (self.allocator.alloc(u8, string.len)) |newStr| {
                std.mem.copy(u8, newStr, string);
                return newStr;
            } else |_| {
                return StringError.OutOfMemory;
            }
        }

        return null;
    }

    pub fn charAt(self: Self, index: usize) ?[]const u8 {
        if (self.buffer) |buffer| {
            if (Self.getIndex(buffer, index, true)) |i| {
                const size = Self.getUTF8Size(buffer[i]);
                return buffer[i..(i + size)];
            }
        }
        return null;
    }

    pub fn len(self: Self) usize {
        if (self.buffer) |buffer| {
            var length: usize = 0;
            var i: usize = 0;

            while (i < self.size) {
                i += Self.getUTF8Size(buffer[i]);
                length += 1;
            }

            return length;
        } else {
            return 0;
        }
    }

    pub fn find(self: Self, literal: []const u8) ?usize {
        if (self.buffer) |buffer| {
            const index = std.mem.indexOf(u8, buffer[0..self.size], literal);
            if (index) |i| {
                return Self.getIndex(buffer, i, false);
            }
        }

        return null;
    }

    pub fn remove(self: *Self, index: usize) StringError!void {
        try self.removeRange(index, index + 1);
    }

    pub fn removeRange(self: *Self, start: usize, end: usize) StringError!void {
        const length = self.len();
        if (end < start or end > length) return StringError.InvalidRange;

        if (self.buffer) |buffer| {
            const rStart = Self.getIndex(buffer, start, true).?;
            const rEnd = Self.getIndex(buffer, end, true).?;
            const difference = rEnd - rStart;

            var i: usize = rEnd;
            while (i < self.size) : (i += 1) {
                buffer[i - difference] = buffer[i];
            }

            self.size -= difference;
        }
    }

    pub fn trimStart(self: *Self, whitelist: []const u8) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) : (i += 1) {
                const size = Self.getUTF8Size(buffer[i]);
                if (size > 1 or !inWhitelist(buffer[i], whitelist)) break;
            }

            if (Self.getIndex(buffer, i, false)) |k| {
                self.removeRange(0, k) catch {};
            }
        }
    }

    pub fn trimEnd(self: *Self, whitelist: []const u8) void {
        self.reverse();
        self.trimStart(whitelist);
        self.reverse();
    }

    pub fn trim(self: *Self, whitelist: []const u8) void {
        self.trimStart(whitelist);
        self.trimEnd(whitelist);
    }

    pub fn clone(self: Self) StringError!Self {
        var new_string = Self.init(self.allocator);
        try new_string.concat(self.str());
        return new_string;
    }

    pub fn reverse(self: *Self) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = Self.getUTF8Size(buffer[i]);
                if (size > 1) std.mem.reverse(u8, buffer[i..(i + size)]);
                i += size;
            }

            std.mem.reverse(u8, buffer[0..self.size]);
        }
    }

    pub fn repeat(self: *Self, n: usize) StringError!void {
        try self.allocate(self.size * (n + 1));
        if (self.buffer) |buffer| {
            var i: usize = 1;
            while (i <= n) : (i += 1) {
                var j: usize = 0;
                while (j < self.size) : (j += 1) {
                    buffer[((i * self.size) + j)] = buffer[j];
                }
            }

            self.size *= (n + 1);
        }
    }

    pub inline fn isEmpty(self: Self) bool {
        return self.size == 0;
    }

    pub fn split(self: Self, delimiters: []const u8, index: usize) ?[]const u8 {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            var block: usize = 0;
            var start: usize = 0;

            while (i < self.size) {
                const size = Self.getUTF8Size(buffer[i]);
                if (size == delimiters.len) {
                    if (std.mem.eql(u8, delimiters, buffer[i..(i + size)])) {
                        if (block == index) return buffer[start..i];
                        start = i + size;
                        block += 1;
                    }
                }

                i += size;
            }

            if (i >= self.size - 1 and block == index) {
                return buffer[start..self.size];
            }
        }

        return null;
    }

    pub fn splitToString(self: Self, delimiters: []const u8, index: usize) StringError!?Self {
        if (self.split(delimiters, index)) |block| {
            var string = Self.init(self.allocator);
            try string.concat(block);
            return string;
        }

        return null;
    }

    pub fn clear(self: *Self) void {
        if (self.buffer) |buffer| {
            for (buffer) |*ch| ch.* = 0;
            self.size = 0;
        }
    }

    pub fn toLowercase(self: *Self) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = Self.getUTF8Size(buffer[i]);
                if (size == 1) buffer[i] = std.ascii.toLower(buffer[i]);
                i += size;
            }
        }
    }

    pub fn toUppercase(self: *Self) void {
        if (self.buffer) |buffer| {
            var i: usize = 0;
            while (i < self.size) {
                const size = Self.getUTF8Size(buffer[i]);
                if (size == 1) buffer[i] = std.ascii.toUpper(buffer[i]);
                i += size;
            }
        }
    }

    pub fn substr(self: Self, start: usize, end: usize) StringError!Self {
        var result = Self.init(self.allocator);

        if (self.buffer) |buffer| {
            if (Self.getIndex(buffer, start, true)) |rStart| {
                if (Self.getIndex(buffer, end, true)) |rEnd| {
                    if (rEnd < rStart or rEnd > self.size)
                        return StringError.InvalidRange;
                    try result.concat(buffer[rStart..rEnd]);
                }
            }
        }

        return result;
    }

    pub usingnamespace struct {
        pub const Writer = std.io.Writer(*Self, StringError, appendWrite);

        pub fn writer(self: *Self) Writer {
            return .{ .context = self };
        }

        fn appendWrite(self: *Self, m: []const u8) !usize {
            try self.concat(m);
            return m.len;
        }
    };

    pub usingnamespace struct {
        pub const StringIterator = struct {
            string: *Self,
            index: usize,

            pub fn next(it: *StringIterator) ?[]const u8 {
                if (it.string.buffer) |buffer| {
                    if (it.index == it.string.size) return null;
                    var i = it.index;
                    it.index += Self.getUTF8Size(buffer[i]);
                    return buffer[i..it.index];
                } else {
                    return null;
                }
            }
        };

        pub fn iterator(self: *Self) StringIterator {
            return StringIterator{
                .string = self,
                .index = 0,
            };
        }
    };

    fn inWhitelist(char: u8, whitelist: []const u8) bool {
        var i: usize = 0;
        while (i < whitelist.len) : (i += 1) {
            if (whitelist[i] == char) return true;
        }

        return false;
    }

    inline fn isUTF8Byte(byte: u8) bool {
        return ((byte & 0x80) > 0) and (((byte << 1) & 0x80) == 0);
    }

    fn getIndex(unicode: []const u8, index: usize, real: bool) ?usize {
        var i: usize = 0;
        var j: usize = 0;
        while (i < unicode.len) {
            if (real) {
                if (j == index) return i;
            } else {
                if (i == index) return j;
            }
            i += Self.getUTF8Size(unicode[i]);
            j += 1;
        }

        return null;
    }

    inline fn getUTF8Size(char: u8) u3 {
        return std.unicode.utf8ByteSequenceLength(char) catch {
            return 1;
        };
    }
};
