# Comptime trong Zig — Hướng dẫn toàn diện

> Phiên bản xác minh: **Zig 0.17.0** (`zig version`), đối chiếu [Zig Language Reference 0.17.1 — comptime](https://ziglang.org/documentation/0.17.1/#comptime).
> Mọi ví dụ dưới đây đã chạy qua `zig test`/`zig build-obj` trên máy (bộ test 10/10 + 4 probe lỗi).

---

## Mục lục

1. [Comptime là gì? Tại sao nó ở trung tâm thiết kế Zig](#1-comptime-là-gì-tại-sao-nó-ở-trung-tâm-thiết-kế-zig)
2. [Compile-time parameters — cách Zig làm generics](#2-compile-time-parameters--cách-zig-làm-generics)
   - [2.1 Duck typing tại comptime](#21-duck-typing-tại-comptime)
   - [2.2 `if`/`switch` được inline khi điều kiện comptime-known](#22-ifswitch-được-inline-khi-điều-kiện-comptime-known)
3. [Compile-time variables (`comptime var`)](#3-compile-time-variables-comptime-var)
4. [Compile-time expressions (`comptime {}`)](#4-compile-time-expressions-comptime-)
5. [Namespace-level: mọi biểu thức đều ngầm comptime](#5-namespace-level-mọi-biểu-thức-đều-ngầm-comptime)
6. [Generic data structures — hàm trả về `type`](#6-generic-data-structures--hàm-trả-về-type)
7. [Case study: `print` — format string do userland viết](#7-case-study-print--format-string-do-userland-viết)
8. [Liên hệ giữa comptime và memory model](#8-liên-hệ-giữa-comptime-và-memory-model)
9. [Các builtin hỗ trợ comptime](#9-các-builtin-hỗ-trợ-comptime)
10. [Lỗi thường gặp (probe thật)](#10-lỗi-thường-gặp-probe-thật)
11. [Nguồn & liên kết](#11-nguồn--liên-kết)

---

## 1. Comptime là gì? Tại sao nó ở trung tâm thiết kế Zig

Langref mở đầu mục này bằng:

> *"Zig places importance on the concept of whether an expression is **known at compile-time**. There
> are a few different places this concept is used, and these building blocks are used to keep the
> language small, readable, and powerful."*

Comptime là **khái niệm "giá trị biết trước lúc biên dịch hay lúc chạy"** được Zig nâng lên thành
nguyên tắc thiết kế. Thay vì thêm một ngôn ngữ macro/preprocessor riêng (như C/C++), Zig dùng **một cơ
chế duy nhất** — `comptime` — để giải quyết đồng thời nhiều việc:

| Nhu cầu | Trong C/C++ | Trong Zig |
|---|---|---|
| Generics | templates (cú pháp riêng) | `comptime T: type` |
| Hằng số phức tạp | constexpr/macros | biểu thức namespace-level ngầm comptime |
| Reflection | không/khó | `@typeInfo`, `@TypeOf`, `@field`… |
| Inline "tùy kiểu" | template specialization / macros | `if (T == bool)` tự inline |
| Format string an toàn | macros `printf` | một hàm thường trong std dùng comptime |

Câu kết của mục case study rất đúng trọng tâm:

> *"Zig does not special case string formatting in the compiler … It's Zig all the way down."*

(Không có "ngôn ngữ con" nào; mọi thứ đều là Zig.)

---

## 2. Compile-time parameters — cách Zig làm generics

> *"Compile-time parameters is how Zig implements generics. It is **compile-time duck typing**."*

Tham số đánh dấu `comptime` có **hai nghĩa bắt buộc**:

1. **Ở chỗ gọi (callsite):** giá trị phải biết tại compile-time, nếu không → compile error.
2. **Trong thân hàm:** giá trị *được coi là* biết tại compile-time → có thể dùng để phân nhánh,
   chọn kiểu, sinh code khác nhau.

Vì **type là first-class citizen** trong Zig (gán vào biến, truyền làm tham số, trả về từ hàm được),
bạn truyền một *kiểu* vào tham số `comptime`:

```zig
fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

const f = max(f32, 3.0, 1.0);  // sinh bản dành cho f32
const i = max(u64, 12, 64);    // sinh bản dành cho u64
```

Đã chạy thật:

```
test "comptime parameters: same fn for f32 and u64" ... OK
```

### 2.1 Duck typing tại comptime

"Compile-time duck typing" nghĩa là: hàm sẽ được *phân tích (analyze) riêng cho từng tổ hợp kiểu*, và
lỗi kiểu chỉ xảy ra khi tổ hợp đó thực sự được dùng. Truyền type **runtime** vào tham số `comptime` là
compile error:

```zig
fn foo(condition: bool) void {
    const result = max(if (condition) f32 else u64, 1234, 5678); // ❌
    _ = result;
}
```

```
error: unable to resolve comptime value
       const result = max(if (condition) f32 else u64, 1234, 5678);
note: argument to comptime parameter must be comptime-known
```

Còn dùng `max(bool, ...)` khi thân hàm viết `a > b` thì lỗi ngay trong lần phân tích kiểu đó:

```
error: operator > not allowed for type 'bool'
```

### 2.2 `if`/`switch` được inline khi điều kiện comptime-known

Bởi vì trong thân hàm có `comptime T`, bạn có thể phân nhánh **theo kiểu** và compiler sẽ **bỏ hẳn
nhánh không đúng** — nhánh sai *không bao giờ được phân tích*, kể cả nếu nó chứa thứ vô nghĩa:

```zig
fn max(comptime T: type, a: T, b: T) T {
    if (T == bool) {
        return a or b;      // nhánh này chỉ chạy cho bool
    } else if (a > b) {
        return a;
    } else {
        return b;
    }
}
try @import("std").testing.expectEqual(true, max(bool, false, true));
```

Langref nói rõ cơ chế:

> *"Zig implicitly inlines `if` expressions when the condition is known at compile-time, and the
> compiler guarantees that it will **skip analysis of the branch not taken**."*

`switch` cũng được "implicitly inline" tương tự khi nhánh (target expression) comptime-known.

---

## 3. Compile-time variables (`comptime var`)

> *"The programmer can label variables as `comptime`. This guarantees … **every load and store of the
> variable is performed at compile-time**. Any violation of this results in a compile error."*

```zig
var x: i32 = 1;       // biến runtime
comptime var y: i32 = 1; // biến comptime

x += 1;
y += 1;

if (y != 2) {          // y comptime-known → if này bị tính tĩnh, không bao giờ chạy
    @compileError("not reached");
}
```

**Kết hợp với `inline while`/`inline for`** ta có kỹ thuật "đánh giá một phần" (partial evaluation):
hàm được **sinh ra nhiều phiên bản** tùy giá trị comptime, biến comptime lặp để chọn nhánh:

```zig
fn performFn(comptime prefix_char: u8, start_value: i32) i32 {
    var result: i32 = start_value;
    comptime var i = 0;
    inline while (i < cmd_fns.len) : (i += 1) {
        if (cmd_fns[i].name[0] == prefix_char) {
            result = cmd_fns[i].func(result);
        }
    }
    return result;
}
try expectEqual(6,  performFn('t', 1));  // two + three
try expectEqual(1,  performFn('o', 0));  // one
try expectEqual(99, performFn('w', 99)); // không gọi gì
```

Compiler sinh 3 phiên bản khác nhau của `performFn` (đã xem trong langref) — **ngay cả trong debug
build**. Lưu ý lời cảnh báo của langref: đây **không phải** cách "tối ưu hơn", mà là cách *đảm bảo thứ
phải tính lúc compile thì tính lúc compile* → bắt lỗi sớm và cho phép diễn đạt mà ngôn ngữ khác phải
dùng macro/preprocessor.

---

## 4. Compile-time expressions (`comptime {}`)

> *"A programmer can use a `comptime` expression to guarantee that the expression will be evaluated at
> compile-time. If this cannot be accomplished, the compiler will emit an error."*

Trong một biểu thức `comptime`:

- Mọi biến đều là **comptime variables**.
- Mọi `if`/`while`/`for`/`switch` được đánh giá tại comptime (hoặc lỗi nếu không làm được).
- **`return`/`try` không hợp lệ** (trừ khi chính hàm đang được gọi ở comptime).
- Mọi thứ **có runtime side-effect hoặc phụ thuộc runtime** → compile error (vd gọi `extern fn`):

```zig
extern fn exit() noreturn;
pub fn main() void {
    comptime {
        exit(); // ❌ error: comptime call of extern function
    }
}
```

Điểm mạnh: **một hàm có thể được gọi cả ở runtime lẫn comptime mà không cần sửa**:

```zig
fn fibonacci(index: u32) u32 {
    if (index < 2) return index;
    return fibonacci(index - 1) + fibonacci(index - 2);
}

try expectEqual(13, fibonacci(7));          // runtime
try comptime expectEqual(13, fibonacci(7)); // comptime
```

Nếu bỏ base case, lỗi sẽ được phát hiện **ngay khi biên dịch** với stack trace comptime:

```
error: overflow of integer type 'u32' with value '-1'
    return fibonacci(index - 1) + fibonacci(index - 2);
note: called at comptime here (7 times)
```

Còn với `i32` (signed) thì compiler bỏ cuộc sau **1000 branches** mặc định (tăng bằng `@setEvalBranchQuota`).

---

## 5. Namespace-level: mọi biểu thức đều ngầm comptime

> *"At Namespace level (outside of any function), **all expressions are implicitly comptime
> expressions**."*

Đây là điều khiến hằng số phức tạp trở nên dễ dàng — bạn có thể gọi hàm để khởi tạo dữ liệu hằng:

```zig
const first_25_primes = firstNPrimes(25);      // chạy lúc compile
const sum_of_first_25_primes = sum(&first_25_primes); // = 1060

fn firstNPrimes(comptime n: usize) [n]i32 { ... }
fn sum(numbers: []const i32) i32 { ... }

test {
    try @import("std").testing.expectEqual(1060, sum_of_first_25_primes);
}
```

Khi build, Zig nhúng **kết quả đã tính sẵn** vào binary (langref cho xem LLVM IR: một mảng 25 số nguyên
tố + hằng 1060). Hàm `sum` vẫn có thể được gọi ở runtime với slice bình thường — **không có cú pháp
đặc biệt nào** cho hai chế độ.

---

## 6. Generic data structures — hàm trả về `type`

Không có từ khoá "generic" — chỉ là **một hàm nhận `comptime T: type` và trả về `struct`**:

```zig
fn List(comptime T: type) type {
    return struct {
        items: []T,
        len: usize,
    };
}

var buffer: [10]i32 = undefined;
var list = List(i32){ .items = &buffer, .len = 0 };
```

- Vì hàm được call ở comptime và **memoized**, `LinkedList(i32) == LinkedList(i32)` (đã test).
- Tên tự suy ra là `List(i32)` cho thông báo lỗi/dễ đọc.
- **Struct tự tham chiếu**: `Node.next: ?*Node` hoạt động vì các decl top-level order-independent và
  kích thước con trỏ biết trước (đã test trong `c1_comptime`).

---

## 7. Case study: `print` — format string do userland viết

`std.debug.print("{s} {d}", .{...})` **không được nhúng đặc biệt vào compiler** — nó là một hàm userland
dùng comptime:

1. `comptime format: []const u8` — format string bắt buộc comptime-known (nhưng *không bắt buộc* là
   literal: một `const fmt` cũng được).
2. `args: anytype` — nhận bất kỳ kiểu nào.
3. `inline for` trên format + `comptime var state` duyệt từng ký tự, gọi `self.printValue(args[next_arg])` cho `{}`.
4. `printValue` dùng `switch (@typeInfo(@TypeOf(value)))` để chọn cách in theo kiểu.
5. Lỗi format (thừa/thiếu đối số) được `@compileError` phát hiện lúc biên dịch:

```
error: unused argument in 'here is a string: '{s}' here is a number: {}'
       1 => @compileError("unused argument in '" ++ fmt ++ "'"),
```

Đây là minh hoạ hoàn hảo cho câu: *"Zig all the way down"*.

---

## 8. Liên hệ giữa comptime và memory model

- **Giá trị comptime không chiếm bộ nhớ runtime** — chỉ tồn tại trong lúc compile; chỉ khi được lưu
  vào `const` (hoặc cần địa chỉ) thì mới được materialize vào binary, thường nằm ở **global constant
  data** (xem [`variables.md`](variables.md) mục 8 và [`memory_model.md`](memory_model.md) mục 3.1).
- `comptime var` **không phải runtime storage**; mọi load/store là việc của semantic analysis.
- Một biến `const` local mà init **comptime-known** thì bản thân nó comptime-known → có thể nằm ở
  rodata thay vì stack (đã thí nghiệm trong [`variables.md`](variables.md) mục 5.3).
- Hai thái cực "lúc nào thì runtime": chỉ khi giá trị được *ép buộc* chạy runtime (truyền vào hàm
  runtime, lấy địa chỉ runtime, gọi function pointer…) compiler mới vật chất hoá nó.

---

## 9. Các builtin hỗ trợ comptime

| Builtin | Vai trò |
|---|---|
| `@TypeOf(expr)` | lấy type của biểu thức (comptime) |
| `@typeInfo(T)` | reflection: `@typeInfo(u8).int.bits == 8` (đã test) |
| `@typeName(T)` | tên type (chuỗi comptime) |
| `@compileError(msg)` | báo lỗi biên dịch có điều kiện |
| `@compileLog(...)` | in log lúc compile (debug) |
| `@setEvalBranchQuota(n)` | tăng quota 1000 nhánh mặc định |
| `@field`, `@hasField`, `@FieldType` | reflection trên field |
| `@inComptime()` | trả về true nếu đang ở comptime |
| `@embedFile`, `@import` | đưa file/mô-đun vào lúc compile |
| `@bitCast`, `@errorCast`, `@intCast`… | được hưởng result-type + có thể tính ở comptime |

---

## 10. Lỗi thường gặp (probe thật)

| Thông điệp lỗi (Zig 0.17.0) | Nguyên nhân |
|---|---|
| `unable to resolve comptime value` … `argument to comptime parameter must be comptime-known` | truyền giá trị runtime vào tham số `comptime` |
| `comptime call of extern function` | gọi hàm ngoài (extern) trong `comptime {}` |
| `operator > not allowed for type 'bool'` | thân hàm duck-typing không xử lý kiểu được dùng |
| `overflow of integer type 'u32' with value '-1'` | đệ quy sai base-case khi chạy comptime với `u32` |
| `local variable is never mutated … consider using 'const'` | khai báo `var` rồi không bao giờ gán lại — hãy dùng `const` |

---

## 11. Nguồn & liên kết

- [Zig Language Reference 0.17.1 — comptime](https://ziglang.org/documentation/0.17.1/#comptime)
- [`variables.md`](variables.md) mục 8 — biến `comptime var` & vùng nhớ của chúng
- [`memory_model.md`](memory_model.md) — comptime vs runtime memory
- [`struct.md`](struct.md) — generic struct trả về từ hàm `type`
- [`enum.md`](enum.md) — `@EnumLiteral`/`@backingInt` (cũng là cơ chế comptime)

---

*Viết cho mục đích học tập; mọi đoạn trích quan trọng từ nguồn chính thức có link để tự kiểm chứng.*
