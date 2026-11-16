# Optionals & Error Handling nâng cao trong Zig — Hướng dẫn toàn diện

> Phiên bản xác minh: **Zig 0.17.0** (`zig version`), đối chiếu [Zig Language Reference 0.17.1 — Optionals](https://ziglang.org/documentation/0.17.1/#Optionals).
> Mọi ví dụ dưới đây đã chạy qua `zig test`/`zig build-obj`/`zig run` trên máy (bộ test **31/31 OK** — `o1_opt.zig` 22 + `o2_switch.zig` 9 + chương trình đo `@sizeOf` + **10 probe lỗi âm** ở `neg/`).
> Tài liệu này **giả định bạn đã đọc** [`errors.md`](errors.md) (error set / error union / `catch` / `try` cơ bản) — phần dưới chỉ đào **nâng cao** và mối liên hệ với **Optionals**.

---

## Mục lục

1. [Optionals cơ bản: `?T` và `null`](#1-optionals-cơ-bản-t-và-null)
2. [Optional pointers — null = address 0](#2-optional-pointers--null--address-0)
3. [Unwrap & capture: `orelse`, `if |v|`, `.?`, `while`](#3-unwrap--capture-orelse-if-v--while)
4. [Optional + reflection: `@typeInfo(...).optional.child`](#4-optional--reflection-typeinfoptionalchild)
5. [Error handling nâng cao (gắn liền Optionals)](#5-error-handling-nâng-cao-gắn-liền-optionals)
   - [5.1 `catch` block đa câu lệnh & named block](#51-catch-block-đa-câu-lệnh--named-block)
   - [5.2 `else |err| switch` — bắt từng lỗi & `leftover_err`](#52-else-err-switch--bắt-từng-lỗi--leftover_err)
   - [5.3 `while` với error union](#53-while-với-error-union)
   - [5.4 Optional lồng error union: thứ tự unwrap](#54-optional-lồng-error-union-thứ-tự-unwrap)
   - [5.5 handle-then-unreachable & sự khác biệt ReleaseFast](#55-handle-then-unreachable--sự-khác-biệt-releasefast)
6. [Bảng `@sizeOf`: null-optimized vs tag byte (đo thật)](#6-bảng-sizeof-null-optimized-vs-tag-byte-đo-thật)
7. [Lỗi thường gặp (probe thật 0.17.0)](#7-lỗi-thường-gặp-probe-thật-0170)
8. [Liên hệ memory model](#8-liên-hệ-memory-model)
9. [Nguồn & liên kết](#9-nguồn--liên-kết)

---

## 1. Optionals cơ bản: `?T` và `null`

Một **optional type** là một kiểu "có thể là giá trị con, hoặc `null`". Cú pháp là dấu hỏi **đặt TRƯỚC** kiểu:

```zig
const normal_int: i32 = 1234;
const optional_int: ?i32 = 5678; // kiểu ?i32: có thể là i32, hoặc null
```

> *"One area that **Zig provides safety without compromising efficiency or readability** is with the optional type."*
> — langref (Optionals)

Khác với các ngôn ngữ khác, ở đây sự an toàn đến từ **hệ thống kiểu**, không phải chi phí runtime. Mục 2 và 6 sẽ "chứng minh bằng đo đạc": optional pointer **hoàn toàn không tốn thêm byte**, và optional giá trị chỉ tốn thêm một tag byte.

### null là một kiểu riêng, chỉ dùng được qua cast

> *"Just like `undefined`, `null` has its own type, and the only way to use it is to **cast it to a different type**."*

```zig
// null tự nó không có "kiểu giá trị nào cả"; phải có kiểu đích:
const optional_value: ?i32 = null; // null -> ?i32 (cast hợp lệ)
```

Coercion **hai chiều** vào optional (đã test `test "optional: coerce từ null và từ child type"`):

```zig
var foo: ?i32 = null; // null -> ?i32
foo = 1234;           // child type (i32) -> ?i32
```

⚠️ **Lưu ý đặc biệt:** giá trị `0` **KHÔNG phải** `null`. Một `?u32` bằng `0` vẫn là non-null:

```zig
const a: ?u32 = 0; // non-null! payload là 0
try expect(a != null);
try expectEqual(0, a.?);
```

Đây là điểm nhiều người nhầm khi chuyển từ C sang — trong C `0` và `NULL` trộn lẫn khái niệm; trong Zig chúng khác hẳn (mục 2 giải thích tại sao sự khác biệt này lại **tiết kiệm** bộ nhớ ở optional pointer).

---

## 2. Optional pointers — null = address 0

### Vì sao phải có `?*T`?

> *"Null references are the source of many runtime exceptions, and even stand accused of being the worst mistake of computer science. **Zig does not have them.** Instead, you can use an **optional pointer**."*

Trong Zig **pointer không thể null** (đó là tính an toàn của nó). Muốn "con trỏ có thể rỗng", bạn bọc bằng `?`: `?*T`. Điểm mấu chốt — langref khẳng định và ta **đo được**:

> *"An optional pointer is guaranteed to be **the same size as a pointer**. The null of the optional is guaranteed to be **address 0**."*

```zig
try expectEqual(@sizeOf(?*i32), @sizeOf(*i32)); // 8 == 8 (đã đo thật)
```

Cơ chế: null của optional pointer chính là **giá trị con trỏ 0** (address 0) — không cần thêm tag byte nào. Compiler vẫn "chỉ tay" được khi bạn lỡ gán `null` vào cái không thể null, vì kiểu `*T` đã loại `null` ngay từ đầu.

### So sánh C `malloc` vs Zig

Task kinh điển: gọi `malloc`, nếu null thì trả null.

| | C | Zig |
|---|---|---|
| Khai báo | `void *malloc(size_t size);` | `extern fn malloc(size: usize) ?[*]u8;` |
| Kiểm tra | `if (!ptr) return NULL;` | `const ptr = malloc(1234) orelse return null;` |
| Kiểu con trỏ dùng tiếp | `void *` (vẫn có thể null!) | `[*]u8` (chắc chắn non-null) |

```zig
fn doAThing() ?*Foo {
    const ptr = malloc(1234) orelse return null;
    // ptr có kiểu [*]u8, KHÔNG còn là ?[*]u8
    _ = ptr;
}
```

Đã chạy thật với `zig test -lc` (test `call malloc from Zig: orelse return null`) — sau `orelse`, kiểu của `ptr` là `[*]u8`; nếu `malloc` trả null, hàm **return null** ngay.

> *"Here, Zig is at least as convenient, if not more, than C. And, the type of `ptr` is `[*]u8` not `?[*]u8`. The `orelse` keyword **unwrapped** the optional type and therefore `ptr` is **guaranteed to be non-null** everywhere it is used in the function."*
> — langref

### Non-null guarantee giúp optimizer

Cách kiểm tra NULL kiểu C `if (foo) { ... }` tương đương Zig:

```zig
fn doSomethingWithFoo(foo: *Foo) void { _ = foo; }

fn doAThing(optional_foo: ?*Foo) void {
    if (optional_foo) |foo| {
        // foo là *Foo — pointer thật, chắc chắn non-null
        doSomethingWithFoo(foo);
    }
}
```

> *"One benefit to this is that functions which take pointers as arguments can be annotated with the **"nonnull" attribute** … The optimizer can sometimes make better decisions knowing that pointer arguments cannot be null."*

Tức là vẻ ngoài ta "viết nhiều hơn" C một chút, nhưng đổi lại: (a) compiler không cho gán null vào `*T`; (b) bên trong block capture, `foo` là pointer thật → optimizer được tự do (attribute `nonnull` dành cho hàm nhận pointer).

---

## 3. Unwrap & capture: `orelse`, `if |v|`, `.?`, `while`

Có **bốn cách** "bóc" một optional, mỗi cách một sắc thái:

### 3.1 `orelse` — trả default khi null

```zig
const a: ?i32 = null;
try expectEqual(-1, a orelse -1);   // null -> default
const b: ?i32 = 42;
try expectEqual(42, b orelse -1);   // non-null -> payload, default bị bỏ qua
try expectEqual(i32, @TypeOf(b orelse -1)); // kết quả KHÔNG optional
```

- Vế phải phải "hoà hợp" được với payload (xem 💡 ở dưới).
- `orelse unreachable` — giả định không null (mục 5.5).

💡 **`orelse` dùng peer-resolution giữa payload & default (đo thật 0.17.0).** Với giá trị runtime, `?u32 orelse i64` cho kết quả kiểu **`i64`** (u32 coerce được vào i64 nên Zig widen) — đừng ngạc nhiên khi "default" loại khác vẫn chạy. Nếu **hai chiều đều không coerce được** (vd `?u32 orelse []const u8`) → compile error `incompatible types: 'u32' and '[]const u8'` (mục 7).

### 3.2 `if (o) |v|` — capture kèm non-null guarantee

```zig
const a: ?u32 = 0;
if (a) |value| {
    // value có kiểu u32, KHÔNG phải ?u32
    try expectEqual(u32, @TypeOf(value));
} else {
    unreachable; // nhánh null
}
```

- `else` **không bắt buộc** (muốn test thêm `b == null` thì dùng `==`).
- Capture **theo con trỏ** để sửa giá trị gốc: `if (c) |*value| value.* = 2;` (đã test).
- Optional pointer kết hợp `if` chính là ví dụ `doAThing(optional_foo)` ở mục 2.

### 3.3 `.?` — assert non-null (null → panic ở debug/safe)

```zig
const o: ?i32 = 5;
try expectEqual(5, o.?);       // nếu null ở đây -> panic
try expectEqual(i32, @TypeOf(o.?));
```

Khi optional là `null`, `.?` kích hoạt **illegal behavior** → trong chế độ **debug/safe** sẽ in panic:

```
thread 171319 panic: attempt to use null value
```

(có `exit 134` — SIGABRT; ở `ReleaseFast` thì im lặng, xem mục 5.5.) Nên dùng `.?` cũng như `unreachable`: **chỉ khi bạn chắc chắn** — nó như một assert miễn phí của compiler.

### 3.4 `while (o) |v|` — duyệt chuỗi giá trị optional

> *"Just like `if` expressions, `while` loops can take an optional as the condition and capture the payload. **When null is encountered the loop exits**."*

Pattern này chính là nền tảng của **iterator** trong std. Ví dụ `std.mem.tokenizeAny` trả `?[]const u8`:

```zig
const text = "Zig;0.17;optional";
var it = std.mem.tokenizeAny(u8, text, ";");
const parts = [_][]const u8{ "Zig", "0.17", "optional" };
var i: usize = 0;
while (it.next()) |tok| { // next() trả ?[]const u8; null -> thoát vòng
    try expectEqualStrings(parts[i], tok);
    i += 1;
}
try expectEqual(parts.len, i);
```

Và bạn hoàn toàn có thể **tự viết iterator** trả `?T` (đã test — giá trị `2,1,0` rồi `null`):

```zig
const Seq = struct {
    n: u32 = 3,
    fn next(self: *Seq) ?u32 {
        if (self.n == 0) return null; // null -> kết thúc vòng lặp
        self.n -= 1;
        return self.n;
    }
};

var seq = Seq{};
var sum: u32 = 0;
var steps: u32 = 0;
while (seq.next()) |v| : (steps += 1) sum += v; // 2+1+0
try expectEqual(3, sum);
try expectEqual(3, steps);
```

---

## 4. Optional + reflection: `@typeInfo(...).optional.child`

Optional là kiểu bậc hai, có thể **self-reflect** bằng `@typeInfo(T).optional.child`:

```zig
const foo: ?i32 = 1234;
try comptime expectEqual(i32, @typeInfo(@TypeOf(foo)).optional.child);
try comptime expectEqual(?i32, @TypeOf(foo));
```

Kiểm tra thật đã chạy (`test "optional: @typeInfo(...).optional.child"`). Reflection này **rất hữu ích trong generic helper** khi cần lấy "kiểu con" của một optional — kết hợp với `error_union.payload` ở mục 5.4.

---

## 5. Error handling nâng cao (gắn liền Optionals)

> Phần này **không lặp lại** error set/`catch`/`try` cơ bản (đã ở [`errors.md`](errors.md)) — chỉ đào các kỹ thuật xử lý nâng cao và mối liên hệ hệ thống kiểu với Optionals.

### 5.1 `catch` block đa câu lệnh & named block

`catch` không chỉ bắt "một default" — có thể chạy **nhiều câu lệnh** trước khi tạo giá trị, nhờ **named block**:

```zig
var attempts: u32 = 0;
const cfg = loadConfig("x") catch blk: {
    attempts += 1;   // log, đếm, dọn dẹp...
    attempts += 1;
    break :blk 0;    // default
};
try expectEqual(2, attempts);
try expectEqual(0, cfg);
```

### 5.2 `else |err| switch` — bắt từng lỗi & `leftover_err`

Khi **không dùng `try`** (muốn hàm hiện tại tự quyết định), pattern chuẩn là:

```zig
const ConfigError = error{ NotFound, InvalidFormat, OutOfMemory };

fn loadConfig(path: []const u8) ConfigError!u8 {
    if (path.len == 0) return error.NotFound;
    switch (path[0]) {
        'x' => return error.InvalidFormat,
        '!' => return error.OutOfMemory,
        else => {},
    }
    return 42;
}

// Xử lý 2 trong 3 lỗi; error.NotFound để lọt qua nhánh else.
fn openConfig(path: []const u8) ConfigError!u8 {
    return loadConfig(path) catch |err| switch (err) {
        error.InvalidFormat => 0, // sửa định dạng
        error.OutOfMemory => 1,   // thử lại
        else => |leftover_err| return leftover_err, // trả đúng lỗi còn sót
    };
}
```

**Tại sao `else => |leftover_err|` lại cần thiết?** Vì `switch` trên error set phải **exhaustive** (mục 7: `switch must handle all possibilities`). Sau khi bạn liệt kê các prong đã xử lý, nhánh `else` bắt **phần còn lại** — và điểm tinh tế ở đây là *kiểu của `leftover_err` được **thu hẹp** lại*: không còn là cả `ConfigError`, mà chỉ là tập các lỗi chưa liệt kê.

Ta kiểm chứng điều đó bằng reflection (đã test `test "leftover_err có kiểu là error set hẹp"`):

```zig
fn typeOfLeftover() type {
    return comptime switch (@as(ConfigError, error.NotFound)) {
        error.InvalidFormat => unreachable,
        error.OutOfMemory => unreachable,
        else => |leftover| @TypeOf(leftover), // error{NotFound}
    };
}
try comptime expectEqual(error{ NotFound }, typeOfLeftover());
```

Kết quả: kiểu của `leftover` là `error{NotFound}` — **error set hẹp hơn** `ConfigError` (chỉ còn các lỗi chưa xử lý). Việc `switch` đầy đủ prong giúp compiler "khấu trừ" từng lỗi bạn đã loại, cho phép `else` bọc lại đúng phần còn sót. Nếu bạn liệt kê **đủ toàn bộ** lỗi của error set cụ thể thì switch đã exhaustive và **không cần `else`** (đã probe: `switch (e: error{A,B}) { error.A => .., error.B => .. }` không ghi `else` vẫn compile OK); còn với inferred error set, người ta thường giữ `else => unreachable` làm "hàng rào" cho các lỗi tương lai.

### 5.3 `while` với error union

> *"`while` loops can take an **error union** as the condition and capture the payload **or the error code**. When the condition results in an error code the `else` branch is evaluated and the loop is finished."*

Cú pháp: `while (expr) |val| { } else |err| { }` — `else |err|` xuất hiện thì condition **bắt buộc là error union type**. Mô-típ "duyệt cho tới khi lỗi rồi trả lỗi":

```zig
var g_numbers_left: u32 = undefined;
fn eventuallyErrorSequence() anyerror!u32 {
    return if (g_numbers_left == 0) error.ReachedZero else blk: {
        g_numbers_left -= 1;
        break :blk g_numbers_left;
    };
}

fn sumWhile() !u32 {
    var sum: u32 = 0;
    while (eventuallyErrorSequence()) |value| {
        sum += value;
    } else |err| {
        return err; // gặp lỗi -> trả lỗi từ hàm
    }
    return sum;
}

g_numbers_left = 3;
try std.testing.expectError(error.ReachedZero, sumWhile()); // tổng 2+1+0 rồi... lỗi
```

Ở đây mỗi lượt lặp "xài" một giá trị; khi chuỗi cạn, hàm trả `error.ReachedZero` → `else |err|` chặn lại. Khác với `while` optional (thoát khi `null`), biến thể error union **thoát bằng nhánh `else |err|`** — nơi bạn bắt buộc quyết định việc trả lỗi.

Kết hợp hai thứ bạn đã có: optional-while cho iterator, error-union-while cho "chuỗi thao tác có thể lỗi từng bước".

### 5.4 Optional lồng error union: thứ tự unwrap

Ba biến thể quan trọng, **thứ tự bóc luôn là "zì từ ngoài vào trong"**:

| Kiểu | Đọc là | Bóc lần 1 | Bóc lần 2 |
|---|---|---|---|
| `?E!T` | `?(E!T)` — optional bọc error union | `orelse` (bóc optional) | `catch`/`try` (bóc error union) |
| `E!?T` | `E!(?T)` — error union, payload là optional | `try`/`catch` (bóc lỗi) | `orelse`/`.?`/`if` (bóc optional) |
| `E!?*T` | `E!(?*T)` — error union, payload là optional pointer | `try` (bóc lỗi) | `.?`/`if` (bóc optional pointer) |

Đã xác minh type-parsing bằng `@typeName` (chạy thật 0.17.0): `?anyerror!i32` là **optional**, child là `anyerror!i32`.

**Ví dụ `E!?T` — mô-típ thực tế** (hàm đọc database: "không tìm thấy dòng" là lỗi, "dòng tồn tại nhưng rỗng" là `null` hợp lệ):

```zig
fn lookupName(id: u32) anyerror!?[]const u8 { // E!?T
    if (id == 0) return error.NotFound;
    if (id == 1) return null;  // hợp lệ: dòng không có tên
    return "ziggii";
}

fn upperName(id: u32) ![]const u8 {
    const maybe = try lookupName(id);      // bóc E trước -> ?[]const u8
    const name = maybe orelse return error.Missing; // bóc ? sau
    return name;
}

try expectEqualStrings("ziggii", try upperName(2));
try std.testing.expectError(error.NotFound, upperName(0));
try std.testing.expectError(error.Missing, upperName(1)); // null, không phải lỗi
```

Chú ý ngữ nghĩa: `error.NotFound` (id=0) và `null` (id=1) là **hai đường khác nhau** — cái đầu là lỗi, cái sau là giá trị rỗng hợp lệ. Đây chính là siêu năng lực của việc tách bạch hai khái niệm.

**Ví dụ `E!?*T`** — optional pointer trong error union, bóc bằng `try` rồi `if`:

```zig
var g_target: ?*u32 = null;
fn nextFreeSlot() anyerror!?*u32 { return g_target; }

var slot: u32 = 0;
g_target = &slot;
const maybe_ptr = try nextFreeSlot(); // bóc E -> ?*u32
if (maybe_ptr) |p| p.* = 7;           // bóc optional pointer
try expectEqual(7, slot);
```

**Ví dụ `?E!T`** — optional bọc error union, bóc optional TRƯỚC:

```zig
var a: ?anyerror!i32 = null;
var b: ?anyerror!i32 = error.BadValue;
var c: ?anyerror!i32 = 42;
try expectEqual(5, (a orelse @as(anyerror!i32, 5)) catch 9); // null -> 5
try expectEqual(9, (b orelse @as(anyerror!i32, 5)) catch 9); // lỗi -> 9
try expectEqual(42, (c orelse @as(anyerror!i32, 5)) catch 9);
```

📌 **Gotcha thật (0.17.0) — constant folding làm mất kiểu error union:** nếu viết `(a orelse 5) catch 9` với `a` là `const` optional, compiler **comptime-fold** `a orelse 5` thành `comptime_int` → `catch` báo `expected error union type, found 'comptime_int'`. Cách sửa: ép default bằng `@as(anyerror!i32, 5)` (hoặc để optional là runtime). Khi gặp lỗi kỳ lạ dạng này, hãy nghĩ tới constant folding.

**Reflection tổng hợp** — một generic helper dùng cả `.error_union` lẫn `.optional.child` (đã test):

```zig
fn unwrapGeneric(comptime T: type) type {
    const payload = @typeInfo(T).error_union.payload; // vd ?u8
    return @typeInfo(payload).optional.child;         // vd u8
}
const v: anyerror!?u8 = 5;
try comptime expectEqual(u8, unwrapGeneric(@TypeOf(v)));
```

### 5.5 handle-then-unreachable & sự khác biệt ReleaseFast

Mô-típ "xử lý hết các lỗi khả dĩ, phần còn lại để `unreachable`" — **`unreachable` ở đây là một assert**:

```zig
const v = loadConfig("ok") catch |err| switch (err) {
    error.OutOfMemory => 0,   // có thể xảy ra -> xử lý
    else => unreachable,      // với input này: không thể xảy ra
};
try expectEqual(42, v);
```

- Nếu input thay đổi khiến giả định sai → **panic ở debug/safe**, đúng thời điểm, đúng dòng:
  ```
  thread 173937 panic: reached unreachable code
  ```
- Còn ở **`ReleaseFast`** (safety tắt) thì **im lặng** — probe cùng file chạy `-O ReleaseFast` thoát với `exit 133` (SIGTRAP), **không có thông điệp nào**. Nghĩa là: `unreachable` là **miễn phí ở release** nhưng bạn **mất đi tấm lưới an toàn** — hãy test ở debug.
- ⚠️ Nếu `switch` chỉ có một prong `else => unreachable` (không liệt kê error nào), Zig hạ tầng xuống theo hướng "unwrap error", và panic sẽ in thông điệp khác: `attempt to unwrap error: A`.

Hai dạng "assert" tương đương nhau, khác đối tượng:

| Biểu thức | Giả định | Khi sai (debug) |
|---|---|---|
| `parseU64("1234", 10) catch unreachable` | không lỗi | `panic: attempt to unwrap error: X` |
| `a orelse unreachable` | không null | `panic: attempt to use null value` |

Cả hai đều đã chạy thật; ở ReleaseFast cả hai đều không thông điệp (xem mục 7).

---

## 6. Bảng `@sizeOf`: null-optimized vs tag byte (đo thật)

Đo bằng chương trình chạy thật trên Zig 0.17.0 (macOS arm64):

```
@sizeOf(i32)     = 4
@sizeOf(?i32)    = 8
@sizeOf(u32)     = 4
@sizeOf(?u32)    = 8
@sizeOf(bool)    = 1
@sizeOf(?bool)   = 2
@sizeOf(f64)     = 8
@sizeOf(?f64)    = 16
@sizeOf(*i32)    = 8
@sizeOf(?*i32)   = 8
@sizeOf([*]u8)   = 8
@sizeOf(?[*]u8)  = 8
@sizeOf([]u8)    = 16
@sizeOf(?[]u8)   = 16
```

| Kiểu con | `@sizeOf(T)` | `@sizeOf(?T)` | Giải thích |
|---|---|---|---|
| `i32` | 4 | **8** | 4 data + 1 tag byte + 3 padding (align 4) |
| `u32` | 4 | **8** | như trên |
| `bool` | 1 | **2** | 1 data + 1 tag |
| `f64` | 8 | **16** | 8 data + 1 tag + 7 padding (align 8) |
| `*i32` (pointer) | 8 | **8** | **null-optimized**: null = giá trị con trỏ 0 |
| `[*]u8` (many-ptr) | 8 | **8** | null-optimized |
| `[]const u8` (slice) | 16 | **16** | null-optimized: null = `ptr == 0` (và bỏ qua `.len`) |

**Kết luận đo được** — đừng đoán, đây là số thật:

- 💡 **Pointer là ngoại lệ "null-optimized"**: vì con trỏ thật không bao giờ là address 0, Zig tận dụng luôn giá trị 0 làm `null` → `?*T` **không tốn thêm byte nào**.
- 💡 **Bất ngờ: slice cũng null-optimized.** `?[]const u8 = 16` đúng bằng `[]const u8`. Null được mã hoá bằng `ptr == 0` (phần `.len` trở nên không quan trọng). Nhiều tài liệu chỉ nhắc pointer — đây là chi tiết đo được, ít người ngờ.
- 💡 **Giá trị thường CẦN tag byte**: `?i32` thêm **1 byte tag** để phân biệt "đang có payload" vs "null", cộng **padding** tới bội của `@alignOf(?T)` (`@alignOf(?i32)=4`, `@alignOf(?bool)=1`, `@alignOf(?f64)=8`).

Vì sao pointer "null-safe" mà vẫn không tốn bộ nhớ: chính vì **kiểu hệ thống tách bạch** — `*T` không thể null (không cần tag), còn `?*T` có null miễn phí (dùng sentinel 0). Trả lời câu hỏi "safety mà không đổi hiệu năng" của mục 1: đây là cách Zig làm điều đó.

---

## 7. Lỗi thường gặp (probe thật 0.17.0)

| Thông điệp lỗi (đã probe) | Nguyên nhân |
|---|---|
| `error: expected type 'i32', found '?i32'` … `note: cannot convert optional to payload type` … `note: consider using '.?', 'orelse', or 'if'` | gán một optional vào biến non-optional (thiếu unwrap) |
| `thread N panic: attempt to use null value` (debug; `exit 134`/`141`) | dùng `.?` trên `null`, hoặc deref optional pointer `null` (`p.?.*`); ở ReleaseFast không in gì (im lặng) |
| `error: switch must handle all possibilities` … `note: unhandled error value: 'error.C'` | `switch` trên error set thiếu prong (không exhaustive) |
| `error: incompatible types: 'u32' and '[]const u8'` … notes `type 'u32' here` / `type '[]const u8' here` | `orelse` với fallback không coerce được hai chiều với payload |
| `error: expected error union type, found 'comptime_int'` … `note: consider omitting 'try'` | `try` dùng trên biểu thức không phải error union (trong probe: `try 42`) |
| `error: expected error union type, found 'comptime_int'` (ở `(a orelse 5) catch 9`) | gotcha constant-folding: optional `const` + default `comptime_int` bị fold làm mất kiểu error union (mục 5.4) |
| `error: local variable is never mutated` … `note: consider using 'const'` | khai báo `var` nhưng không bao giờ gán lại (đặc trưng 0.17); sửa: dùng `const`, hoặc thêm `_ = &v;` |
| `thread N panic: reached unreachable code` (debug) | chạm vào `unreachable` khi giả định sai; ReleaseFast thoát im lặng (SIGTRAP) |
| `thread N panic: attempt to unwrap error: A` (debug) | `catch unreachable`/`switch` chỉ-`else=>unreachable` gặp lỗi thật |

> Xem thêm bảng lỗi cơ bản về error union/catch ở [`errors.md`](errors.md) mục 12.

---

## 8. Liên hệ memory model

- **Optional pointer = pointer + sentinel 0** — không tốn thêm (mục 6). Điều này nối thẳng với câu chuyện "địa chỉ 0" trong [`memory_model.md`](memory_model.md): chính vì hệ thống bảo vệ bạn **không bao giờ** có pointer trỏ address 0 (trừ khi chủ đích `?*T`), nên Zig "mượn" 0 để làm null miễn phí.
- **Optional giá trị (`?i32`, `?bool`…) cần tag byte** (mục 6) — giống cách error union `E!T` lưu payload + tag trong một storage (xem [`errors.md`](errors.md) mục 11). Đó là lý do `?f64 = 16`: 8 data + 1 tag + padding theo alignment.
- `null` là một **kiểu riêng** (chỉ dùng qua cast), tương tự `undefined` — thuộc nhóm "giá trị đặc biệt có kiểu `@TypeOf` riêng", liên hệ [`values.md`](values.md) về giá trị & [`variables.md`](variables.md) về result location (thêm hệ thống `optional result location` khi gán vào vị trí kết quả).
- **`try`/`orelse`/`catch` không cấp phát**: unwrap optional/error union chỉ là **đọc storage của biến + rẽ nhánh** — không có exception frame, không heap (đã được phân tích chi tiết ở [`errors.md`](errors.md) mục 10–11 về error return trace & zero-cost).
- **Comptime folding** (mục 5.4) là nhân tố bất ngờ khiến kiểu bị "tối giản" — nhắc lại câu chuyện comptime trong [`comptime.md`](comptime.md).

---

## 9. Nguồn & liên kết

- [Zig Language Reference 0.17.1 — Optionals](https://ziglang.org/documentation/0.17.1/#Optionals) (Optional Type, null, Optional Pointers)
- [0.17.1 — while with Optionals](https://ziglang.org/documentation/0.17.1/#while-with-Optionals) & [if with Optionals](https://ziglang.org/documentation/0.17.1/#if-with-Optionals)
- [0.17.1 — while with Error Unions](https://ziglang.org/documentation/0.17.1/#while-with-Error-Unions)
- [0.17.1 — catch](https://ziglang.org/documentation/0.17.1/#catch) & [try](https://ziglang.org/documentation/0.17.1/#try) (error handling nâng cao)
- [`errors.md`](errors.md) — error set / error union / `catch` / `try` / `errdefer` cơ bản
- [`variables.md`](variables.md) — lưu trữ giá trị, result location
- [`values.md`](values.md) — giá trị, đặc biệt `null`/`undefined`
- [`memory_model.md`](memory_model.md) — pointer, address 0, layout bộ nhớ
- [`comptime.md`](comptime.md) — constant folding & generic
- [`struct.md`](struct.md) — struct & `@sizeOf` (cách đo layout)

---

*Viết cho mục đích học tập; mọi đoạn trích quan trọng từ nguồn chính thức có link để tự kiểm chứng. Các con số `@sizeOf`, thông điệp panic và text lỗi đều là output thật từ Zig 0.17.0 trên máy (scratch `/tmp/zigenum/optionals/` — `o1_opt.zig`, `o2_switch.zig`, `sizes.zig`, `neg/`).*
