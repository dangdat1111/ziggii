# Vectors (SIMD) trong Zig — Hướng dẫn toàn diện

> Phiên bản xác minh: **Zig 0.17.0** (`zig version`), đối chiếu
> [Zig Language Reference 0.17.1 — Vectors](https://ziglang.org/documentation/0.17.1/#Vectors),
> [§Relationship with Arrays](https://ziglang.org/documentation/0.17.1/#Relationship-with-Arrays),
> [§Destructuring Vectors](https://ziglang.org/documentation/0.17.1/#Destructuring-Vectors).
> Mọi ví dụ dưới đây đã chạy thực tế trên máy (Apple M4, arm64, NEON 128-bit): bộ test dương
> **20/20 OK** + **8 probe lỗi** (7 lỗi lúc biên dịch, 1 panic lúc runtime) + 1 cảnh báo `@ptrCast`.

---

## Mục lục

1. [Vectors là gì? Cụm dữ liệu song song](#1-vectors-là-gì-cụm-dữ-liệu-song-song)
2. [`@Vector` — tạo kiểu vector, độ dài comptime](#2-vector--tạo-kiểu-vector-độ-dài-comptime)
3. [Phép toán element-wise (và điều cấm)](#3-phép-toán-element-wise-và-điều-cấm)
4. [`@splat`, index và `@reduce` (vector → scalar)](#4-splat-index-và-reduce-vector--scalar)
5. [`@shuffle` — xáo trộn phần tử](#5-shuffle--xáo-trộn-phần-tử)
6. [`@select` — chọn phần tử theo mask](#6-select--chọn-phần-tử-theo-mask)
7. [Vector ↔ Array: coerce, `@bitCast`, cấm `@ptrCast`](#7-vector--array-coerce-bitcast-cấm-ptrcast)
8. [Destructuring Vectors (`punpckldq`)](#8-destructuring-vectors-punpckldq)
9. [Kích thước & SIMD thực tế trên máy](#9-kích-thước--simd-thực-tế-trên-máy)
10. [Ứng dụng gọn gàng](#10-ứng-dụng-gọn-gàng)
11. [Lỗi thường gặp (probe thật 0.17.0)](#11-lỗi-thường-gặp-probe-thật-0170)
12. [Nguồn & liên kết](#12-nguồn--liên-kết)

---

## 1. Vectors là gì? Cụm dữ liệu song song

Langref định nghĩa rất gọn:

> *"A vector is a group of booleans, Integers, Floats, or **Pointers** which are operated on **in
> parallel**, using SIMD instructions **if possible**."*
> (— vector là một nhóm các boolean, số nguyên, số thực hoặc con trỏ được thao tác **song song**,
> dùng lệnh SIMD **nếu có thể**.)

Giống array nhưng dữ liệu được xử lý *cả cụm* bằng một lệnh máy — không phải vòng lặp từng phần tử. Ý
"if possible" nghĩa là mã dùng vector **luôn chạy đúng**: máy có SIMD → nhanh, máy không → compiler tự
xử lý từng phần tử, **không báo lỗi**. Trên máy viết doc này (Apple M4 arm64, NEON 128-bit) có SIMD
thật sự — xem [mục 9](#9-kích-thước--simd-thực-tế-trên-máy).

```zig
const a = @Vector(4, i32){ 1, 2, 3, 4 };
const b = @Vector(4, i32){ 5, 6, 7, 8 };
const c = a + b;                // { 6, 8, 10, 12 } — một nhát, không phải vòng lặp
try expectEqual(6, c[0]);
try expectEqual(12, c[3]);
```

---

## 2. `@Vector` — tạo kiểu vector, độ dài comptime

```zig
@Vector(len: comptime_int, Element: type) type
```

- Độ dài `len` phải **biết lúc comptime** — compiler cần nó để chọn kiểu SIMD register.
- `Element` (base type) bị giới hạn: **bool, integer, float hoặc pointer**. Không có struct/array bên
  trong vector.
- Literal khởi tạo giống array: `@Vector(4, i32){ 1, 2, 3, 4 }`.

Độ dài hợp lệ (langref):

> *"Zig supports any comptime-known vector length up to **2^32-1**, although small powers of two
> (2-64) are most typical. Note that excessively long vector lengths (e.g. 2^20) may result in
> **compiler crashes** on current versions of Zig."*

- Tối đa **2³²−1** phần tử; thông dụng: lũy thừa của 2 khoảng **2–64**.
- ⚠️ Vector quá dài (~`2^20`) có thể **làm compiler crash** — đừng dùng.

Khi kiểu đích đã biết từ ngữ cảnh, literal viết ngắn: `const v: @Vector(4, f32) = .{ 1.0, 2.0, 3.0, 4.0 };`

---

## 3. Phép toán element-wise (và điều cấm)

> *"Vectors generally support the same builtin operators as their underlying base types. The only
> exception to this is the keywords `and` and `or` on vectors of bools, since these operators affect
> control flow, which is not allowed for vectors. **All other operations are performed element-wise**,
> and return a vector of the same length as the input vectors."*

Hỗ trợ (đều element-wise, trả vector cùng độ dài):

| Nhóm | Ví dụ |
|---|---|
| Số học | `+`, `-`, `*`, `/`, `@divFloor`, `@sqrt`, `@ceil`, `@log`… |
| Bitwise | `>>`, `<<`, `&`, `\|`, `^`, `~` |
| So sánh | `<`, `>`, `<=`, `>=`, `==`, `!=` → trả **vector bool** |
| Boolean not | `!` trên vector bool |

```zig
const v = @Vector(4, i32){ 1, -1, 1, -1 };
const mask = v > @as(@Vector(4, i32), @splat(0));   // { true, false, true, false } : @Vector(4, bool)
const neg = !mask;                                    // { false, true, false, true }
const shl = @Vector(4, u8){ 1, 2, 3, 4 } << @splat(1); // { 2, 4, 6, 8 }
```

### 🚫 Điều cấm số 1: trộn scalar + vector

> *"It is **prohibited** to use a math operator on a mixture of scalars (individual numbers) and
> vectors."*

`vec + 1` → **lỗi biên dịch**; phải "nhân bản" scalar thành vector bằng `@splat`:

```zig
const r = v + @as(@Vector(4, i32), @splat(1)); // ✓ đúng
// const r = v + 1; // ✗ error: mixed scalar and vector operands: '@Vector(4, i32)' and 'comptime_int'
```

### 🚫 Điều cấm số 2: `and`/`or` trên vector bool

`and`/`or` là toán tử **điều khiển luồng** (short-circuit), không được dùng cho vector — dù cùng base
type là `bool`:

```zig
const a: @Vector(4, bool) = .{ true, false, true, true };
const b: @Vector(4, bool) = .{ true, true, false, false };
// const r = a and b; // ✗ error: expected type 'bool', found '@Vector(4, bool)'
```

Muốn kết hợp từng phần tử: dùng `&`/`|` (bitwise vẫn có trên vector bool) hoặc `@select` (mục 6).

💡 Vì các phép toán thông thường hoạt động theo từng phần tử nên **không có** phép nào *giảm độ dài*
vector ngoài `@reduce` (mục 4).

---

## 4. `@splat`, index và `@reduce` (vector → scalar)

### `@splat` — scalar → vector

```zig
@Vector(4, i32) const v = @splat(42);   // { 42, 42, 42, 42 }
const arr: [4]u32 = @splat(@as(u32, 5)); // @splat cũng sinh được array
```

> *"Produces an array or vector where each element is the value `element` … The return type, including
> the number of elements, is inferred."* — độ dài do kiểu đích quyết định.

### Index — lấy scalar ra khỏi vector

Cú pháp index như array; index **comptime hoặc runtime** đều hợp lệ:

```zig
const v = @Vector(4, i32){ 10, 20, 30, 40 };
try expectEqual(10, v[0]);     // index comptime
var i: usize = 2;              // index runtime cũng OK
_ = &i;
try expectEqual(30, v[i]);
```

### `@reduce` — giảm cả vector về một scalar

```zig
@reduce(comptime op: std.lang.ReduceOp, value: anytype) E
```

Giảm theo lượt (horizontal reduction) bằng toán tử `op`. Bảng toán tử **có sẵn trong Zig 0.17.0**
(đọc `std.lang.ReduceOp` — chỉ có đúng 7 giá trị):

| Op | Áp dụng được cho |
|---|---|
| `@reduce(.Min, v)` / `@reduce(.Max, v)` | số nguyên, số thực |
| `@reduce(.Add, v)` / `@reduce(.Mul, v)` | số nguyên (wrap), số thực |
| `@reduce(.And, v)` / `@reduce(.Or, v)` / `@reduce(.Xor, v)` | số nguyên + bool |
| ~~`.AddSat`~~ | ❌ **không tồn tại** trong 0.17 (probe: `enum 'lang.ReduceOp' has no member named 'AddSat'`) |

Langref nói rõ: *"Every operator is available for integer vectors. `.And`, `.Or`, `.Xor` are additionally
available for bool vectors, `.Min`, `.Max`, `.Add`, `.Mul` are additionally available for floating point
vectors. Note that `.Add` and `.Mul` reductions on integral types are **wrapping**."*

```zig
const v = @Vector(4, i32){ 1, -1, 3, 7 };
try expectEqual(10, @reduce(.Add, v));   // 1 + -1 + 3 + 7
try expectEqual(-21, @reduce(.Mul, v));  // 1 * -1 * 3 * 7 (wrap)
try expectEqual(-1, @reduce(.Min, v));
try expectEqual(7, @reduce(.Max, v));

const mask = @Vector(4, bool){ true, false, true, true };
try expectEqual(false, @reduce(.And, mask)); // false vì có một phần tử false
```

⚠️ `.Add`/`.Mul` trên số nguyên là **wrapping** (không báo overflow trong ReleaseFast); trên số thực thì
giữ tính kết hợp, trừ khi float mode `.optimized` (xem [`@setFloatMode`](https://ziglang.org/documentation/0.17.1/#setFloatMode)).

---

## 5. `@shuffle` — xáo trộn phần tử

Cú pháp langref:

```zig
@shuffle(comptime E: type, a: @Vector(a_len, E), b: @Vector(b_len, E), comptime mask: @Vector(mask_len, i32)) @Vector(mask_len, E)
```

Quy tắc mask (comptime, kiểu `i32`):

> *"Positive numbers select from `a` starting at 0. **Negative values select from `b`, starting at -1**
> and going down. It is recommended to use the `~` operator for indexes from `b` so that both indexes
> can start from 0 (i.e. `~@as(i32, 0)` is `-1`)."*

- Mask phần tử **dương** → lấy từ `a` (bắt đầu 0); **âm** → lấy từ `b` (bắt đầu −1, hay viết `~i`).
- Độ dài mask quyết định độ dài kết quả; index ngoài bounds → **compile error**; `E` phải là
  int/float/pointer/bool. Xáo trong một vector: truyền `undefined` cho tham số còn lại.

```zig
// Xáo TRONG một vector: đổi thứ tự, lặp, bỏ phần tử
const a = @Vector(7, u8){ 'o', 'l', 'h', 'e', 'r', 'z', 'w' };
const mask1 = @Vector(5, i32){ 2, 3, 1, 1, 0 };
const res1: @Vector(5, u8) = @shuffle(u8, a, undefined, mask1); // "hello" ✓ (đã test)

// Trộn HAI vector: mask âm lấy từ b (bắt đầu -1)
const b = @Vector(4, u8){ 'w', 'd', '!', 'x' };
const mask2 = @Vector(6, i32){ -1, 0, 4, 1, -2, -3 }; // -1 -> b[0]='w', 4 -> a[4]='r'...
const res2: @Vector(6, u8) = @shuffle(u8, a, b, mask2); // "world!" ✓ (đã test)
```

Lỗi khi mask vượt bounds (probe thật):

```
error: mask element at index '1' selects out-of-bounds index
note: index '7' exceeds bounds of '@Vector(4, i32)' given here
```

---

## 6. `@select` — chọn phần tử theo mask

```zig
@select(comptime T: type, pred: @Vector(len, bool), a: @Vector(len, T), b: @Vector(len, T)) @Vector(len, T)
```

> *"Selects values element-wise from `a` or `b` based on `pred`. If `pred[i]` is true, the
> corresponding element in the result will be `a[i]` and otherwise `b[i]`."*

```zig
const pred = @Vector(4, bool){ true, false, true, false };
const a = @Vector(4, i32){ 1, 2, 3, 4 };
const bb = @Vector(4, i32){ 10, 20, 30, 40 };
const r: @Vector(4, i32) = @select(i32, pred, a, bb);
// r = { 1, 20, 3, 40 } ✓ (đã test)
```

💡 Từng phần tử độc lập nhau — đây là "phần `else`" cho phép so sánh/số học: tính `a = cond ? x : y`
cho cả cụm mà không cần rẽ nhánh (branchless), rất có lợi cho SIMD.

---

## 7. Vector ↔ Array: coerce, `@bitCast`, cấm `@ptrCast`

Langref (Relationship with Arrays) nêu đúng chìa khóa:

> *"Vectors and Arrays each have a well-defined **bit layout** and therefore support `@bitCast` between
> each other. **Type Coercion implicitly performs `@bitCast`**. Arrays have well-defined byte layout,
> but vectors **do not**, making `@ptrCast` between them **Illegal Behavior**."*

Tóm tắt:

| Thao tác | Hợp lệ? | Vì sao |
|---|---|---|
| Coerce `[4]f32` ↔ `@Vector(4, f32)` | ✅ tự động | Coercion ngầm `@bitCast`; bit layout xác định |
| `@bitCast` qua lại | ✅ tường minh | bit layout xác định |
| `@ptrCast` vector ↔ array | ❌ **Illegal Behavior** | vector **không có byte layout** |

### 7.1 Coerce tự động (arr → vec → arr roundtrip)

```zig
const arr1: [4]f32 = [_]f32{ 1.1, 3.2, 4.5, 5.6 };
const vec: @Vector(4, f32) = arr1; // array -> vector (coerce)
const arr2: [4]f32 = vec;          // vector -> array (coerce)
try expectEqual(arr1, arr2);       // roundtrip khớp ✓ (đã test)
```

Vì coercion là `@bitCast` ngầm — chỉ diễn giải lại cùng dãy bit, không copy đổi thứ tự, rất nhanh.

### 7.2 Slice độ dài comptime → vector qua `.*`

```zig
const arr1: [4]f32 = .{ 1.1, 3.2, 4.5, 5.6 };
const vec2: @Vector(2, f32) = arr1[1..3].*; // { 3.2, 4.5 } ✓ (đã test)
```

`arr1[1..3]` là slice độ dài comptime-known (2), `.*` giải tham chiếu thành *array* rồi coerce sang
vector.

### 7.3 Lấy vector từ **offset runtime** — ví dụ langref

> *"To extract a comptime-known length from a runtime-known offset, first extract a new slice from the
> starting offset, then an array of comptime-known length."*

```zig
const slice: []const f32 = &arr1;
var offset: u32 = 1; // var để offset là runtime-known
_ = &offset;
const vec3: @Vector(2, f32) = slice[offset..][0..2].*;
try expectEqual(slice[offset], vec3[0]);       // arr1[1]
try expectEqual(slice[offset + 1], vec3[1]);   // arr1[2]
```

Phải cắt slice mới từ `offset` rồi lấy `[0..2]` vì **độ dài của `.*` phải comptime-known** — không viết
thẳng `slice[offset..offset+2].*`.

### 7.4 `@bitCast` tường minh

```zig
const arr: [4]f32 = .{ 1.0, 2.0, 3.0, 4.0 };
const vec: @Vector(4, f32) = @bitCast(arr);
try expectEqual(@as(f32, 2.0), vec[1]);
const back: [4]f32 = @bitCast(vec); // roundtrip ✓ (đã test)
```

Còn xem lại dãy byte dưới kiểu khác — reinterpret trong vector cũng được:

```zig
const bytes: [8]u8 = .{ 1, 2, 3, 4, 5, 6, 7, 8 };
const as_u32: @Vector(2, u32) = @bitCast(bytes);
try expectEqual(@as(u32, 0x04030201), as_u32[0]); // little-endian ✓ (đã test)
```

### ⚠️ 7.5 Cấm `@ptrCast`

Probe thật trên máy (arm64, vector align 16) — `@ptrCast(&arr)` sang `*const @Vector(4, f32)`:

```
error: @ptrCast increases pointer alignment
note: '*const [4]f32' has alignment '4'
note: '*const @Vector(4, f32)' has alignment '16'
note: use @alignCast to assert pointer alignment
```

Còn nếu dùng `@alignCast` để gượng ép vượt qua, dereference sẽ vướng lỗi khác:

```
error: comptime dereference requires '@Vector(4, f32)' to have a well-defined layout
```

→ Vector **không có byte layout** nên Zig chặn `@ptrCast` ở biên dịch. Dù `@alignCast` lách qua và chạy
đúng trên máy này (đã thử, ra `{ 1, 2, 3, 4 }`) thì đây vẫn là **Illegal Behavior** — không được đảm
bảo, dễ vỡ khi đổi kiến trúc. Cứ dùng `@bitCast`/coerce.

---

## 8. Destructuring Vectors (`punpckldq`)

Vectors **có thể destructure** — bóc từng phần tử thành biến, dùng `_` cho phần tử bỏ qua:

```zig
pub fn unpack(x: @Vector(4, f32), y: @Vector(4, f32)) @Vector(4, f32) {
    const a, const c, _, _ = x; // lấy phần tử 0 và 2 của x
    const b, const d, _, _ = y; // lấy phần tử 0 và 2 của y
    return .{ a, b, c, d };
}
```

Ví dụ langref mô phỏng lệnh x86 `punpckldq` (*unpack low doublewords*) — trộn xen kẽ nửa thấp của hai
vector. Chạy thật trên máy:

```zig
const x: @Vector(4, f32) = .{ 1.0, 2.0, 3.0, 4.0 };
const y: @Vector(4, f32) = .{ 5.0, 6.0, 7.0, 8.0 };
print("{}", .{unpack(x, y)});
```

```
{ 1, 5, 2, 6 }   ← khớp output langref §Destructuring Vectors ✓ (đã test)
```

→ `{ a, b, c, d }` chính là anonymous struct literal; kết quả là `@Vector(4, f32)` vì kiểu đích suy từ
hàm `unpack`. Destructuring chi tiết xem [`values.md`](values.md), [`comptime.md`](comptime.md).

---

## 9. Kích thước & SIMD thực tế trên máy

### 9.1 Bảng `@sizeOf`/`@alignOf` đo thật (Apple M4, arm64)

| Kiểu vector | `@sizeOf` | `@alignOf` | Ghi chú |
|---|---:|---:|---|
| `@Vector(4, f32)` | 16 | 16 | 128-bit → khớp 1 register NEON |
| `@Vector(2, f32)` | 8 | 8 | |
| `@Vector(4, u32)` | 16 | 16 | |
| `@Vector(4, f64)` | 32 | 16 | 256-bit, align 16 |
| `@Vector(8, u8)` | 8 | 8 | |
| `@Vector(16, u8)` | 16 | 16 | 128-bit |
| `@Vector(4, bool)` | 1 | 1 | **mask đóng gói theo bit** (xem 9.3) |
| `@Vector(9, bool)` | 2 | 2 | └ ceil(N/8) byte |
| `@Vector(16, bool)` | 2 | 2 | |

Máy này (ARM64, NEON 128-bit): `@Vector(4, f32)` = 128 bit → size 16, align 16, khớp trọn một register
`q` → 1 lệnh xử lý cả cụm. Alignment tùy CPU model (x86-64 AVX 256-bit có thể khác 32…).

💡 Chi tiết alignment tổng quát (struct, cache line) xem [`memory_model.md`](memory_model.md#44-alignment).

### 9.2 Vector so với native SIMD size (langref)

> *"Operations on vectors shorter than the target machine's native SIMD size will typically compile to
> **single SIMD instructions**, while vectors longer … will compile to **multiple SIMD instructions**."*

Kiểm chứng bằng `zig build-obj -O ReleaseFast -femit-asm` trên M4 (NEON 128-bit):

- `v + @splat(1)` với `@Vector(4, f32)` (128-bit) → chỉ 2 lệnh:
  ```
  fmov.4s   v1, #1.00000000   ; splat hằng số ra 4 lane
  fadd.4s   v0, v0, v1        ; cộng cả 4 phần tử 1 lệnh
  ```
- `@Vector(8, f32)` (256-bit) → **2** lệnh `fadd.4s` (chia thành 2 nhóm 128-bit)
- `@reduce(.Max, v)` → 1 lệnh NEON: `smaxv.4s s0, v0`

→ Compiler tự "xếp" vector vào register SIMD và chia nhỏ khi quá dài; bạn không cần can thiệp.

### 9.3 Vector bool = bitmask

`@Vector(N, bool)` không phải N byte mà là **N bit đóng gói** (mask): `@sizeOf(@Vector(8, bool)) = 1`,
`@Vector(16, bool) = 2`. Đây là nguồn gốc của khái niệm *mask vector* trong SIMD — kết quả so sánh
(`v > @splat(0)`) chính là cái mask 1-bit này.

---

## 10. Ứng dụng gọn gàng

`std.simd` **có sẵn trong Zig 0.17.0** (`std/simd.zig` — kiểm tra tồn tại và dùng được). Chạy thật:

```zig
const std = @import("std");
const print = std.debug.print;

fn dot4(a: @Vector(4, f32), b: @Vector(4, f32)) f32 {
    return @reduce(.Add, a * b); // nhân 4 cặp 1 lệnh, rồi cộng dồn
}

pub fn main() void {
    const a: @Vector(4, f32) = .{ 1.0, 2.0, 3.0, 4.0 };
    const b: @Vector(4, f32) = .{ 4.0, 5.0, 6.0, 7.0 };
    print("dot4 = {d}\n", .{dot4(a, b)}); // 60 (1*4 + 2*5 + 3*6 + 4*7) ✓

    const scores = @Vector(8, f32){ 0.9, 0.4, 0.8, 0.2, 0.95, 0.1, 0.7, 0.6 };
    const mask = scores >= @as(@Vector(8, f32), @splat(0.5));
    const n = std.simd.countTrues(mask);  // đếm phần tử >= 0.5
    print("above 0.5: {d}/8\n", .{n});    // 5/8 ✓

    if (std.simd.suggestVectorLength(f32)) |lanes| {
        print("suggested f32 lanes for this CPU: {d}\n", .{lanes}); // 4 (128-bit NEON)
    }
}
```

Kết hợp lại: dot product chỉ là `@reduce(.Add, a * b)` (nhân 1 lệnh + thu gọn), đếm mask dùng
`std.simd.countTrues`, còn `std.simd.suggestVectorLength(f32)` cho biết nên chạy mấy lane cho CPU hiện
tại (M4 → 4) — phần phép toán vector là core ngôn ngữ, không cần thư viện.

---

## 11. Lỗi thường gặp (probe thật 0.17.0)

| Thông điệp lỗi (Zig 0.17.0) | Nguyên nhân |
|---|---|
| `error: mixed scalar and vector operands: '@Vector(4, i32)' and 'comptime_int'` | dùng `vec + 1` (trộn scalar/vector) — phải `@splat` |
| `error: expected type 'bool', found '@Vector(4, bool)'` | dùng `and`/`or` trên vector bool (cấm vì control flow) |
| `error: @ptrCast increases pointer alignment` (4 → 16) rồi `use @alignCast to assert pointer alignment` | `@ptrCast` vector ↔ array — Illegal Behavior, bị chặn ở biên dịch |
| `error: comptime dereference requires '@Vector(4, f32)' to have a well-defined layout` | cố dereference pointer sang vector (kể cả sau `@alignCast`) |
| `error: enum 'lang.ReduceOp' has no member named 'AddSat'` | op `@reduce` không tồn tại (`AddSat` **không có** trong 0.17) |
| `error: @reduce operation 'Add' requires integer or float operand; found '@Vector(4, bool)'` | `@reduce(.Add)` trên vector bool — bool chỉ có `.And`/`.Or`/`.Xor` |
| `error: mask element at index '1' selects out-of-bounds index` / `note: index '7' exceeds bounds` | `@shuffle` mask vượt bounds (comptime bắt) |
| `error: index 4 outside array of length 4` | index **comptime** ngoài bounds vector |
| `panic: index out of bounds: index 7, len 4` | index **runtime** ngoài bounds — panic khi safety on (debug) |
| `error: type '@Vector(4, i32)' does not support field access` | `for`/`in` trực tiếp lên vector — phải coerce sang array rồi duyệt |
| `local variable is never mutated … consider using 'const'` | khai báo `var` (vd `var offset`) không bao giờ gán lại — thêm `_ = &offset;` |

---

## 12. Nguồn & liên kết

- [Zig Language Reference 0.17.1 — Vectors](https://ziglang.org/documentation/0.17.1/#Vectors),
  [§Relationship with Arrays](https://ziglang.org/documentation/0.17.1/#Relationship-with-Arrays),
  [§Destructuring Vectors](https://ziglang.org/documentation/0.17.1/#Destructuring-Vectors)
- Builtins langref 0.17.1: [`@Vector`](https://ziglang.org/documentation/0.17.1/#Vector),
  [`@splat`](https://ziglang.org/documentation/0.17.1/#splat), [`@reduce`](https://ziglang.org/documentation/0.17.1/#reduce),
  [`@shuffle`](https://ziglang.org/documentation/0.17.1/#shuffle), [`@select`](https://ziglang.org/documentation/0.17.1/#select)
- [`memory_model.md`](memory_model.md) mục 4 — alignment, cache line
- [`comptime.md`](comptime.md) — độ dài vector, mask `@shuffle`/`@splat` đều là comptime
- [`values.md`](values.md) — destructuring (tuple/array/vector)
- [`build_system.md`](build_system.md) — chế độ `ReleaseFast` (mục 4) để mã có SIMD tối đa
- [`struct.md`](struct.md) mục 7 — `packed struct` (không dùng `@Vector` trong packed, nhưng liên
  quan khái niệm bit layout/ngầm `@bitCast`)

---

*Viết cho mục đích học tập; mọi đoạn trích quan trọng từ nguồn chính thức có link để tự kiểm chứng.
Các probe thực nghiệm đặt tại `/tmp/zigenum/vectors/` (scratch) — không thuộc repo dự án.*
