//! ENUM
const Type = enum {
    ok,
    not_ok,
};

const status = Type.ok;

const Value = enum(u2) {
    zero = 0,
    one = 1,
    two= 2,
    three= 3,
};

const Value3 = enum(u4){
    a,
    b = 5,
    c = 6,
    d,
    e = 15,
};

const Suit = enum{
    clubs,
    spades,
    diamonds,
    hearts,

    pub fn isClubs(self: Suit) bool {
       return self == Suit.clubs;
    }

};

const Foo = enum{
    string,
    number,
    none,
};


const std = @import("std");
pub fn main() !void {
    std.debug.print("value : {}\n", .{@backingInt(Value.one)});

    std.debug.print("value3 : {}\n", .{@backingInt(Value3.b)});

    const anwser = Suit.spades;

    std.debug.print("Suit is Clubs -> {}\n", .{anwser.isClubs()});

    const foo = Foo.none;
    const what_is_this = switch (foo) {
        Foo.string => "this is string",
        Foo.number => "this is number",
        Foo.none => "this is none",
    };
    std.debug.print("what is this -> {s}\n", .{what_is_this});

}
