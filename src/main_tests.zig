const std = @import("std");
const assert = std.debug.assert;
const eql = std.mem.eql;
const expect = std.testing.expect;
const testing = std.testing;
const test_allocator = std.testing.allocator;

const scaleWriter = @import("main.zig").scaleWriter;
const Compact = @import("main.zig").Compact;

// `ScaleWriter` basic works.
test "basic writing works" {
    var list = std.ArrayList(u8).init(test_allocator);
    defer list.deinit();
    var w = scaleWriter(list.writer());

    try w.write(123);
    try w.write(21);
    try w.write(0x1234);
    try w.write(0x12345678);
    try w.write(@as(?u8, 0x12));
    try w.write(@as(?u8, null));
    try w.write(@as(?u32, null));
    try w.write(@as(?u32, 0x12345678));

    try expect(eql(u8, list.items, &[_]u8{ 123, 21, 0x34, 0x12, 0x78, 0x56, 0x34, 0x12, 0x01, 0x12, 0x00, 0x00, 0x01, 0x78, 0x56, 0x34, 0x12 }));
}

// Test the examples from the Polkadot Wiki.
test "conformance" {
    try test_encode(@as(i8, 69), [_]u8{0x45});
    try test_encode(@as(u16, 42), [_]u8{ 0x2a, 0x00 });
    try test_encode(@as(u32, 16777215), [_]u8{ 0xff, 0xff, 0xff, 0x00 });
}

// Compact encoding works.
test "compact" {
    try test_encode(Compact{ .U8 = 0 }, [_]u8{0x00});
    try test_encode(Compact{ .U16 = 0 }, [_]u8{0x00});
    try test_encode(Compact{ .U32 = 0 }, [_]u8{0x00});

    try test_encode(Compact{ .U8 = 1 }, [_]u8{0x04});
    try test_encode(Compact{ .U16 = 1 }, [_]u8{0x04});
    try test_encode(Compact{ .U32 = 1 }, [_]u8{0x04});

    try test_encode(Compact{ .U8 = 42 }, [_]u8{0xa8});
    try test_encode(Compact{ .U16 = 42 }, [_]u8{0xa8});
    try test_encode(Compact{ .U32 = 42 }, [_]u8{0xa8});

    try test_encode(Compact{ .U8 = 69 }, [_]u8{ 0x15, 0x01 });
    try test_encode(Compact{ .U16 = 69 }, [_]u8{ 0x15, 0x01 });
    try test_encode(Compact{ .U32 = 69 }, [_]u8{ 0x15, 0x01 });

    try test_encode(Compact{ .U16 = 65535 }, [_]u8{ 0xfe, 0xff, 0x03, 0x00 });
    try test_encode(Compact{ .U32 = 65535 }, [_]u8{ 0xfe, 0xff, 0x03, 0x00 });
}

test "compact::try_from" {
    try expect(std.meta.eql(try Compact.try_from(@as(u8, 0)), Compact{ .U8 = 0 }));
}

test "slice::u8" {
    try test_encode([_]u8{}, [_]u8{0x00});
    try test_encode([_]u8{0x00}, [_]u8{ 0x04, 0x00 });
    try test_encode([_]u8{ 0x10, 0x02 }, [_]u8{ 0x08, 0x10, 0x02 });
}

test "slice::u16" {
    try test_encode([_]u16{}, [_]u8{0x00});
    try test_encode([_]u16{0x00}, [_]u8{ 0x04, 0x00, 0x00 });
    try test_encode([_]u16{0x1234}, [_]u8{ 0x04, 0x34, 0x12 });

    // conformance
    try test_encode([_]u16{ 4, 8, 15, 16, 23, 42 }, [_]u8{ 0x18, 0x04, 0x00, 0x08, 0x00, 0x0f, 0x00, 0x10, 0x00, 0x17, 0x00, 0x2a, 0x00 });
}

test "struct" {
    const Struct = struct {
        a: u8,
        b: u16,
        c: u32,
    };

    try test_encode(Struct{ .a = 1, .b = 2, .c = 3 }, [_]u8{ 0x01, 0x02, 0x00, 0x03, 0x00, 0x00, 0x00 });

    const Struct2 = struct {
        a: ?u8,
        b: ??u8 = null,
    };

    try test_encode(Struct2{ .a = null }, [_]u8{ 0x00, 0x00 });
    try test_encode(Struct2{ .a = 0 }, [_]u8{ 0x01, 0x00, 0x00 });
    try test_encode(Struct2{ .a = 1 }, [_]u8{ 0x01, 0x01, 0x00 });
    try test_encode(Struct2{ .a = null, .b = 1 }, [_]u8{ 0x00, 0x01, 0x01, 0x01 });
}

test "struct::custom" {
    const Struct = struct {
        a: u8,

        pub fn scaleEncode(self: *const @This(), writer: anytype) !void {
            try writer.write(123);
            try writer.write(self.a);
            try writer.write(32);
        }
    };

    try test_encode(Struct{ .a = 1 }, [_]u8{ 123, 0x01, 32 });
}

test "slice::compact::u16" {
    try test_encode([_]Compact{Compact{ .U16 = 0 }}, [_]u8{ 0x04, 0x00 });
    try test_encode([_]Compact{ Compact{ .U16 = 1 }, Compact{ .U16 = 2 } }, [_]u8{ 0x08, 0x04, 0x08 });
}

fn test_encode(input: anytype, output: anytype) anyerror!void {
    var list = std.ArrayList(u8).init(test_allocator);
    defer list.deinit();
    var w = scaleWriter(list.writer());
    try w.write(input);

    try expect(eql(u8, list.items, &output));
}
