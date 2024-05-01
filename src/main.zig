const std = @import("std");
const native_endian = @import("builtin").target.cpu.arch.endian();

/// Compact encoding of an `u8`, `u16`, or `u32`.
///
/// Example:
/// ```zig
/// Compact.try_from(123).scaleEncode(writer);
/// ```
pub const Compact = union(enum) {
    U8: u8,
    U16: u16,
    U32: u32,

    const Self = @This();

    /// Try to construct a `Compact` from an arbitrary value.
    ///
    /// Errors at compile-time when the passed type cannot be compacted.
    pub fn try_from(v: anytype) !Self {
        const T = @TypeOf(v);

        return switch (@typeInfo(T)) {
            .Int => |info| {
                if (info.bits <= 8) {
                    return .{ .U8 = @as(u8, @intCast(v)) };
                } else if (info.bits <= 16) {
                    return .{ .U16 = @as(u16, @intCast(v)) };
                } else if (info.bits <= 32) {
                    return .{ .U32 = @as(u32, @intCast(v)) };
                } else {
                    @compileError("bigint suppot missing");
                }
            },
            .ComptimeInt => {
                return Self.try_from(@as(std.math.IntFittingRange(v, v), v));
            },
            else => @compileError("Unable to compact type '" ++ @typeName(T) ++ "'"),
        };
    }

    /// Implement the "interface" function for SCALE encoding.
    ///
    /// Note that Zig does not have interfaces. It only has `comptime std.meta.hasFn` to check that a type has a function with a specific name. Not necessarily the right function, not even the right arguments, not visibility (pub) - just *a* function with that name. Very shitty IMHO. What if i call this function `encode`, instead of `scaleEncode`? Then some other format like `Json` or `Toml` could get confused as to what this function is doing and could take it for their own...
    pub fn scaleEncode(self: *const Compact, writer: anytype) !void {
        return switch (self.*) {
            .U8 => |v| writer.writeU8Compact(v),
            .U16 => |v| writer.writeU16Compact(v),
            .U32 => |v| writer.writeU32Compact(v),
        };
    }
};

/// Construct a `ScaleWriter` from a writer.
pub fn scaleWriter(writer: anytype) ScaleWriter(@TypeOf(writer)) {
    return .{ .writer = writer };
}

/// A writer that encodes values in SCALE format.
pub fn ScaleWriter(comptime WriterType: type) type {
    return struct {
        const Self = @This();

        writer: WriterType,
        pub const Error = WriterType.Error;

        fn writeRaw(self: *Self, bytes: []const u8) Error!void {
            return self.writer.writeAll(bytes);
        }

        pub fn writeBool(self: *Self, v: bool) Error!void {
            return self.writeU8(if (v) 1 else 0);
        }

        /// Encode and write an arbitrary value to the stream.
        ///
        /// Errors at compile-time when the passed type cannot be encoded.
        pub fn write(self: *Self, v: anytype) Error!void {
            const T = @TypeOf(v);
            return switch (@typeInfo(T)) {
                .Int => |info| {
                    if (info.bits <= 8) {
                        try self.writeU8(@as(u8, @intCast(v)));
                    } else if (info.bits <= 16) {
                        try self.writeU16(@as(u16, @intCast(v)));
                    } else if (info.bits <= 32) {
                        try self.writeU32(@as(u32, @intCast(v)));
                    } else {
                        @compileError("bigint suppot missing");
                    }
                },
                .ComptimeInt => {
                    return self.write(@as(std.math.IntFittingRange(v, v), v));
                },
                .Bool => {
                    self.writeBool(if (v) true else false);
                },
                .Optional => {
                    if (v) |inner| {
                        try self.writeBool(true);
                        try self.write(inner);
                    } else {
                        try self.writeBool(false);
                    }
                },
                .Array => {
                    // forward to `Pointer`
                    return self.write(&v);
                },
                .Vector => |info| {
                    const array: [info.len]info.child = v;
                    // forward to `Array`
                    return self.write(&array);
                },
                .Struct => |S| {
                    if (comptime std.meta.hasFn(T, "scaleEncode")) {
                        try v.scaleEncode(self);
                        return;
                    }

                    inline for (S.fields) |Field| {
                        // don't include void fields
                        if (Field.type == void) continue;

                        // TODO: S.is_tuple
                        try self.write(@field(v, Field.name));
                    }
                },
                .Union => {
                    if (comptime std.meta.hasFn(T, "scaleEncode")) {
                        try v.scaleEncode(self);
                        return;
                    }
                    @compileError("Unable to encode type '" ++ @typeName(T) ++ "'");
                },
                .Pointer => |ptr_info| switch (ptr_info.size) {
                    .One => switch (@typeInfo(ptr_info.child)) {
                        .Array => {
                            // Coerce `*[N]T` to `[]const T`.
                            const Slice = []const std.meta.Elem(ptr_info.child);
                            return self.write(@as(Slice, v));
                        },
                        else => {
                            return self.write(v.*);
                        },
                    },
                    .Many, .Slice => {
                        if (ptr_info.size == .Many and ptr_info.sentinel == null)
                            @compileError("unable to stringify type '" ++ @typeName(T) ++ "' without sentinel");
                        const slice = if (ptr_info.size == .Many) std.mem.span(v) else v;

                        if (slice.len > std.math.maxInt(u32)) {
                            unreachable; // TODO
                        }
                        try self.writeU32Compact(@intCast(slice.len));
                        for (slice) |x| {
                            try self.write(x);
                        }
                    },
                    else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
                },
                else => @compileError("Unable to encode type '" ++ @typeName(T) ++ "'"),
            };
        }

        pub fn writeU8(self: *Self, v: u8) Error!void {
            const array = [1]u8{v};
            return self.writeRaw(&array);
        }

        pub fn writeU8Compact(self: *Self, v: u8) Error!void {
            if (v < 64) {
                return self.writeU8(v << 2);
            } else {
                return self.writeU16((@as(u16, v) << 2) | 1);
            }
        }

        pub fn writeU16(self: *Self, v: u16) Error!void {
            const ordered: [2]u8 = to_bits(v);
            return self.writeRaw(&ordered);
        }

        pub fn writeU16Compact(self: *Self, v: u16) Error!void {
            if (v < 64) {
                return self.writeU8(@as(u8, @truncate(v)) << 2);
            } else if (v < 1 << 14) {
                return self.writeU16(v << 2 | 1);
            } else {
                return self.writeU32(@as(u32, v) << 2 | 2);
            }
        }

        pub fn writeU32(self: *Self, v: u32) Error!void {
            const ordered: [4]u8 = to_bits(v);
            return self.writeRaw(&ordered);
        }

        pub fn writeU32Compact(self: *Self, v: u32) Error!void {
            if (v < 64) {
                return self.writeU8(@as(u8, @truncate(v)) << 2);
            } else if (v < 1 << 14) {
                return self.writeU16(@as(u16, @truncate(v)) << 2 | 1);
            } else if (v < 1 << 30) {
                return self.writeU32(v << 2 | 2);
            } else {
                try self.writeU8(0b11);
                return self.writeU32(v);
            }
        }

        fn to_bits(v: anytype) [@sizeOf(@TypeOf(v))]u8 {
            return @bitCast(to_le(v));
        }

        fn to_le(v: anytype) @TypeOf(v) {
            return switch (native_endian) {
                .little => v,
                .big => @byteSwap(v),
            };
        }
    };
}
