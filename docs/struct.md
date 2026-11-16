# Struct trong Zig — Hướng dẫn toàn diện

> Phiên bản xác minh: **Zig 0.17.0** (`zig version`), đối chiếu [Zig Language Reference 0.17.1 — struct](https://ziglang.org/documentation/0.17.1/#struct).
> Mọi ví dụ dưới đây đã chạy qua `zig test`/`zig build-obj` trên máy (bộ test 13/13 + 4 probe lỗi).

---

## Mục lục

1. [Struct là gì? Namespace + data](#1-struct-là-gì-namespace--data)
2. [Khởi tạo: struct literal `.{...}`](#2-khởi-tạo-struct-literal-)
3. [Layout bộ nhớ: field order do compiler quyết định](#3-layout-bộ-nhớ-field-order-do-compiler-quyết-định)
4. [`@fieldParentPtr` — từ field ptr suy base ptr](#4-fieldparentptr--từ-field-ptr-suy-base-ptr)
5. [Default field values (và cạm bẫy của nó)](#5-default-field-values-và-cạm-bẫy-của-nó)
6. [`extern struct` — layout C ABI](#6-extern-struct--layout-c-abi)
7. [`packed struct` — layout theo bit](#7-packed-struct--layout-theo-bit)
   - [7.1 Backing integer & `@backingInt`/`@fromBackingInt`](#71-backing-integer--backingintfrombackingint)
   - [7.2 Field < 1 byte: pointer không cùng địa chỉ, có bit offset](#72-field--1-byte-pointer-không-cùng-địa-chỉ-có-bit-offset)
   - [7.3 Alignment của packed struct](#73-alignment-của-packed-struct)
8. [Alignment của field (`align(n)`)](#8-alignment-của-field-alignn)
9. [Struct naming — tên tự suy ra](#9-struct-naming--tên-tự-suy-ra)
10. [Anonymous struct literal & Tuples](#10-anonymous-struct-literal--tuples)
11. [Struct generic — hàm trả về `type`](#11-struct-generic--hàm-trả-về-type)
12. [Lỗi thường gặp (probe thật)](#12-lỗi-thường-gặp-probe-thật)
13. [Nguồn & liên kết](#13-nguồn--liên-kết)

---

## 1. Struct là gì? Namespace + data

Struct trong Zig vừa là **kiểu dữ liệu tổng hợp** vừa là một **namespace** (hộp khai báo): chứa field,
hàm, hằng số, `comptime` block, thậm chí cả `var` (biến toàn cục mang namespace).

```zig
const Point = struct { x: f32, y: f32 };

const Vec3 = struct {
    x: f32, y: f32, z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return Vec3{ .x = x, .y = y, .z = z };
    }
    pub fn dot(self: Vec3, other: Vec3) f32 {
        return self.x * other.x + self.y * other.y + self.z * other.z;
    }
};

// Method chỉ là "hàm gọi bằng dấu chấm": có thể gọi cả cách thường
const r = Vec3.dot(v1, v2);
```

Langref nhấn mạnh: *"Other than being available to call with dot syntax, struct methods are **not
special**."* — `self` chỉ là tham số đầu tiên, không có `this`/receiver đặc biệt (đã test).

Struct có thể rỗng (size 0), mang hằng số:

```zig
const Empty = struct { pub const PI = 3.14; };
try expectEqual(0, @sizeOf(Empty));
```

---

## 2. Khởi tạo: struct literal `.{...}`

- Cú pháp tường minh: `Point{ .x = 0.1, .y = 0.2 }`.
- Cú pháp **anonymous struct literal**: khi result type đã biết từ ngữ cảnh, có thể bỏ tên type:
  `const p: Point = .{ .x = 1, .y = 2 };`. Langref: *"the struct literal will directly instantiate
  the **result location**, with **no copy**"* (liên quan [`variables.md`](variables.md) mục 7).
- Khi **thiếu field** không có default → compile error:
  ```
  error: missing struct field: b
  ```
- Khi đọc field không tồn tại:
  ```
  error: no field named 'z' in struct '...'
  ```

---

## 3. Layout bộ nhớ: field order do compiler quyết định

Langref nói rất rõ:

> *"Zig gives no guarantees about the order of fields and the size of the struct but the fields are
> guaranteed to be **ABI-aligned**. … **Struct field order is determined by the compiler**."*

Nghĩa là với `struct` thường, compiler **được phép sắp lại field** để giảm padding. Kết quả đo thật
trên Zig 0.17.0 (test `layout: regular vs extern struct`):

```
regular: size=8 offset a=4 b=0 c=5   ← compiler xếp lại (a vào padding b)!
extern : size=12 offset a=0 b=4 c=8  ← thứ tự C ABI cố định
```

Tức là struct `{ a: u8, b: u32, c: u8 }` chỉ tốn **8 byte** chứ không phải 12 — compiler đặt `b` đầu
tiên rồi nhét `a`, `c` vào phần padding. Vì vậy:

- Muốn **layout khớp C ABI** (qua biên giới `extern c`/mạng/đĩa) → dùng `extern struct`.
- Muốn **nén theo bit** → dùng `packed struct`.
- Muốn đảm bảo thứ tự tay → tự sắp field và kiểm tra bằng `@sizeOf`/`@offsetOf`.

---

## 4. `@fieldParentPtr` — từ field ptr suy base ptr

Ngược từ con trỏ field → con trỏ struct gốc. **Cú pháp thay đổi trong 0.17**: truyền *tên field dạng
chuỗi* trước (`@fieldParentPtr("x", x)`), thay vì cú pháp kiểu-trước của các bản cũ:

```zig
const Point = struct { x: f32, y: f32 };

fn setYBasedOnX(x: *f32, y: f32) void {
    const p: *Point = @fieldParentPtr("x", x);
    p.y = y;
}

var point = Point{ .x = 0.1, .y = 0.2 };
setYBasedOnX(&point.x, 0.9); // point.y = 0.9 ✓ (đã test)
```

Hữu ích khi bạn có con trỏ tới field (vd từ bộ nhớ map) và cần tìm object chứa nó.

---

## 5. Default field values (và cạm bẫy của nó)

Mỗi field có thể khai báo giá trị mặc định — **biểu thức thực thi lúc comptime** — cho phép bỏ qua
field đó khi khởi tạo:

```zig
const Foo = struct {
    a: i32 = 1234,
    b: i32,
};
const x: Foo = .{ .b = 5 }; // a = 1234
```

> ⚠️ **Cạm bẫy (langref nêu rõ):** default values chỉ nên dùng khi *không thể vi phạm bất biến dữ
> liệu* nếu bỏ field. Langref dẫn ví dụ `Threshold{ .minimum = 0.25, .maximum = 0.75 }` rồi khởi tạo
> `.maximum = 0.20` → vi phạm `maximum >= minimum` → **illegal behavior lúc runtime**. Giải pháp: bỏ
> default, cung cấp hằng `const default: Threshold = .{...}` hoặc dùng một init-method nhận giá trị
> runtime.

---

## 6. `extern struct` — layout C ABI

> *"An `extern struct` has in-memory layout **matching the C ABI** for the target. If well-defined
> in-memory layout is not required, `struct` is a better choice because it places fewer restrictions
> on the compiler."*

- Thứ tự field đúng như khai báo, không padding đổi chỗ (đã test ở mục 3).
- Dùng khi giao tiếp với C, đọc/ghi binary format, hoặc cần layout tái tạo được.
- (Tương ứng: `extern union`, `extern enum` — trong 0.17 `extern enum` đã bị loại; dùng `enum(c_int)`.)

---

## 7. `packed struct` — layout theo bit

> *"All packed structs have a **backing integer**, which is implicitly determined by the total bit
> count of fields, or explicitly specified. Packed structs have well-defined memory layout - exactly
> the same ABI as their backing integer."*

Packed struct "đọc" các field như một chuỗi bit trên **backing integer**, từ bit thấp tới cao. Loại
field hợp lệ: integer (đúng bề rộng bit), `bool` (1 bit), `enum` (bit width tag type), packed union,
packed struct.

```zig
const Full = packed struct { number: u16 };                    // backing: u16 (2 byte)
const Divided = packed struct { half1: u8, quarter3: u4, quarter4: u4 }; // cũng 2 byte

test "packed struct @bitCast (runtime and comptime)" {
    const full = Full{ .number = 0x1234 };
    const divided: Divided = @bitCast(full);
    // divided.half1 = 0x34, quarter3 = 0x2, quarter4 = 0x1 (đã test)
    const ordered: [2]u8 = @bitCast(full);
    // ordered[0] = 0x34, ordered[1] = 0x12
}
```

Packed struct tham gia được `@bitCast`/`@ptrCast` để reinterpret vùng nhớ — **ngay cả ở comptime**.

### 7.1 Backing integer & `@backingInt`/`@fromBackingInt`

Backing integer có thể tự suy (mặc định **unsigned**) hoặc khai báo tường minh `packed struct(u8)` —
bề rộng phải **khớp chính xác** tổng bit các field, nếu không:

```
error: backing integer bit width does not match total bit width of fields
note: backing integer 'u32' has bit width '32'
note: struct fields have total bit width '24'
```

Đổi qua lại giữa packed struct và số nguyên bằng `@backingInt`/`@fromBackingInt` (0.17 — thay thế
`@intFromEnum`-style):

```zig
const PackedStruct = packed struct(u8) { lo: u4, hi: u4 };
const original: PackedStruct = .{ .lo = 0b1100, .hi = 0b0101 };
const backing_int = @backingInt(original);        // 0b0101_1100, type u8 (đã test)
const reconstructed: PackedStruct = @fromBackingInt(backing_int);
try expectEqual(original, reconstructed);
```

### 7.2 Field < 1 byte: pointer không cùng địa chỉ, có bit offset

Zig **cho phép lấy địa chỉ** field không nằm ở byte boundary:

```zig
const BitField = packed struct { a: u3, b: u3, c: u2 };
const ptr = &bit_field.b; // OK
try expectEqual(2, ptr.*);
```

Nhưng con trỏ đó có **thuộc tính bit offset**, không thể truyền vào nơi cần con trỏ ABI-aligned:

```
error: expected type '*const u3', found '*align(1:3:1) u3'
note: pointer host size '1' cannot cast into pointer host size '0'
note: pointer bit offset '3' cannot cast into pointer bit offset '0'
```

Các field con-bit **chia sẻ cùng địa chỉ** (chỉ khác nhau bit offset):

```zig
@intFromPtr(&bit_field.a) == @intFromPtr(&bit_field.b) == @intFromPtr(&bit_field.c)  // true
@bitOffsetOf(BitField, "b") == 3   // vị trí bit
@offsetOf(BitField, "b") == 0      // vị trí byte
```

⚠️ Langref cảnh báo: field access là *shorthand cho bitshift trên backing integer* và **không phải
atomic** — đừng gán từng field qua con trỏ `volatile` trong MMIO; hãy dựng giá trị hoàn chỉnh rồi ghi
một lần (`gpio.* = new_states;`).

### 7.3 Alignment của packed struct

Packed struct có alignment **bằng backing integer**; có thể *over-align* khi cần:

```zig
const S = packed struct { a: u32, b: u32 };
var foo: S align(4) = .{ .a = 1, .b = 2 };
const ptr: *align(4) S = &foo;
```

So sánh packed struct = so sánh backing integer (chỉ `==`/`!=`):

```zig
const x: S = .{ .a = 1, .b = 2 };
const y: S = .{ .b = 2, .a = 1 };
try expectEqual(x, y); // true — cùng backing integer
```

---

## 8. Alignment của field (`align(n)`)

Field có thể được yêu cầu alignment riêng:

```zig
const S = struct {
    a: u32 align(2),
    b: u32 align(64),
};
var foo = S{ .a = 1, .b = 2 };
try expectEqual(64, @alignOf(S));          // S lấy alignment lớn nhất
try expectEqual(*align(2) u32, @TypeOf(&foo.a));
try expectEqual(*align(64) u32, @TypeOf(&foo.b));
```

Alignment của struct = max(alignment các field) (đã test: 64). Chi tiết alignment & cache line -> xem
[`memory_model.md`](memory_model.md#44-alignment).

---

## 9. Struct naming — tên tự suy ra

Mọi struct đều **anonymous**; tên chỉ để đẹp khi lỗi/debug, theo quy tắc langref:

1. Trong khai báo biến → tên theo biến đó (`struct_name.main.Foo`).
2. Trong return → tên theo hàm + tham số serialize (`List(i32)`).
3. Ngoài ra → `(file.func__struct_ID)`.
4. Trong struct khác → cha.con.

Đo thật:

```
named after variable: s1_struct.test.struct naming rules.Local
anonymous literal   : s1_struct.test.struct naming rules__struct_1019
```

---

## 10. Anonymous struct literal & Tuples

- **Anonymous struct literal** `.{}` khi không cần tên type (đã trình ở mục 2).
- **Tuples**: anonymous struct với field được đặt tên **số 0,1,2…** — không dùng được `.` trừ khi bọc
  `@""`. Có `.len`, index (chỉ khi index comptime-known), nối bằng `++`, duyệt bằng `inline for`:

```zig
const values = .{ @as(u32, 1234), @as(f64, 12.34), true, "hi" } ++ .{ false, false };
try expectEqual(1234, values[0]);
try expectEqual(false, values[4]);
try expectEqual(6, values.len);
try expectEqual('h', values.@"3"[0]); // "hi"[0]
```

- **Destructuring tuple** để trả nhiều giá trị từ một block/hàm (xem [`values.md`](values.md)):

```zig
const div, const mod = divmod(10, 3); // div=3, mod=1
```

---

## 11. Struct generic — hàm trả về `type`

```zig
fn LinkedList(comptime T: type) type {
    return struct {
        pub const Node = struct {
            prev: ?*Node,
            next: ?*Node,
            data: T,
        };
        first: ?*Node,
        last: ?*Node,
        len: usize,
    };
}
const ListOfInts = LinkedList(i32); // MỘT kiểu duy nhất, memoized
```

- `LinkedList(i32) == LinkedList(i32)` (đã test) — hàm comptime được memoize.
- Struct **tự tham chiếu** qua con trỏ: `?*Node` — size biết trước nên OK (order-independent).
- Đầy đủ về generics xem [`comptime.md`](comptime.md) mục 6.

---

## 12. Lỗi thường gặp (probe thật)

| Thông điệp lỗi (Zig 0.17.0) | Nguyên nhân |
|---|---|
| `missing struct field: b` | bỏ sót field không có default trong struct literal |
| `no field named 'z' in struct '...'` | trỏ tới field không tồn tại |
| `backing integer bit width does not match total bit width of fields (32 vs 24)` | bề rộng backing integer sai so với tổng bit field |
| `expected type '*const u3', found '*align(1:3:1) u3'` … `pointer bit offset '3' cannot cast` | truyền con trỏ tới field con-bit vào nơi cần pointer ABI-aligned |
| `local variable is never mutated … consider using 'const'` | khai báo `var` không bao giờ gán lại |

---

## 13. Nguồn & liên kết

- [Zig Language Reference 0.17.1 — struct](https://ziglang.org/documentation/0.17.1/#struct)
- [`memory_model.md`](memory_model.md) mục 4 — struct layout, alignment, packed/extern
- [`comptime.md`](comptime.md) mục 6 — generic struct
- [`values.md`](values.md) — destructuring tupe/array/vector
- [`enum.md`](enum.md) — enum (một dạng namespace tương tự struct)

---

*Viết cho mục đích học tập; mọi đoạn trích quan trọng từ nguồn chính thức có link để tự kiểm chứng.*
