const std = @import("std");

pub fn addOne (num : i32) i32 {
    return num + 1;
}
test addOne {
    try std.testing.expect(addOne(41) == 42);
    try std.testing.expectEqual(42, addOne(41));
}

test "skip test" {
    return error.SkipZigTest;
}
test "expectEqual demo" {
    const expected: i32 = 42;
    const actual = 42;

    // The first argument to `expectEqual` is the known, expected, result.
    // The second argument is the result of some expression.
    // The actual's type is casted to the type of expected.
    try std.testing.expectEqual(expected, actual);
}

test "expectError demo" {
    const expected_error = error.DemoError;
    const actual_error_union: anyerror!void = error.DemoError;

    // `expectError` will fail when the actual error is different than
    // the expected error.
    try std.testing.expectError(expected_error, actual_error_union);
}
