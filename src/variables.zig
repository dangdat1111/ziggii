const std = @import("std");

pub fn main() !void {
    // bắt buộc phải có giá trị khởi tạo
    //var x : i32; -> expected '=', but found ';'
    //_ = &x;

    // -> nếu muốn gán giá trị từ biến rỗng -> dùng undefined
    //Mọi biến `var`/`const` **đều phải có giá trị khởi tạo** tại điểm khai báo. Nếu thực sự muốn gán giá
    //trị sau (ví dụ đổ dữ liệu vào buffer), dùng `= undefined`:
    var x : i32 = undefined;
    x = 10;
    std.debug.print("x = {}\n", .{x});

    const arr : [2]u8 = .{1,2};
    //arr = .{5,6};
    //std.debug.print("arr  : {any}\n", .{arr});

    //const p: *[2]u8 = &arr;
    //std.debug.print("p  : {any}\n", .{p});

    const p: *const [2]u8 = &arr;
    std.debug.print("p  : {any}\n", .{p});

    // var là 1 biến runtime có thể đổi giá trị, nhưng khi khai báo var  a = 1
    // -> zig sẽ suy luận là comptime_int -> comptime_int là immutable ==> lỗi
    // nhưng khi gán kiểu dữ liệu var a : u32 = 1
    // -> lỗi vì trong toàn bộ scope biến a không bị thay đổi
    // fix : thay đổi giá trị của a
    // tóm lại : var là 1 biến runtime - chỉ xảy ra ở runtime mà thôi !!!!
    var a:u32 = 1;
    a = a + 1;
    std.debug.print("a : {}\n", .{a});

}

