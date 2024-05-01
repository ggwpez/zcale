# Run Tests

```bash
zig test src/main_tests.zig
```

## Example

See [tests](./src/main_tests.zig) for examples.

```zig
const std = @import("std");
const test_allocator = std.testing.allocator;

var buffer = std.ArrayList(u8).init(test_allocator);
defer list.deinit();
var scale = scaleWriter(list.writer());

// Encode a specific type:
scale.writeU32(0x12345678);
// Encode an inferred type:
scale.write(0x12345678);

// Encode a compact integer:
scale.writeCompactU32(0x12345678);

// Encode a struct:
const Struct = struct {
	a: u8,
	b: u16,
	c: u32,
};

var s = Struct{ .a = 1, .b = 2, .c = 3 };
scale.write(s);

// Also works for slices, options, enums etc:
scale.write([_]u8{1, 2, 3, 4});
scale.write(@as(?u32, null));
```

Custom encoder for a struct (or union):

```zig
const Struct = struct {
	a: u8,

	pub fn scaleEncode(self: *const @This(), writer: anytype) !void {
		try writer.write(123);
		try writer.write(self.a);
		try writer.write(32);
	}
};

scale.write(Struct{ .a = 1 });
```
