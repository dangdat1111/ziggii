# Integers & Floats trong Zig — và các toán tử số học/bit

> Phiên bản xác minh: **Zig 0.17.0** (`zig version` → 0.17.0), đối chiếu với
> [Zig Language Reference 0.17.1 — Integers](https://ziglang.org/documentation/0.17.1/#Integers),
> [0.17.1 — Floats](https://ziglang.org/documentation/0.17.1/#Floats),
> [0.17.1 — Operators](https://ziglang.org/documentation/0.17.1/#Operators),
> [0.17.1 — Illegal Behavior](https://ziglang.org/documentation/0.17.1/#Illegal-Behavior) và
> [0.17.1 — Builtin Functions](https://ziglang.org/documentation/0.17.1/#Builtin-Functions).
> Toàn bộ con số và thông điệp lỗi dưới đây **đã chạy thật** trên Zig 0.17.0 (macOS ARM64):
> bộ test dương 17/17 (số nguyên) + 9/9 (số thực), 8 probe lỗi âm (có output gốc), và demo
> float mode `strict`/`optimized` chạy đúng 2 kết quả khác nhau như langref.

---

## Mục lục

1. [Cốt lõi: hai "thế giới" số — comptime & runtime](#1-cốt-lõi-hai-thế-giới-số--comptime--runtime)
2. [Integers: `iN`/`uN` và arbitrary bit-width](#2-integers-inun-và-arbitrary-bit-width)
3. [Integer literals](#3-integer-literals)
4. [`comptime_int` — kiểu của literal số](#4-comptime_int--kiểu-của-literal-số)
5. [Runtime integers & safety-checked Illegal Behavior](#5-runtime-integers--safety-checked-illegal-behavior)
6. [Các toán tử số (từ Table of Operators)](#6-các-toán-tử-số-từ-table-of-operators)
   - [6.1 Số học cơ bản `+` `-` `*` `/`](#61-số-học-cơ-bản-----)
   - [6.2 Wrapping `+% -% *% -%` và Saturating `+| -| *| <<|`](#62-wrapping----và-saturating----)
   - [6.3 Chia & dư: `/`, `%`, `@divTrunc/@divFloor/@divExact/@rem/@mod`](#63-chia--dư---divtruncdivfloordivexactremmod)
   - [6.4 Dịch bit `<<` `>>`, `@shlExact/@shrExact`](#64-dịch-bit---shlexactshrexact)
   - [6.5 Bitwise `&` `|` `^` `~`](#65-bitwise----)
   - [6.6 So sánh & logic `== != < > <= >=`, `and or !`](#66-so-sánh--logic-----and-or-)
   - [6.7 Bắt overflow một cách "có kiểm soát"](#67-bắt-overflow-một-cách-có-kiểm-soát)
7. [Floats: `f16 f32 f64 f80 f128 c_longdouble`](#7-floats-f16-f32-f64-f80-f128-clongdouble)
8. [Float literals & `comptime_float`](#8-float-literals--comptimefloat)
9. [NaN / Infinity — bắt buộc dùng `std.math`](#9-nan--infinity--bắt-buộc-dùng-stdmath)
10. [Float mode: `.strict` (mặc định) vs `.optimized`](#10-float-mode-strict-mặc-định-vs-optimized)
11. [Cast số: `@intCast @truncate @floatCast @floatFromInt @intFromFloat @intFromBool @backingInt/@fromBackingInt`](#11-cast-số-intcast-truncate-floatcast-floatfromint-intfromfloat-intfrombool-backingintfrombackingint)
12. [Bảng lỗi thường gặp (probe thật trên 0.17.0)](#12-bảng-lỗi-thường-gặp-probe-thật-trên-0170)
13. [Tổng kết nhanh](#13-tổng-kết-nhanh)
14. [Liên hệ các tài liệu khác](#14-liên-hệ-các-tài-liệu-khác)
15. [Nguồn tham khảo](#15-nguồn-tham-khảo)

---

## 1. Cốt lõi: hai "thế giới" số — comptime & runtime

Muốn hiểu số trong Zig, hãy nhớ một sự phân tầng tuyệt đối quan trọng (mở đầu mục
**Integers** của langref 0.17.1):

> *"Integer literals have **no size limitation**, and if any Illegal Behavior occurs, the compiler
> catches it."* — *"However, once an integer value is no longer known at compile-time, it must have a
> **known size**, and is vulnerable to **safety-checked** Illegal Behavior."*

Dịch: **số `comptime` không có giới hạn kích thước** (literal bao nhiêu bit cũng được), mọi hành vi
bất hợp lệ bị compiler bắt ngay lúc biên dịch. Còn **số runtime phải có kích thước cố định** và sẽ bị
theo dõi bởi *safety checks* (panic khi overflow / chia cho 0 ở build mode Debug/Safe).

Ví dụ kinh điển từ langref — hai tham số `a`, `b` chỉ biết giá trị ở runtime:

```zig
fn divide(a: i32, b: i32) i32 {
    return a / b; // dễ dính cả Integer Overflow lẫn Division by Zero
}
```

Vì `a/b` là toán tử mặc định nên vừa có thể tràn, vừa có thể chia cho 0 — và Zig không "lờ" đi: ở chế
độ an toàn nó panic (mục 5, 6.3).

> 💡 Đây gọi là **Illegal Behavior (hành vi bất hợp lệ)** — viết hoa, mang nghĩa kỹ thuật: Zig *định
> nghĩa* nó là lỗi (có safety check khi bật), không phải *undefined behavior* kiểu C. Xem
> [langref — Illegal Behavior](https://ziglang.org/documentation/0.17.1/#Illegal-Behavior).

---

## 2. Integers: `iN`/`uN` và arbitrary bit-width

Kiểu số nguyên trong Zig: **`iN`** (có dấu) / **`uN`** (không dấu), với **`N` từ 1 tới 65535** —
*arbitrary bit-width*, không bắt buộc là bội của 8:

> *"Zig supports **arbitrary bit-width integers**, referenced by using an identifier of `i` or `u`
> followed by digits. For example, the identifier `i7` refers to a signed 7-bit integer. The maximum
> allowed bit-width of an integer type is **65535**. For signed integer types, Zig uses a **two's
> complement** representation."*

- Các kiểu đặc biệt: `usize`/`isize` (theo kích thước con trỏ), `comptime_int` (mục 4); nhóm đầy đủ
  trong [values.md](values.md#2-primitive-types-cột-đầy-đủ-từ-0171).

### 2.1 Bảng đo thật (macOS ARM64, Zig 0.17.0)

| Kiểu | `@bitSizeOf` | `@sizeOf` (byte) | Ghi chú |
|---|---|---|---|
| `i7` / `u7` | 7 | 1 | bit-size 7 nhưng chiếm tròn 1 byte |
| `i24` | 24 | **4** | ABI làm tròn lên alignment 4 byte |
| `u128` | 128 | 16 | |
| `usize` | 64 | 8 | bằng kích thước con trỏ |
| `bool` | 1 | 1 | dùng làm "số 0/1" được |
| `f64` | 64 | 8 | |
| `f80` | 80 | 16 | AArch64 lưu ở 16 byte nhưng độ chính xác 80 bit |
| `c_longdouble` | 64 | 8 | trên AArch64 mac = `f64` |

> ⚠️ **`@bitSizeOf` ≠ `@sizeOf`.** `@sizeOf` = số byte thật khi lưu trong bộ nhớ (có thể có padding,
> phụ thuộc target); `@bitSizeOf` = số bit khi type đó là field của một packed struct/union. Muốn số
> bit "sạch", langref khuyên dùng `@sizeOf(T)` **hay** `@typeInfo(T).int.bits`. Cả hai builtin trả `0`
> cho `comptime_int`/`type` (kiểu không tồn tại ở runtime).

Bằng `@Int` ta có thể dựng kiểu theo signedness + bit:

```zig
const a = @Int(.unsigned, 7); // == u7
const b = @Int(.signed, 18);  // == i18
// @Int(comptime signedness: std.lang.Signedness, comptime bits: u16) type
// → bits là u16, tương ứng giới hạn 65535 bit
```

Test đã chạy: `@Int(.unsigned, 7) == u7` và `@Int(.signed, 18) == i18` đều OK.

### 2.2 Two's complement

Số có dấu lưu dạng **bù hai** (two's complement): bit cao nhất là bit dấu. Kiểm chứng:

```zig
const bits: u8 = @bitCast(@as(i8, -1));
try expectEqual(@as(u8, 0xff), bits); // -1 trong i8 = 0xff
```

Hệ quả: `-@as(i8, 1) == @as(i8, -1)`, và wrapping `+%` thực chất là **cộng theo vòng tròn trên bù
hai** (xem 6.2).

---

## 3. Integer literals

Từ langref — mọi literal đều có thể ghi nén dấu gạch dưới giữa hai chữ số:

```zig
const decimal_int = 98222;
const hex_int = 0xff;          // thập lục phân
const octal_int = 0o755;       // bát phân
const binary_int = 0b11110000; // nhị phân
const one_billion = 1_000_000_000;
const binary_mask = 0b1_1111_1111;
const big_address = 0xFF80_0000_0000_0000; // lớn cỡ nào cũng OK ở comptime
```

Literal số nguyên có kiểu `comptime_int` (mục 4) — tức là **chưa có kích thước cố định** cho tới khi
được ép sang kiểu `iN`/`uN` cụ thể.

---

## 4. `comptime_int` — kiểu của literal số

`comptime_int` là **kiểu của mọi literal integer** và của mọi giá trị số tính được lúc biên dịch. Nó:

- **Không giới hạn kích thước**: `const huge = 1 << 100;` hợp lệ, không "tràn".
- **Chỉ tồn tại ở compile-time**: không khai báo biến *runtime* mang kiểu này được — lỗi nổi tiếng:
  ```zig
  var x = 1; // ❌
  ```
  ```
  error: variable of type 'comptime_int' must be const or comptime
      var x = 1;
          ^
  note: to modify this variable at runtime, it must be given an explicit fixed-size number type
  ```
  → Sửa: `const x = 1;` (giữ comptime) hoặc `var x: u8 = 1;` (ép sang kích thước cố định).
  (Chi tiết trong [values.md](values.md#4-kiểu-của-literal-comptimeint--comptimefloat) và
  [variables.md](variables.md#24-var-với-giá-trị-comptime-không-cần-kiểu-tường-minh).)

- **Coerce tự do sang kiểu kích thước cố định** khi giá trị **nằm vừa miền** của kiểu đích — vì
  con số đã biết lúc compile nên compiler tự kiểm tra:

  ```zig
  const x: u8 = 255;     // ✅ 255 vừa khớp u8
  const a: u64 = 255;
  const y: u8 = a;       // ✅ comptime-known, coerce được sang kiểu nhỏ hơn
  // const bad: u8 = 300; // ❌ probe âm #1 — xem mục 12
  ```

- Khi trộn với một giá trị kiểu cố định trong biểu thức, `comptime_int` **hoà vào kiểu kia** (Peer
  Type Resolution — mục 11).

> 💡 `comptime_int` không có địa chỉ, không chiếm byte runtime; nó là "con số trong đầu compiler".
> Xem thêm [comptime.md](comptime.md) và [values.md](values.md#4-kiểu-của-literal-comptimeint--comptimefloat).

---

## 5. Runtime integers & safety-checked Illegal Behavior

Khi một số **không còn biết ở compile-time**, nó bắt buộc mang kiểu có kích thước cố định (`iN`/`uN`)
và — quan trọng — mọi phép toán mặc định trên nó **có thể vi phạm quy tắc**:

| Hành vi bất hợp lệ | Toán tử | Chế độ | Thông điệp panic thật (0.17.0) |
|---|---|---|---|
| Integer Overflow | `+` `-` `-`(neg) `*` `/` | giữ nguyên → panic ở Debug/Safe | `thread 147605 panic: integer overflow` |
| Division by Zero | `/` | giữ nguyên → panic | `thread 147705 panic: division by zero` |
| Remainder by Zero | `%` | giữ nguyên → panic | `panic: division by zero` *(langref 0.17.1 — chưa probe lại trên máy này)* |
| Shift mất bit | `<<` (dùng `@shlExact`) | panic | `thread 147928 panic: left shift overflowed bits` |
| Cast tràn | `@intCast` | panic | `thread ... panic: integer does not fit in destination type` |
| Float→Int ngoài khoảng | `@intFromFloat` | panic | `panic: integer part of floating point value out of bounds` |

Minh hoạ runtime overflow (đã chạy thật, build-exe rồi chạy binary):

```zig
const std = @import("std");
pub fn main() void {
    var byte: u8 = 255;
    _ = &byte;          // bảo compiler: coi như giá trị runtime
    byte += 1;          // 255 + 1 tràn u8
    std.debug.print("value: {}\n", .{byte});
}
```
```
thread 147605 panic: integer overflow
.../neg_runtime_overflow.zig:6:10: 0x100c911c3 in main (neg_runtime_overflow)
    byte += 1;
         ^
```

Còn khi **tính ở comptime** (mọi thứ biết trước) thì compiler **bắt ngay tại biên dịch**:

```zig
comptime {
    var byte: u8 = 255;
    byte += 1;
}
```
```
error: overflow of integer type 'u8' with value '256'
    byte += 1;
    ~~~~~^~~~
```

> 💡 Vì vậy Zig cho **toán tử mặc định = an toàn** (bắt lỗi), và đưa ra **bộ toán tử thay thế** có
> ngữ nghĩa xác định rõ — wrapping `+%`, saturating `+|` — để bạn chọn khi *muốn* vòng/ngắt mà không
> panic. Đó là chủ đề mục 6.

---

## 6. Các toán tử số (từ Table of Operators)

Langref khẳng định: **không có operator overloading** — mỗi ký hiệu có đúng một nghĩa trong bảng:

> *"There is no operator overloading. When you see an operator in Zig, you know that it is doing
> something from this table, and nothing else."*

Dưới đây là phần toán tử **số & bit** lọc từ [Table of Operators](https://ziglang.org/documentation/0.17.1/#Table-of-Operators)
(dịch gọn). (Các toán tử không phải số như `++`, `**`… bàn ở cuối mục này.)

| Cú pháp | Tên | Kiểu | Đặc điểm chính (0.17.1) |
|---|---|---|---|
| `a + b` / `a += b` | Addition | Int, Float | có thể overflow; Peer Type Resolution |
| `a +% b` | Wrapping Addition | Int | cộng vòng bù hai |
| `a +| b` | Saturating Addition | Int | kẹt tại min/max |
| `a - b` / `a -= b` | Subtraction | Int, Float | có thể overflow |
| `a -% b` | Wrapping Subtraction | Int | trừ vòng |
| `a -| b` | Saturating Subtraction | Int | kẹt |
| `-a` | Negation | Int, Float | có thể overflow (vd `-minInt(iN)`) |
| `-%a` | Wrapping Negation | Int | vòng |
| `a * b` / `a *= b` | Multiplication | Int, Float | có thể overflow |
| `a *% b` | Wrapping Multiplication | Int | vòng |
| `a *| b` | Saturating Multiplication | Int | kẹt |
| `a / b` / `a /= b` | Division | Int, Float | overflow + division by zero; dấu & dương phải comptime-known (xem 6.3) |
| `a % b` / `a %= b` | Remainder Division | Int, Float | division by zero; dấu & dương phải comptime-known |
| `a << b` | Bit Shift Left | Int | `b` comptime-known hoặc kiểu `log2(bit(a))` |
| `a <<| b` | Saturating Shift Left | Int | dịch nhưng kẹt |
| `a >> b` | Bit Shift Right | Int | unsigned = logical, signed = arithmetic |
| `a & b` / `a &= b` | Bitwise And | Int | |
| `a \| b` / `a \|= b` | Bitwise Or | Int | |
| `a ^ b` / `a ^= b` | Bitwise Xor | Int | |
| `~a` | Bitwise Not | Int | đảo toàn bộ bit |
| `==` `!=` `<` `>` `<=` `>=` | So sánh | Int, Float, bool… | Peer Type Resolution |
| `and` / `or` / `!` | Logical And/Or/Not | bool | `and`/`or` ngắn mạch (short-circuit) |

> ⚠️ Lưu ý hai ký hiệu dễ nhầm: **`++` là toán nối mảng** (array concatenation, yêu cầu hai vế có độ
> dài comptime-known), **không phải** toán tử số. Và **Zig KHÔNG có toán `**` (luỹ thừa)** — muốn luỹ
> thừa dùng `std.math.pow`. Toán `||` là merge **error set**, không phải "or" số.

### 6.1 Số học cơ bản `+` `-` `*` `/`

- `+` `-` `*` và phép `-` (negation) của số **có dấu** đều có thể **overflow** → panic ở chế độ an toàn,
  hoặc bị bắt ở comptime. `iN`/`uN` không "lớn dần tràn đi đâu được", giống C hay mọi ngôn ngữ — điểm
  khác là Zig *báo chứ không thầm lặng*.
- `/` trên số nguyên: kết quả **làm tròn về 0** (truncated), và dính cả overflow lẫn division-by-zero.
- Với toán `/` và `%`, langref yêu cầu:

> *"Signed integer operands must be **comptime-known and positive**. In other cases, use `@divTrunc`,
> `@divFloor`, `@divCeil`, or `@divExact` instead."* (cho `/`)
> *"Signed or floating-point operands must be **comptime-known and positive**. In other cases, use
> `@rem` or `@mod` instead."* (cho `%`)

→ Đây là **quy tắc thú vị nhất** khi học Zig số học: toán tử `/` và `%` **cố ý hạn chế** để ép bạn
dùng hàm tường minh cho trường hợp dấu không xác định lúc compile (chi tiết 6.3).

### 6.2 Wrapping `+% -% *% -%` và Saturating `+| -| *| <<|`

Langref:

> *"Operators such as `+` and `-` cause Illegal Behavior on integer overflow. **Alternative operators
> are provided** for wrapping and saturating arithmetic on all targets. `+%` and `-%` perform
> **wrapping** arithmetic while `+|` and `-|` perform **saturating** arithmetic."*

- **Wrapping**: cộng/trừ/nhân **theo vòng tròn bù hai** — đúng thứ phần cứng làm, không bao giờ panic.
- **Saturating**: kẹt tại min/max của kiểu, không bao giờ panic.

Bảng ví dụ (tất cả đã chạy OK trong `f1_ints.zig`):

```zig
// WRAPPING — vòng theo bù hai
try expectEqual(@as(u8, 0),   @as(u8, 255) +% 1);      // 256 → 0
try expectEqual(@as(u8, 255), @as(u8, 0) -% 1);        // -1 → 255
try expectEqual(@as(u8, 144), @as(u8, 200) *% 2);      // 400 % 256 = 144
try expectEqual(@as(i8, -128), -%@as(i8, -128));       // -(-128) vòng lại -128
try expectEqual(@as(u32, 0),   @as(u32, 0xffffffff) +% 1); // langref example

// SATURATING — kẹt tại biên
try expectEqual(@as(u8, 255), @as(u8, 255) +| 1);      // kẹt max
try expectEqual(@as(u32, 0),  @as(u32, 0) -| 1);       // kẹt min
try expectEqual(@as(u8, 255), @as(u8, 200) *| 2);      // kẹt max
try expectEqual(@as(u8, 255), @as(u8, 1) <<| 8);       // dịch trái saturating
```

Các biến thể gán ghép cũng tồn tại: `+=`, `+%=`, `+|=`, `-=`, `-%=`, `-|=`, `*=`, `*%=`, `*|=`,
`<<=`, `<<|=`, `>>=`, `&=`, `|=`, `^=`.

### 6.3 Chia & dư: `/`, `%`, `@divTrunc/@divFloor/@divExact/@rem/@mod`

Đây là chỗ dễ nhầm nhất, cần nói rõ **hai khái niệm dư khác nhau**:

| Builtin | Nghĩa | Dấu của kết quả | Ví dụ `(-7) op 3` |
|---|---|---|---|
| `@divTrunc(a, b)` | chia, **làm tròn về 0** | dấu theo thương | `-2` |
| `@divFloor(a, b)` | chia, **làm tròn xuống** (floor) | dấu theo mẫu số | `-3` |
| `@divExact(a, b)` | chia **chính xác**, lẻ là Illegal Behavior | — | lỗi nếu `7/3` |
| `@rem(a, b)` | **remainder** — dấu theo **số bị chia** | như `-7` → `-1` | `-1` |
| `@mod(a, b)` | **modulo** — dấu theo **số chia** | như `3` → `2` | `2` |
| `/` `%` | chỉ dùng khi dương & comptime-known | — | dùng 2 cái trên |

```zig
try expectEqual(@as(i32, -2), @divTrunc(@as(i32, -7), @as(i32, 3))); // về 0
try expectEqual(@as(i32, -3), @divFloor(@as(i32, -7), @as(i32, 3))); // floor
try expectEqual(@as(i32, 2),  @divExact(@as(i32, 8),  @as(i32, 4))); // phải chia hết

// % — cả hai vế comptime-known & DƯƠNG mới được dùng
try expectEqual(@as(i32, 1), @as(i32, 10) % @as(i32, 3));
// dấu: @rem theo số bị chia (-7 → -1), @mod theo số chia (+3 → 2)
try expectEqual(@as(i32, -1), @rem(@as(i32, -7), @as(i32, 3)));
try expectEqual(@as(i32, 2),  @mod(@as(i32, -7), @as(i32, 3)));
```

> 💡 Cách nhớ: **`@rem` = remainder (phép dư của phép chia truncated)** — dấu cùng số bị chia.
> **`@mod` = modulo (phần dư của phép chia floor)** — dấu cùng số chia, luôn trả về giá trị "âm nhẹ
> nhất" trong khoảng `[0, |b|)`. Hai đại lượng này chỉ trùng khi cả hai vế cùng dấu hoặc chia hết.
> Lý do `x % y` bị hạn chế: một vế dấu tuỳ ý thì `%` không xác định theo nghĩa nào — Zig bắt bạn chọn.

`@divExact` nhiều thứ hơn mức cần thiết cũng là Illegal Behavior — ngược lại, `@rem`/`@mod`/`@divTrunc`
cho phép dấu lẫn lộn tuỳ ý (an toàn). (Xem thêm mục **Exact Division** trong langref Illegal Behavior.)

### 6.4 Dịch bit `<<` `>>`, `@shlExact/@shrExact`

- `a << b` **dịch trái**, chèn 0 vào bên phải. Khi dịch, các bit tràn ra **ngoài độ rộng của `a` sẽ bị
  mất** — nếu muốn bắt chuyện này, dùng `@shlExact` (panic nếu mất bit) hoặc `@shlWithOverflow`.
- Điều kiện của `b`: *"`b` must be **comptime-known or have a type with `log2` number of bits as `a`."*
  Tức là với `u8` (8 bit) thì shift-amount phải kiểu `u3` (= log2(8)); với `u64` là `u6`…

```zig
try expectEqual(@as(u8, 0b1000), @as(u8, 0b0001) << @as(u3, 3)); // u3 = log2(8)
try expectEqual(@as(u8, 0b101),  @as(u8, 0b1010) >> @as(u1, 1)); // dịch phải LOGICAL (unsigned)
try expectEqual(@as(i8, -4),     @as(i8, -8) >> @as(u3, 1));    // dịch phải ARITHMETIC (signed)
```

- `a >> b` **dịch phải**; langref quy định điểm khác nhau tinh tế:

> *"When LHS is unsigned, performs a **logical shift**, inserting zeroes at the most-significant bit.
> When LHS is signed, performs an **arithmetic shift**, inserting ones at the most-significant bit if
> and only if the most significant bit is one."*

→ Với `u8`: `0b1010 >> 1 == 0b101`; với `i8`: `-8 >> 1` giữ dấu → `-4`.

- Probe âm `@shlExact` (0.17.0): `@shlExact(@as(u8, 0b01010101), 2)` ở runtime → mất 2 bit:
  ```
  thread 147928 panic: left shift overflowed bits
  ```
- Với `comptime_int` thì dịch bao nhiêu bit cũng OK vì không có độ rộng cố định:
  `@as(comptime_int, 0b1) << 8 == 0b100000000`.

### 6.5 Bitwise `&` `|` `^` `~`

Đúng như tên gọi, trên từng bit, áp dụng cho integer:

```zig
try expectEqual(@as(u8, 0b001), @as(u8, 0b011) & @as(u8, 0b101)); // And
try expectEqual(@as(u8, 0b110), @as(u8, 0b010) | @as(u8, 0b100)); // Or
try expectEqual(@as(u8, 0b110), @as(u8, 0b011) ^ @as(u8, 0b101)); // Xor
try expectEqual(@as(u8, 0b01010000), ~@as(u8, 0b10101111));      // Not
```

> 💡 `~a` (bitwise not) đảo **mọi bit** — `~@as(u8, 0)` = `0b11111111` = 255. Cùng shifting, đây là
> hạt nhân bù hai: **`-x == ~x +% 1`** (đã test: `~@as(u8, 1) +% 1 == 0b11111111` = -1 khi wrap;
> `~@as(u8, 0) +% 1 == 0` = -0).

### 6.6 So sánh & logic `== != < > <= >=`, `and or !`

- So sánh trên Int/Float/bool trả về `bool`; gọi **Peer Type Resolution** cho hai vế (mục 11).
- `and`/`or` là toán logic trên `bool`, có **short-circuit**: `a and b` chỉ đánh giá `b` khi `a == true`
  (và `a or b` chỉ đánh giá `b` khi `a == false`).
- `!a` là boolean not: `!false == true`.

```zig
try expect((false and true) == false); // langref example
try expect((false or true) == true);
```

### 6.7 Bắt overflow một cách "có kiểm soát"

Khi bạn muốn lỗi tràn thành **giá trị có thể xử lý** thay vì panic/compile-error, có 3 tầng:

**Tầng 1 — Builtin overflow tuplet** (`@addWithOverflow`, `@subWithOverflow`, `@mulWithOverflow`,
`@shlWithOverflow`). Trả về **tuple** `{T, u1}`:

> *"These builtins return a tuple containing whether there was an overflow (as a `u1`) and the possibly
> overflowed bits of the operation."*

```zig
const ov = @addWithOverflow(@as(u8, 255), @as(u8, 10));
ov[0] == 9;   // phần bị wrap
ov[1] == 1;   // u1: có overflow?
// tuple này có fields: .@0 cho bits bị wrap, .@1 cho cờ overflow
```

**Tầng 2 — hàm `std.math` trả error** (`std.math.add/sub/mul/divTrunc/divFloor/divCeil/divExact/shl`).
Đã chạy thật:

```zig
const r = std.math.add(u8, byte, 1);
if (r) |v| { ... } else |err| {
    print("unable to add one: {s}\n", .{@errorName(err)}); // → "Overflow"
}
```
```
unable to add one: Overflow
```

**Tầng 3 — wrapping/saturating** (`+%`/`+|`…) như 6.2 — chọn "nghĩa đã định" thay vì lỗi.

---

## 7. Floats: `f16 f32 f64 f80 f128 c_longdouble`

Zig có 6 kiểu float (langref, mục Floats):

> - `f16` — IEEE-754-2008 **binary16**
> - `f32` — IEEE-754-2008 **binary32**
> - `f64` — IEEE-754-2008 **binary64**
> - `f80` — IEEE-754-2008 **80-bit extended precision**
> - `f128` — IEEE-754-2008 **binary128**
> - `c_longdouble` — khớp `long double` theo C ABI của target

Đo thật trên macOS ARM64 (Zig 0.17.0): `f16=2B`, `f32=4B`, `f64=8B`, `f128=16B`,
`f80: bitSize=80, sizeOf=16` (AArch64 cất 16 byte nhưng dùng đủ 80 bit chính xác),
`c_longdouble=8B` (trên AArch64 mac nó là `f64`).

- Mọi kiểu float đều tuân **IEEE-754** ở mode mặc định `.strict` (mục 10).
- Float **không** bị "số học phải kiểm soát" kiểu integer: cộng `f32` lớn tràn thành `+inf` **không
  panic** (semantics IEEE) — nếu cần, tự kiểm bằng `std.math.isFinite`.
- So sánh float cẩn thận với NaN (NaN != chính nó) — xem mục 9.

---

## 8. Float literals & `comptime_float`

Langref mở đầu mục Float Literals:

> *"Float literals have type `comptime_float` which is guaranteed to have **the same precision and
> operations of the largest other floating point type**, which is `f128`."*

→ `comptime_float` (kiểu của literal float) có độ chính xác không dưới `f128`, và:

> *"Float literals coerce to **any floating point type**, and to **any integer type when there is no
> fractional component**."*

```zig
const floating_point = 123.0E+77;      // dạng E, dấu phẩy động
const another_float = 123.0;
const hex_floating_point = 0x103.70p-5; // hex float: phần nguyên.Phần thập phân p-5
const another_hex_float = 0x103.70;
const yet_another_hex_float = 0x103.70P-5;

const lightspeed = 299_792_458.000_000; // underscore tách chữ số
const nanosecond = 0.000_000_001;
const more_hex = 0x1234_5678.9ABC_CDEFp-10;

const small: f16 = 1.5;  // literal coerce sang mọi float
const eight: u8 = 100.0; // literal KHÔNG phần thập phân coerce sang integer
```

Đo thật: `@TypeOf(0.5) == comptime_float`; mọi literal trên đều biên dịch & assert đúng giá trị.

> ⚠️ Literal như `0.5` chưa có kiểu runtime; nó "có chất" chỉ khi nằm trong ngữ cảnh ép kiểu (khai báo
> `const x: T = ...`, tham số hàm, `@as`) hoặc peer resolution — lý do `@as(f32, ...)` quen thuộc đến vậy.

---

## 9. NaN / Infinity — bắt buộc dùng `std.math`

> *"There is **no syntax for NaN, infinity, or negative infinity**. For these special values, one must
> use the standard library."*

```zig
const std = @import("std");
const inf = std.math.inf(f32);
const negative_inf = -std.math.inf(f64);
const nan = std.math.nan(f128);
```

Đã kiểm chứng trên 0.17.0: `std.math.inf(f32)`, `std.math.nan(f64)`, `std.math.maxInt(T)`,
`std.math.minInt(T)`, `std.math.isInf`, `std.math.isNan`, `std.math.isFinite` đều tồn tại. Hai quan
sát quan trọng:

- **Đừng "tự tạo" inf bằng `1.0 / 0.0` một cách naïvely**: ở **comptime**, `const q = 1.0 / 0.0;` báo
  lỗi *"division by zero here causes illegal behavior"* (probe đã gặp). Ở **runtime strict mode**,
  chia float cho 0 cho `inf`/`nan` theo IEEE mà **không panic** (đo thật bên dưới) — nhưng tốt nhất
  vẫn là dùng `std.math` rõ ràng.
- NaN khó chịu: `nan == nan` là `false`; đừng so sánh bằng `==` với NaN, dùng `std.math.isNan`.

Thực nghiệm strict mode (runtime):

```
a/b = inf (isInf=1 isNan=0)     // 1.0/0.0 → +inf, không panic
a/b = nan (isInf=0 isNan=1)     // 0.0/0.0 → NaN
```

---

## 10. Float mode: `.strict` (mặc định) vs `.optimized`

Mặc định mọi phép toán float chạy **`.strict`** — tuân thủ IEEE nghiêm ngặt. Bạn có thể mở
**`.optimized`** cho từng block bằng `@setFloatMode`:

> `@setFloatMode(comptime mode: FloatMode) void` — *"Changes the current scope's rules about how
> floating point operations are defined."*
> - `.strict` (default) — phép toán float tuân thủ IEEE compliance nghiêm ngặt.
> - `.optimized` — cho phép: giả định đối số/kết quả không là NaN hay ±Inf; coi dấu của zero không
>   quan trọng; dùng nghịch đảo thay phép chia; **fused multiply-add**; và các biến đổi **đại số tương
>   đương nhưng có thể đổi kết quả** (vd tái kết hợp). "This is equivalent to `-ffast-math` in GCC."

Float mode **kế thừa xuống block con** và có thể override ở bất kỳ scope nào; có thể đặt cho cả struct/
module bằng `comptime` block. `FloatMode` lấy từ `@import("std").lang.FloatMode`.

Ví dụ langref: `x + big - big` với `big = 1 << 40`, `x = 0.001` — thứ tự tính thay đổi kết quả:

```zig
const big = @as(f64, 1 << 40);
export fn foo_strict(x: f64) f64     { return x + big - big; } // strict
export fn foo_optimized(x: f64) f64  {
    @setFloatMode(.optimized);        // bật fast-math cho block này
    return x + big - big;
}
```

Langref chỉ rõ một lưu ý lớn: *"For this test we have to **separate code into two object files** —
otherwise the optimizer figures out all the values at compile-time, which operates in strict mode."*
Trên máy hiện tại (0.17.0, `-O fast`) chạy **cả hai cách** — một file và hai object file — cùng cho:

```
optimized = 0.001
strict = 0.0009765625
```

Giải thích: strict mode **không được phép tái kết hợp** nên tính trung gian `x + big` (tràn độ chính
xác f64) rồi trừ `big` → mất số; optimized mode gộp `big - big = 0` rồi trả đúng `x`.

> ⚠️ `@setFloatMode(.optimized)` là **fast-math**: kết quả có thể "sai" theo kiến thức IEEE, NaN/Inf
> không được bảo đảm — chỉ bật khi bạn chấp nhận đánh đổi tốc độ ↔ độ chính xác, và đừng bật cho
> code phải so khớp bit-chính-xác (ví dụ mô phỏng, tiền tệ).

---

## 11. Cast số: `@intCast @truncate @floatCast @floatFromInt @intFromFloat @intFromBool @backingInt/@fromBackingInt`

Zig phân biệt nghiêm các kiểu cast số (mỗi thao tác một builtin, không có "cast tắt" kiểu C):

| Builtin | Chiều | An toàn? | Ghi chú |
|---|---|---|---|
| `@intCast(x)` | int → int | ✅ panic nếu không vừa | kết quả theo result type (vế trái hoặc `@as`) |
| `@truncate(x)` | int → int | ✅ **không panic** | **cắt bit thấp**, cố ý mất bit cao |
| `@floatCast(x)` | float → float | ✅ không panic | có thể mất độ chính xác (→ `inf`) |
| `@floatFromInt(x)` | int → float | ✅ mọi giá trị đều hợp lệ | làm tròn về biểu diễn gần nhất |
| `@intFromFloat(x)` | float → int | ✅ panic nếu ngoài khoảng | **cắt bỏ phần thập phân** (truncate về 0); 0.17.1 ghi "Deprecated, equivalent to `@trunc`" — vẫn dùng được, không emit warning trên 0.17.0 |
| `@intFromBool(b)` | bool → `u1` | ✅ | `true→1`, `false→0` |
| `@backingInt(e)` / `@fromBackingInt(n)` | enum ↔ int | ✅ | 0.17 thay thế `@intFromEnum`/`@enumFromInt` (mục 13) |

### 11.1 `@intCast` — result type & `@as`

```zig
const a: u16 = 0x00cd;
const b: u8  = @intCast(a);         // result type = u8 (từ vế trái), panic nếu tràn
const c: u8  = @as(u8, @intCast(a)); // tương đương — @as rõ ràng hơn
```

Đo thật: cả hai cách đều cho `205` (= 0xcd). Tràn → panic `integer does not fit in destination type`
(mục 12). Khi `@intCast` nhận `comptime_int`, nó tương đương Type Coercion (tự kiểm lúc compile).

**Phân biệt `@intCast` và `@truncate`:** `@intCast` *giữ nguyên giá trị* (phải nằm vừa), còn
`@truncate` *cắt bit* (`0xabcd` → `0xcd`, giữ luôn giá trị thấp dù tràn). Chọn theo ý đồ: muốn chắc
chắn dùng `@intCast`; muốn mạnh tay mask/vòng dùng `@truncate`.

### 11.2 Float ↔ Int & precision

- `@floatFromInt` hợp lệ với **mọi giá trị mọi kiểu nguyên** (không lỗi); f32 có 24 bit significand nên
  `u32` lớn bị làm tròn.
- `@intFromFloat` **cắt phần thập phân về 0**: `@intFromFloat(42.99) == 42`, `-42.99 → -42`. Nếu phần
  nguyên ngoài miền kiểu đích → panic `integer part of floating point value out of bounds`.
- `@floatCast` xuống kiểu nhỏ có thể tràn thành `±inf` mà không panic (đã đo: `@floatCast` f64→f32 của
  `1e320` cho `inf`).

> ⚠️ **Int → Float không phải lúc nào cũng coerce được tự động**: langref có bảng "lớn nhất mà float
> giữ tròn không mất bit" — `f16` giữ tròn tới `i12/u11`, `f32` tới `i25/u24`, `f64` tới `i54/u53`,
> `f80` tới `i65/u64`, `f128` tới `i114/u113`. Kiểu lớn hơn **bắt buộc phải** `@floatFromInt` tường minh.

### 11.3 Peer type resolution & widening (cơ bản)

Khi hai toán hạng khác kiểu xuất hiện trong một biểu thức, Zig tìm một **peer type** chung:

- Nếu một vế là `comptime_int`/`comptime_float` và giá trị **vừa** kiểu còn lại → hoà vào kiểu đó
  (đã đo: `@as(u16, 1) + 2` cho `u16`; `@TypeOf(r) == u16`).
- Nếu cả hai là kiểu kích thước cố định khác nhau, Zig nâng lên kiểu **lớn hơn** theo thứ tự
  signedness/độ rộng (widening) — ví dụ `u8 + u16 → u16`.
- **Không có** ép kiểu "chặt tay" kiểu C tự nhiên nào khác: mọi chuyển đổi rõ ràng đều qua builtin.

> 💡 Nếu peer type không thể quyết định hoặc gây mất thông tin, Zig **từ chối biên dịch** và bảo bạn
> cast tường minh — đó là lý do code Zig luôn "nói rõ" kiểu hơn hẳn C.

---

## 12. Bảng lỗi thường gặp (probe thật trên 0.17.0)

Mọi dòng dưới đây lấy từ **output thật** của Zig 0.17.0 (các file probe trong `/tmp`):

| Thông điệp lỗi (0.17.0) | Nguyên nhân |
|---|---|
| `error: type 'u8' cannot represent integer value '300'` | gán literal comptime 300 vào u8 (probe âm #1) |
| `error: variable of type 'comptime_int' must be const or comptime` (+ note *"to modify this variable at runtime, it must be given an explicit fixed-size number type"*) | `var x = 1;` — comptime_int trong biến runtime (probe #2) |
| `error: overflow of integer type 'u8' with value '256'` | overflow **tính ở comptime** (probe #4) |
| `thread 147605 panic: integer overflow` | overflow **ở runtime**, `var byte: u8 = 255; byte += 1;` (probe #3) |
| `thread 147705 panic: division by zero` | chia runtime cho 0 (probe #5) |
| `thread 147788 panic: integer does not fit in destination type` | `@intCast` tràn (probe #6) — *lưu ý: thông điệp 0.17 là "does not fit", không phải "truncated bits"* |
| `thread 147860 panic: integer part of floating point value out of bounds` | `@intFromFloat` ngoài khoảng (probe #7) |
| `thread 147928 panic: left shift overflowed bits` | `@shlExact` mất bit (probe #8) |
| `error: division by zero here causes illegal behavior` | phép chia **comptime** cho 0 (kể cả float literal) |
| `error: local variable is never mutated … consider using 'const'` | khai báo `var` không gán lại — dùng `const` hoặc `_ = &x;` |
| (0.17.1 langref ghi "Deprecated" cho `@intFromFloat` nhưng 0.17.0 **không** emit warning khi dùng) | — |

> ⚠️ Lưu ý khác mọi bản cũ: **`@intFromEnum`/`@enumFromInt` đã deprecated trong 0.17** — dùng
> `@backingInt`/`@fromBackingInt`. Và tên cũ thời 0.13 `@intToFloat`/`@floatToInt` hiện là
> `@floatFromInt`/`@intFromFloat` — đã kiểm chứng cả hai tên mới chạy trên 0.17.0.

---

## 13. Tổng kết nhanh

| Câu hỏi | Trả lời |
|---|---|
| Kiểu integer có dấu/không dấu | `iN`/`uN`, `N` từ 1 đến **65535** bit, dùng bù hai cho có dấu |
| Kiểu của literal số | `comptime_int` (integer), `comptime_float` (float) — không giới hạn kích thước |
| `var x = 1;` lỗi gì? | comptime_int không được làm biến runtime; thêm kiểu `u8` hoặc để `const` |
| `255 + 1` trên `u8` | overflow → panic (runtime) / compile error (comptime) |
| Muốn "vòng" mà không panic | `+% -% *% -%` (wrapping) — bù hai |
| Muốn "kẹt" mà không panic | `+| -| *| <<|` (saturating) |
| `/` và `%` dùng được khi nào? | vế dấu **phải comptime-known & dương**; còn lại dùng `@divTrunc/@divFloor/@divExact/@divCeil` và `@rem/@mod` |
| Dư theo dấu số nào? | `@rem` — dấu theo **số bị chia**; `@mod` — dấu theo **số chia** |
| Shift right khác nhau gì? | `uN` → logical (chèn 0); `iN` → arithmetic (chèn bít dấu) |
| Mất bit khi shift | dùng `@shlExact`/`@shrExact` để có panic thay vì nuốt im |
| Kích thước thật | `@sizeOf` = byte (có padding/ABI), `@bitSizeOf` = bit (packed); `i24` đo thật = 4 byte |
| Float literal | `0x103.70p-5` (hex), `123.0E+77`, underscore; `comptime_float` chính xác như f128 |
| Đặc biệt NaN/Inf | không có cú pháp literal → `std.math.inf/nan` |
| Float mode | `.strict` (mặc định, IEEE) ⇄ `.optimized` (`@setFloatMode`, fast-math) |
| Cast "vừa giá trị" | `@intCast`/`@floatCast`/`@floatFromInt`/`@intFromFloat`/`@intFromBool` |
| Cast "cắt bit" | `@truncate` |
| Enum ↔ số | `@backingInt`/`@fromBackingInt` (thay `@intFromEnum`/`@enumFromInt`) |

---

## 14. Liên hệ các tài liệu khác

- [`values.md`](values.md) — bảng Primitive Types, chi tiết `comptime_int`/`comptime_float`,
  `undefined`, destructuring. **Đọc kèm mục 2 & 4 ở đây.**
- [`comptime.md`](comptime.md) — comptime vs runtime, vì sao integer có hai "đời" sống; `comptime var`.
- [`variables.md`](variables.md#24-var-với-giá-trị-comptime-không-cần-kiểu-tường-minh) — lỗi
  `comptime_int must be const or comptime`; biến là *storage* cần kiểu kích thước cố định.
- [`memory_model.md`](memory_model.md#44-alignment) — `@sizeOf`/`@alignOf`, padding, ABI; mục 4.1 nói
  `usize` là "kiểu cỡ bộ nhớ".
- [`enum.md`](enum.md#2-tag-type-kiểu-số-nền--backing-integer) — tag type (backing integer) của enum,
  `@backingInt`/`@fromBackingInt` (mục 6.1).
- [`struct.md`](struct.md#71-backing-integer--backingintfrombackingint) — packed struct dùng **backing
  integer** = tổng bit các field → liên hệ `@bitSizeOf` ở đây.
- [`errors.md`](errors.md) — error union & `catch`/`try`, nơi `std.math.add` trả `error.Overflow` được
  xử lý.
- [`identifiers.md`](identifiers.md) — luật tên/scope (literal có chữ `_` tách số cũng là identifier
  syntax, không phải "biến").

---

## 15. Nguồn tham khảo

**Tài liệu chính thức (0.17.1):**
- [Zig Language Reference 0.17.1 — Integers](https://ziglang.org/documentation/0.17.1/#Integers)
- [0.17.1 — Floats](https://ziglang.org/documentation/0.17.1/#Floats) (Float Literals, Floating Point Operations)
- [0.17.1 — Operators / Table of Operators / Precedence](https://ziglang.org/documentation/0.17.1/#Operators)
- [0.17.1 — Illegal Behavior](https://ziglang.org/documentation/0.17.1/#Illegal-Behavior) → Integer Overflow, Wrapping Operations, Exact Left Shift Overflow, Division by Zero, Remainder Division by Zero, Out of Bounds Float to Integer Cast
- [0.17.1 — Builtin Functions](https://ziglang.org/documentation/0.17.1/#Builtin-Functions) → `@intCast`, `@truncate`, `@floatCast`, `@floatFromInt`, `@intFromFloat`, `@intFromBool`, `@bitSizeOf`, `@sizeOf`, `@setFloatMode`, `@addWithOverflow`…
- [0.17.1 — Type Coercion: Compile-Time Known Numbers](https://ziglang.org/documentation/0.17.1/#Type-Coercion-Compile-Time-Known-Numbers)

**Nguồn đọc tại chỗ:** `/tmp/zigenum/variables/sec_integers_floats.txt` (trích mục Integers → Floats →
Operators → Precedence từ langref 0.17.1) và `/tmp/zigenum/variables/langref0171.txt`.

**Bộ test kiểm chứng (scratch, `/tmp/zigenum/integers_floats/`):**
- `f1_ints.zig` — 17 test số nguyên (sizes, comptime_int, wrapping/saturating, chia & dư, shift, bitwise,
  overflow-bắt được, `@intCast`/`@truncate`/`@intFromBool`, peer resolution) → **17/17 OK**.
- `f2_floats.zig` — 9 test số thực (sizes f16…c_longdouble, literals, inf/nan, `@floatFromInt`/
  `@intFromFloat`/`@floatCast`, coerce) → **9/9 OK**.
- `f3_floatmode.zig` — demo `.strict` vs `.optimized` → `strict = 0.0009765625`, `optimized = 0.001`.
- `neg/` — 8 probe âm, thông điệp lỗi gốc (xem mục 12).

---

*Tài liệu viết cho mục đích học tập; các con số (kích thước, panic, kết quả float) được chạy trên máy
hiện tại: macOS ARM64, Zig 0.17.0. Kích thước ABI (`@sizeOf(i24)=4`, `@sizeOf(f80)=16`,
`c_longdouble=8` trên AArch64) và đường dẫn module có thể khác trên target khác nhưng bản chất ngôn
ngữ (bù hai, `comptime_int`, wrapping/saturating, safety checks, float mode) là bất biến. Những điểm
0.17-specific (`@intFromFloat` ghi deprecated trong langref 0.17.1 nhưng còn dùng được không warning;
tên mới `@floatFromInt`/`@intFromFloat`; `@backingInt`/`@fromBackingInt` thay enum-int builtin cũ) đã
để ghi chú ngay trong bài.*
