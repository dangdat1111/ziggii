extern "c" fn @"abs"(i : c_int) c_int;
const std = @import("std");
pub fn main() void {
    // hợp lệ
        //const foo = 1;
        //const _foo = 2;
        //const foo_ = 3;
        //const F123 = 4;
        //const foo2 = 5;
        //const snake_case_name = 6;

    // không hợp lệ
        //const 1foo = 1;
        //const foo-bar = 1;
        //const màu_xanh =1;
        //const if = 1 ;
        //const @foo =  1;
        //const u8 =1 ;
        //const true = 1;
        //var _ = 3;
        //const @"" = 1;

    // String identifiers syntax - @"...."
        //const @"indentifier with spaces in it" = 0xff;
        //const @"1SmallStep4Man" = 112358;
        //const @"if" = 10;
        //const @"latin-non-ascii-emoji" = 7;
        //const x = @"indentifier with spaces in it";
    const Color = enum{
        red,
        @"really red",
    };
    const c: Color = .@"really red";
    //@tagName(c);
    std.debug.print("c tag name = {s}\n", .{@tagName(c)});

    const Point = struct{
        x : i32,
        @"y value" : i32,
    };
    const x : Point = .{
        .x = 1,
        .@"y value" = 2,
    };
    std.debug.print("point : {}\n", .{x});

    //FFI
    const a = @abs(-43);
    std.debug.print("zig ffi a = {}\n", .{a});

    // Zig không shadowing - khác với Rust
    const pi = 3.14;
    fn fa() void {
        { var pi  = 1234;}
    };

}
