// struct
const Point = struct {
     x : i32,
     y : i32,
};

//instance
const p: Point = .{
    .x = 3,
    .y = 4,
};

const Vec3 = struct {
    a : u32,
    b : u32,
    c : u32,

    pub fn init(x: u32, y: u32, z: u32) Vec3{
        return Vec3{
            .a = x,
            .b = y,
            .c = z,
        };
    }

    pub fn sum(self : Vec3, other: Vec3) u32 {
        return self.a * other.a + self.b * other.b + self.c * other.c;
    }

};

const std = @import("std");

pub fn main() !void {
    //std.debug.print("p : {}\n", .{p});
    //std.debug.print("x : {d}, y : {d}\n", .{p.x, p.y},);

    //zig dont have constructor. init is init not constructor
    //const vec : Vec3 = Vec3{
    //    .a = 1,
    //    .b = 2,
    //    .c = 3,
    //};

    //const other: Vec3 = Vec3 {
    //    .a = 1,
    //    .b = 2,
    //    .c = 3,
    //};

    const vec = Vec3.init(1,2,3);
    const other = Vec3.init(1,2,3);

    std.debug.print("sum : {}\n",.{vec.sum(other)});
}
