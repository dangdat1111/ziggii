# Variables trong Zig — và mối liên hệ với Memory Model

> Phiên bản xác minh: **Zig 0.17.0** (`zig version` → 0.17.0), đối chiếu với
> [Zig Language Reference 0.17.1 — Variables](https://ziglang.org/documentation/0.17.1/#Variables)
> và [0.17.1 — Memory](https://ziglang.org/documentation/0.17.1/#Memory).
> Mọi ví dụ dưới đây đã chạy qua `zig test`/`zig build-obj` trên máy để kiểm chứng
> (bộ test ở mục tổng hợp).

---

## Mục lục

1. [Cốt lõi: "A variable is a unit of Memory storage"](#1-cốt-lõi-a-variable-is-a-unit-of-memory-storage)
2. [`const` vs `var` — quy tắc vàng](#2-const-vs-var--quy-tắc-vàng)
3. [Shadowing — điều cấm kỵ](#3-shadowing--điều-cấm-kỵ)
4. [Bốn loại biến theo scope & lifetime (langref)](#4-bốn-loại-biến-theo-scope--lifetime-langref)
   - [4.1 Namespace Level Variables](#41-namespace-level-variables)
   - [4.2 Locally-Scoped Global Variables](#42-locally-scoped-global-variables)
   - [4.3 Thread Local Variables](#43-thread-local-variables)
   - [4.4 Local Variables](#44-local-variables)
5. [Liên hệ Memory Model: "Where are the bytes?"](#5-liên-hệ-memory-model-where-are-the-bytes)
   - [5.1 Bảng ánh xạ biến → vùng bộ nhớ](#51-bảng-ánh-xạ-biến--vùng-bộ-nhớ)
   - [5.2 Kết quả chạy thật: in địa chỉ từng vùng](#52-kết-quả-chạy-thật-in-địa-chỉ-từng-vùng)
   - [5.3 Hai const local "sống" ở hai nơi khác nhau](#53-hai-const-local-sống-ở-hai-nơi-khác-nhau)
   - [5.4 Hết hạn: "expired local" & Illegal Behavior](#54-hết-hạn-expired-local--illegal-behavior)
6. [Value semantics: biến là *storage*, không phải "refer"](#6-value-semantics-biến-là-storage-không-phải-refer)
7. [Result Location Semantics — viết thẳng vào đích, bỏ bản sao trung gian](#7-result-location-semantics--viết-thẳng-vào-đích-bỏ-bản-sao-trung-gian)
8. [Comptime variables — biến không chiếm bộ nhớ runtime](#8-comptime-variables--biến-không-chiếm-bộ-nhớ-runtime)
9. [Kích thước & alignment — một biến chiếm bao nhiêu byte?](#9-kích-thước--alignment--một-biến-chiếm-bao-nhiêu-byte)
10. [undefined, 0xaa và các safety mode](#10-undefined-0xaa-và-các-safety-mode)
11. [Bảng tổng kết nhanh](#11-bảng-tổng-kết-nhanh)
12. [Video từ chính tác giả (Andrew Kelley)](#12-video-từ-chính-tác-giả-andrew-kelley)
13. [Nguồn tham khảo & liên kết với các tài liệu khác](#13-nguồn-tham-khảo--liên-kết-với-các-tài-liệu-khác)

---

## 1. Cốt lõi: "A variable is a unit of Memory storage"

Mục **Variables** của [langref 0.17.1](https://ziglang.org/documentation/0.17.1/#Variables) mở đầu
bằng một câu rất quan trọng:

> *"A variable is a unit of **Memory** storage."*

Dịch: **"Một biến là một đơn vị lưu trữ bộ nhớ."**

Ý nghĩa: trong Zig, biến **không** phải là khái niệm trừu tượng "tên gọi cho một giá trị" như trong
các ngôn ngữ GC — biến **mô tả một vùng bộ nhớ cụ thể** (địa chỉ + kích thước + kiểu). Vì vậy, muốn
hiểu biến trong Zig thì **bắt buộc phải hiểu memory model** của Zig: biến đó nằm ở vùng nhớ nào, sống
tới khi nào, ai cấp phát và ai thu hồi.

Toàn bộ mục này vì thế được viết theo cấu trúc: *biến → storage → vùng bộ nhớ*. Nếu bạn chưa đọc
[`memory_model.md`](memory_model.md) (bức tranh tổng thể về bộ nhớ Zig: stack/heap/global/static),
bạn nên đọc song song — tài liệu này sẽ nối kết chặt với nó.

---

## 2. `const` vs `var` — quy tắc vàng

Langref đặt nguyên tắc đầu tiên rất rõ:

> *"It is generally preferable to use `const` rather than `var` … This causes **less work for both
> humans and computers** to do when reading code, and creates more optimization opportunities."*

Tức là: **ưu tiên `const`** — ít chi phí cho cả người đọc lẫn compiler, và mở ra nhiều cơ hội tối ưu
hơn (biết trước biến không đổi thì compiler có thể xếp nó vào vùng hằng số, hoặc tối ưu thành hằng
immediate thay vì giữ nơi trên stack).

### 2.1 Phải khởi tạo ngay

```zig
pub fn main() void {
    var x: i32; // ❌ không được! "expected '=', found ';'"
    _ = &x;
}
```

Thông điệp lỗi chuẩn trên Zig 0.17.0:

```
error: expected '=', found ';'
    var x: i32;
              ^
```

Mọi biến `var`/`const` **đều phải có giá trị khởi tạo** tại điểm khai báo. Nếu thực sự muốn gán giá
trị sau (ví dụ đổ dữ liệu vào buffer), dùng `= undefined`:

```zig
var buffer: [1024]u8 = undefined; // chấp nhận: tạm thời "vô nghĩa", ghi đè sau
```

### 2.2 `const` áp lên toàn bộ *bytes* mà identifier trỏ tới

Đây là câu kinh điển của mục Variables:

> *"`const` applies to all of the bytes that the identifier immediately addresses. **Pointers have
> their own const-ness**."*

Nghĩa là:

- `const arr: [2]u8 = ...` → **toàn bộ 2 byte** của `arr` là bất biến. Không thể lấy con trỏ `*[2]u8`
  (mut) vào mảng đó.
- Nhưng **con trỏ có const riêng của nó**: một biến `*const u8` khác với `*u8`; một biến `const p:
  *u8` thì *biến `p`* không gán lại được, **nhưng byte `p.*` vẫn ghi được** (vì con trỏ không const).

Xác minh bằng probe lỗi (`zig test`):

```zig
const arr = [2]u8{ 1, 2 };
test "const bytes cannot get a mutable pointer" {
    const p: *[2]u8 = &arr; // ❌ error: expected type '*[2]u8', found '*const [2]u8'
    _ = p;
}
```

```
error: expected type '*[2]u8', found '*const [2]u8'
note: cast discards const qualifier
```

Ngược chiều — con trỏ `*const` thì không ghi qua nó được, kể cả khi nó đang trỏ vào biến `var`:

```zig
pub fn bump(x: *const u8) void {
    x.* += 1; // ❌ error: cannot assign to constant
}
```

```
error: cannot assign to constant
    x.* += 1;
```

### 2.3 Gán lại `const` = lỗi

```zig
const x = 1234;
test "cannot reassign const" {
    x += 1; // ❌ error: cannot assign to constant
}
```

### 2.4 `var` với giá trị comptime không cần kiểu tường minh?

Không — một lỗi dễ mắc: `var a = 1;` thì `1` là `comptime_int`, mà biến `var` là runtime storage nên
**phải có kiểu kích thước cố định**:

```
error: variable of type 'comptime_int' must be const or comptime
    var a = 1;
note: to modify this variable at runtime, it must be given an explicit fixed-size number type
```

→ Đúng là `var a: u8 = 1;` hoặc `const a = 1;`. (Chi tiết về `comptime_int` trong
[`values.md`](values.md).)

---

## 3. Shadowing — điều cấm kỵ

> *"Variables are **never allowed to shadow** Identifiers from an outer scope."*

Zig **cấm tuyệt đối** việc dùng tên trùng với identifier ở scope bên ngoài (kể cả block lồng nhau):

```zig
const pi = 3.14;
test "shadowing" {
    {
        var pi: i32 = 1234; // ❌ error: local variable shadows declaration of 'pi'
        _ = &pi;
    }
}
```

```
error: local variable shadows declaration of 'pi'
note: declared here
```

Hệ quả tốt đẹp của luật này (trích 0.17.1, mục Blocks → Shadowing):

> *"Because of this, when you read Zig code you can always rely on an identifier to consistently mean
> the same thing within the scope it is defined."*

Tuy nhiên, **dùng cùng tên ở hai scope độc lập (không lồng nhau) thì không phải shadowing** — hoàn
toàn hợp lệ:

```zig
test "same name in separate scopes is NOT shadowing" {
    {
        const pi = 3.14;
        _ = pi;
    }
    {
        var pi: bool = true;
        _ = &pi;
    }
}
```

Ngoài ra, `_` là **identifier discard** (chỉ dùng để vứt giá trị), được phép "trùng" vì nó không phải
một cái tên thật:

```zig
var a: u8 = 1;
var b: u8 = 2;
a, b = .{ 9, 10 }; // destructuring vào var có sẵn
_ = a; // vứt đi
```

(Liên quan đến Scope/Block — xem [`identifiers.md`](identifiers.md).)

---

## 4. Bốn loại biến theo scope & lifetime (langref)

Mục **Variables** 0.17.1 phân biệt rõ **4 loại** theo *nơi khai báo* → quyết định *lifetime*
(thời gian sống) và *vùng nhớ*:

| Loại | Khai báo ở đâu | Lifetime | Vùng bộ nhớ |
|---|---|---|---|
| **Namespace Level** | top-level (file / struct / enum / union / opaque) | toàn chương trình | global data / global constant data |
| **Locally-Scoped Global** | trong hàm, thông qua namespace `const S = struct { var … }` | toàn chương trình | global data |
| **Thread Local** | container level, có từ khoá `threadlocal` | theo vòng đời luồng | TLS |
| **Local** | trong hàm / `comptime` block / block có nhãn | đến khi hàm trả về | stack frame |

### 4.1 Namespace Level Variables

> *"Namespace level variables have **global lifetime** and are **order-independent** and **lazily
> analyzed**. The initialization value of namespace level variables is **implicitly comptime**. If a
> namespace level variable is `const` then its value is comptime-known, otherwise it is
> runtime-known."*

- **Order-independent**: khai báo sau dùng trước vẫn được (giống mọi decl ở top-level).

```zig
var y: i32 = add(10, x); // khai báo TRƯỚC x vẫn OK
const x: i32 = add(12, 34);

fn add(a: i32, b: i32) i32 {
    return a + b;
}
// x = 46 (comptime-known), y = 56 (runtime-known, init thoải mái ở comptime)
```

- **Lazily analyzed**: biến khai báo nhưng không ai dùng → compiler không cần phân tích (tiết kiệm
  thời gian build).
- **Init bắt buộc là comptime**: vì khởi tạo xảy ra "khi build", giá trị khởi tạo phải tính được lúc
  comptime; nếu là giá trị runtime → lỗi.

```zig
var g_base: u32 = 1;
var g: usize = @intFromPtr(&g_base); // ❌ không tính được ở comptime (địa chỉ runtime)
```

```
error: unable to evaluate comptime expression
       var g: usize = @intFromPtr(&g_base);
note: operation is runtime due to this operand
```

- Được khai báo **bên trong** `struct` / `enum` / `union` / `opaque` (mỗi namespace là một "hộp"
  biến):

```zig
const Counter = struct {
    var hits: u64 = 0; // global data
    fn next() u64 {
        hits += 1;
        return hits;
    }
};
try std.testing.expectEqual(2, Counter.next()); // lần 2
```

### 4.2 Locally-Scoped Global Variables

> *"It is also possible to have local variables with **global lifetime** by using **namespaces inside
> functions**."*

Đây là mẹo "static local" kiểu Zig: khai báo một `struct` *trong* hàm, bên trong nó là `var` có
lifetime toàn chương trình — nhưng **chỉ truy cập được từ trong hàm đó**:

```zig
fn foo() i32 {
    const S = struct {
        var x: i32 = 1234;
    };
    S.x += 1;
    return S.x; // 1235, rồi 1236, …
}
```

> ⚠️ Lưu ý: đây là tính năng ghi trong langref **0.17.1**; ở các phiên bản cũ cách viết này có thể
> chưa được hỗ trợ/khác hành vi. Đã chạy OK trên Zig 0.17.0.

### 4.3 Thread Local Variables

> *"A variable may be specified to be a thread-local variable using the `threadlocal` keyword, which
> makes **each thread work with a separate instance** of the variable … Thread local variables may
> not be `const`."*

```zig
threadlocal var tls_counter: i32 = 1234;

fn bumpTls() void {
    tls_counter += 1; // chỉ sửa bản của luồng đang chạy
}

test "thread local: one instance per thread" {
    const t1 = try std.Thread.spawn(.{}, bumpTls, .{});
    const t2 = try std.Thread.spawn(.{}, bumpTls, .{});
    bumpTls();
    t1.join();
    t2.join();
    try std.testing.expectEqual(1235, tls_counter); // main luồng chỉ bị bump đúng 1 lần
}
```

Ba quy tắc đáng chú ý (đã xác minh):

- **`threadlocal` chỉ được khai báo ở container level** (top-level / struct) — **trong thân hàm là
  lỗi cú pháp**: `error: expected statement, found 'threadlocal'`.
- **Không được `threadlocal const`**:
  ```
  error: threadlocal variable cannot be constant
  threadlocal const x: i32 = 5;
  ```
  (hợp lý: bản sao của mỗi luồng phải có khả năng khác nhau… nhưng điểm chính là tên biến là storage
  có thể đổi).
- Trong [**Single Threaded Builds**](https://ziglang.org/documentation/0.17.1/#Single-Threaded-Builds),
  mọi biến `threadlocal` được xử lý như Namespace Level Variables bình thường.

### 4.4 Local Variables

> *"Local variables occur inside Functions, `comptime` blocks, and labeled Blocks. When a local
> variable is `const`, it means that after initialization, the variable's value will not change. **If
> the initialization value of a const variable is comptime-known, then the variable is also
> comptime-known.**"*

- Sống **trong stack frame** của lần gọi hàm; kết thúc khi hàm trả về (xem [5.4](#54-hết-hạn-expired-local--illegal-behavior)).
- `const` local với init **comptime-known** → bản thân cũng comptime-known → có thể được đặt ở vùng
  hằng số toàn cục thay vì stack (xem thí nghiệm [5.3](#53-hai-const-local-sống-ở-hai-nơi-khác-nhau)).
- `const` local với init **runtime** (ví dụ `const c: u32 = rv;` với `rv` là biến runtime) → **vẫn
  phải nằm trên stack** (vì giá trị chưa biết lúc compile), chỉ là không gán lại được.

---

## 5. Liên hệ Memory Model: "Where are the bytes?"

Mục **Memory** của langref khai mở bằng câu nền tảng (đã phân tích sâu trong
[`memory_model.md`](memory_model.md)):

> *"The Zig language performs **no memory management on behalf of the programmer**. … Zig programmers
> must always be able to answer the question: **Where are the bytes?**"*

Bởi vì *biến = unit of memory storage*, câu hỏi "các byte của biến này đang ở đâu?" chính là bài toán
trung tâm khi khai báo biến trong Zig.

### 5.1 Bảng ánh xạ biến → vùng bộ nhớ

Trích trực tiếp mục **Where are the bytes?** (0.17.1) + đối chiếu bảng phân loại mục 4:

| Thứ bạn viết | Vùng bộ nhớ | Cấp phát | Ghi được? |
|---|---|---|---|
| `"hello"` (string literal) | **global constant data** | khi build | ❌ |
| `const x = 5;` (comptime-known) | **global constant data** | khi build | ❌ |
| compile-time variables (`comptime var`) | **global constant data** | khi build | ❌ (load/store chỉ xảy ra ở comptime) |
| `var` trong hàm / `const` local runtime | **stack frame** | vào hàm | ✅ (chỉ `var`) |
| `var` ở top-level hoặc trong struct | **global data** | khi chương trình start | ✅ |
| `threadlocal var` | **TLS** (mỗi luồng một bản) | khi luồng start | ✅ |
| `allocator.alloc` / `create` | **do allocator quyết định** | khi bạn gọi | ✅ |

> Langref nói thẳng về hai "loại hằng" nằm cùng vùng với chuỗi:
> *"Just like string literals, `const` declarations, when the value is known at comptime, are stored
> in the global constant data section. **Also Compile Time Variables are stored in the global constant
> data section.**"*

### 5.2 Kết quả chạy thật: in địa chỉ từng vùng

Đây là kết quả `zig test pos2_where.zig` trên máy (macOS, aarch64) — minh hoạ trực tiếp bảng trên:

```
stack local            @0x16cf7de6c   ← vùng địa chỉ cao (stack)
stack big buffer       @0x16cf7deb0   (cách local 68 byte)
string literal (rodata)@0x102feb33c   ← vùng thấp (read-only data)
const comptime (rodata)@0x102fea394   ← đúng sát chuỗi, cũng read-only
global var             @0x10302aca0   ← writable data, cao hơn rodata một chút
struct stat            @0x103075318   ← cũng writable global data
heap buffer (page)     @0x1030f8000   ← do page_allocator quyết định
```

- **string literal và const comptime nằm cạnh nhau**, trong vùng chỉ đọc — đúng lời langref.
- **global var và struct-var nằm trong vùng writable**.
- **stack nằm tận vùng địa chỉ cao** (cổ điển), heap ở vùng thấp hơn.
- (Con số cụ thể chỉ mang tính minh hoạ; trên máy/OS khác thứ tự tương đối có khác, nhưng *phân lớp*
  rodata / data / stack / heap là bản chất.)

### 5.3 Hai const local "sống" ở hai nơi khác nhau

Thí nghiệm tinh tế: cùng là `const local`, nhưng **comptime-known → rodata**, còn **runtime → stack**:

```
local const runtime  @0x16d879ec4   ← cùng quãng stack với biến runtime gốc
local const comptime @0x1026ef0a4   ← nằm cạnh string literal (rodata)
(rodata anchor)      @0x1026f01ec
(stack anchor)       @0x16d879ec0
```

```zig
var rv: u32 = 9;
const local_const_runtime: u32 = rv;    // copy từ runtime → stack
const local_const_comptime: u32 = 123;  // biết trước → có thể để rodata
```

→ Ép kiểu "const local" sẽ ảnh hưởng **nơi các byte sống**. Đó chính là lý do langref nói `const`
"creates more optimization opportunities".

### 5.4 Hết hạn: "expired local" & Illegal Behavior

Về stack, langref nói rõ (mục Where are the bytes?):

> *"`var` declarations inside functions are stored in the function's **stack frame**. Once a function
> returns, any Pointers to variables in the function's stack frame become **invalid references**, and
> dereferencing them becomes **unchecked Illegal Behavior**."*

Zig 0.17 thậm chí đã chặn ngay lúc biên dịch trường hợp phổ biến nhất — **trả con trỏ về biến local**:

```zig
fn get() *u8 {
    var x: u8 = 1;
    return &x; // ❌
}
```

```
error: returning address of expired local variable 'x'
note: declared runtime-known here
```

Đây là sự giao thoa hoàn hảo giữa *variables* và *memory model*: biến local thuộc về stack frame, nên
"địa chỉ của nó" không được lọt ra ngoài. Với con trỏ có lifetime phức tạp hơn, Zig dựa vào **quy ước
ownership** của lập trình viên (mục Lifetime and Ownership — xem [`memory_model.md`](memory_model.md#8-lifetime--ownership--hoặc-ai-sở-hữu-byte-này)).

---

## 6. Value semantics: biến là *storage*, không phải "refer"

Một hệ quả trực tiếp của *"variable = unit of storage"*: **gán biến = copy dữ liệu**, không phải tạo
alias. Đã xác minh:

```zig
test "arrays are copied on assignment" {
    const a = [4]u8{ 1, 2, 3, 4 };
    var b = a;     // b là MỘT bản copy 4 byte tách biệt
    b[0] = 99;
    try std.testing.expect(a[0] == 1);  // a không đổi
    try std.testing.expect(b[0] == 99);
}

test "structs are copied on assignment" {
    const Pair = struct { a: u32, b: u32 };
    const p1 = Pair{ .a = 1, .b = 2 };
    var p2 = p1;
    p2.a = 100;
    try std.testing.expect(p1.a == 1); // p1 không đổi
}
```

Điểm ngoại lệ quan trọng: **slice `[]T` là một con trỏ (struct `{ptr, len}`)** chứ không phải khối dữ
liệu. Khi gán slice, bạn **copy descriptor (16 byte)**, không copy dữ liệu phía sau — nên "gán slice
rồi sửa qua slice mới" sẽ **sửa luôn dữ liệu gốc**:

```zig
test "slice assignment copies the descriptor, not the data" {
    var arr = [_]u8{ 1, 2, 3, 4 };
    const s1: []u8 = &arr;
    var s2 = s1;
    s2[0] = 77;                 // sửa SAME backing array
    try std.testing.expect(arr[0] == 77);
}
```

Đây là lý do mọi thảo luận về biến trong Zig phải đi kèm câu hỏi: *biến này là **dữ liệu** (copy theo
value) hay là **view/pointer** (chia sẻ vùng nhớ)?* (Chi tiết slice/pointer trong
[`memory_model.md`](memory_model.md#42-pointer-single-item-vs-many-item).)

---

## 7. Result Location Semantics — viết thẳng vào đích, bỏ bản sao trung gian

Liên kết nữa giữa biến và memory model là cách Zig **đặt giá trị vào biến**. Mục
[Result Location Semantics](https://ziglang.org/documentation/0.17.1/#Result-Location-Semantics) giải
thích:

> *"Every expression is assigned optional result location information … **this system is the primary
> mechanism of type inference in the language** … a result location: a pointer to which the value must
> be **directly written**. This can be used to **prevent intermediate copies** when initializing data
> structures, which can be important for types which must have a fixed memory address ("pinned"
> types)."*

Nói đơn giản: khi bạn viết

```zig
const x: u32 = 42;
```

thì `x` cung cấp cho literal `42` một **result type** (`u32`) và một **result location** (địa chỉ của
`x`) — compiler **coerce rồi ghi thẳng vào đúng chỗ**, không tạo biến tạm `comptime_int` rồi copy qua.

Bảng lan truyền result type (trích langref) đáng nhớ:

| Expression | Parent Result Type | Sub-expression Result Type |
|---|---|---|
| `const val: T = x` | – | `x` là `T` |
| `var val: T = x` | – | `x` là `T` |
| `val = x` | – | `x` là `@TypeOf(val)` |
| `&x` | `*T` | `x` là `T` |
| `&x` | `[]T` | `x` là một array of `T` |
| `.{ .a = x }` | `T` | `x` là `@FieldType(T, "a")` |

→ Với biến, ý nghĩa là: **type annotation trên khai báo biến là cơ chế ép kiểu chính** (không cần
`@as`), và giá trị được **ghi trực tiếp vào storage** của biến.

---

## 8. Comptime variables — biến không chiếm bộ nhớ runtime

Mục [Comptime → Compile-Time Variables](https://ziglang.org/documentation/0.17.1/#Comptime) mô tả:

> *"The programmer can label variables as `comptime`. This guarantees to the compiler that **every load
> and store of the variable is performed at compile-time**. Any violation of this results in a compile
> error."*

Đã xác minh hành vi:

```zig
test "comptime var evaluated at compile time" {
    var x: i32 = 1;          // runtime
    comptime var y: i32 = 1; // comptime: mọi load/store diễn ra lúc biên dịch
    x += 1;
    y += 1;
    try std.testing.expectEqual(2, x);
    try std.testing.expectEqual(2, y);
    // Vì y comptime-known, if này bị tính tĩnh và không bao giờ chạy:
    if (y != 2) @compileError("wrong y value");
}
```

**Vi phạm** (gán giá trị runtime vào `comptime var`) là compile error:

```zig
fn make(v: u8) void {
    comptime var cv: u8 = v; // ❌ khi v từ runtime
    cv += 1;
}
```

```
error: unable to resolve comptime value
       comptime var cv: u8 = v;
note: 'comptime' keyword forces comptime evaluation
```

**Ứng dụng kinh điển**: `comptime var` + `inline while` để viết hàm *tính một phần lúc biên dịch* —
compiler sẽ sinh ra nhiều phiên bản hàm cho từng giá trị comptime (ví dụ `performFn` trong langref
tạo 3 phiên bản ứng với `'t'`, `'o'`, `'w'`). Đây là cách Zig làm "macros/metaprogramming không cần
preprocessor".

Về memory model: **compile-time variables được lưu trong global constant data section** (chỉ tồn tại
khi được materialize vào binary); chúng không phải runtime storage theo nghĩa stack/heap. Trong 0.17,
biến khai báo trong biểu thức `comptime` đều **mặc định là comptime variables**.

---

## 9. Kích thước & alignment — một biến chiếm bao nhiêu byte?

Vì biến là *storage*, kích thước và alignment của nó là chuyện bậc nhất. Bảng đo được trên máy
(Zig 0.17.0, 64-bit):

```zig
test "sizes and alignment of variable storage" {
    try std.testing.expect(@sizeOf(u64) == 8);
    try std.testing.expect(@sizeOf(usize) == 8);  // pointer-sized
    try std.testing.expect(@sizeOf(*u32) == 8);   // một con trỏ
    try std.testing.expect(@sizeOf([]u8) == 16);  // ptr + len
    try std.testing.expect(@sizeOf([]const u8) == 16);
    try std.testing.expect(@alignOf(u64) == 8);
    try std.testing.expect(@alignOf(u8) == 1);
}
```

- **Slice tốn 16 byte** = con trỏ + độ dài; assignment slice copy 16 byte này (mục 6).
- **Biến local được căn chỉ alignment đúng kiểu**: `@intFromPtr(&x) % @alignOf(T) == 0` (đã assert
  thành công). Địa chỉ sai alignment là **Illegal Behavior** (nói rõ trong
  [`memory_model.md`](memory_model.md#44-alignment)).
- `usize` đúng bằng kích thước con trỏ → mọi `len`, index, `@intFromPtr` đều về `usize`.

---

## 10. `undefined`, `0xaa` và các safety mode

- `undefined` là giá trị "chưa có ý nghĩa" — có thể coerce sang mọi kiểu (chi tiết:
  [`values.md`](values.md#undefined)).
- Trong mode **debug / safe**, Zig **điền `0xaa`** vào vùng nhớ undefined để bắt lỗi sớm và dò trong
  debugger. Đã chạy thật:

```
undefined local bytes: aa aa aa aa
all 0xaa? true
```

> Langref nhấn mạnh đây **chỉ là chi tiết cài đặt** (implementation feature), *không* phải ngữ nghĩa
> ngôn ngữ: *"not guaranteed to be observable to code."* Trong ReleaseFast, byte vùng undefined có thể
> là `00` hoặc rác khác → **đừng bao giờ dựa vào `0xaa` để logic**.

- Sự khác nhau giữa `debug / fast / safe / small` ảnh hưởng **hành vi bộ nhớ của biến** (bound-check,
  padding 0xaa, leak-detection) — bảng so sánh ở [`memory_model.md`](memory_model.md#97-debug-vs-release--hành-vi-bộ-nhớ-khác-nhau).

---

## 11. Bảng tổng kết nhanh

| Câu hỏi | Trả lời |
|---|---|
| Biến là gì? | **Một đơn vị lưu trữ bộ nhớ** (storage), không phải "tên cho giá trị" |
| Nên dùng `const` hay `var`? | **`const`** (trừ khi phải đổi giá trị) |
| `const` nghĩa gì với bộ nhớ? | Toàn bộ bytes identifier trỏ tới là bất biến; con trỏ có const riêng |
| Biến có được bỏ qua init? | Không — phải gán ngay; muốn khởi tạo sau thì dùng `= undefined` |
| Có shadowing được không? | **Không bao giờ**; cùng tên khác scope độc lập thì OK; `_` là discard |
| Biến ở top-level sống đâu? | global data (`var`) hoặc global constant data (`const` comptime) |
| Biến trong hàm sống đâu? | stack frame; hết hạn khi hàm trả về |
| `threadlocal` là gì? | Mỗi luồng một bản riêng; không được `const`; chỉ ở container level |
| Gán biến = ? | **Copy dữ liệu** (value semantics); riêng slice copy descriptor `{ptr,len}` |
| `comptime var` là gì? | Load/store lúc biên dịch; nằm global constant data; vi phạm → compile error |
| Ai ngăn con trỏ "bay hơi"? | Compiler chặn `return &local` ("expired local"); còn lại do lập trình viên (ownership) |
| Server chi phí bộ nhớ? | Không GC, không hidden allocation: bạn phải trả lời "Where are the bytes?" |

---

## 12. Video từ chính tác giả (Andrew Kelley)

Bạn yêu cầu tìm **video từ chính chủ** (Andrew Kelley) nói rõ về memory model / "biến nằm ở đâu".
Danh sách dưới đây **đã xác minh tồn tại** (oEmbed/tìm kiếm YouTube) và đều do **Andrew Kelley tự
nói**:

| Video | Nội dung liên quan đến Variables ↔ Memory |
|---|---|
| [**A Practical Guide to Applying Data-Oriented Design**](https://www.youtube.com/watch?v=IroPQ150F6c) ⭐ | Handmade Seattle 2019 — giải thích trực quan **bộ nhớ hoạt động thế nào** (cache line, footprint), mỗi "biến/mảng" nên nằm sát nhau ra sao. Bản gốc ghi tại event, video trên YouTube là bản lưu trữ của bài nói này. |
| [**Intro to the Zig Programming Language • GOTO 2022**](https://www.youtube.com/watch?v=YXrb-DqsBNU) | Giới thiệu Zig từ chính tác giả; gồm triết lý "no hidden memory allocation", vì sao Zig không runtime/GC. |
| [**Zig Compiler Internals — Zig SHOWTIME**](https://www.youtube.com/watch?v=8MbREuiLQrM) | Andrew mổ xẻ **cách chính compiler Zig tự quản bộ nhớ** — ví dụ sống về "where are the bytes" ngay trong trình biên dịch. |
| [**The Road to Zig 1.0**](https://www.youtube.com/watch?v=Gv2I7qTux7g) | Định hướng/bản đồ phát triển; nhiều đoạn bàn về memory safety, undefined behavior, các vùng nhớ. |
| [**Interview with Zig language creator Andrew Kelley** (Context Free)](https://www.youtube.com/watch?v=ZvskDoP09Ao) | Phỏng vấn dài; lý do Zig chọn **manual memory management**, không GC, allocator tường minh. |
| [**Don't Forget To Flush — Andrew Kelley** (TigerBeetle)](https://www.youtube.com/watch?v=f30PceqQWko) | Minute-talk về **cache/memory visibility**: khi nào store phải "được flushed" ra bộ nhớ — góc nhìn phần cứng của memory model. |
| [**Zig Live Coding: Implementing a General Purpose Allocator**](https://vimeo.com/491443376) | Andrew **live-code một allocator** — học cách "biến heap" thực sự được cấp phát/bảo vệ ra sao. |

> 💡 Gợi ý xem: bắt đầu bằng **DOD** (trực giác phần cứng) → **GOTO 2022 / Context Free** (triết lý
> "ai quản lý bytes") → **Zig Compiler Internals** (xem nó áp dụng vào thực tế thế nào) → **GPA
> livecode** (đỉnh cao: tự viết allocator).
>
> (Bộ video tương đương về **allocator + hiệu năng bộ nhớ** từ các contributor Zig như Benjamin Feng
> và các tài liệu khác đã liệt kê trong [`memory_model.md`](memory_model.md#12-video-từ-chuyên-gia-về-zig).)

---

## 13. Nguồn tham khảo & liên kết với các tài liệu khác

**Tài liệu chính thức:**
- [Zig Language Reference 0.17.1 — Variables](https://ziglang.org/documentation/0.17.1/#Variables)
  (Namespace Level / Locally-Scoped Global / Thread Local / Local)
- [Zig Language Reference 0.17.1 — Blocks → Shadowing](https://ziglang.org/documentation/0.17.1/#Blocks)
- [Zig Language Reference 0.17.1 — Comptime → Compile-Time Variables](https://ziglang.org/documentation/0.17.1/#Comptime)
- [Zig Language Reference 0.17.1 — Result Location Semantics](https://ziglang.org/documentation/0.17.1/#Result-Location-Semantics)
- [Zig Language Reference 0.17.1 — Memory (Where are the bytes? / Lifetime and Ownership)](https://ziglang.org/documentation/0.17.1/#Memory)
- [Zig Language Reference 0.17.1 — Assignment / undefined](https://ziglang.org/documentation/0.17.1/#Assignment)

**Các tài liệu của dự án (đọc theo thứ tự đề xuất):**
1. [`memory_model.md`](memory_model.md) — bức tranh tổng thể bộ nhớ (đọc kèm: nền tảng để hiểu mục 5).
2. [`identifiers.md`](identifiers.md) — luật tên: vì sao không shadowing; scope.
3. [`values.md`](values.md) — literal & `comptime_int`/`comptime_float`, `undefined`, destructuring.
4. (sắp tới) `struct.md` / `comptime.md` / `errors.md`.

---

*Tài liệu viết cho mục đích học tập; mọi đoạn trích quan trọng lấy từ nguồn chính thức và có link để
tự kiểm chứng. Hành vi máy (địa chỉ vùng nhớ, `0xaa`) mang tính minh hoạ trên máy đang chạy (macOS
ARM64); trên hệ khác con số có thể lệch nhưng phân lớp rodata / data / stack / heap là bản chất
ngôn ngữ.*
