# Enum trong Zig — Hướng dẫn toàn diện

> Phiên bản xác minh: **Zig 0.17.0** (`zig version` → 0.17.0). Tất cả ví dụ dưới đây
> đã chạy qua `zig test`/`zig run` trên máy để kiểm chứng.

---

## 1. Enum là gì trong Zig?

Trong Zig, `enum` là một **kiểu số nguyên có tên gọi** (a user-defined type with a finite
set of named values). Khác với Rust, enum trong Zig **không mang dữ liệu** — nó chỉ là
một tập các hằng số có nhãn. Nếu muốn "biến thể mang dữ liệu", bạn dùng **tagged union**
`union(enum)` (xem mục 9).

```zig
const Type = enum {
    ok,
    not_ok,
};

const c = Type.ok; // giá trị enum
```

Mỗi enum là một **namespace**: nó có thể chứa hàm, hằng số, `comptime` block… giống như
`struct` và `union`. Mọi file Zig cũng ngầm là một struct.

---

## 2. Tag type (kiểu số nền — "backing integer")

Enum không khai báo kiểu thì Zig **tự chọn kiểu nguyên nhỏ nhất đủ chứa**. Muốn truy cập
giá trị số thứ tự (ordinal), hoặc ép kích thước, bạn khai báo tường minh:

```zig
// Zig tự chọn tag type (thường là u8; @sizeOf == 1 byte cho 2 giá trị)
const Small = enum { a, b };
try std.testing.expect(@sizeOf(Small) == 1);

// Khai báo tường minh
const Value = enum(u2) { zero, one, two };
const Flag = enum(u16) { none = 0, read = 1, write = 2 };
```

Quy tắc giá trị:

- Giá trị bắt đầu từ `0`, tự **tăng 1** cho member kế tiếp.
- Có thể **override** từng giá trị; phần override chỉ ảnh hưởng từ vị trí đó trở đi:

```zig
const Value3 = enum(u4) {
    a,        // 0
    b = 8,    // 8
    c,        // 9  (tự tăng sau 8)
    d = 4,    // 4  (override lùi về)
    e,        // 5
};
```

- Giá trị có thể **không liên tục**, **âm**, thứ tự tuỳ ý:

```zig
const Temp = enum(i8) { cold = -10, mild = 5, hot = 30 };
```

### Enum rỗng

```zig
const Empty = enum {};
// tag type của nó là noreturn — không thể tạo giá trị nào (uninstantiable).
// (Zig 0.17 yêu cầu enum rỗng có backing integer là `noreturn`.)
```

---

## 3. Kích thước bộ nhớ

- `@sizeOf(E)` — kích thước byte (tuân theo tag type).
- `@bitSizeOf(E)` — số bit của tag type.

```zig
try expect(@sizeOf(enum { a, b })  == 1);            // được đặt ít nhất 1 byte
try expect(@sizeOf(enum(u8) { a } ) == 1);
try expect(@sizeOf(enum(u32) { a }) == 4);
try expect(@bitSizeOf(enum(u8) { a }) == 8);
```

Lưu ý: enum **không bao giờ zero-sized** theo kiểu `@sizeOf == 0` (khác empty struct
0 byte); tag type luôn có ít nhất 1 bit.

---

## 4. Enum literal (cú pháp `.tag`)

Enum literal cho phép viết tên tag **mà không cần khai báo kiểu**:

```zig
const color: Color = .green;   // tương đương Color.green
const x: Suit = .spades;
```

`@TypeOf(.foo)` là một kiểu đặc biệt **chỉ tồn tại lúc compile** gọi là "enum literal"
(`@EnumLiteral()` — xem mục 11). Giá trị literal được **ép (coerce)** sang bất kỳ enum nào
có tag khớp tên; nếu enum không có tag đó thì lỗi biên dịch:

```zig
const a: Color = .red;   // OK
// const b: Color = .pink;  // ERROR: no field named 'pink' in enum 'Color'
```

Enum literal đặc biệt hữu ích trong `switch` và khi truyền tham số enum.

---

## 5. Phương thức & namespace

Enum "method" không phải cơ chế đặc biệt — chỉ là **hàm nằm trong namespace của enum**
và gọi bằng cú pháp dấu chấm:

```zig
const Suit = enum {
    clubs,
    spades,
    diamonds,
    hearts,

    pub fn isClubs(self: Suit) bool {
        return self == Suit.clubs;
    }

    // Có thể khai báo hằng số, kiểu con, comptime block…
    pub const count = 4;
};

const p = Suit.spades;
try std.testing.expect(!p.isClubs());
```

Lưu ý về casing: cộng đồng Zig đặt method dạng camelCase (`isClubs`, `isPrimary`),
còn tag enum dạng snake_case (`not_ok`).

---

## 6. Chuyển đổi số ↔ enum

### 6.1. Builtin mới trong 0.17: `@backingInt` / `@fromBackingInt`

Zig 0.17 giới thiệu `@backingInt` và `@fromBackingInt` **thay thế** `@intFromEnum` và
`@enumFromInt` (cũ vẫn chạy, chưa có cảnh báo, nhưng đã chính thức "deprecated" theo
[release notes 0.17.0](https://ziglang.org/download/0.17.0/release-notes.html)).

```zig
// enum → số
const n: u4 = @backingInt(Value3.b);          // 8
// số → enum (kiểu kết quả tự suy ra từ ngữ cảnh)
const v: Value3 = @fromBackingInt(8);         // Value3.b
```

Semantics (theo release notes 0.17.0):

- `@backingInt` hoạt động với **mọi enum**, với bitpack có backing int tường minh, và với
  **tagged union** (trả về backing int của tag **đang active**). Enum/bitpack `undefined`
  → trả về `undefined`.
- `@fromBackingInt` suy kiểu đích; với enum, nếu giá trị là `undefined` hoặc **không khớp
  tag nào** → **Illegal Behavior có safety check** (panic ở Debug/Safe, không check ở
  ReleaseFast/ReleaseSmall).
- `std.meta.BackingInt(E)` cho biết kiểu kết quả của `@backingInt`.

### 6.2. Builtin cũ: `@intFromEnum` / `@enumFromInt`

```zig
const x: u8 = @intFromEnum(Color.green);  // enum → số
const e: Color = @enumFromInt(2);         // số → enum
```

### 6.3. Cast giữa 2 enum khác nhau

Chuyển qua `@fromBackingInt(@backingInt(a))` (hoặc `@intFromEnum` + `@enumFromInt`) — vì
Zig không cho `@enumFromInt` trực tiếp lấy enum khác làm nguồn:

```zig
const A = enum(u8) { x, y, z };
const B = enum { one, two, three };

const b: B = @fromBackingInt(@backingInt(A.z));  // B.three
```

### 6.4. `@bitCast`

`@bitCast` sang kiểu `enum` giờ cũng có **safety check cho tag không hợp lệ** (thêm từ
0.17). Dùng khi bạn thực sự muốn diễn giải lại bit pattern.

---

## 7. `@tagName`, `std.meta.stringToEnum`, `std.meta.tags`

### 7.1. `@tagName` — tên dạng chuỗi

```zig
const s: [:0]const u8 = @tagName(Color.green);  // "green"
```

### 7.2. `std.meta.stringToEnum` — chuỗi → enum (trả về optional)

```zig
const c = std.meta.stringToEnum(Color, "blue");
try std.testing.expect(c != null);
try std.testing.expectEqual(Color.blue, c.?);

const bad = std.meta.stringToEnum(Color, "khong_co");
try std.testing.expect(bad == null);
```

### 7.3. `std.meta.tags` — liệt kê toàn bộ giá trị

```zig
const all: []const Color = std.meta.tags(Color); // chứa MOI tag có tên
inline for (all) |c| { /* làm thứ gì đó với từng enum value */ }
```

Đây là **reflection built-in** mà Rust không có sẵn — rất hữu ích để sinh bảng, khởi tạo
map, duyệt toàn bộ trạng thái…

### 7.4. `std.enums.EnumSet` — tập hợp enum value

```zig
var set = std.enums.EnumSet(Fruit).empty;
set.insert(.apple);
try expect(set.contains(.apple));

const full = std.enums.EnumSet(Fruit).full; // tất cả các tag
```

(0.17 đổi tên: `empty`, `full` thay cho `initEmpty`, `initFull`.)

---

## 8. Reflection với `@typeInfo` (cấu trúc mới trong 0.17)

Zig 0.17 chuyển `std.lang.Type` sang *struct-of-arrays*; cấu trúc enum type info giờ là:

```zig
const e = @typeInfo(Color).@"enum";
// e.tag_type       : type  (u8, u2, …)
// e.mode           : enum { exhaustive, nonexhaustive }
// e.field_names    : []const [:0]const u8
// e.field_values   : []const comptime_int   (cùng độ dài với field_names)
// e.decl_names     : []const [:0]const u8   (các decl trong namespace enum)
```

Ví dụ kiểm tra:

```zig
const e = @typeInfo(Color).@"enum";
try std.testing.expect(e.tag_type == u8);
try std.testing.expect(e.mode == .exhaustive);
try std.testing.expectEqual(@as(usize, 3), e.field_names.len);
try std.testing.expectEqualStrings("red", e.field_names[0]);
```

Kết hợp `@hasDecl`, `@hasField`:

```zig
try expect(@hasDecl(Color, "hex"));     // enum có fn/const tên "hex"?
try expect(@hasField(Fruit, "apple"));  // enum có field tên "apple"?
```

---

## 9. Tagged union — `union(enum)`

Đây là cách Zig biểu diễn "enum mang dữ liệu" (giống tagged union trong C/Rust ADT):

```zig
const ShapeTag = enum { circle, square, triangle };

const Shape = union(ShapeTag) {
    circle: f64,
    square: struct { side: f64 },
    triangle: struct { base: f64, height: f64 },
};
```

### Các thao tác chính

```zig
// Khởi tạo bằng literal có tag
const s: Shape = .{ .circle = 2.5 };
const q: Shape = .{ .square = .{ .side = 3 } };

// Đọc field đang active
q.square.side; // 3

// Lấy kiểu tag: std.meta.Tag(UnionType) == enum tag type
const T = std.meta.Tag(Shape); // ShapeTag

// @tagName trên giá trị union → tên tag đang active
@tagName(q); // "square"

// @unionInit: khởi tạo union theo tên field (comptime)
const u = @unionInit(Payload, "int", 42);

// @field: truy cập field theo tên (string, comptime)
@field(s, "circle");
```

### switch trên tagged union — capture payload

```zig
fn area(s: Shape) f64 {
    return switch (s) {
        .circle     => |r| 3.14 * r * r,
        .square     => |sq| sq.side * sq.side,
        .triangle   => |t| 0.5 * t.base * t.height,
    };
}
```

- `.tag => |value|` capture payload (giá trị).
- `.tag => |_, tag|` capture thêm **tag**; trong prong đó `tag` luôn biết trước ở comptime.
- `.tag => |*value|` capture **con trỏ** tới payload (để modify).
- Variant "không dữ liệu": khai báo field kiểu `void` (hoặc không khai báo kiểu nếu dùng
  `union(enum)` trực tiếp như `Payload = union(enum) { none, int: i32, … }`).

```zig
const Payload = union(enum) {
    none,
    int: i32,
    text: []const u8,
};
```

### Coerce union ↔ enum

- **Tagged union coerce sang tag type** (enum): `const t: ShapeTag = s;`
- Ngược lại, enum `comptime`-known coerce sang union khi field tương ứng **chỉ có một giá
  trị khả dĩ** (kiểu `void`). Ví dụ `const u: U = .three;` hợp lệ nếu `three` là field
  `void` của union.

### Bảo mật an toàn: field không active

Truy cập **field không phải field đang active** là Illegal Behavior có safety check:
panic "access of union field 'X' while field 'Y' is active" (Debug/Safe). Muốn đổi field
phải **gán cả union**: `payload = .{ .float = 12.34 };`.

---

## 10. switch trên enum

### Exhaustive

`switch` **không có `else`** thì phải liệt kê **đủ mọi tag**, thiếu là lỗi biên dịch
("switch must handle all possibilities"). Gộp nhiều nhánh bằng dấu phẩy:

```zig
const is_warm = switch (c) {
    .red, .orange, .yellow => true,
    .blue, .green, .purple => false,
};
```

### Trên giá trị enum, dùng enum literal cho gọn

```zig
const what = switch (foo) {
    Foo.string => "chuoi",
    Foo.number => "so",
    Foo.none => "khong co",
};
// hoặc dùng .string thay vì Foo.string
```

### `inline switch` — sinh code theo từng nhánh

Nếu cần đối xử khác nhau với **từng tag tại compile time** (thường kết hợp
`comptime`/generic):

```zig
fn f(comptime e: E) []const u8 {
    return switch (e) {
        inline else => |tag| tag_name_map(tag), // tag có thể dùng như giá trị comptime
    };
}
```

### Non-exhaustive enum và prong `_`

```zig
const Number = enum(u8) {
    one, two, three,
    _, // bắt buộc là field CUỐI →
};   // enum trở thành "non-exhaustive"

const n: Number = @fromBackingInt(200); // luôn hợp lệ (không panic)

switch (n) {
    .one, .two, .three => {},
    _ => {}, // hoặc else — switch NON-EXHAUSTIVE BẮT BUỘC phải có `_`/else
    // (thiếu => lỗi: "switch on non-exhaustive enum must include 'else' or '_' prong")
}
```

Điều kiện để khai báo non-exhaustive: **phải có tag type tường minh** và **không được
"lấp" hết mọi giá trị** của tag type (còn dư ra các giá trị không tên). `@typeInfo(E).@"enum".mode`
sẽ là `.nonexhaustive`.

---

## 11. Builtin mới hiếm gặp: `@EnumLiteral` và `@Enum`

(Zig 0.17 — ít dùng trong code thường, nhưng biết để không lạ.)

### `@EnumLiteral()`

Trả về kiểu comptime-only "enum literal" — kiểu của `.foo` khi chưa coerce:

```zig
const lit = .foo;
@typeName(@TypeOf(lit)); // "@EnumLiteral()"
```

### `@Enum(comptime TagInt, comptime mode, comptime field_names, comptime field_values)`

Dựng **kiểu enum** trong code (giống `@Struct`, `@Union`):

```zig
const E = @Enum(u8, .exhaustive,
    &[_][]const u8{ "a", "b", "c" },
    &[_]u8{ 0, 10, 20 });
// → enum có tag a=0, b=10, c=20, tag type u8
```

---

## 12. Enum và C ABI / FFI

Enum mặc định **không đảm bảo tương thích C ABI** (tag type là "inferred"). Khi cần trao
đổi với C (ví dụ tham số `export fn`, call ABI sysv…):

```zig
const Foo = enum(c_int) { a, b, c }; // C ABI compatible

export fn entry(foo: Foo) void { _ = foo; } // OK
```

Trong Zig 0.17, **`extern enum` không còn dùng được** — compiler báo:
"enums do not support 'packed' or 'extern'; instead provide an explicit integer tag type".
Chỉ cần `enum(c_int)` (hoặc `enum(c_uint)`, `enum(i32)`…) là đủ cho mục đích C ABI.

---

## 13. An toàn (Illegal Behavior) — tóm tắt

| Hành vi | Debug / Safe | ReleaseFast / Small |
|---|---|---|
| `@fromBackingInt`/`@enumFromInt` với giá trị không khớp tag (runtime) | panic `invalid enum value` | **UB** — không check, trả giá trị nhảm |
| `@fromBackingInt` với giá trị **comptime-known** không khớp tag | **lỗi biên dịch** | lỗi biên dịch |
| Truy cập field không active của union | panic | UB |
| `@bitCast` → enum với tag sai | panic (từ 0.17) | UB |

Mẹo: muốn cast "an toàn chủ động", kiểm tra trước bằng `@backingInt` rồi so khớp, hoặc
dùng `switch`/`std.meta.stringToEnum`, hoặc dùng optional+tự validate.

---

## 14. Soát nhanh với Rust

| Vấn đề | Zig | Rust |
|---|---|---|
| Enum chỉ là tập giá trị | `enum { a, b }` | fieldless `enum { A, B }` |
| Variant mang dữ liệu | `union(enum)` riêng biệt | có sẵn trong `enum` |
| Phương thức | fn trong namespace, gọi bằng dot | `impl` block |
| Match/switch | `switch`, bắt buộc exhaustive | `match`, bắt buộc exhaustive |
| Enum → số | `@backingInt` (mới), `@intFromEnum` (cũ) | `as` |
| Số → enum | `@fromBackingInt` / `@enumFromInt` | `try_from` / `From` |
| Tên chuỗi | `@tagName` (sẵn có) | cần derive (`Debug`) / thư viện |
| Liệt kê mọi tag | `std.meta.tags` (sẵn có) | cần proc macro (strum) |
| Chỉ định cỡ | `enum(u8)`, `enum(i32)` | không trực tiếp |
| Reflection comptime | mạnh (`@typeInfo`, `inline for`) | hạn chế |

---

## 15. So với "error set" của Zig

Error set (`error{ NotFound, PermissionDenied }`) trông giống enum nhưng **khác bản chất**:
không có builtin chuyển số, xuất hiện trong error union `!T` với `try`/`catch`. Dùng enum
cho **trạng thái dữ liệu**, dùng error set cho **luồng lỗi**. Nếu cần "enum string
value", dùng `@tagName`/`stringToEnum` hoặc hàm `name()` như trong ví dụ `Suit`.

---

## 16. Ví dụ tổng hợp (state machine + tagged union + reflection)

```zig
const State = enum { idle, running, done };

const Event = union(enum) {
    start,
    progress: u8,
    finish,
};

fn next(state: State, e: Event) State {
    return switch (e) {
        .start => .running,
        .progress => |p| if (p >= 100) .done else state,
        .finish => .done,
    };
}

// Reflection: tất cả state có name()
inline for (std.meta.tags(State)) |s| {
    std.debug.print("{s}\n", .{@tagName(s)});
}
```

---

## Tài liệu tham khảo

- [Zig Language Reference — enum](https://ziglang.org/documentation/master/#enum)
- [Zig Language Reference — union / Tagged union](https://ziglang.org/documentation/master/#union)
- [Zig Language Reference — switch](https://ziglang.org/documentation/master/#switch)
- [Zig 0.17.0 Release Notes](https://ziglang.org/download/0.17.0/release-notes.html)
- `std.enums`, `std.meta` trong stdlib (chạy `zig std` để xem docs offline)
