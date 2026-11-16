# Pointers & Slices trong Zig — hướng dẫn toàn diện

> Phiên bản xác minh: **Zig 0.17.0** (`zig version` → 0.17.0), đối chiếu với
> [Zig Language Reference 0.17.1 — Pointers](https://ziglang.org/documentation/0.17.1/#Pointers),
> [0.17.1 — Slices](https://ziglang.org/documentation/0.17.1/#Slices) và
> [0.17.1 — Type Coercion: Slices, Arrays and Pointers](https://ziglang.org/documentation/0.17.1/#Type-Coercion-Slices-Arrays-and-Pointers).
> Mọi ví dụ đã chạy thật `zig test`/`zig build-obj` trên máy (macOS ARM64) —
> **41 test dương OK + 12 probe âm** (bộ test ở [mục 14](#14-bộ-test-tổng-hợp--kết-quả)).

---

## Mục lục

1. [Ba họ "con trỏ"](#1-ba-họ-con-trỏ)
2. [Bảng kích thước: pointer mảnh vs slice "mập"](#2-bảng-kích-thước-pointer-mảnh-vs-slice-mập)
3. [Address-of `&` — tạo con trỏ từ biến](#3-address-of--tạo-con-trỏ-từ-biến)
4. [Type coercion: Slices, Arrays và Pointers](#4-type-coercion-slices-arrays-và-pointers)
5. [Alignment](#5-alignment)
6. [`volatile` và `allowzero`](#6-volatile-và-allowzero)
7. [Sentinel-terminated: `[N:0]T`, `[*:0]T`, `[:0]T`](#7-sentinel-terminated-n0t-0t-0t)
8. [Slices: view, slicing và bounds checking](#8-slices-view-slicing-và-bounds-checking)
9. [Slicing by length — `[a..][0..b]`](#9-slicing-by-length--a0b)
10. [Cast builtins cho con trỏ (tên 0.17)](#10-cast-builtins-cho-con-trỏ-tên-017)
11. [C Pointers `[*c]T` — cây cầu qua C](#11-c-pointers-ct--cây-cầu-qua-c)
12. [Comptime pointers](#12-comptime-pointers)
13. [Lỗi thường gặp — probe thật trên 0.17.0](#13-lỗi-thường-gặp--probe-thật-trên-0170)
14. [Bộ test tổng hợp & kết quả](#14-bộ-test-tổng-hợp--kết-quả)
15. [Liên hệ memory model & cross-link](#15-liên-hệ-memory-model--cross-link)
16. [Nguồn tham khảo](#16-nguồn-tham-khảo)

---

## 1. Ba họ "con trỏ"

Mục [Pointers](https://ziglang.org/documentation/0.17.1/#Pointers) mở đầu:

> *"Zig has two kinds of pointers: single-item and many-item."*

| Cú pháp | Tên | Trỏ tới | Cú pháp hỗ trợ |
|---|---|---|---|
| `*T` | **single-item pointer** | đúng **1** phần tử `T` | `ptr.*` (deref), `ptr[0..1]` (slice syntax), `ptr - ptr` |
| `[*]T` | **many-item pointer** | **nhiều** phần tử, **không biết độ dài** | `ptr[i]`, `ptr[start..]`, `ptr + int`, `ptr - ptr` |
| `[]T` | **slice** (fat pointer) | `ptr` + **length runtime** | `slice[i]`, `slice[start..end]`, `slice.len` |

`[*]T` yêu cầu `T` phải có size biết trước: *"it cannot be `anyopaque` or any other opaque
type."* Gắn với array có kiểu quan trọng thứ tư: **`*[N]T`** — *"pointer to N items, same as
single-item pointer to an array"* — hỗ trợ `array_ptr[i]`, `array_ptr[start..end]`,
`array_ptr.len`, `array_ptr - array_ptr`. Nó là con trỏ *mảnh* (8 byte) nhưng nhờ `N` comptime-known
nên "biết" độ dài — bước đệm sang slice (mục 4). Họ thứ năm `[*c]T` (C pointer) ở mục 11.

> 💡 Đừng gọi chung một tiếng "con trỏ" cho cả ba — mức độ an toàn khác nhau hoàn toàn (mục 8).

## 2. Bảng kích thước: pointer mảnh vs slice "mập"

Đo thật (64-bit, Zig 0.17.0):

```zig
try expectEqual(8,  @sizeOf(*u8));       // single-item
try expectEqual(16, @sizeOf([]u8));      // slice = ptr + len (fat pointer)
try expectEqual(8,  @sizeOf(?*u8));      // optional ptr (null-opt, KHÔNG tốn thêm)
try expectEqual(16, @sizeOf(?[*c]u8));   // optional C ptr: +1 bit null (như ?usize)
```

| Kiểu | Ý nghĩa | `@sizeOf` | Bounds-check index |
|---|---|---|---|
| `*T` | đúng 1 phần tử, deref `ptr.*` | 8 | không |
| `[*]T` | nhiều phần tử, không có len | 8 | **không** (đã probe, mục 8) |
| `[*:0]T` | nhiều phần tử, dừng theo sentinel | 8 | chỉ tại sentinel |
| `*[N]T` | pointer tới array | 8 | có (N comptime) |
| `[]T` | slice `{ ptr, len }` | **16** | **có** (panic) |
| `[:0]T` | slice + sentinel | **16** | có |
| `?*u8` | optional pointer | 8 | — |
| `[*c]T` / `?[*c]u8` | C pointer / optional C pointer | 8 / **16** | kém an toàn |

> *"`[]T` — is a slice (a fat pointer, which contains a pointer of type `[*]T` and a length)."*
> Khớp với [`variables.md`](variables.md#9-kích-thước--alignment--một-biến-chiếm-bao-nhiêu-byte)
> (slice copy 16-byte descriptor) và [`memory_model.md`](memory_model.md#42-pointer-single-item-vs-many-item).

⚠️ `@sizeOf(?*u8) == 8` nhờ **null-pointer optimization** (địa chỉ 0 làm `null`); riêng optional **C
pointer** không được tối ưu → 16 byte, đúng lời langref: *"Optional C pointers introduce another bit
to keep track of null, just like `?usize`."*

## 3. Address-of `&` — tạo con trỏ từ biến

Const-ness của biến đi vào kiểu con trỏ (đã test):

```zig
test "address of const gives *const T" {
    const x: i32 = 1234;
    const x_ptr = &x;
    try expectEqual(*const i32, @TypeOf(x_ptr));  // const → *const
    try expectEqual(1234, x_ptr.*);
}
test "address of var gives *T and allows mutation" {
    var y: i32 = 5678;
    const y_ptr = &y;
    try expectEqual(*i32, @TypeOf(y_ptr));        // var → * (mut)
    y_ptr.* += 1;
    try expectEqual(5679, y_ptr.*);               // sửa qua con trỏ sửa luôn biến
}
```

- Cạm bẫy 0.17: `var` **không bao giờ gán lại** bị chặn lúc biên dịch (`local variable is never
  mutated`); chỉ cần địa chỉ thì dùng `_ = &x;` (đã test OK).
- `&array[i]` → `*T` (single-item, không hỗ trợ pointer arithmetic).
- Slice syntax trên con trỏ: `ptr[0..1]` biến `*T` thành `*[1]T`, rồi coerce sang `[*]T` (đã test):
  ```zig
  var x: i32 = 1234;
  const x_array_ptr = x[0..1];                    // *[1]i32
  const x_many_ptr: [*]i32 = x_array_ptr;         // coerce sang many-item
  ```

## 4. Type coercion: Slices, Arrays và Pointers

File [coerce_slices_arrays_and_pointers](https://ziglang.org/documentation/0.17.1/#Type-Coercion-Slices-Arrays-and-Pointers)
của langref chạy nguyên bản trên 0.17.0 → **8/8 OK**:

```
1/8 ...test.*const [N]T to []const T...OK
...
8/8 ...test.[:x]T to [*:x]T...OK
All 8 tests passed.
```

| # | Coercion | Ý nghĩa | Ví dụ |
|---|---|---|---|
| 1 | `*const [N]T` → `[]const T` | const array ptr → slice const | `const x: []const u8 = "hello";` |
| 2 | `*const [N]T` → `E![]const T` | qua **error union** | `const x: anyerror![]const u8 = "hello";` |
| 3 | `*const [N]T` → `?[]const T` | qua **optional** | `const x: ?[]const u8 = "hello";` |
| 4 | `*[N]T` → `[]T` | N trở thành len slice | `const x: []u8 = &buf;` |
| 5 | `*[N]T` → `[*]T` | bỏ kiến thức độ dài | `const x: [*]u8 = &buf;` |
| 6 | `*[N]T` → `?[*]T` | optional many-item | `const x: ?[*]u8 = &buf;` |
| 7 | `*T` → `*[1]T` | single-item → mảng độ dài 1 | `const y: *[1]i32 = &x;` |
| 8 | `[:x]T` → `[*:x]T` | sentinel slice → sentinel ptr | `const buf2: [*:0]const u8 = buf;` |

Langref chú thích dòng #5 rất quan trọng: *"`x[5]` would be **an uncaught out of bounds** pointer
dereference!"* — sau coerce sang `[*]T`, độ dài biến mất khỏi kiểu.

**String literal** có kiểu `*const [N:0]u8` và kéo sang nhiều đích (đã test):

```zig
const hello: *const [5:0]u8 = "hello";        // len comptime, [5] là sentinel 0
const as_slice: []const u8 = "hello";         // *const [N:0]u8 → []const u8
const as_ss: [:0]const u8 = "hello";          // → [:0]const u8
const as_sp: [*:0]const u8 = "hello";         // → [*:0]const u8 (đã test thêm)
try expectEqual(0, as_ss[5]);                 // sentinel slice đọc được vị trí len
```

Thêm const thì được, **bỏ const thì bị chặn** — probe thật:

```
error: expected type '*[5]u8', found '*const [5]u8'
    const p: *[5]u8 = &arr;
                      ^~~~
note: cast discards const qualifier
```

## 5. Alignment

> *"Each type has an alignment … the memory address must be evenly divisible by this number. You can
> use `@alignOf` to find out this value for any type. … Alignment depends on the CPU architecture, but
> is always a power of two, and less than `1 << 29`."* — Sai alignment là **Illegal Behavior** (được
> safety-check ở runtime), chi tiết [`memory_model.md`](memory_model.md#44-alignment).

```zig
var x: i32 = 1234;
try expect(@intFromPtr(&x) % @alignOf(i32) == 0);   // local luôn align đúng
const ptr: *align(@alignOf(i32)) i32 = &x;          // pointer khai align tường minh
var foo: u8 align(4) = 100;                          // over-align biến
try expectEqual(*align(4) u8, @TypeOf(&foo));        // align "dính" vào kiểu con trỏ
```
(Test `alignment basics + over-aligned variable` → OK, kể cả `@typeInfo(...).pointer.attrs.@"align" == 4`.)

Hai chiều coerce: **align lớn → nhỏ** được phép (`[]align(4) u8 → []u8`, đã test); **nhỏ → lớn** phải
qua `@alignCast` — no-op ở runtime nhưng **chèn safety check**; địa chỉ thật sự align đủ thì OK (đã
test `@alignCast(&arr[0])` với `arr: [4]u8 align(4)`).

Probe **sai alignment** (đúng ví dụ langref) → panic thật:

```
1/1 n5_aligncast.test.pointer alignment safety...thread 148929 panic: incorrect alignment
    const int_slice = std.mem.bytesAsSlice(u32, @as([]align(4) u8, @alignCast(slice4)));
                                                                   ^
```

Còn `@ptrCast` **không được tăng alignment** — lỗi biên dịch:

```
n10_ptrcast_align.zig:5:21: error: @ptrCast increases pointer alignment
note: '*u8' has alignment '1'
note: '*u32' has alignment '4'
note: use @alignCast to assert pointer alignment
```

⚠️ Alignment phụ thuộc kiến trúc; con trỏ tới field sub-byte của packed struct là `*align(1:3:1) T`
(host size + bit offset) — xem [`struct.md`](struct.md#72-field--1-byte-pointer-không-cùng-địa-chỉ-có-bit-offset).

## 6. `volatile` và `allowzero`

**`volatile`** — cho MMIO, ngăn tối ưu/xoá store:

> *"Loads and stores are assumed to not have side effects. If a given load or store should have side
> effects, such as Memory Mapped Input/Output (MMIO), use `volatile` … guaranteed to all happen and in
> the same order as in source code."*

```zig
test "volatile pointer" {
    const mmio_ptr: *volatile u8 = @ptrFromInt(0x12345678);
    try expectEqual(*volatile u8, @TypeOf(mmio_ptr));
}
```
> 🚨 *"`volatile` is unrelated to concurrency and Atomics. If you see code that is using `volatile` for
> something other than MMIO, it is probably a bug."*

**`allowzero`** — cho phép địa chỉ 0:

> *"This pointer attribute allows a pointer to have address zero. This is only ever needed on the
> freestanding OS target … If you want to represent null pointers, use Optional Pointers instead."*

```zig
test "allowzero pointer allows address 0" {
    var zero: usize = 0;            // runtime-known
    _ = &zero;
    const ptr: *allowzero i32 = @ptrFromInt(zero);
    try expectEqual(0, @intFromPtr(ptr));
}
```

Không có `allowzero`, Zig 0.17.0 chặn địa chỉ 0 ở **hai mức** (đã probe):

- 0 comptime-known → lỗi biên dịch: `error: pointer type '*i32' does not allow address zero`.
- 0 runtime → panic khi deref: `panic: cast causes pointer to be null`.

## 7. Sentinel-terminated: `[N:0]T`, `[*:0]T`, `[:0]T`

> *"The syntax `[*:x]T` describes a pointer that has a length determined by a sentinel value. This
> provides protection against buffer overflow and overreads."*

| Kiểu | Đặc điểm | `@sizeOf` |
|---|---|---|
| `[N:0]T` | **sentinel array**, len comptime | 8 (sau con trỏ) |
| `[*:0]T` | **sentinel pointer**, dừng theo sentinel | 8 |
| `[:0]T` | **sentinel slice**, len runtime + bảo đảm sentinel tại `len` | 16 |

```zig
test "sentinel slice [:0]u8 via slice syntax with colon" {
    var array = [_]u8{ 3, 2, 1, 0, 3, 2, 1, 0 };
    var runtime_length: usize = 3;
    _ = &runtime_length;
    const slice = array[0..runtime_length :0];
    try expectEqual([:0]u8, @TypeOf(slice));
    try expectEqual(3, slice.len);
    try expectEqual(0, slice[3]);      // sentinel slice đọc được vị trí len
}
test "sentinel-terminated array [4:0]u8 coerces to [*:0]u8" {
    var array: [4:0]u8 = .{ 1, 2, 3, 0 };
    const ptr: [*:0]u8 = &array;
    try expectEqual(3, ptr[2]);
}
```

**Lỗi thật** khi nạp array *không* terminator `0` vào `[*:0]const u8` (kiểu tham số `printf` C):

```
n2_no_sentinel.zig:8:19: error: expected type '[*:0]const u8', found '*const [14]u8'
    print_cstring(&non_null_terminated_msg);
                  ^~~~~~~~~~~~~~~~~~~~~~~~
note: destination pointer requires '0' sentinel
```

**Panic thật** khi vị trí sentinel không khớp giá trị (slice `:0`):

```
1/1 n4_sentinel_mismatch.test.sentinel mismatch...thread 148882 panic: sentinel mismatch: expected 0, found 1
    const slice = array[0..runtime_length :0];
                       ^
```

> 💡 Langref: *"In Zig, we generally prefer Slices rather than Sentinel-Terminated Pointers"* — ưu
> tiên slice trừ khi giao tiếp C.

## 8. Slices: view, slicing và bounds checking

> *"A slice is a pointer and a length. The difference between an array and a slice is that the
> array's length is part of the type and known at compile-time, whereas the slice's length is known
> at runtime."*

**Slice là view, không sở hữu dữ liệu** — chỉ là cặp `{ptr, len}` trỏ vào vùng nhớ do ai đó khác sở
hữu (stack/heap/global/rodata, mục 15).

```zig
test "slice is a view (not owning)" {
    var array = [_]i32{ 1, 2, 3, 4 };
    var start: usize = 1;            // runtime → kết quả là slice
    _ = &start;
    const slice = array[start..];    // s[1..] → 3 phần tử ([]i32)
    try expectEqual([]i32, @TypeOf(slice));
    slice[0] = 99;                   // sửa qua slice → sửa luôn array
    try expectEqual(99, array[1]);
}
```

Slicing bằng index/range: `s[1..3]`, `s[0..len]`, `s[0..]`. Nếu `start` **và** `end` đều comptime →
kết quả là **`*[N]T`** chứ không phải slice (kiểu an toàn hơn, đã test):

```zig
const array_ptr = array[0..array.len];   // *[4]i32, không phải []i32!
```

`slice.ptr` là `[*]T`; `&slice[0]` là `*T`, cùng địa chỉ (đã test). ⚠️ Langref: *"`slice.ptr` does not
invoke safety checking, while `&slice[0]` asserts that the slice has `len > 0`."*

Slice rỗng: `&[0]u8{}` hay `[]u8 = &.{}` — *"a zero-length initialization can always be used to create
an empty slice, even if the slice is mutable."*

**Bounds checking**: slice CÓ, pointer KHÔNG. Probe thật:

```
1/1 n3_slice_oob.test.slice index out of bounds is safety-checked...thread 148866 panic: index out of bounds: index 10, len 4
    slice[10] += 1;
         ^
```
```
1/1 n11_slice_bounds_build.test.slice construction out of range...thread 149117 panic: start index 3 is larger than end index 2
```
```
1/1 n7_ptr_oob.test.many-item pointer index out of bounds...OK      ← [*]T KHÔNG bị chặn!
All 1 tests passed.
```

> *"Slices have bounds checking and are therefore protected against this kind of Illegal Behavior.
> This is one reason we prefer slices to pointers."*

⚠️ Pointer arithmetic trực tiếp trên `slice.ptr` làm **hỏng slice** (`len` không tự cập nhật theo
`ptr`): *"directly incrementing the pointer from a slice will corrupt it"* — muốn arithmetic thì gán
sang `[*]T` rồi nhích biến đó (đã chạy thử).

## 9. Slicing by length — `[a..][0..b]`

> *"The pattern `[a .. a + b]` is always better expressed `[a..][0..b]`"* — slice trong bộ nhớ là
> `{ptr, len}` nên `[a..][0..b]` ít hơn một phép trừ trong mã máy; nếu `a` runtime, `b` comptime thì
> kết quả là `*[b]T`, "a generally more safe type because the length is compile-time known".

```zig
test "example" {
    var array = [_]i32{ 1, 2, 3, 4 };
    var runtime_start: usize = 1;
    _ = &runtime_start;
    const length = 2;
    const array_ptr_len = array[runtime_start..][0..length];
    try expectEqual(*[length]i32, @TypeOf(array_ptr_len));   // *[2]i32, không phải slice
}
```
```
1/1 slicing_by_length.test.example...OK
```

## 10. Cast builtins cho con trỏ (tên 0.17)

> ⚠️ **0.17**: `@ptrToInt` / `@intToPtr` **không còn** — dùng **`@intFromPtr`** (ptr → `usize`) và
> **`@ptrFromInt`** (int → ptr). Cả hai đã chạy OK trên 0.17.0.

```zig
test "@intFromPtr and @ptrFromInt (0.17 names)" {
    const ptr: *i32 = @ptrFromInt(0xdeadbee0);
    const addr = @intFromPtr(ptr);
    try expectEqual(usize, @TypeOf(addr));
    try expectEqual(0xdeadbee0, addr);
}
```

- **`@ptrCast`** — đổi kiểu phần tử; `@typeInfo(*u32).pointer.child == u32` (đã test). Langref cảnh
  báo có thể tạo *undetectable Illegal Behavior*; muốn đọc logical bits không phụ thuộc endian thì
  dùng `@bitCast`. Không được tăng alignment (mục 5).
- **`@alignCast`** — xác nhận/nâng alignment, safety-checked no-op (mục 5).
- **`@constCast`** — bỏ `const` khỏi con trỏ (đã test). ⚠️ Chỉ dùng khi vùng nhớ thật sự ghi được
  (vd `var` đang bị giữ dạng `*const`); rodata thì ghi qua sẽ là Illegal Behavior.
- **`@volatileCast`** — thêm/bớt `volatile` (đã test cả 2 hướng với result type tường minh).

```zig
test "@constCast removes const from a pointer" {
    var arr = [5]u8{ 1, 2, 3, 4, 5 };
    const p: *const [5]u8 = &arr;
    const q: *[5]u8 = @constCast(p);
    try expectEqual(*[5]u8, @TypeOf(q));
}
```

| Builtin | 0.17 | Làm gì |
|---|---|---|
| `@intFromPtr` | ✅ (không còn `@ptrToInt`) | pointer → `usize` |
| `@ptrFromInt` | ✅ (không còn `@intToPtr`) | integer → pointer |
| `@ptrCast` | ✅ | đổi kiểu phần tử; **không tăng alignment** |
| `@alignCast` | ✅ | xác nhận align (safety-checked) |
| `@constCast` | ✅ | bỏ `const` |
| `@volatileCast` | ✅ | thêm/bớt `volatile` |
| `@bitCast` | ✅ | reinterpret bits, không phụ thuộc endian |

## 11. C Pointers `[*c]T` — cây cầu qua C

> *"This type is to be avoided whenever possible. The only valid reason for using a C pointer is in
> auto-generated code from translating C code."* — `[*c]T` là "con trỏ trung dung" vì dịch header C
> không rõ nên dùng `*T` hay `[*]T`.

Đặc tính (langref + probe): hỗ trợ mọi cú pháp của `*T` lẫn `[*]T`; **coerce** được sang các pointer
khác & optional (nếu địa chỉ 0 → safety-check); **cho phép địa chỉ 0**; coerce/so sánh được với số
nguyên; optional C pointer +1 bit null; **không hỗ trợ** alignment (Zig-only) — *"Use normal Pointers
please!"*.

```zig
test "C pointer: coerce, deref, integer address, optional, compare" {
    const x: i32 = 1234;
    const cp: [*c]const i32 = &x;
    try expectEqual(1234, cp.*);
    try expect(cp != null);                       // so sánh null
    const addr: usize = @intFromPtr(cp);
    try expect(addr != 0);                        // so sánh số nguyên
    const normal: *const i32 = cp;                // coerce ngược lại pointer thường
    try expectEqual(1234, normal.*);
}
test "C pointer trỏ struct: csp.*.member (giống ->)" {
    const S = struct { a: i32, b: i32 };
    var s = S{ .a = 1, .b = 2 };
    const csp: [*c]S = &s;
    try expectEqual(1, csp.*.a);                  // deref rồi chấm field — như `->` C
    var arr = [_]S{ .{ .a = 10, .b = 20 }, .{ .a = 30, .b = 40 } };
    const carr: [*c]S = &arr;
    try expectEqual(30, carr[1].a);               // trỏ MẢNG struct thì dùng carr[i]
}
```
```
1/3 cpointers.test.C pointer: coerce, deref, integer address, optional, compare...OK
2/3 cpointers.test.C pointer trỏ tới struct: dùng csp.*.member (giống ->)...OK
3/3 cpointers.test.optional C pointer mang bit null (giống ?usize)...OK
All 3 tests passed.
```

## 12. Comptime pointers

> *"Pointers work at compile-time too, as long as the code does not depend on an undefined memory
> layout."* — và địa chỉ dựng bằng `@ptrFromInt` được giữ ở comptime miễn là **không deref**.

```zig
test "comptime pointers" {
    comptime {
        var x: i32 = 1;
        const ptr = &x;
        ptr.* += 1;
        x += 1;
        try expectEqual(3, ptr.*);
    }
}
test "comptime @ptrFromInt" {
    comptime {
        const ptr: *i32 = @ptrFromInt(0xdeadbee0);  // giữ giá trị, không deref
        const addr = @intFromPtr(ptr);
        try expectEqual(usize, @TypeOf(addr));
        try expectEqual(0xdeadbee0, addr);
    }
}
```
```
1/2 comptime_pointers.test.comptime pointers...OK
2/2 comptime_pointers.test.comptime @ptrFromInt...OK
All 2 tests passed.
```

## 13. Lỗi thường gặp — probe thật trên 0.17.0

Tất cả thông điệp dưới đây lấy từ **output thật** của `zig test`/`zig build-obj` (scratch
`/tmp/zigenum/pointers/neg/`):

| Thông điệp lỗi (0.17.0) | Loại | Nguyên nhân |
|---|---|---|
| `expected type '*[5]u8', found '*const [5]u8'` + `cast discards const qualifier` | compile | con trỏ mut vào const array |
| `expected type '[*:0]const u8', found '*const [14]u8'` + `destination pointer requires '0' sentinel` | compile | array không sentinel → `[*:0]T` |
| `returning address of expired local variable 'x'` (+ `declared runtime-known here`) | compile | trả `&local` (dangling) |
| `local variable is never mutated` (+ `consider using 'const'`) | compile | `var` không bao giờ gán lại |
| `pointer type '*i32' does not allow address zero` | compile | `@ptrFromInt(0)` comptime, không `allowzero` |
| `@ptrCast increases pointer alignment` (+ `use @alignCast …`) | compile | `@ptrCast` tăng alignment |
| `panic: index out of bounds: index 10, len 4` | runtime | index slice ngoài `[0,len)` |
| `panic: start index 3 is larger than end index 2` | runtime | dựng slice `s[a..b]` với `a > b` |
| `panic: sentinel mismatch: expected 0, found 1` | runtime | vị trí sentinel sai giá trị |
| `panic: incorrect alignment` | runtime | `@alignCast` tới địa chỉ misaligned |
| `panic: cast causes pointer to be null` | runtime | `@ptrFromInt(0)` runtime + deref, không `allowzero` |
| *(không lỗi!)* `n7_ptr_oob …OK` | ⚠️ | `[*]T` index ngoài bounds **không được check** |

## 14. Bộ test tổng hợp & kết quả

Scratch: `/tmp/zigenum/pointers/`.
- **Positive 41/41 OK**: `p1_ptr.zig` (22 test: size, address-of, coerce, slice view, sentinel,
  alignment, volatile, allowzero, cast builtins, ptr arithmetic, C pointer) · `coerce_…` (8, nguyên
  bản langref) · `cpointers.zig` (3) · `slicing_by_length.zig` (1) · `comptime_pointers.zig` (2) ·
  `var_used_by_addr.zig` (1) · `ptr_arith_slice.zig` (1) · `casts2.zig` (2) ·
  `extra_check.zig` (1).
- **Negative 12**: 11 lỗi thật (compile + runtime) + 1 bằng chứng "pointer không check bounds".

```
1/22 p1_ptr.test.@intFromPtr and @ptrFromInt (0.17 names)...OK
... (đủ 22 test — "All 22 tests passed.")
```

Không con số nào trong doc bịa: mọi size/alignment/panic/error đều tái lập được từ bản ghi trên.

## 15. Liên hệ memory model & cross-link

Một slice `[]T` (16 byte) thường nằm **trên stack** nhưng **trỏ tới dữ liệu khắp nơi** — đúng tinh
thần "Where are the bytes?" của [`memory_model.md`](memory_model.md#2-triết-lý-cốt-lõi-where-are-the-bytes):

| Con trỏ/slice trỏ tới | Vùng bộ nhớ |
|---|---|
| `&"hello"`; `&const_comptime` | **global constant data** (rodata) |
| `&local_var` | **stack frame** (hết hạn khi hàm trả về) |
| `&global_var` | **global data** |
| `allocator.alloc` (trả `[]T`) | **heap** |

Ba quy tắc lifetime đã probe thật:

1. `return &local` bị chặn ngay khi compile — *"expired local"* (xem
   [`variables.md`](variables.md#54-hết-hạn-expired-local--illegal-behavior)).
2. Ngoài ca compiler tự bắt, **lifetime do lập trình viên quản** (ownership): con trỏ có thể "xuyên
   vùng nhớ" stack → heap → rodata nhưng bạn phải đảm bảo nó không bay hơi —
   [`memory_model.md`](memory_model.md#8-lifetime--ownership--hoặc-ai-sở-hữu-byte-này).
3. Slice là descriptor: copy slice = copy 16 byte `{ptr,len}`; dữ liệu phía sau chỉ là một —
   [`variables.md`](variables.md#6-value-semantics-biến-là-storage-không-phải-refer).

Cross-link: [`memory_model.md`](memory_model.md#42-pointer-single-item-vs-many-item) (bảng 3 họ con
trỏ; [4.4 Alignment](memory_model.md#44-alignment); [4.5 volatile/allowzero](memory_model.md#45-volatile-allowzero-address-space)) ·
[`variables.md`](variables.md) (const-ness của con trỏ, slice copy descriptor) ·
[`values.md`](values.md#5-string-literals--unicode-code-point-literals) (kiểu string literal) ·
[`identifiers.md`](identifiers.md) (luật tên, `@` builtin) ·
[`struct.md`](struct.md#72-field--1-byte-pointer-không-cùng-địa-chỉ-có-bit-offset) (pointer field
sub-byte packed struct, tự tham chiếu `?*Node`) · [`zig-testing.md`](zig-testing.md).

## 16. Nguồn tham khảo

- [Zig Language Reference 0.17.1 — Pointers](https://ziglang.org/documentation/0.17.1/#Pointers)
- [Zig Language Reference 0.17.1 — Slices](https://ziglang.org/documentation/0.17.1/#Slices)
- [Zig Language Reference 0.17.1 — Type Coercion: Slices, Arrays and Pointers](https://ziglang.org/documentation/0.17.1/#Type-Coercion-Slices-Arrays-and-Pointers)
- [Zig Language Reference 0.17.1 — C Pointers](https://ziglang.org/documentation/0.17.1/#C-Pointers)
- [Zig Language Reference 0.17.1 — Sentinel-Terminated (Pointers/Slices/Arrays)](https://ziglang.org/documentation/0.17.1/#Sentinel-Terminated-Pointers)
- [Zig Language Reference 0.17.1 — Stricter Qualification](https://ziglang.org/documentation/0.17.1/#Type-Coercion-Stricter-Qualification)

**Ghi chú phiên bản:** xác minh trên **Zig 0.17.0** (homebrew). Tên builtin (`@intFromPtr`/
`@ptrFromInt`) và một số thông điệp lỗi là đặc thù 0.17; chạy bản khác có thể lệch — hãy đối chiếu
langref tương ứng.

---

*Tài liệu viết cho mục đích học tập; mọi đoạn trích quan trọng lấy từ nguồn chính thức có link để tự
kiểm chứng. Mọi con số (kích thước, alignment) và thông điệp lỗi mang tính minh hoạ, đo lại trên máy
đang chạy (macOS ARM64, Zig 0.17.0); trên kiến trúc/phiên bản khác có thể lệch nhưng bản chất (slice
là fat pointer 16 byte, bounds-check, sentinel, alignment sai là Illegal Behavior) là bất biến của
ngôn ngữ.*
