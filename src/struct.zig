const Point = struct {
    x : f32,
    y : f32,
};

// create instance
const p : Point = .{
    .x =0.12,
    .y = 0.13,
};

const Vec3 = struct {
    a : i32,
    b : i32,
    c : i32,

    pub fn init(x : i32, y : i32, z : i32) Vec3 {
        return Vec3{
            .a = x,
            .b = y,
            .c = z,
        };
    }

    pub fn sum(self : Vec3, other: Vec3) i32{
       return self.a * other.a + self.b * other.b + self.c * other.c;
    }
};


const std = @import("std");
pub fn main() !void {
    std.debug.print("p : {}\n", .{p});

    const vec1 = Vec3.init(1,2,3);
    const vec2 = Vec3.init(1,2,3);

    const sum_vec = vec1.sum(vec2);
    std.debug.print("sum vec : {}\n", .{sum_vec});


}
