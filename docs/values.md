# Value trong Zig — Hướng dẫn toàn diện

> Tham chiếu tài liệu: [Zig Language Reference 0.17.1 — Values](https://ziglang.org/documentation/0.17.1/#Values).
> Kiểm chứng thực tế trên **Zig 0.17.0** (bản đang cài trong máy): mọi ví dụ đã chạy qua
> `zig test` / `zig run` / `zig build-obj`; các thông báo lỗi là lỗi thật của compiler.
> Chỗ nào tài liệu 0.17.1 khác hành vi 0.17.0, mình sẽ ghi chú rõ ở cuối.

---

## 1. "Value" nghĩa là gì trong Zig?

Trang Values của langref bao phủ **các giá trị nguyên thuỷ** — cách bạn viết và dùng dữ
liệu tầng thấp nhất:

1. **Primitive Types** — các kiểu có sẵn (`u8`, `i32`, `f64`, `bool`, `usize`…).
2. **Primitive Values** — `true`, `false`, `null`, `undefined`.
3. **String literals & Unicode code point literals** — chuỗi, ký tự, escape, UTF-8.
4. **Assignment** — `const`/`var`, ý nghĩa "bytes mà identifier trỏ tới".
5. **`undefined`** — giá trị "chưa khởi tạo".
6. **Destructuring** — tách tuple/array/vector.

(Các mục liên quan nằm ở phần khác: `Integers`, `Floats`, `Optionals`, `Comptime`.)

---

## 2. Primitive Types (cột đầy đủ từ 0.17.1)

| Kiểu | C tương đương | Ý nghĩa |
|---|---|---|
| `i8` / `i16` / `i32` / `i64` / `i128` | `int8_t`…`__int128` | số nguyên có dấu |
| `u8` / `u16` / `u32` / `u64` / `u128` | `uint8_t`…`__int128` | số nguyên không dấu |
| `isize` | `intptr_t`, `ssize_t` | số nguyên cỡ con trỏ (có dấu) |
| `usize` | `uintptr_t`, `size_t` | số nguyên cỡ con trỏ (không dấu) — dùng cho index/len |
| `c_char`…`c_ulonglong`, `c_longdouble` | `char`…`long double` | cho ABI tương thích C |
| `f16` / `f32` / `f64` / `f80` / `f128` | `_Float16`…`_Float128` | dấu phẩy động IEEE-754 |
| `bool` | `bool` | `true` hoặc `false` |
| `anyopaque` | `void` | dùng cho **con trỏ type-erased** |
| `noreturn` | (không có) | kiểu của `break`, `continue`, `return`, `unreachable`, `while (true) {}` |
| `type` | (không có) | kiểu của các kiểu |
| `anyerror` | (không có) | một error code |
| `comptime_int` | (không có) | chỉ dùng cho giá trị **comptime-known** — kiểu của integer literal |
| `comptime_float` | (không có) | chỉ dùng cho giá trị **comptime-known** — kiểu của float literal |

### Số nguyên độ rộng bit tuỳ ý

```zig
const x7: i7 = -64;        // signed 7-bit, phạm vi -64..63
const small: u3 = 0b111;   // unsigned 3-bit, max 7
// @bitSizeOf(i7) == 7; @sizeOf(i7) == 1 (đóng gói vào ít nhất 1 byte)
```

Giới hạn: bit-width tối đa là **65535**. Muốn dựng kiểu trong code dùng `@Int(.unsigned, 18)`.

### Kích thước thực tế (đã kiểm chứng trên aarch64-macos)

```zig
@sizeOf(u8) == 1;  @sizeOf(u16) == 2;  @sizeOf(u64) == 8;  @sizeOf(u128) == 16;
@sizeOf(usize) == @sizeOf(isize);      // trên máy 64-bit = 8
@sizeOf(f32) == 4;  @sizeOf(f64) == 8; @sizeOf(bool) == 1;
```

Lưu ý: `@sizeOf(anyopaque)` **không lấy được** (kiểu "uninstantiable") — chỉ dùng qua con
trỏ `*anyopaque`.

---

## 3. Primitive Values

| Tên | Kiểu | Ý nghĩa |
|---|---|---|
| `true`, `false` | `bool` | hai giá trị boolean |
| `null` | optional | gán optional về "rỗng" |
| `undefined` | bất kỳ (coerce) | "chưa có giá trị" — xem mục 6 |

```zig
const flag: bool = true;
var maybe: ?i32 = null; // optional
var uninit: i32 = undefined;
```

---

## 4. Kiểu của literal: `comptime_int` / `comptime_float`

Một đặc trưng lớn của Zig: **literal số không có kiểu cố định**. Mỗi số ghi trong code có
kiểu `comptime_int` (hoặc `comptime_float`) — kiểu này chỉ tồn tại lúc compile, "đủ lớn
để chứa giá trị". Kiểu thật chỉ được quyết định khi bạn **ép (coerce)** hoặc kết hợp với
giá trị khác.

```zig
const x = 1234;             // comptime_int
const a: i16 = 1234;        // ép sang i16
const f = 5.5;              // comptime_float
const g: f32 = 5.5;         // ép sang f32

// "fit" được kiểm lúc compile: 300 không fit u8 → compile error khi ép
const ok: u8 = 255;         // OK
// const bad: u8 = 300;     // error: expected type 'u8', found comptime_int 300
```

Nhờ vậy Zig luôn biết giá trị có vừa kiểu hay không **tại thời điểm biên dịch**, và những
phép tính trên literal không tràn (tràn literal → lỗi compile).

---

## 5. String literals & Unicode code point literals

### 5.1. Kiểu của chuỗi: `*const [N:0]u8`

```zig
const bytes = "hello";
@TypeOf(bytes) == *const [5:0]u8; // con trỏ tới array [5:0]u8 (sentinel 0)
bytes.len == 5;
bytes[5] == 0;                    // index tới sentinel trả về 0
```

- Kiểu **mã hoá cả độ dài** và việc **null-terminated** (`[5:0]`).
- **Coerce** tự do sang: slice `[]const u8`, sentinel slice `[:0]const u8`, many-item
  pointer `[*:0]const u8`.
- **Dereference** (`bytes.*`) cho array `[5:0]u8`.
- Chuỗi rỗng `""` có kiểu `*const [0:0]u8` (len 0).

### 5.2. UTF-8: byte không bị sửa

Mã nguồn Zig là UTF-8; byte trong chuỗi được giữ nguyên nghĩa UTF-8. Điểm quan trọng:

```zig
"💯".len == 4;            // len đếm BYTE, không phải số ký tự
"💯"[1] == 0x9f;          // index trả về từng byte — có thể "cắt ngang" ký tự đa byte
std.mem.eql(u8, "💯", "\xf0\x9f\x92\xaf"); // chuỗi nguồn == chuỗi escape hex
```

Chuỗi tiếng Việt giữ nguyên UTF-8: `"xin chào"` có `len == 9` (à chiếm 2 byte).

### 5.3. Unicode code point literal (character literal)

```zig
'e'               // comptime_int, giá trị 101
'\x65' == 'e'     // escape hex
'\u{1f4a9}' == 128169
'💯' == 128175
const cp: u32 = 'A';   // 65 — dùng như số
@TypeOf('e') == comptime_int
```

### 5.4. Bảng escape sequences (0.17.1)

| Escape | Nghĩa |
|---|---|
| `\n` | newline |
| `\r` | carriage return |
| `\t` | tab |
| `\\` | backslash |
| `\'` | single quote |
| `\"` | double quote |
| `\xNN` | **1 byte** hex (đủ 2 chữ số) |
| `\u{NNNNNN}` | Unicode **scalar value** (1+ chữ số hex), mã hoá UTF-8; max `0x10ffff` |

Đã kiểm chứng:

- `\xG1` → lỗi `expected hex digit, found 'G'` (bắt buộc đủ 2 chữ hex).
- `'\u{110000}'` → lỗi `unicode escape does not correspond to a valid unicode scalar value`.
- `"\u{d800}"` (surrogate trong **string**) → lỗi (không encode UTF-8 được).
- `'\u{d800}'` trong **character literal** → **vẫn chấp nhận** = 0xd800 (lỏng hơn wording
  "scalar value" của doc — ghi chú ở mục 9).

### 5.5. Nhúng byte không phải UTF-8 bằng `\xNN`

```zig
const s = "\xff\xfe";          // chuỗi có byte không hợp lệ UTF-8
s[1] == 0xfe;                  // index lấy byte thô
```

### 5.6. Multiline string literal `\\`

```zig
const text =
    \\Dòng 1
    \\Dòng 2
    \\  dòng 3 có indent
;
// text == "Dòng 1\nDòng 2\n  dòng 3 có indent"
```

- Mỗi dòng mở đầu bằng `\\` (giống comment, đi tới hết dòng); **không có escape**.
- Dòng KẾ TIẾP cũng mở đầu bằng `\\` thì ghép thêm `\n`.
- Dòng không bắt đầu bằng `\\` → literal **kết thúc** ở cuối dòng hiện tại.
- Dùng khi nhúng C/HTML/SQL…; tham khảo `@embedFile` cho file ngoài.

---

## 6. Assignment: `const` vs `var` và bản chất "bytes"

Quy tắc ngân từ doc:

> `const` applies to **all of the bytes that the identifier immediately addresses**.
> Pointers have their own const-ness.

```zig
const x = 1234;        // không thể gán lại: x += 1 → "cannot assign to constant"
var y: i32 = 5678;     // có thể sửa: y += 1 → 5679
```

- `var` **bắt buộc phải khởi tạo** (với một giá trị hoặc `undefined`); `var x: i32;`
  → lỗi `expected '=', found ';'`.
- `const` bảo vệ **bytes mà identifier trực tiếp trỏ tới**:

```zig
const arr = [4]u8{ 1, 2, 3, 4 };
// arr[0] = 9        // ERROR: cannot assign to constant (byte bị const)
const p: *const [4]u8 = &arr;  // OK: con trỏ const

var arr2 = [4]u8{ 1, 2, 3, 4 };
const q: *[4]u8 = &arr2;       // var → được con trỏ mutable
q.*[0] = 99;                   // OK
```

Tức là `const Foo` không có nghĩa "mọi thứ bên trong bất biến" — nó nghĩa là "không thể
ghi qua identifier này". Con trỏ/slice có `const` riêng của chúng (`*const` vs `*`,
`[]const u8` vs `[]u8`).

---

## 7. `undefined`

`undefined` là primitive value dùng để **khai báo biến nhưng chưa quan tâm giá trị**:

```zig
var x: i32 = undefined;
x = 1; // ghi đè sau
```

- Coerce được sang **mọi kiểu**; sau khi coerce **không thể phát hiện** giá trị còn
  `undefined` hay không.
- Nghĩa dịch ra: *"Không phải giá trị có nghĩa. Dùng giá trị này là bug. Nó sẽ không được
  dùng, hoặc bị ghi đè."*
- **0xaa fill** (đã kiểm chứng):

```zig
var buf: [8]u8 = undefined;
// Debug  (zig run)                  → aa aa aa aa aa aa aa aa
// ReleaseSafe (-O ReleaseSafe)      → aa aa aa aa aa aa aa aa
// ReleaseFast (-O ReleaseFast)      → 00 00 … (không điền, thường là 0)
```

Đây là biện pháp giúp bắt bug sớm / dễ nhìn trong debugger — **không phải ngữ nghĩa ngôn
ngữ**, không nên code dựa vào nó.

---

## 8. Destructuring — tách tuple / array / vector

Tách **toàn bộ các phần tử** của indexable aggregate (tuple/array/vector) vào các biến:

```zig
var x: u32 = undefined;
var y: u32 = undefined;
var z: u32 = undefined;

const tuple = .{ 1, 2, 3 };
x, y, z = tuple;                 // gán cho biến có sẵn

const array = [_]u32{ 4, 5, 6 };
x, y, z = array;

const vector: @Vector(3, u32) = .{ 7, 8, 9 };
x, y, z = vector;
```

### Quy tắc đã kiểm chứng

- Chỉ xuất hiện **trong block** — ở namespace scope là compile error
  (`expected ';' after declaration`).
- LHS là danh sách cách dấu phẩy; mỗi phần có thể là **lvalue** (biến `var` có sẵn) hoặc
  **khai báo mới** `var x: T` / `const x`;
- Bỏ giá trị bằng **`_`**: `_, kept, _ = tuple;`
- **Số phần tử khớp chính xác** với LHS (dư/thiếu → compile error).
- Có thể **`comptime`** đứng trước destructure → toàn bộ đánh giá lúc compile,
  `var` thành `comptime var`.
- **Slice runtime KHÔNG destructure được** (độ dài không biết trước): muốn destructure
  phải deref về array trước (`slice[0..3].*`).

Ví dụ:

```zig
const t = .{ 10, 20, 30 };
comptime _, const mid, _ = t;   // mid == 20, tính tại compile
```

---

## 9. Ghi chú chênh lệch 0.17.1 (doc) vs 0.17.0 (compiler đang cài)

- Doc 0.17.1 mô tả `\u{...}` là "Unicode **scalar value** UTF-8 encoded" — ngụ ý các
  **surrogate** (U+D800–U+DFFF) không hợp lệ.
- Compiler 0.17.0: string literal `"\u{d800}"` **lỗi** (đúng doc), nhưng character literal
  `'\u{d800}'` **vẫn chấp nhận** (= 0xd800, như tài liệu master cũ từng ghi "can be used
  for surrogate code points"). Nếu nâng cấp/siết chặt về sau, hãy tránh `'\u{d800}'`.

---

## 10. Pitfalls thường gặp

1. `len` của chuỗi là **số byte**, không phải số ký tự — cắt `s[i..j]` theo byte có thể
   "cắt ngang" ký tự đa byte (dùng `std.unicode.*` nếu cần xử lý đúng code point).
2. `\x` **luôn 2 chữ số hex**, biểu diễn 1 byte; `\u{}` biểu diễn cả code point (nhiều byte).
3. Literal số là `comptime_int`: gán vào kiểu nhỏ mà không fit → compile error; dùng
   `@intCast` khi cần chuyển chủ động.
4. Dùng `undefined` cho `var` là OK; nhưng đọc giá trị `undefined` là hành vi nguy hiểm —
   trong Debug hay gặp toàn byte `0xaa`.
5. `const` không khiến struct/array bên trong bất biến hoàn toàn — chỉ vô hiệu hoá ghi qua
   identifier đó; con trỏ cần `const` riêng.

---

## 11. Khác biệt nhanh với Rust

| Vấn đề | Zig | Rust |
|---|---|---|
| Kiểu của integer literal | `comptime_int` (coerce theo ngữ cảnh, check fit lúc compile) | `i32` mặc định + suy luận |
| Chuỗi | `*const [N:0]u8` (sentinel), tự coerce slice/pointer | `&'static str` |
| Ký tự | code point literal = `comptime_int` (số) | `char` (kiểu riêng) |
| Khởi tạo biến | `var` bắt buộc có giá trị/`undefined`; `undefined` tường minh | `let mut`; không có `undefined` (trừ MaybeUninit) |
| `const` | "bytes identifier trỏ tới"; pointer có const riêng | const bất biến toàn phần |
| Destructuring | tuple/array/vector, đếm phần tử khớp chính xác | pattern match mạnh hơn (nested, enum) |

---

## Tài liệu tham khảo

- [Zig Language Reference 0.17.1 — Values](https://ziglang.org/documentation/0.17.1/#Values)
- [Zig Language Reference 0.17.1 — Primitive Types](https://ziglang.org/documentation/0.17.1/#Primitive-Types)
- [Zig Language Reference — Integers](https://ziglang.org/documentation/0.17.1/#Integers)
- [Zig Language Reference — Comptime](https://ziglang.org/documentation/0.17.1/#comptime)
- Zig 0.17.0 release notes (đã dùng để đối chiếu hành vi compiler)
