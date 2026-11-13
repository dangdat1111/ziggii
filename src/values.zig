const std = @import("std");
pub fn main() !void {
    // primitive value (kiểu dữ liệu nguyên thuỷ )
    // (`u8`, `i32`, `f64`, `bool`, `usize`…).
        //const flag : bool = true;
        //var maybe: ?i32 = null; // optional type
        //var uninit : i32 = undefined; // chưa có giá trị

    // kiểu của literal : "comptime_int / comptime_float"
    // literal không có kiểu cố định
    // chỉ tồn tại lúc compile
        //const x = 1234; //comptime_int
        //const a : i16 = 1234; // ép sang i16
        //const f = 5.5; // comptime_float
        //const g : f32 = 5.5; // ép sang f32
        //const ok : u8 = 255;
        //const bad : u8 = 300;

    // String literals & unicode code point literals
    // String : *const [N:0]u8
        //const bytes = "hello";
        //@TypeOf(bytes) == *const [5:0]u8;

    //array
    const a : [5]u8 = [5]u8{1,2,3,4,5};
    std.debug.print("a : {any}\n", .{a});

    // Để Zig tự đếm số phần tử bằng dấu gạch dưới `_` (rất phổ biến)
    const b = [_]u32{1,2,3,34,5,56,12};
    std.debug.print("len of b : {}\n", .{b.len});

    // Nối hai mảng tại thời điểm biên dịch bằng toán tử `++`
    const c = [_]i32{1,2} ++ [_]i32{3,4};
    std.debug.print("c : {any}\n", .{c});

}
