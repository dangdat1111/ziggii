# Allocators trong Zig — quản lý bộ nhớ heap tự chọn, tường minh

> Phiên bản xác minh: **Zig 0.17.0** (`zig version` → 0.17.0, cài qua homebrew), đối chiếu
> [Zig Language Reference 0.17.1 — Memory](https://ziglang.org/documentation/0.17.1/#Memory),
> guide chính thức [Choosing an Allocator](https://ziglang.org/learn/choosing-an-allocator/) và
> **chính source std của toolchain** (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/mem/Allocator.zig`,
> `std/heap.zig`, `std/heap/debug_allocator.zig`, `std/heap/SafeAllocator.zig`, `std/testing.zig`).
>
> Mọi ví dụ + output **đều chạy thật** trên máy (macOS ARM64, scratch `/tmp/zigenum/allocators/`):
> **35 test dương OK** (6 file probe) + **3 probe âm** (1 compile-error, 2 panic).
> Chi tiết ở [mục 13](#13-bộ-test-tổng-hợp--kết-quả).
>
> ⚠️ **Cảnh báo API 0.17** (đã đọc src std): `GeneralPurposeAllocator`/GPA và `StackAllocator`
> được nhắc trong tài liệu cũ **không còn**; thay cho GPA, **0.17 dùng `SafeAllocator`**
> (`DebugAllocator` bị đánh dấu *deprecated*, chỉ còn là tên cũ trỏ tới SafeAllocator).
> Các allocator toàn cục (`page_allocator`, `c_allocator`, `smp_allocator`, `wasm_allocator`,
> `brk_allocator`) đều là **giá trị `Allocator` trực tiếp** — không có method `.allocator()` như các
> allocator có trạng thái (Arena, FixedBuffer, Safe, Debug).

---

## Mục lục

1. [Tư tưởng: Zig không quản lý bộ nhớ — "Where are the bytes?"](#1-tư-tưởng-zig-không-quản-lý-bộ-nhớ--where-are-the-bytes)
2. [Allocator interface 0.17: `ptr` + `vtable`](#2-allocator-interface-017-ptr--vtable)
3. [Global allocator (giá trị trực tiếp)](#3-global-allocator-giá-trị-trực-tiếp)
4. [Bộ method của `std.mem.Allocator`](#4-bộ-method-của-stdmemallocator)
5. [`std.testing.allocator` — giám sát rò rỉ trong test](#5-stdtestingallocator--giám-sát-rò-rỉ-trong-test)
6. [SafeAllocator — "GPA thời 0.17" và 4 lớp bảo vệ](#6-safeallocator--gpa-thời-017-và-4-lớp-bảo-vệ)
7. [DebugAllocator (deprecated) & `std.heap.Check`](#7-debugallocator-deprecated--stdheapcheck)
8. [ArenaAllocator — dồn nhiều alloc vào một cuộc đời](#8-arenaallocator--dồn-nhiều-alloc-vào-một-cuộc-đời)
9. [FixedBufferAllocator — không heap, chỉ buffer có sẵn](#9-fixedbufferallocator--không-heap-chỉ-buffer-có-sẵn)
10. [MemoryPool — alloc nhanh cho nhiều object cùng kiểu](#10-memorypool--alloc-nhanh-cho-nhiều-object-cùng-kiểu)
11. [Chọn allocator nào? — flowchart rút gọn](#11-chọn-allocator-nào--flowchart-rút-gọn)
12. [Lỗi thường gặp & thông điệp thật trên 0.17.0](#12-lỗi-thường-gặp--thông-điệp-thật-trên-0170)
13. [Bộ test tổng hợp & kết quả](#13-bộ-test-tổng-hợp--kết-quả)
14. [Liên hệ memory model & cross-link](#14-liên-hệ-memory-model--cross-link)
15. [Nguồn tham khảo](#15-nguồn-tham-khảo)

---

## 1. Tư tưởng: Zig không quản lý bộ nhớ — "Where are the bytes?"

Mục [Memory](https://ziglang.org/documentation/0.17.1/#Memory) của langref mở đầu:

> *"The Zig language performs no memory management on behalf of the programmer. This is why Zig has
> no runtime, and why Zig code works seamlessly in so many environments, including real-time software,
> operating system kernels, embedded devices, and low latency servers. As a consequence, Zig programmers
> must always be able to answer the question: **Where are the bytes?**"*
>
> *(Ngôn ngữ Zig không quản lý bộ nhớ thay cho lập trình viên. Vì vậy Zig không có runtime, và chạy
> mượt trong môi trường real-time, kernel, nhúng, server độ trễ thấp. Hệ quả: lập trình viên Zig luôn
> phải trả lời được câu hỏi: **Các byte đang ở đâu?**)*

Điểm khác biệt với C:

> *"Like Zig, the C programming language has manual memory management. However, unlike Zig, C has a
> default allocator — malloc, realloc, and free. When linking against libc, Zig exposes this allocator
> with `std.heap.c_allocator`. However, **by convention, there is no default allocator in Zig.**"*
>
> *(Giống Zig, C quản lý bộ nhớ thủ công. Nhưng C có allocator mặc định — malloc/realloc/free. Khi link
> libc, Zig phơi bày allocator này qua `std.heap.c_allocator`. Tuy nhiên, **theo quy ước, Zig không có
> allocator mặc định.**)*

Hệ quả thiết kế: hàm nào cần cấp phát **nhận một tham số `Allocator`**, và cấu trúc dữ liệu nhận
allocator ở hàm khởi tạo. Người gọi quyết định byte đến từ đâu (stack? heap OS? buffer tĩnh?), và do đó
kiểm soát được hiệu năng, đời sống và khả năng phát hiện bug.

💡 **Liên hệ:** memory model — xem [memory_model.md#5 (Allocator — trái tim của quản lý bộ nhớ heap)](memory_model.md#5-allocator--trái-tim-của-quản-lý-bộ-nhớ-heap).

---

## 2. Allocator interface 0.17: `ptr` + `vtable`

`std.mem.Allocator` trong 0.17 là một **interface** thô, gồm đúng 2 field (đọc thẳng
`/.../std/mem/Allocator.zig`):

```zig
pub const Error = error{OutOfMemory};

ptr: *anyopaque,          // con trỏ "bị xoá kiểu" tới trạng thái của implementation
vtable: *const VTable,    // bảng 4 hàm
```

`VTable` — bốn hàm thô mà một allocator **phải** cài:

```zig
pub const VTable = struct {
    // Trả pointer tới `len` byte với `alignment` cho trước, hoặc `null` nếu thất bại.
    alloc: *const fn (*anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8,

    // "Co giãn" TẠI CHỖ (không dời địa chỉ): true = thành công, false = không làm được
    // (vì không nén được, chưa chắc thất bại — có thể dùng remap).
    resize: *const fn (*anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool,

    // "Co giãn" có quyền DỜI địa chỉ: trả null nghĩa là "tự alloc+copy+free sẽ hiệu quả hơn".
    remap: *const fn (*anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8,

    // Giải phóng và làm mất hiệu lực vùng nhớ.
    free: *const fn (*anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void,
};
```

Điểm sáng tạo của API này:

- **Error duy nhất — `error{OutOfMemory}`.** Không có "allocation failed with invalid args" v.v.
- **Layout là data:** vì `Allocator` chỉ là 2 field (`ptr`, `vtable`), nó **truyền qua tham số nhẹ** và
  có thể là **giá trị toàn cục** (`page_allocator` chỉ là hằng số). So sánh với `malloc` — một hàm,
  interface này là một *giá trị*.
- **Kiểm-tra-tính-hợp-lệ được tách khỏi interface:** các lớp bọc an toàn (`SafeAllocator`,
  `FailingAllocator` trong test) **chèn** giữa người gọi và implementation `VTable` — bọc một `Allocator`
  bằng một `Allocator` khác, không đổi chữ ký.
- `ret_addr` cho phép hiện stack trace khi bắt lỗi (ai gọi alloc này?).

🐍 Probe `a1_basic` thực hành trên interface này qua `page_allocator`/`smp_allocator`
(14/14 OK — mục [13](#13-bộ-test-tổng-hợp--kết-quả)).

---

## 3. Global allocator (giá trị trực tiếp)

Đây là mảnh quan trọng phải sửa tư duy khi chuyển từ Zig ≤0.14: **các allocator "toàn cục" là giá trị
`Allocator`**, không phải struct có `.allocator()`. Dùng thẳng sans-serif:

| Tên (std.heap) | Bản chất | Ghi chú |
|---|---|---|
| `page_allocator` | Gọi trực tiếp `mmap`/`VirtualAlloc` **mỗi lần alloc** | Đơn giản, an toàn; **tốn 1 syscall/alloc**, có overhead trang (thường 4KiB trở lên). Không thread-state riêng. |
| `c_allocator` | Bọc `malloc`/`realloc`/`free`/`posix_memalign` của libc | Chỉ link được khi `-lc`; trimming overhead thấp hơn page_allocator. |
| `smp_allocator` | Hoán đổi segment cho đa luồng (`Io`/TLP-aware) | Dùng cho server đa luồng; mỗi thread có arena cục bộ. |
| `wasm_allocator` | Cho WASM (`BrkAllocator` phía sau) | Trên native không dùng. |
| `brk_allocator` | Heap `brk` cũ của OS | Tồn tại nhưng hiếm dùng ở 0.17. |

Verified trên 0.17.0 (`std/heap.zig`):

```zig
pub const page_allocator: Allocator = ...;
pub const smp_allocator: Allocator = .{ ... };
pub const wasm_allocator: Allocator = .{ ... };
pub const brk_allocator: Allocator = .{ ... };
```

Code thật (từ `a1_basic.zig`):

```zig
const buf = try std.heap.page_allocator.alloc(u8, 1024);
defer std.heap.page_allocator.free(buf);

const buf2 = try std.heap.smp_allocator.alloc(u8, 4096); // dùng thẳng, không .allocator()
```

### ⚠️ `c_allocator` trên macOS tự có libc

Khi `zig test` trên macOS, **toolchain tự link libSystem** nên `c_allocator` chạy được **cả khi không
truyền `-lc`**. Trên Linux, `zig test a1_c.zig` không có `-lc` sẽ dính `@compileError` ngay trong
`c_allocator_impl`:

```
error: C allocator is only available when linking against libc
```

(Xác minh `std/heap.zig`: khối `comptime { if (!builtin.link_libc) @compileError(...) }` nằm ngay trong
`c_allocator_impl`.)

---

## 4. Bộ method của `std.mem.Allocator`

Trên interface 2-field đó, std bọc các method tiện ích (đọc nhanh trong `mem/Allocator.zig`). Bảng dưới
đây là API **dùng hàng ngày**:

| Method | Ký hiệu 0.17 | Ghi chú / probe đã chạy |
|---|---|---|
| `alloc(self, T, n)` | `Allocator.Error![]T` | Cấp mảng `n` phần tử; `n == 0` hợp lệ, trả slice rỗng (không lỗi). |
| `allocZeroed(self, T, n)` | `Allocator.Error![]T` | Giống `alloc` nhưng đảm bảo vùng nhớ toàn **0** (page_allocator thường đã zero sẵn). |
| `create(self, T)` | `Allocator.Error!*T` | Cấp đúng 1 object trên heap (0.17 trả ptr, tự động align). |
| `free(self, memory)` | `void` | Giải phóng; **bắt buộc** truyền lại đúng len + alignment ban đầu. |
| `destroy(self, ptr)` | `void` | Đối xứng với `create`. |
| `realloc(self, memory, new_len)` | `Allocator.Error![]T` | Co/giãn (cho phép dời); dữ liệu cũ được **sao chép** nếu dời. |
| `reallocAdvanced(self, old_mem, new_n, ret_addr)` | `Allocator.Error![]T` | Co/giãn từ một **mảnh thô** (raw pointer, không cần slice đúng kiểu); hàm này hết 2 callbacks `os_*` của thời GPA. |
| `resize(self, memory, new_len)` | `bool` | Thử co/giãn **tại chỗ**; `false` = chưa chắc thất bại (thử `remap`/`realloc`). |
| `remap(self, memory, new_len)` | `?[]T` | Co/giãn cho dời; `null` = nên tự alloc+copy+free. |
| `dupe(self, T, slice)` | `Allocator.Error![]T` | Sao chép slice sang vùng mới (từng byte). |
| `print(self, fmt, args)` | `Allocator.Error![]u8` | Format động, trả slice đã cấp phát (đừng quên `free`). |
| `allocSentinel(self, T, n, sentinel)` | `Allocator.Error![:sentinel]T` | Cấp mảng + buộc phần tử cuối = sentinel (vd C string `0`). |
| `allocWithOptions` | chấp nhận `alignment` tùy biến | probe dùng `.@"16"` → ptr chia hết 16. |
| `allocBytesAligned(self, align, byte_count, ret_addr)` | `Allocator.Error![*]align(...)u8` | Cấp **nhiều-phần-tử-phần-tử mảnh** với alignment comptime (tầng thấp, dùng cho vùng thô). |

Vài hành vi đã verify bằng test thật (`a1_basic.zig`, 14/14 OK):

```zig
// create/destroy
const p = try std.heap.page_allocator.create(Point);
defer std.heap.page_allocator.destroy(p);
p.* = .{ .x = 3, .y = 4 };

// realloc giữ dữ liệu cũ: ghi 0..15 vào 16 byte, realloc lên 32, 16 byte đầu còn nguyên
buf = try std.heap.page_allocator.realloc(buf, 32);

// realloc về 0 == free (luôn "thành công", trả slice rỗng)
buf = try std.heap.page_allocator.realloc(buf, 0);

// resize trả bool; resize(…, 0) cũng trả true
if (allocator.resize(buf, 50)) buf = buf[0..50];

// dupe/print/allocSentinel/allocWithOptions đều hoạt động
const dup = try allocator.dupe(u8, "xin chao");
const s = try allocator.print("{d} / {s}", .{ 42, "zig" });
const st = try allocator.allocSentinel(u8, 5, 0);  // s[5] == 0
const al = try allocator.allocWithOptions(u8, 64, .@"16", null);

// quá khổ -> error.OutOfMemory (không phải segfault)
try std.testing.expectError(error.OutOfMemory,
    std.heap.page_allocator.alloc(u8, std.math.maxInt(usize)));
```

---

## 5. `std.testing.allocator` — giám sát rò rỉ trong test

Đọc `std/testing.zig`:

```zig
pub var allocator_instance: std.heap.SafeAllocator = undefined;
pub const allocator = if (builtin.is_test) allocator_instance.allocator()
                      else @compileError("not testing");
```

→ **`std.testing.allocator` chính là một `SafeAllocator`** (bọc thêm một lớp `FailingAllocator`/base).
Dùng nó làm "child allocator" trong test để **mọi leak đều bị báo về cuối test** (kèm stack trace lúc
alloc). Quy ước trong ví dụ std và mọi code Zig: test dùng `std.testing.allocator`, và mọi heap đều nên
được cấp từ một allocator "cha" là nó.

```zig
var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
defer arena.deinit();          // nếu arena trả lại không sạch -> runner báo leak
```

---

## 6. SafeAllocator — "GPA thời 0.17" và 4 lớp bảo vệ

`std.heap.SafeAllocator` (`std/heap/SafeAllocator.zig`) là allocator **an toàn nặng overhead**, thay thế
vai trò của `GeneralPurposeAllocator`/`DebugAllocator` cũ. Khởi tạo:

```zig
var sa: std.heap.SafeAllocator = .init(child_allocator, .{ });
const allocator = sa.allocator();
```

- Sinh ra để **chạy trong Debug/test** nhằm bắt bug: mọi allocation được gắn metadata, checksum, canary.
- **Chậm và tốn bộ nhớ** cố ý: "khi alloc 1 byte, hiệu quả <1% — cần hơn 100 byte overhead".
  (Đọc đúng comment, mục tiêu là thay thế GPA.)
- `Options` (`heap/SafeAllocator.zig`):
  `stack_trace_frames`, `check_write_after_free` (mặc định bật khi debug),
  `canary` (chống truyền nhầm allocation giữa các SafeAllocator), `bucket_size_log2`, `block_size_log2`.

### 6.1 Bảo vệ #1 — phát hiện rò rỉ

`deinit()` trả về **số lượng allocation rò rỉ** (không phải số byte!). Verify bằng probe (rò rỉ 128B và
70KB đều trả `1`):

```
[SafeAllocator] (err): leaked [addr: 102760010, len: 128 (0x80) align: 1] allocated at:
    (stack trace tại chỗ alloc)
```

⚠️ Vì thông báo được log ở mức `err`, **`zig test` trả exit code 1** ngay cả khi mọi test `OK` — đây là
cơ chế CẢNH BÁO leak làm hỏng pipeline CI, không phải bug test.

### 6.2 Bảo vệ #2 — phát hiện double free (tức thì)

Free một vùng đã free → panic **ngay lần free thứ hai**, in ra đủ ba dấu vết (alloc / first free /
second free):

```
thread 199997 panic: double free of [addr: 102bb8010, len: 16 (0x10) align: 1]
alloc:  ...
first free:  ...
second free: ...
```

### 6.3 Bảo vệ #3 — phát hiện ghi-sau-free (LAZY!)

Mechanism (đọc `SafeAllocator.zig`): lúc `free`, vùng nhớ bị **ghi đè 0x55**; lúc dò bucket
(`checkFreed`), chỗ nào khác `0x55` → panic. → Việc ghi sai **KHÔNG bị bắt ngay lúc ghi**, chỉ bị phát
hiện khi **vùng đó được dò lại** (lúc `deinit()` chẳng hạn). Probe thật:

```
// free rồi ghi buf[0] = 1: nếu không deinit => PASS lặng lẽ (bộ nhớ vẫn ghi được!)
// chỉ khi gọi deinit() => dò bucket => panic:
thread 200690 panic: write after free at *100288010
original alloc of [addr: 100288010, len: 16 (0x10) align: 1]: ...
free: ...
```

💡 Khác với double-free, **use-after-free không bao giờ "hứa" bắt được ngay** — SafeAllocator chỉ làm
*xác suất bắt cao hơn* qua dấu 0x55 và checksum footer. Đừng tin UAF được chẩn đoán tức thì.

### 6.4 Bảo vệ #4 — canary & checksum footer

Mỗi allocation có footer chứa canary + checksum; nếu vùng xung quanh bị ghi đè (buffer overflow nhẹ),
checksum lệch → `panic("corrupted footer metadata ...")` hoặc warn khi dò bucket.

---

## 7. DebugAllocator (deprecated) & `std.heap.Check`

Trong 0.17, `std.heap.DebugAllocator` và `std.heap.Check` **bị đánh dấu deprecated** trong `heap.zig`:

```zig
/// Deprecated; use `SafeAllocator`.
pub const DebugAllocator = @import("heap/debug_allocator.zig").DebugAllocator;
/// Deprecated.
pub const Check = enum { ok, leak };
```

Chúng vẫn hoạt động (tên cũ trỏ sang cùng implementation `debug_allocator.zig`), và đáng nắm vì **rất
nhiều code/guide cũ dùng**. Khác GPA cũ: `DebugAllocator` giờ là **hàm comptime nhận cấu hình trả về
một type**:

```zig
var gpa = std.heap.DebugAllocator(.{}) {};       // .{} là Config comptime
const allocator = gpa.allocator();                // lấy Allocator
_ = gpa.deinit();                                 // trả std.heap.Check: .ok hoặc .leak
gpa.deinitWithoutLeakChecks();                     // trả void, bỏ qua kiểm tra
```

Probe thật (`a4_debug.zig`, 5/5 OK):

```zig
// roundtrip sạch -> .ok
try std.testing.expect(gpa.deinit() == .ok);

// giới hạn bộ nhớ: Config compute-time, field DEAD khi tắt:
var gpa2 = std.heap.DebugAllocator(.{ .enable_memory_limit = true }) {};
gpa2.requested_memory_limit = 32;
try std.testing.expectError(error.OutOfMemory, allocator.alloc(u8, 1024));
```

Cấu hình `Config` (0.17): `stack_trace_frames`, `enable_memory_limit`, `safety`, `thread_safe`,
`never_unmap`, `retain_metadata`, `never_unmap_end_addresses`... (đọc `debug_allocator.zig`).

⚠️ **Field phụ thuộc comptime-config KHÔNG biến mất khi tắt** — nó chỉ đổi kiểu thành struct rỗng `{}`.
(Đừng mặc định "tắt là 'no field'"; đã thử và không ra compile error — xem [mục 12](#12-lỗi-thường-gặp--thông-điệp-thật-trên-0170).)

---

## 8. ArenaAllocator — dồn nhiều alloc vào một cuộc đời

`std.heap.ArenaAllocator.init(child).allocator()`: mọi allocation được cấp **từng cục** và chỉ được
giải phóng **toàn bộ** khi `.deinit()` (hoặc `.reset()`). Lý tưởng cho "một request sinh ra nhiều mảnh,
dùng một lần".

Probe thật (`a2_arena.zig`, 5/5 OK):

```zig
var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
defer arena.deinit();
const allocator = arena.allocator();

const p = try allocator.create(Point);
const buf = try allocator.alloc(u8, 100);
const s = try allocator.dupe(u8, "neu-arena");
const f = try allocator.print("x={d}", .{p.x});
// KHÔNG gọi free lẻ nào: deinit dọn tất cả
```

- `free()` một mảnh không phải "gần nhất" là **no-op** (vẫn không leak, deinit dọn).
- `reset(.free_all)` → giải phóng toàn bộ, **tái sử dụng được**; `reset(.retain_capacity)` → giữ backing
  (đỡ syscall); `reset(.{ .retain_with_limit = N })` → giữ tối đa N byte.
- Enum `ResetMode` 0.17 dùng các tên `free_all` / `retain_capacity` / `retain_with_limit`
  (đã compile-verified):

```zig
_ = @as(std.heap.ArenaAllocator.ResetMode, .free_all);
_ = @as(std.heap.ArenaAllocator.ResetMode, .{ .retain_with_limit = 1024 });
```

---

## 9. FixedBufferAllocator — không heap, chỉ buffer có sẵn

`std.heap.FixedBufferAllocator.init(&buf).allocator()`: cấp phát **từ một vùng byte do bạn đưa** (stack,
global, static). Không gọi OS. Vượt buffer → `error.OutOfMemory`. Có `fba.end_index` cho biết lượng đã
dùng, `fba.reset()` dùng lại.

Chính là ví dụ mở đầu của langref (100 byte stack → concat "foo"+"bar" → "foobar"), probe thật
(`a3_fixed.zig`, 6/6 OK):

```zig
var buffer: [100]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&buffer);
const allocator = fba.allocator();
const result = try concat(allocator, "foo", "bar");  // "foobar"
```

Hành vi đã verify:

```zig
// vượt buffer -> OOM
_ = try allocator.alloc(u8, 64);
try std.testing.expectError(error.OutOfMemory, allocator.alloc(u8, 1));

// end_index thay đổi theo lượng dùng; free mảnh "gần nhất" lùi end_index
try std.testing.expect(fba.end_index == 0);
_ = try allocator.alloc(u8, 10);
try std.testing.expect(fba.end_index == 10);

// realloc mảnh "gần nhất" có thể mở rộng TẠI CHỖ (giữ nguyên địa chỉ)
const slice1 = try allocator.realloc(slice0, 10);
try std.testing.expect(slice1.ptr == slice0.ptr);
```

💡 Mô hình "arena nhỏ trên stack" — không heap, không syscall, **không cần free thủ công**, rất hợp
parser/đường dẫn ngắn hạn.

---

## 10. MemoryPool — alloc nhanh cho nhiều object cùng kiểu

`std.heap.MemoryPool(Item)` (`memory_pool.Extra` phía sau, `std/heap/memory_pool.zig`): cấp phát **nhanh,
một hạng object duy nhất** — lý tưởng khi bạn tạo/huỷ liên tục node cùng kiểu (vd `std.ArrayList` nội
bộ, graph). Khai báo:

```zig
pub fn MemoryPool(comptime Item: type) type {
    return memory_pool.Extra(Item, .{ .alignment = null });
}
```

Sinh ra để vượt trội general-purpose đối với lượng lớn object cùng type; quản lý danh sách free-list
cục bộ → ít contention, ít overhead. (Có mặt và compile-verified; chủ đề sâu hơn thuộc "data structures"
— mục này chỉ giới thiệu để biết allocator nào dùng khi nào.)

---

## 11. Chọn allocator nào? — flowchart rút gọn

Dựa trên [Choosing an Allocator](https://ziglang.org/learn/choosing-an-allocator/) và flowchart langref,
tinh gọn cho 0.17:

```
Bạn có cần heap ("byte động") không?
└─ Không → FixedBufferAllocator trên stack/static buffer  ──► (nhanh, không syscall)
└─ Có ── Bạn có thao tác trên "nhiều mảnh dùng chung một cuộc đời" không?
        ├─ Có → ArenaAllocator.init(child)   (deinit cả lô)
        └─ Không ── Nhiều object cùng 1 kiểu, tạo/huỷ dày đặc?
                  ├─ Có → MemoryPool(T)
                  └─ Không ── Chế độ nào?
                            ├─ Test / dev, cần bắt bug:
                            │     SafeAllocator bọc testing.allocator  (hoặc std.testing.allocator)
                            ├─ Production đa luồng: smp_allocator (hoặc c_allocator nếu -lc)
                            └─ Production GUI/CLI đơn giản 1 luồng:
                                  page_allocator (bỏ qua overhead) hoặc c_allocator
```

Quy ước văn hoá Zig: một executable/CLI thường tạo **1 arena to** ở `main` (bọc `std.heap.page_allocator`)
rồi truyền allocator xuống hàm (langref gợi ý mô hình "CLI arena"). Điều này khớp triết lý *"Where are
the bytes?"* — bạn luôn biết byte đang nằm ở đâu và ai sở hữu.

---

## 12. Lỗi thường gặp & thông điệp thật trên 0.17.0

Bảng dưới là **thông điệp đã thu được thật** (không dựng) từ các probe âm:

| Tình huống | Hành vi / thông điệp thật (0.17.0) | Phân cấp |
|---|---|---|
| Gọi allocator trong `comptime` | `error: unable to evaluate comptime expression` (từ `heap/PageAllocator.zig` lúc instantiate) | **compile-time** — allocator là interface runtime, không phải hàm comptime |
| Double free qua SafeAllocator | `panic: double free of [addr: ..., len: ...]` kèm `alloc` / `first free` / `second free` | **runtime panic** (tức thì) |
| Ghi sau free (mảnh nhỏ) + deinit | chỉ bị bắt khi dò bucket: `panic: write after free at *...`; nếu không ai dò → lặng lẽ "OK" | **runtime, LAZY** — đừng tin là bắt ngay |
| Quên free (leak) | `[SafeAllocator] (err): leaked [addr..., len...]`; `deinit()` trả **số lượng** leak; `zig test` exit code 1 | **runtime log err** làm hỏng exit code |
| Dùng `alloc`/`free` với len/alignment sai | phụ thuộc allocator; SafeAllocator panics qua checksum footer (corrupted footer metadata ...) | undefined ở mức interface |

Lưu ý cạm bẫy thêm:

- **Cấp phát rồi quên `defer free`** — bug phổ biến số 1; trong test dùng `std.testing.allocator` để auto-
  phát hiện.
- **`alloc(u8, 0)` là hợp lệ** (slice rỗng, `free` no-op) — đừng viết nhánh đặc biệt cho trường hợp 0.
- **`realloc(buf, 0)` tương đương `free`** và luôn "thành công".
- **`c_allocator` đòi `-lc`** — trên macOS tự link; trên Linux nhớ truyền `-lc`.
- Đừng `@ptrCast` tuỳ tiện slice từ allocator — alignment của allocation là do **allocator quyết định**,
  dùng `allocWithOptions`/`allocBytesAligned` khi cần align lớn. (Xem [pointers.md#5 (Alignment)](pointers.md#5-alignment).)

---

## 13. Bộ test tổng hợp & kết quả

All in `/tmp/zigenum/allocators/`, chạy bằng `/opt/homebrew/Cellar/zig/0.17.0/bin/zig test`.

| File | Nội dung | Kết quả |
|---|---|---|
| `a1_basic.zig` | page/smp_allocator: alloc/free, create/destroy, realloc, resize, alignment, overflow→OOM, dupe, print, allocSentinel, allocWithOptions | **14/14 OK** |
| `a2_arena.zig` | Arena: free lẻ là no-op, reset.free_all / retain_capacity / retain_with_limit, ResetMode | **5/5 OK** |
| `a3_fixed.zig` | FixedBuffer: OOM khi vượt, end_index, reset, realloc tại chỗ, ví dụ langref "foobar" | **6/6 OK** |
| `a1_c.zig` | c_allocator: alloc/free/create/realloc (+ note macOS tự link libc) | **2/2 OK** |
| `a4_debug.zig` | DebugAllocator(.{}): deinit→.ok, create/destroy, enable_memory_limit→OOM, deinitWithoutLeakChecks | **5/5 OK** |
| `a5_safe.zig` | SafeAllocator: roundtrip sạch (deinit=0), bọc testing.allocator, realloc giữ dữ liệu | **3/3 OK** |
| `a6_leak_demo.zig` | Leak cố ý: deinit()=1 (đếm khối), exit code 1 do err-log | 1/1 OK, **exit 1** (by design) |
| `neg/01_comptime.zig` | Gọi alloc trong comptime | **compile error** |
| `neg/02_double_free.zig` | Free 2 lần qua SafeAllocator | **panic** (3 dấu vết) |
| `neg/03_write_after_free.zig` | Free → ghi → deinit (dò bucket) | **panic** write-after-free |

Trích output thật:

```
$ zig test a1_basic.zig
14/14 a1_basic.test.allocWithOptions: alignment tuỳ chọn...OK
All 14 tests passed.

$ zig test a4_debug.zig
All 5 tests passed.

$ zig test a6_leak_demo.zig
1/1 a6_leak_demo.test.leak-demo: ... [SafeAllocator] (err): leaked [addr: ..., len: 128 ...]
OK
error: the following test command failed with exit code 1:   # LÀ tín hiệu leak

$ zig test neg/02_double_free.zig
1/1 02_double_free.test.neg: double free bị bắt...thread 199997 panic: double free of [addr: ...]
```

---

## 14. Liên hệ memory model & cross-link

- **Cơ sở:** vì sao "byte ở đâu" quan trọng — [memory_model.md](memory_model.md),
  mục 5 [Allocator — trái tim của quản lý bộ nhớ heap](memory_model.md#5-allocator--trái-tim-của-quản-lý-bộ-nhớ-heap),
  mục 6 [Heap allocation failure & error.OutOfMemory](memory_model.md#6-heap-allocation-failure--erroroutofmemory).
- **Lỗi OOM** là `error.OutOfMemory` — cách `try`/`catch`/`switch` xử lý: [errors.md](errors.md).
- **Alignment** của vùng cấp phát và `@alignCast`/`@ptrCast`: [pointers.md#5 (Alignment)](pointers.md#5-alignment).
- **Tham chiếu/var** + `defer`/`errdefer` để free đúng lúc: [variables.md](variables.md).
- **Đa luồng & `smp_allocator`**, allocator trên từng thread: [concurrency.md](concurrency.md).
- **Tích hợp build**: allocator trong `build.zig`/steps heap: [build_system.md](build_system.md).

---

## 15. Nguồn tham khảo

1. [Zig Language Reference 0.17.1 — Memory](https://ziglang.org/documentation/0.17.1/#Memory)
2. [Zig Learn — Choosing an Allocator](https://ziglang.org/learn/choosing-an-allocator/)
3. Source std của chính toolchain (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/`):
   `mem/Allocator.zig`, `heap.zig`, `heap/SafeAllocator.zig`, `heap/debug_allocator.zig`,
   `testing.zig`.
4. [std.heap](https://ziglang.org/documentation/0.17.1/std/#A;std:heap) — danh sách API đầy đủ.

---

**Ghi chú phiên bản:** xác minh trên **Zig 0.17.0** (homebrew). Names (`SafeAllocator`, `DebugAllocator`
deprecated, allocators-toàn-cục-là-giá-trị, `deinit()`-trả-số-đếm-leak, `retain_with_limit`,
comptime-alloc-error) là đặc thù 0.17; sách/guide viết cho 0.11–0.14 thường nhắc `GeneralPurposeAllocator`
/GPA/`.allocator()` cho page_allocator — sẽ lệch, hãy đối chiếu std của bản mình đang chạy.

---

*Tài liệu viết cho mục đích học tập bằng thực nghiệm trên máy thật (macOS ARM64, Zig 0.17.0). Mọi con
số, thông điệp lỗi và đếm test là kết quả đo lại, không dựng từ trí nhớ; trên nền tảng/phiên bản khác có
thể lệch nhưng bản chất (interface `ptr`+`vtable`, không-default-allocator, Error=OOM, arena/fixedbuffer
mô hình, SafeAllocator bắt leak/double-free) là bất biến.*
