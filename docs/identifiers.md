# Identifiers trong Zig — Hướng dẫn toàn diện

> Phiên bản xác minh: **Zig 0.17.0** (`zig version` → 0.17.0). Mọi ví dụ đã chạy qua
> `zig test` / `zig build-obj` để kiểm chứng; các thông báo lỗi bên dưới là **lỗi thật**
> do compiler 0.17.0 in ra.

---

## 1. Identifier là gì trong Zig?

Identifier (tên định danh) là cái tên bạn dùng để tham chiếu đến **biến, hằng, hàm,
kiểu, enum tag, label, capture, field, module…**. Quy tắc hình thái (lexical) do tokenizer
định nghĩa; các quy tắc "ngữ nghĩa" (shadowing, primitive names, keyword) do compiler
kiểm tra.

Quy tắc cơ bản (từ [Zig Language Reference — Identifiers](https://ziglang.org/documentation/master/#Identifiers)):

> Identifiers must start with an alphabetic character or underscore and may be followed
> by any number of alphanumeric characters or underscores. They must not overlap with any keywords.

Tức là: **ASCII** chữ cái (`a-z`, `A-Z`) hoặc `_` ở đầu → sau đó thêm chữ số tùy ý,
không được trùng keyword.

```zig
const foo = 1;
const _foo = 2;
const foo_ = 3;
const foo2 = 4;      // chữ số sau ký tự đầu là hợp lệ
const F123 = 5;
const snake_case_name = 6;
```

---

## 2. Những tên KHÔNG hợp lệ (đã chạy thật)

| Ví dụ | Lỗi compiler 0.17.0 (tóm tắt) |
|---|---|
| `const 1foo = 1;` | `expected 'an identifier', found 'a number literal'` |
| `foo-bar` (tách đôi) | bị parse thành **phép trừ** `foo - bar` → `use of undeclared identifier 'foo'` |
| `const foo bar = 1;` | `expected ';' after declaration` |
| `const màu_xanh = 1;` (Unicode trực tiếp) | `expected ';' after declaration` |
| `const if = 1;` (keyword) | `expected 'an identifier', found 'if'` |
| `const @foo = 1;` (`@` không phải builtin) | `expected 'an identifier', found 'a builtin function'` |
| `const u8 = 1;` (primitive type) | `name shadows primitive 'u8'` |
| `const true = 1;` (primitive value) | `name shadows primitive 'true'` |
| `var _ = 3;` | `'_' used as an identifier without @"_" syntax` |
| `const @"" = 1;` (tên rỗng) | `identifier cannot be empty` |

Hai điểm đáng chú ý:

- **Không có Unicode trong tên** trừ khi dùng `@"..."` (mục 3). Zig chỉ chấp nhận ASCII —
  khác hẳn Rust (cho phép Unicode trong identifier).
- **`_` không thể dùng làm tên khai báo** (`var _`, `const _`) — nhưng được dùng làm
  **discard** và **capture** (mục 8, 9).

---

## 3. String Identifier Syntax — `@"..."`

Khi tên không thỏa quy tắc trên (cần link với thư viện ngoài, hay muốn dùng keyword,
số, khoảng trắng, ký tự lạ chẳng hạn), dùng `@"..."`:

```zig
const @"identifier with spaces in it" = 0xff;
const @"1SmallStep4Man" = 112358;
const @"if" = 10;                  // dùng keyword làm tên
const @"latin-non-ascii-✓-emoji-🚀" = 7; // Unicode OK bên trong "..."

// Dùng lại thì cũng phải qua @"...":
const x = @"identifier with spaces in it"; // 255
```

Ứng dụng thực tế:

```zig
// 1) Enum tag có tên đặc biệt
const Color = enum {
    red,
    @"really red",
};
const c: Color = .@"really red";
@tagName(c); // "really red"

// 2) Field của struct có khoảng trắng
const Point = struct {
    x: i32,
    @"y value": i32,
};
const p = Point{ .x = 1, .@"y value" = 2 };

// 3) Hàm có tên là keyword / số
fn @"if"(a: i32) i32 { return a * 2; }
const v = @"if"(5);

// 4) FFI: tên C không phải identifier Zig (vd 'abs', 'fstat$INODE64', 'error')
extern "c" fn @"abs"(i: c_int) c_int;
extern "c" fn @"fstat$INODE64"() void;
const a = @"abs"(-42); // 42

// 5) Thoát khỏi tên primitive: @"u8", @"true", @"_"
const @"u8" = 9;
const @"_" = 1;
```

Lưu ý Zig 0.17: **`@""` (tên rỗng) là lỗi** (`identifier cannot be empty`), và để đặt tên
đúng nghĩa `_` cho một khai báo thì phải viết `@"_"`.

---

## 4. Tên bị CẤM: Keyword & tên primitive

### 4.1. Keyword

Zig có một tập **keyword** cố định; không dùng làm identifier (trừ qua `@"..."`). Danh
sách từ [Keyword Reference](https://ziglang.org/documentation/master/#Keyword-Reference)
(master; kiểm chứng một phần trên 0.17.0):

```
addrspace   align       allowzero   and         anyframe    anytype
asm         bitpack     break       callconv    catch       comptime
const       continue    defer       else        enum        errdefer
error       export      extern      fn          for         if
inline      linksection noalias     noinline    nosuspend   opaque
or          orelse      pub         resume      return      struct
suspend     switch      test        threadlocal try         union
unreachable var         volatile    while
```

Thay đổi theo thời gian (đã kiểm chứng trên 0.17.0):

- `async`, `await` — **đã bỏ** (0.17 bỏ hệ async). `const await = 1;` biên dịch OK.
- `usingnamespace` — **đã bỏ** từ lâu.
- `suspend` / `resume` / `nosuspend` / `anyframe` — vẫn còn là keyword.
- `addrspace`, `noalias`, `linksection`, `bitpack`, `callconv`, `threadlocal`… — keyword
  "chuyên dụng" ít gặp nhưng vẫn dành riêng.

### 4.2. Tên primitive type / value

Các tên kiểu nguyên thuỷ và giá trị nguyên thuỷ cũng **bị dành riêng** — khai báo trùng
sẽ báo `name shadows primitive 'X'` (và mách nên dùng `@"X"`):

```zig
// Lỗi: name shadows primitive 'u8' / 'void' / 'true'
const u8 = 1;    // cần @"u8"
const void = 1;  // cần @"void"
const true = 1;  // cần @"true"
```

Bao gồm toàn bộ primitive types (`void`, `bool`, `noreturn`, `type`, `anyerror`,
`anyopaque`, `comptime_int`, `comptime_float`, mọi `iN`/`uN`, `fN`, `c_*`) và primitive
values (`true`, `false`, `null`, `undefined`).

---

## 5. Không shadowing — điểm khác biệt lớn so với Rust/C

Zig **cấm "che" (shadow)** một identifier bằng một identifier trùng tên trong scope lồng
nhau. Quy tắc này áp dụng ở mọi cấp: local, global, **cả capture trong `for`/`if`/`switch`**
(các `|x|`), và tham số hàm.

```zig
const pi = 3.14;
fn f() void {
    {
        var pi: i32 = 1234; // ERROR: local variable shadows declaration of 'pi'
    }
}
```

```zig
const x = 1;
for (array) |x| { } // ERROR: capture 'x' shadows local constant from outer scope
```

Hệ quả tốt đẹp: khi đọc code Zig, một cái tên **luôn mang cùng một nghĩa** trong scope
nó được định nghĩa. Nếu hai scope **tách rời nhau** (sibling blocks), trùng tên là hợp lệ:

```zig
test "separate scopes" {
    { const pi = 3.14; _ = pi; }
    { var pi: bool = true; _ = &pi; } // OK — scope khác nhau
}
```

Các quy tắc liên quan:

- Khai báo **trùng tên cùng scope** → `redeclaration of local constant 'y'`.
- **Dùng trước khai báo trong hàm** → `use of undeclared identifier 'a'` (thứ tự trong
  thân hàm có ý nghĩa).
- Khác với C (cho shadow), Rust/Golang (cấm ở một số mức) — Zig cấm triệt để hơn cả Go.

---

## 6. Namespace & dotted identifiers (`Foo.bar`)

Mỗi `struct`/`enum`/`union`/`opaque` là một **namespace**; identifier bên trong được truy
cập bằng dấu chấm:

```zig
const Point = struct { x: i32, y: i32 };
const Suit = enum {
    clubs,
    pub fn name(self: Suit) []const u8 {
        return switch (self) { .clubs => "clubs", .spades => "spades" };
    }
};

const p = Point{ .x = 1, .y = 2 };
p.x;               // field
Suit.clubs;        // enum tag
s.name();          // method (fn trong namespace, gọi bằng dot)
std.debug.print;   // module con + fn
```

Field/method cùng tên với từ khoá hay tên kỳ lạ → dùng string: `Point.@"y value"`,
`Color.@"really red"`. (0.17 yêu cầu các field/nhãn **public** mới được `@hasDecl` — xem
tài liệu enum.)

---

## 7. Order-independence & lazily analyzed

Ở **namespace scope**, thứ tự khai báo **không quan trọng** — bạn dùng tên trước khi
nó được định nghĩa phía dưới, vì mọi khai báo namespace là order-independent và được
phân tích lười (lazily):

```zig
var y: i32 = add(10, x); // x chưa định nghĩa ở trên — vẫn OK
const x: i32 = 12;
fn add(a: i32, b: i32) i32 { return a + b; }
```

(Tại sao: file Zig là một struct; các decl là thành viên của struct, không phải lệnh tuần
tự. Trong **thân hàm** thì ngược lại — phải khai báo trước khi dùng.)

---

## 8. Labels (nhãn) — identifier đặc biệt

Labels là identifier đặt trước block/vòng lặp/switch, dùng với `break :label` /
`continue :label`:

```zig
// Label trên block: trả giá trị từ block
const x = blk: {
    y += 1;
    break :blk y; // "blk" có thể là bất kỳ tên nào
};

// Label trên while/for: break/continue vòng NGOÀI từ vòng trong
outer: while (true) {
    while (true) break :outer;
}
outer2: while (i < 100) : (i += 1) {
    while (true) continue :outer2;
}

// Label trên switch: break lấy giá trị; continue có operand sẽ chạy lại prong tương ứng
const r = switch (v) {
    .a => blk: { break :blk 10; },
    .b => 0,
};
```

Quy tắc tên label giống identifier thường (không được là keyword; `blk`, `outer`, `loop`
là những tên quen thuộc).

---

## 9. Capture identifiers `|x|`

Các cấu trúc có thể **bắt (capture)** giá trị vào identifier ở giữa dấu `| |`:

```zig
// for: bắt từng phần tử
for (0..5) |i| acc += i;

// while với optional: bắt payload (≈ unwrap), thoát khi null
var w: ?usize = 7;
while (w) |val| : (w = null) { /* val là usize */ }

// if với optional / error union: bắt payload
if (mayBeNull()) |n| { /* n */ } else { /* null */ }
const r = mayFail() catch |err| { /* err là lỗi */ };

// switch trên tagged union: bắt payload, hoặc payload + tag, hoặc *con trỏ* payload
switch (u) {
    .int      => |val|,           // payload theo giá trị
    .int      => |val, tag|,      // tag biết trước ở comptime trong prong này
    .int      => |*ptr| ptr.* += 1, // payload qua con trỏ để SỬA
}
```

Capture cũng là identifier bình thường: bị **cấm shadow** identifier ngoài, và dùng `_`
để bỏ qua giá trị: `for (array) |_| { … }`.

---

## 10. `_` — identifier "bỏ qua" (discard)

`_` là identifier đặc biệt chỉ dùng để **vứt bỏ giá trị**:

```zig
_ = compute();             // bỏ kết quả trả về
const t = .{ 1, 2, 3 };
_, kept, _ = t;            // bỏ phần tử 0 và 2 trong destructuring; kept = 2
for (arr) |_| {}           // bỏ phần tử
const s = struct{ a: i32, b: i32 }{ .a = 1, .b = 2 };
_ = s.b;                   // bỏ field chưa dùng
```

Ghi nhớ:

- `_ = expr;` là **biểu thức discard** — dùng nhiều lần không sao.
- **Không** được khai báo `var _ = 3;` hay `const _ = 3;` → lỗi `'_' used as an identifier
  without @"_" syntax`. Muốn có tên `_` thật sự thì `@"_"`.
- Có thể `@""`…không; `@""` là lỗi.

---

## 11. Builtin identifiers `@...`

Các hàm builtin của Zig có tên bắt đầu bằng `@`: `@import`, `@TypeOf`, `@as`,
`@compileError`, `@intCast`, `@field`, `@This`, `@hasDecl`, `@enumFromInt`/`@backingInt`,
`@tagName`, `@typeInfo`… Sau `@` **bắt buộc** là tên builtin hợp lệ hoặc chuỗi `"..."`;
`@foo` (không phải builtin) là lỗi `expected 'an identifier', found 'a builtin function'`.
Bạn **không định nghĩa lại** được builtin; nhưng có thể ẩn nó bằng tên **khác** (bình
thường), vì tên có `@` không nằm trong namespace bình thường.

---

## 12. Tên của `test`

```zig
test "tên là chuỗi nếu cần khoảng trắng" { … }

test addOne { … } // doctest: tên là identifier PHẢI trỏ tới một decl trong scope
```

Nếu tên là identifier (doctest), nó phải tham chiếu đến một khai báo có thật — đó cũng là
cách dùng identifier để gắn kết test với code.

---

## 13. Style Guide — đặt tên như cộng đồng Zig

Trích [Style Guide — Names](https://ziglang.org/documentation/master/#Names) (master):

| Loại | Quy ước | Ví dụ |
|---|---|---|
| `struct` 0 field (chỉ là namespace) | `snake_case` | `std`, `mem`, `Allocator`… (không, kiểu thì TitleCase) |
| type / type alias | `TitleCase` | `StructName`, `PrimitiveTypeAlias` |
| hàm trả `type` | `TitleCase` | `ListTemplateFunction` (generator) |
| hàm thường | `camelCase` | `functionName`, `addOne` |
| biến / hằng / field | `snake_case` | `global_var`, `const_name`, `field` |
| file: có field | `TitleCase.zig` | `TypeName.zig` |
| file: chỉ namespace | `snake_case.zig` | `dir_name/file_name.zig` |
| thư mục | `snake_case` | `dir_name` |

Chi tiết quan trọng: **acronym/initialism ngắn cũng phải theo quy ước** (không viết
`URLParser` kiểu acronym, mà `UrlParser`? — theo hướng dẫn, acronym vẫn chịu quy ước chữ
hoa thường). Nếu có convention đã tồn tại (như `ENOENT`) thì cứ theo convention đó.
Tránh collision với keyword bằng `@"..."` (không dùng underscore để phân biệt tên trùng
nhau — Style Guide khuyên không dùng `_` chỉ để né trùng tên).

---

## 14. Soát nhanh với Rust

| Vấn đề | Zig | Rust |
|---|---|---|
| Quy tắc ký tự | ASCII + `_`, không có ký tự lạ | ASCII + **Unicode** được phép |
| `@"..."` tên đặc biệt | Có (keyword, số, khoảng trắng…) | dùng **raw identifier** `r#type` (ít mạnh hơn) |
| Keyword | danh sách cố định | danh sách cố định |
| Tên primitive bị cấm | Có (`u8`, `true`…) | Có một phần (`type` tránh được) |
| Shadowing | **Cấm hoàn toàn** | Được phép (nested) |
| Labels | `blk:`, `outer:` + break/continue `:label` | `'label:` khác cú pháp |
| Dotted namespace | struct/enum/union/opaque | module/struct |
| Thứ tự khai báo | namespace order-independent; trong hàm thì không | namespace order-independent |
| `_` | discard (không khai báo được `var _`) | discard pattern |

---

## 15. Pitfalls thường gặp

1. `foo_bar - baz` vs `foo_bar-baz`: `-` luôn là trừ → tên giống nhau dễ nhầm; dùng `_`
   làm separator và cẩn thận khoảng trắng.
2. Đặt tên `u8`/`void`/`true` ở namespace sẽ "name shadows primitive" — đổi tên hoặc `@"u8"`.
3. Muốn dùng keyword làm tên → `@"..."`; đừng chỉ thêm `_` phía sau để né.
4. Capture `|x|` trùng tên biến ngoài → lỗi shadow; đổi tên biến hay capture.
5. Tên Unicode → bắt buộc `@"..."` (khác Rust).

---

## Tài liệu tham khảo

- [Zig Language Reference — Identifiers](https://ziglang.org/documentation/master/#Identifiers)
- [Zig Language Reference — String Identifier Syntax](https://ziglang.org/documentation/master/#String-Identifier-Syntax)
- [Zig Language Reference — Keyword Reference](https://ziglang.org/documentation/master/#Keyword-Reference)
- [Zig Language Reference — Shadowing](https://ziglang.org/documentation/master/#Shadowing)
- [Zig Language Reference — Labels (while/for/switch)](https://ziglang.org/documentation/master/#Labeled-while)
- [Zig Language Reference — Style Guide: Names](https://ziglang.org/documentation/master/#Names)
- [Zig 0.17.0 Release Notes](https://ziglang.org/download/0.17.0/release-notes.html) (async/await bị bỏ)
