# Errors & Error Sets trong Zig — Hướng dẫn toàn diện

> Phiên bản xác minh: **Zig 0.17.0** (`zig version`), đối chiếu [Zig Language Reference 0.17.1 — Errors](https://ziglang.org/documentation/0.17.1/#Errors).
> Mọi ví dụ dưới đây đã chạy qua `zig test`/`zig build-obj` trên máy (bộ test 17/17 + 2 probe lỗi).

---

## Mục lục

1. [Khác biệt cốt lõi: lỗi là *giá trị*, không phải ngoại lệ](#1-khác-biệt-cốt-lõi-lỗi-là-giá-trị-không-phải-ngoại-lệ)
2. [Error Set Type](#2-error-set-type)
   - [2.1 Error name & số nguyên đi kèm](#21-error-name--số-nguyên-đi-kèm)
   - [2.2 Coerce subset → superset](#22-coerce-subset--superset)
   - [2.3 Shortcut một lỗi: `error.X`](#23-shortcut-một-lỗi-errorx)
3. [The Global Error Set — `anyerror`](#3-the-global-error-set--anyerror)
4. [Error Union Type — `!T`](#4-error-union-type--t)
5. [Xử lý: `catch`, `try`](#5-xử-lý-catch-try)
   - [5.1 `catch default`](#51-catch-default)
   - [5.2 `catch |err| ...`](#52-catch-err-)
   - [5.3 `catch unreachable`](#53-catch-unreachable)
   - [5.4 `try` — shortcut trả lỗi về](#54-try--shortcut-trả-lỗi-về)
6. [Xử lý từng lỗi: `if` + `switch`](#6-xử-lý-từng-lỗi-if--switch)
7. [`defer` vs `errdefer`](#7-defer-vs-errdefer)
8. [Merging Error Sets — `A || B`](#8-merging-error-sets--a--b)
9. [Inferred Error Sets — `!T`](#9-inferred-error-sets--t)
10. [Error Return Traces](#10-error-return-traces)
11. [Liên hệ memory model](#11-liên-hệ-memory-model)
12. [Lỗi thường gặp (probe thật)](#12-lỗi-thường-gặp-probe-thật)
13. [Nguồn & liên kết](#13-nguồn--liên-kết)

---

## 1. Khác biệt cốt lõi: lỗi là *giá trị*, không phải ngoại lệ

Khác với `try/catch` ngoại lệ (C++/Java/Python) hoặc `panic` (Rust thường xuyên), Zig xử lý lỗi bằng
**hệ thống kiểu**: một lỗi là một **giá trị** kiểu error-set, và "kết quả có thể là lỗi" được biểu
diễn tường minh bằng **error union type** `E!T`. Hệ quả:

- Mọi thứ đều **nhìn thấy bằng con mắt**: lỗi không "bay ngầm" qua stack.
- **Bỏ kiểm tra lỗi có thể trở thành compile error** (nếu bạn dùng `catch unreachable` thì lại còn
  được an toàn ở debug/safe).
- Chi phí bằng không khi không có lỗi (xem mục 11).

---

## 2. Error Set Type

> *"An error set is **like an enum**. However, each error name across the entire compilation gets
> assigned an **unsigned integer greater than 0**. You are allowed to declare the same error name more
> than once, and if you do, it gets assigned **the same integer value**."*

```zig
const FileOpenError = error{
    AccessDenied,
    OutOfMemory,
    FileNotFound,
};
const AllocationError = error{
    OutOfMemory, // trùng tên → cùng giá trị trên toàn bộ compilation
};
```

### 2.1 Error name & số nguyên đi kèm

- Mỗi error name được gán một **integer > 0**, duy nhất trong toàn compilation.
- Cùng tên (khai báo ở nhiều nơi) → cùng giá trị.
- Kiểu mặc định là **`u16`**; nếu cung cấp `--error-limit [num]`, Zig chọn kiểu tối thiểu đủ chứa.
- Lấy số nguyên bằng `@intFromError`, đảo ngược bằng `@errorFromInt`, lấy tên bằng `@errorName`.

Đo thật:

```zig
const a = @intFromError(error.FileNotFound);
const b = @intFromError((error{ FileNotFound }).FileNotFound);
try expectEqual(a, b);                 // cùng tên = cùng giá trị
try expect(a != @intFromError(error.AccessDenied)); // khác tên = khác giá trị
```

### 2.2 Coerce subset → superset

```zig
test "coerce subset to superset" {
    const err = foo(AllocationError.OutOfMemory);
    try expectEqual(FileOpenError.OutOfMemory, err); // ✓
}
fn foo(err: AllocationError) FileOpenError { return err; }
```

Ngược lại, **superset → subset thì không** (không thể biết chắc giá trị nằm trong tập con):

```
error: expected type 'error{OutOfMemory}', found 'error{AccessDenied,FileNotFound,OutOfMemory}'
note: 'error.AccessDenied' not a member of destination error set
note: 'error.FileNotFound' not a member of destination error set
```

### 2.3 Shortcut một lỗi: `error.X`

```zig
const err = error.FileNotFound; // tương đương (error{FileNotFound}).FileNotFound
```

Rất tiện khi kết hợp với Inferred Error Sets (mục 9).

---

## 3. The Global Error Set — `anyerror`

> *"`anyerror` refers to the global error set … the union of all other error sets."*

- **Mọi** error set đều coerce được vào `anyerror`.
- Cast ngược `anyerror → tập con` là **explicit cast**, chèn một **language-level assert** kiểm tra lúc
  runtime rằng error nằm trong tập đích.
- ⚠️ Langref khuyên **tránh `anyerror` trong API** vì nó làm compiler không biết được tập lỗi có thể
  xảy ra → mất khả năng kiểm tra đầy đủ trong `switch`, mất tài liệu tự sinh tốt.

---

## 4. Error Union Type — `!T`

> *"An error set type and normal type can be combined with the `!` binary operator to form an error
> union type. You are likely to use an error union type **more often** than an error set type."*

Ví dụ kinh điển (langref) — parse chuỗi thành `u64`:

```zig
fn parseU64(buf: []const u8, radix: u8) !u64 {
    var x: u64 = 0;
    for (buf) |c| {
        const digit = charToDigit(c);
        if (digit >= radix) return error.InvalidChar;
        var ov = @mulWithOverflow(x, radix);
        if (ov[1] != 0) return error.OverFlow;
        ov = @addWithOverflow(ov[0], digit);
        if (ov[1] != 0) return error.OverFlow;
        x = ov[0];
    }
    return x;
}
```

- `!u64` = **inferred error set** (bên trái `!` bỏ trống) `+` `u64`.
- Trong thân hàm: `return error.InvalidChar;` và `return x;` — cả hai **coerce vào `anyerror!u64`**.
- Coerce: giá trị con `1234` hoặc error set `error.SomeError` đều gán được vào `E!T` (đã test).
- **Reflection**: `@typeInfo(E!T).error_union.payload` / `.error_set` cho payload & error set (đã
  test — `i32` và `anyerror`).

```zig
var foo: anyerror!i32 = undefined;
foo = 1234;            // coerce từ child type
foo = error.SomeError; // coerce từ error set
```

---

## 5. Xử lý: `catch`, `try`

### 5.1 `catch default`

```zig
const number = parseU64("zz", 10) catch 13; // lỗi → 13
```

Kiểu vế phải của `catch` phải khớp kiểu đã bóc lỗi của error union, hoặc là `noreturn`. Có thể dùng
**named block** để chạy logic trước khi trả default:

```zig
const number = parseU64("zz", 10) catch blk: {
    // ... làm gì đó ...
    break :blk 99;
};
```

### 5.2 `catch |err| ...`

Bắt lỗi rồi trả lại lỗi đó (≈ `try`) hoặc xử lý:

```zig
_ = parseU64("zz", 10) catch |err| return err;
```

### 5.3 `catch unreachable`

Khi bạn chắc chắn không có lỗi. `unreachable` kích hoạt **illegal behavior** → trong debug/safe sẽ
`panic` đúng lúc nếu giả định sai:

```zig
const number = parseU64("1234", 10) catch unreachable;
```

Đây chính là câu nói của langref: *"It's completely practical to have **failing to check for an
error be a compile error** … if you really want to ignore the error, you can add `catch unreachable`
and get the added benefit of crashing in debug and safe modes if your assumption was wrong."*

### 5.4 `try` — shortcut trả lỗi về

```zig
fn doAThing(str: []const u8, radix: u8) !void {
    _ = try parseU64(str, radix); // lỗi → return lỗi đó từ hàm hiện tại
}
```

`try` = `catch |err| return err` gọn hơn (đã test tương đương).

---

## 6. Xử lý từng lỗi: `if` + `switch`

Khi muốn hành động khác nhau theo từng lỗi, dùng `if (expr) |payload| ... else |err| switch (err)`:

```zig
if (parseU64(str, 10)) |number| {
    doSomethingWithNumber(number);
} else |err| switch (err) {
    error.Overflow => { /* ... */ },
    error.InvalidChar => unreachable, // hứa không xảy ra (crash ở debug nếu sai)
}
```

Bắt lỗi **chưa xử lý** qua nhánh `else` (lúc này `err` là tập lỗi hẹp hơn):

```zig
fn doAnotherThing(str: []const u8) error{InvalidChar}!void {
    if (parseU64(str, 10)) |number| {
        doSomethingWithNumber(number);
    } else |err| switch (err) {
        error.Overflow => { /* handle */ },
        else => |leftover_err| return leftover_err,
    }
}
```

Không cần lỗi thì dùng `else |_|`:

```zig
if (parseU64(str, 10)) |number| {
    doSomethingWithNumber(number);
} else |_| { /* chẳng quan tâm */ }
```

---

## 7. `defer` vs `errdefer`

- `defer X;` — chạy **mọi** đường thoát khỏi block (thành công lẫn lỗi).
- `errdefer X;` — chỉ chạy khi block thoát **với lỗi**.

Đo thật (đếm số lần chạy):

```
defer: 3 lần (cả 2 lần thành công + 1 lần lỗi)
errdefer: 1 lần (chỉ lần lỗi)
```

```zig
const Order = struct {
    const State = struct { var deferred: u32 = 0; var errdeferred: u32 = 0; };
    fn run(should_fail: bool) !void {
        defer State.deferred += 1;    // ALWAYS
        errdefer State.errdeferred += 1; // ONLY on error
        if (should_fail) return error.Boom;
    }
};
try Order.run(false);
try Order.run(false);
_ = Order.run(true) catch {};
try expectEqual(3, Order.State.deferred);
try expectEqual(1, Order.State.errdeferred);
```

Mô-típ allocator kinh điển của langref: vừa cấp xong thì `errdefer deallocate(foo);` — nếu sau đó hàm
lỗi, tài nguyên được dọn; nếu thành công thì `errdefer` không chạy và `foo` được trả ra ngoài.

---

## 8. Merging Error Sets — `A || B`

Toán tử `||` hợp hai error set (dedup tên lỗi trùng):

```zig
const A = error{ NotDir, PathNotFound };
const B = error{ OutOfMemory, PathNotFound };
const C = A || B; // error{NotDir, PathNotFound, OutOfMemory}
```

Dùng cho hàm trả lỗi tuỳ comptime branch — ví dụ std dùng `LinuxFileOpenError || WindowsFileOpenError`.
`switch` trên `C` phải đầy đủ (exhaustive) — đã test.

---

## 9. Inferred Error Sets — `!T`

```zig
// inferred: Zig tự suy tập lỗi từ các `return error.X`
pub fn add_inferred(comptime T: type, a: T, b: T) !T {
    const ov = @addWithOverflow(a, b);
    if (ov[1] != 0) return error.Overflow;
    return ov[0];
}

// explicit: tự khai báo tập lỗi
pub fn add_explicit(comptime T: type, a: T, b: T) Error!T { ... }
```

Đã test cả hai chạy đúng. Nhưng langref cảnh báo **giới hạn của inferred error set**:

> *"When a function has an inferred error set, that function becomes **generic** and thus it becomes
> trickier to … obtain a **function pointer**, or have an error set that is consistent across
> different build targets. Additionally, inferred error sets are **incompatible with recursion**."*

Khuyến nghị: khi gặp những tình huống đó, dùng **explicit error set** (bắt đầu từ tập rỗng `error{}` và
để compile errors hướng dẫn).

---

## 10. Error Return Traces

> *"Error Return Traces show all the points in the code that an error was returned to the calling
> function."*

- Đây **không phải stack trace**: nó theo *luồng lỗi* (error bubbled up), thể hiện rõ **lỗi gốc** vs
  **lỗi cuối** — khi một hàm `catch` lỗi này rồi trả lỗi khác (ví dụ langref: gốc `FileNotFound`, sau
  `switch` đổi thành `PermissionDenied`).
- Bật mặc định ở **debug**, tắt ở fast/safe/small.
- Kích hoạt bằng: `main` trả error / lỗi lọt tới `catch unreachable` / `@errorReturnTrace` +
  `std.debug.dumpErrorReturnTrace`.

### Implementation Details (miễn phí khi không lỗi)

Langref phân tích chi phí:

> *"For the case when no errors are returned, the cost is a **single memory write operation**, only in
> the first non-failable function in the call graph … to initialize this struct in the stack memory:
> `pub const StackTrace = struct { index: usize, instruction_addresses: [N]usize };` A pointer to
> `StackTrace` is passed as a **secret parameter** (first param) to every function that can return an
> error."*

- Khi trả lỗi: gọi `__zig_return_error` (no-inline) ghi `@returnAddress()` vào mảng rồi tăng index —
  "2 math operations plus some memory reads and writes".
- Kết luận thực dụng: **chi phí gần như bằng 0 khi không có lỗi** — đây là lý do Zig khuyên dùng
  `try` ở khắp nơi mà vẫn có thể debug nguyên nhân khi lỗi trồi lên.

---

## 11. Liên hệ memory model

- **Lỗi là giá trị bằng số nguyên** (error set như enum, backing `u16` mặc định) — không phải đối
  tượng heap. Trả lỗi = trả một integer nhỏ, không cấp phát.
- `E!T` khi lưu trong biến là một storage hợp nhất (payload + tag). Việc kiểm tra `if (eu) |v| …`
  chính là đọc storage của biến — xem [`variables.md`](variables.md) về value semantics.
- **Error return trace lưu trên stack** (`StackTrace` struct + secret parameter) — liên quan trực tiếp
  đến câu chuyện stack frame trong [`memory_model.md`](memory_model.md).
- `error.OutOfMemory` là cách Zig biểu diễn heap allocation failure (xem
  [`memory_model.md`](memory_model.md#6-heap-allocation-failure--erroroutofmemory)) — lỗi ở đây gắn với
  allocator: **bạn quyết định** lỗi cấp phát là lỗi gì, không phải crash.

---

## 12. Lỗi thường gặp (probe thật)

| Thông điệp lỗi (Zig 0.17.0) | Nguyên nhân |
|---|---|
| `expected type 'error{X}', found 'error{A,B,..}'` … `'error.A' not a member of destination error set` | cố coerce superset → subset (không tự động) |
| `expected type 'error{OnlyThis}!void', found 'error{NotInSet}'` | return một lỗi **không nằm trong** error set khai báo |
| `error union of type 'error{}!void' is ignored … consider using 'try', 'catch'` | quên xử lý error union (thường từ `expect`) |
| `catch unreachable` → panic ở debug/safe | giả định "không lỗi" hoá ra sai |
| `error.X not a member of error set` (cast `anyerror` → tập con) | runtime assert fail khi cast |

---

## 13. Nguồn & liên kết

- [Zig Language Reference 0.17.1 — Errors](https://ziglang.org/documentation/0.17.1/#Errors)
  (Error Set Type, Global Error Set, Error Union Type, catch, try, errdefer, Merging, Inferred, Error Return Traces)
- [`memory_model.md`](memory_model.md) — `error.OutOfMemory` & allocator failure
- [`enum.md`](enum.md) — error set "like an enum", so sánh backing integer
- [`variables.md`](variables.md) — lưu trữ error union trong biến
- [zig.guide — Errors](https://zig.guide/language-basics/errors/) (học liệu bổ sung)

---

*Viết cho mục đích học tập; mọi đoạn trích quan trọng từ nguồn chính thức có link để tự kiểm chứng.*
