# Async & Concurrency trong Zig — Threads, Atomics và Đồng bộ Tường minh

> Phiên bản xác minh: **Zig 0.17.0** (`zig version` → 0.17.0, cài qua homebrew), đối chiếu
> [Zig Language Reference 0.17.1 — Async Functions](https://ziglang.org/documentation/0.17.1/#Async-Functions),
> [— Atomics](https://ziglang.org/documentation/0.17.1/#Atomics), [— volatile](https://ziglang.org/documentation/0.17.1/#volatile),
> [— Single Threaded Builds](https://ziglang.org/documentation/0.17.1/#Single-Threaded-Builds)
> và source std của chính toolchain (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Thread.zig`,
> `atomic.zig`, `Io.zig`, `lang.zig`). Mọi ví dụ + output **đều chạy thật** trên máy
> (scratch `/tmp/zigenum/concurrency/`), không dựng từ trí nhớ.
>
> ⚠️ **Đọc kỹ trước khi đi tiếp**: từ **Zig 0.11.0** trở đi, **async functions đã bị regression** —
> không còn là tính năng ngôn ngữ. Tài liệu này mở đầu bằng sự thật đó (mục 1), sau đó dạy đúng cách
> Zig 0.17 làm concurrency: **thread + atomics + đồng bộ tường minh** — không `async/await`, không
> runtime ngầm.

---

## Mục lục

1. [Sự thật đầu tiên: `async`/`await` không còn trong Zig 0.17](#1-sự-thật-đầu-tiên-asyncawait-không-còn-trong-zig-017)
2. [Threads: `spawn`, `join`, `detach`](#2-threads-spawn-join-detach)
   - [2.1 `SpawnConfig` — stack & allocator](#21-spawnconfig--stack--allocator)
   - [2.2 `getCpuCount` và `sleep`](#22-getcpucount-và-sleep)
3. [Đồng bộ bậc cao: Mutex & bạn đồng hành](#3-đồng-bộ-bậc-cao-mutex--bạn-đồng-hành)
   - [3.1 `std.Io.Mutex` — vì `std.Thread.Mutex` đã biến mất](#31-stdiomutex--vì-stdthreadmutex-đã-biến-mất)
   - [3.2 Counter an toàn bằng Mutex](#32-counter-an-toàn-bằng-mutex)
   - [3.3 Condition, RwLock, Semaphore, Event](#33-condition-rwlock-semaphore-event)
4. [Atomics: đồng bộ không cần runtime](#4-atomics-đồng-bộ-không-cần-runtime)
   - [4.1 `std.atomic.Value(T)`](#41-stdatomicvaluet)
   - [4.2 Memory ordering trong 0.17](#42-memory-ordering-trong-017)
   - [4.3 Builtins 0.17 — cú pháp đã đổi](#43-builtins-017--cú-pháp-đã-đổi)
   - [4.4 Ba cách làm counter atomically](#44-ba-cách-làm-counter-atomically)
5. [Data race = Illegal Behavior (≈ UB)](#5-data-race--illegal-behavior--ub)
   - [5.1 Chế độ `-fsingle-threaded`](#51-chế-độ--fsingle-threaded)
6. [Thread-local storage (TLS)](#6-thread-local-storage-tls)
7. [Bảng tóm tắt: dùng công cụ nào, khi nào](#7-bảng-tóm-tắt-dùng-công-cụ-nào-khi-nào)
8. [Lỗi thường gặp (probe thật trên 0.17.0)](#8-lỗi-thường-gặp-probe-thật-trên-0170)
9. [Nguồn & liên kết](#9-nguồn--liên-kết)

---

## 1. Sự thật đầu tiên: `async`/`await` không còn trong Zig 0.17

Mục [**Async Functions**](https://ziglang.org/documentation/0.17.1/#Async-Functions) của langref 0.17.1
chỉ còn là một **stub** (mục [Atomics](https://ziglang.org/documentation/0.17.1/#Atomics) cùng trang
cũng vậy — `TODO: @atomic rmw`), với nội dung duy nhất:

> *"**Async functions regressed with the release of 0.11.0.** The current plan is to reintroduce them
> as a lower level primitive that powers I/O implementations. Tracking issue: Proposal: stackless
> coroutines as low-level primitives."*

Dịch giữ ý: **"Async functions đã bị regression kể từ bản 0.11.0. Kế hoạch hiện tại là giới thiệu lại
chúng như một primitive cấp thấp làm nền cho các implementation I/O.** (Theo dõi qua proposal
'stackless coroutines as low-level primitives'.)"

Hệ quả trực tiếp: từ 0.11 trở đi **không còn** `async fn` / `await` / `suspend` / `resume` /
`nosuspend` / `anyframe` / `cancel` trong Zig — chúng không còn **là từ khoá**, compiler thậm chí không
nhận ra chúng.

### 1.1 Probe âm: viết `async fn` và `suspend;` trên 0.17.0

```zig
async fn foo() void {}   // ❌

pub fn main() void {
    _ = foo;
}
```

```
error: expected ',' after field
async fn foo() void {}
      ^~
```

`error: expected ',' after field` — parser coi `async` như một **tên field** bình thường (không phải
từ khoá). Các probe tiếp theo:

```zig
suspend;                 // ❌

const x = await nothing();   // ❌ với await
```

```
error: expected block or expression, found ';'
    suspend;
           ^

error: expected ';' after statement
    const x = await nothing();
                    ^~~~~~~
```

> 💡 `suspend`/`await` bị đối xử như **identifier** nên báo lỗi cú pháp chung, chứ không phải
> "keyword has been removed". Bài học: đừng tìm `async` trong Zig 0.17 trở đi.

### 1.2 Vì sao? Triết lý "no hidden runtime" và hệ quả cho người học

Zig theo triết lý **"no hidden control flow"** / **"you control concurrency explicitly"**: chi phối
bộ nhớ (allocator/runtime) lẫn luồng điều khiển đều phải *tường minh*. Coroutine đầy đủ (máy trạng
thái giấu trong compiler, điểm suspension ẩn qua `await`, tự cấp frame) tạo ra một **runtime coroutine
ngầm** — trái với tinh thần đó. Hướng đi được chọn:

- **Loại bỏ** nội dung async khỏi ngôn ngữ (xong từ 0.11).
- **Tương lai**: giới thiệu lại ở tầng **runtime/I/O thấp** (proposal stackless coroutines) làm nền
  cho thư viện I/O — không phải cho code thường ngày.

Hệ quả thực tế cho bạn ở Zig 0.17: làm concurrency bằng **kernel threads** (`std.Thread`) + **atomics**
(`std.atomic` + builtin `@atomic*`) + **đồng bộ tường minh** (mutex/condition/…). Đa luồng là *chủ
động*: `spawn` là yêu cầu OS cấp thread thật; mọi phối hợp dữ liệu là do bạn viết rõ. **Không gì xảy
ra ngầm.**

---

## 2. Threads: `spawn`, `join`, `detach`

`std.Thread` (source `Thread.zig`) trong 0.17 là **một kernel thread thật**. API cốt lõi:

```zig
pub fn spawn(config: SpawnConfig, comptime function: anytype, args: anytype) SpawnError!Thread
pub fn join(self: Thread) void
pub fn detach(self: Thread) void
```

- `std.Thread.spawn(.{}, worker, .{ arg1, arg2, ... })` trả **`SpawnError!Thread`** → phải `try`.
- `join()` **đợi thread xong và thu hồi tài nguyên**; handle bị tiêu thụ (dùng lại sau `join` là UB).
- `detach()` **trả quyền** `join()`: thread tự dọn khi kết thúc — dùng khi không cần đợi.

`c1_threads.zig` — spawn 4 thread, mỗi thread in id, main `join` cả 4:

```zig
const std = @import("std");

fn worker(id: usize) void {
    std.debug.print("thread {d} running\n", .{id});
}

pub fn main() !void {
    var threads: [4]std.Thread = undefined;
    for (0..4) |i| {
        threads[i] = try std.Thread.spawn(.{}, worker, .{i});
    }
    std.debug.print("main: spawned 4, joining...\n", .{});
    for (threads) |t| {
        t.join();
    }
    std.debug.print("main: all 4 threads joined\n", .{});
}
```

Output thật (`zig run c1_threads.zig`):

```
thread 0 running
main: spawned 4, joining...
thread 1 running
thread 3 running
thread 2 running
main: all 4 threads joined
```

> 💡 **Thứ tự in ngẫu nhiên** mỗi lần chạy khác nhau — bản chất của đa luồng: không được giả định
> thứ tự thực thi giữa các thread.

### 2.1 `SpawnConfig` — stack & allocator

`SpawnConfig` 0.17 (đối chiếu `Thread.zig` ~dòng 298) chỉ có **hai** field:

```zig
pub const SpawnConfig = struct {
    stack_size: usize = default_stack_size,   // mặc định 16 MiB (16 * 1024 * 1024)
    allocator: ?std.mem.Allocator = null,      // mặc định: OS cấp stack
};
```

> ⚠️ **Không còn field `detached`** như 0.14. Muốn "fire and forget" thì gọi `thread.detach()` sau
> spawn.

Cấu hình stack nhỏ hơn để tiết kiệm bộ nhớ:

```zig
const t = try std.Thread.spawn(.{
    .stack_size = 1 * 1024 * 1024, // 1 MiB thay vì 16 MiB mặc định
}, worker, .{7});
t.join();
```

Output thật (`c1b_stack.zig`): `thread 7 on custom stack` rồi `done`. Nếu hàm cấp nhiều bộ nhớ stack
(đệ quy sâu) mà stack quá nhỏ → runtime stack overflow.

### 2.2 `getCpuCount` và `sleep`

- `std.Thread.getCpuCount() CpuCountError!usize` — số lõi logic (luôn ≥ 1). Trên máy chạy doc này:
  `cpu count = 10`.
- `std.Thread.sleep` — **đã bị bỏ** ở 0.17 (`error: no member named 'sleep'`). Thay bằng
  `std.Io.sleep(io, duration, clock) → Cancelable!void` — cần một `Io` và một `Io.Clock`:

  ```zig
  try std.Io.sleep(init.io, .{ .nanoseconds = 100 * std.time.ns_per_ms }, .real);
  ```

  Các giá trị `Io.Clock` trong 0.17: `.real`, `.awake`, `.boot`, `.cpu_process`, `.cpu_thread`. Output
  thật: `sleep 100ms...` → `woke up`.

---

## 3. Đồng bộ bậc cao: Mutex & bạn đồng hành

### 3.1 `std.Io.Mutex` — vì `std.Thread.Mutex` đã biến mất

Tìm `std.Thread.Mutex` (một hướng dẫn cũ hay dạy) → compiler từ chối ngay:

```zig
var m: std.Thread.Mutex = .{};
```

```
error: root source file struct 'Thread' has no member named 'Mutex'
```

Trong 0.17 các primitive đồng bộ **đã chuyển sang `std.Io`** — chúng cần một `Io` (nhân điều phối mới
của tầng I/O/đồng bộ). Lấy `Io` từ `main` kiểu `std.process.Init` (hoặc `std.testing.io` khi chạy
test):

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;   // Io mặc định do runtime Zig dựng sẵn
    // …
}
```

`std.Io.Mutex` (source `Io.zig` ~dòng 1716, `extern struct`):

```zig
pub const Mutex = extern struct {
    pub const init: Mutex = .{ .state = .init(.unlocked) };

    pub fn lock(m: *Mutex, io: Io) Cancelable!void   // có thể bị cancel (error.Canceled)
    pub fn lockUncancelable(m: *Mutex, io: Io) void  // không tạo cancelation point
    pub fn tryLock(m: *Mutex) bool                    // không block; false nếu đang khoá
    pub fn unlock(m: *Mutex, io: Io) void
};
```

- Khởi tạo: **`var m: std.Io.Mutex = .init;`** (`.{}` sẽ "missing field" vì `state` không có default).
- `lock(io)` trả `error{Canceled}!void` → **quên `try` không compile được**:

  ```
  error: error union of type 'error{Canceled}!void' is ignored
  note: consider using 'try', 'catch', or 'if'
  ```

  Ví dụ dưới dùng `lockUncancelable` (trả `void`) cho gọn.
- Cạnh đó còn `std.atomic.Mutex` (enum `{unlocked, locked}`) chỉ có `tryLock`/`unlock`, không khoá
  block — dành cho ngữ cảnh comptime/test.

### 3.2 Counter an toàn bằng Mutex

`c2_mutex.zig`: 8 thread × 1000 lần `+= 1` vào shared counter. Không có mutex kết quả sẽ sai vì
`counter.* += 1` là *read-modify-write* không nguyên tử (mục 5); có mutex, đúng như tuần tự:

```zig
const std = @import("std");
const Io = std.Io;

fn worker(io: Io, m: *Io.Mutex, counter: *u64, n: u64) void {
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        m.lockUncancelable(io);
        defer m.unlock(io);      // unlock chắc chắn chạy dù có return sớm
        counter.* += 1;
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var m: Io.Mutex = .init;
    var counter: u64 = 0;

    const num_threads = 8;
    const per_thread = 1000;

    var threads: [8]std.Thread = undefined;
    for (0..num_threads) |i| {
        threads[i] = try std.Thread.spawn(.{}, worker, .{
            io, &m, &counter, per_thread,
        });
    }
    for (threads) |t| t.join();

    std.debug.print("expected: {d}, actual: {d}\n", .{ num_threads * per_thread, counter });
}
```

Output thật:

```
expected: 8000, actual: 8000
```

> ⚠️ Bỏ dòng `lock`/`unlock` đi thì kết quả thất thường (thường < 8000) — đó là data race, Zig **không
> chặn**, kết quả **bất định**. Doc không chạy minh hoạ race (lý do ở [mục 5](#5-data-race--illegal-behavior--ub)).

### 3.3 Condition, RwLock, Semaphore, Event

Tất cả trong `std.Io` 0.17, đều nhận `io`:

| Công cụ | Cách dùng tối thiểu (0.17) |
|---|---|
| **Condition** | `wait(&cond, io, &mutex)` (chờ, tạm thả mutex); `signal(&cond, io)` đánh thức 1; `broadcast(&cond, io)` đánh thức tất cả |
| **RwLock** | `lock(&rw, io)`/`unlock(&rw, io)` — writer độc quyền; `lockShared(&rw, io)`/`unlockShared(&rw, io)` — nhiều reader đồng thời |
| **Semaphore** | `wait(&s, io)` giảm 1 (block nếu = 0); `post(&s, io)` tăng 1 — giới hạn tài nguyên / nhịp điệu |
| **Event** | enum `{unset, waiting, is_set}`; `set(&ev, io)` bật cờ; `wait(&ev, io)` chờ đến khi set |

> 💡 Điểm chung để ghi nhớ: **mọi đồng bộ trong 0.17 đều chảy qua một `Io`** — "no hidden runtime"
> nhưng vẫn có một *nhân điều phối* bạn phải cầm trên tay một cách tường minh.

---

## 4. Atomics: đồng bộ không cần runtime

### 4.1 `std.atomic.Value(T)`

`std.atomic.Value(T)` **có tồn tại trong 0.17** (đã kiểm tra). Đây là struct generic bọc biến `T` +
toàn bộ thao tác nguyên tử (đối chiếu `atomic.zig`):

```zig
var v = std.atomic.Value(u32).init(0);
v.store(5, .release);
const x = v.load(.acquire);
_ = v.fetchAdd(1, .monotonic);   // trả giá trị cũ, cộng nguyên tử
```

Method có sẵn: `load`, `store`, `swap`, `cmpxchgWeak`, `cmpxchgStrong`, `fetchAdd`, `fetchSub`,
`fetchMin`, `fetchMax`, `fetchAnd`, `fetchNand`, `fetchOr`, `fetchXor`, `bitSet`, `bitReset`,
`bitToggle` — đều nhận `comptime order` cuối cùng.

### 4.2 Memory ordering trong 0.17

> ⚠️ **`std.atomic.Order` không tồn tại trong 0.17** (đã probe: `no member named 'Order'`). Enum
> ordering là **`std.builtin.AtomicOrder`** (alias `std.lang.AtomicOrder`; langref nói rõ bằng
> `@import("std").lang.AtomicOrder`).

```zig
pub const AtomicOrder = enum {
    unordered,   // thao tác "không tách rời", không ràng buộc thứ tự quanh nó
    monotonic,   // thứ tự nhất quán toàn cục, nhưng không truyền đồng bộ dữ liệu khác
    acquire,     // load/rmw/cmpxchg: mọi thứ sau nó thấy dữ liệu của release trước đó
    release,     // store/rmw/cmpxchg: mọi thứ trước nó hiện diện cho acquire sau đó
    acq_rel,     // acquire + release (thường cho rmw/cmpxchg)
    seq_cst,     // tuần tự toàn cục — mạnh nhất, chậm nhất
};
```

Nôm na: `monotonic` đủ cho **counter thống kê** (tổng cuối vẫn đúng — mục 4.4 chứng minh), còn
`acquire`/`release` dùng để **truyền dữ liệu** giữa thread (quan hệ happens-before).

### 4.3 Builtins 0.17 — cú pháp đã đổi

Builtin nguyên tử 0.17.1 **đòi tham số `comptime T` tường minh ở đầu** (tutorial 0.14 hay viết
`@atomicRmw(&ptr, …)` sẽ vấp). Quên `T`:

```
error: expected 5 arguments, found 4
    _ = @atomicRmw(&c, .Add, 1, .monotonic);
```

Bốn builtin chính (T ∈ {pointer, bool, float, integer, enum, packed struct}; riêng hai
`cmpxchg` **không** nhận float theo langref):

```zig
@atomicLoad(comptime T: type, ptr: *const T, comptime ordering: AtomicOrder) T
@atomicStore(comptime T: type, ptr: *T, value: T, comptime ordering: AtomicOrder) void
@atomicRmw(comptime T: type, ptr: *T, comptime op: AtomicRmwOp, operand: T, comptime ordering: AtomicOrder) T
@cmpxchgStrong(comptime T: type, ptr: *T, expected_value: T, new_value: T,
               success_order: AtomicOrder, fail_order: AtomicOrder) ?T
@cmpxchgWeak(comptime T: type, ptr: *T, expected_value: T, new_value: T,
             success_order: AtomicOrder, fail_order: AtomicOrder) ?T
```

- `@atomicRmw` trả **giá trị trước khi sửa**; `AtomicRmwOp` = `.Xchg .Add .Sub .And .Nand .Or .Xor
  .Max .Min`.
- `@cmpxchgStrong/Weak` trả `null` nếu **thành công** (giá trị hiện tại = `expected`), trả `?T` giá trị
  thực tế nếu **thất bại**. `Weak` có thể fail "hờ" nhưng hiệu quả hơn trong retry loop; `Strong` bảo
  đảm thành công khi bằng nhau.
- alignment của `ptr` phải **≥ `@sizeOf(T)`**.
- ❌ `@fence` **không phải builtin 0.17** (đã probe): `error: invalid builtin function: '@fence'` — rào
  thủ công không cần thiết, thao tác atomic với order mạnh là đủ.

### 4.4 Ba cách làm counter atomically

`c3_atomics.zig` chạy cùng bài toán (8 thread × 1000 → cần 8000) bằng **ba kỹ thuật**, không mutex:

```zig
const std = @import("std");

// (1) builtin @atomicRmw(.Add)
fn workerRmw(counter: *u32, n: u32) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        _ = @atomicRmw(u32, counter, .Add, 1, .monotonic);
    }
}

// (2) vòng lặp @cmpxchgStrong — lock-free compare-and-exchange
fn workerCmpxchg(counter: *u32, n: u32) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var old = @atomicLoad(u32, counter, .monotonic);
        while (@cmpxchgStrong(u32, counter, old, old + 1, .acq_rel, .acquire)) |actual| {
            old = actual; // ai đó ghi trước mình → thử lại với giá trị mới
        }
    }
}

// (3) std.atomic.Value(u32).fetchAdd
fn workerValue(v: *std.atomic.Value(u32), n: u32) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        _ = v.fetchAdd(1, .monotonic);
    }
}
```

(`main` spawn/join 3 bộ thread y hệt; output **thật**):

```
atomicRmw : 8000 == 8000
cmpxchg   : 8000 == 8000
Value(u32): 8000 == 8000
```

> 💡 Cách (2) là bản vẽ của **vô số thuật toán lock-free**: đọc hiện tại → thử `cmpxchg` → thất bại
> thì nhận giá trị mới và *lặp*. Không thread nào phải "đi ngủ" (không cần futex/mutex) — chỉ tranh
> chấp vài vòng ở mức CPU.

---

## 5. Data race = Illegal Behavior (≈ UB)

Zig **không có bộ nhớ bảo vệ tự động** cho dữ liệu chia sẻ. Mục [Illegal Behavior](https://ziglang.org/documentation/0.17.1/#Illegal-Behavior)
của langref phân loại:

> *"Some Illegal Behavior is **safety-checked** … the compiler will insert safety checks … If it is,
> the safety check fails, which triggers a **panic**."*
>
> *"All other Illegal Behavior is **unchecked** … anything can happen: usually that will be some kind of
> **crash, but the optimizer is free to make Unchecked Illegal Behavior do anything, such as calling
> arbitrary functions or clobbering arbitrary data**. This is similar to the concept of 'undefined
> behavior' in some other languages."*

Dịch giữ ý: một phần Illegal Behavior được **safety-checked** (compiler chen kiểm tra → panic), phần
còn lại **unchecked** — "bất cứ điều gì cũng có thể xảy ra: thường là crash, nhưng optimizer có thể
khiến nó gọi hàm bừa bãi hay xoá bừa dữ liệu. Đây tương tự khái niệm *undefined behavior* ở ngôn ngữ
khác."

Một **data race** (hai thread truy cập cùng bộ nhớ, ≥ 1 bên ghi, không đồng bộ) thuộc nhóm **unchecked
Illegal Behavior** của Zig. Vì langref 0.17.1 không còn mục dành riêng cho threads/races (concurrency
nằm trong std), tài liệu này trình bày theo ngữ nghĩa đó và dấu rõ ở mức "theo ngữ nghĩa Zig". Điều
cần khắc cốt:

- Zig **không cảnh báo hay chặn** bạn — tuỳ cách tối ưu, một race có thể ra kết quả sai, crash, hoặc
  hành vi bất khả dự đoán.
- Trách nhiệm đồng bộ hoàn toàn ở **bạn** (chọn mutex/atomic/threadlocal — [mục 7](#7-bảng-tóm-tắt-dùng-công-cụ-nào-khi-nào)).
- `volatile` **không** cứu data race: langref nhấn mạnh *"volatile is **unrelated** to concurrency and
  Atomics. If you see code that is using volatile for something other than **Memory Mapped
  Input/Output**, it is probably a bug."* — volatile chỉ cho MMIO/thiết bị (xem
  [`memory_model.md`](memory_model.md#45-volatile-allowzero-address-space)).

> ⚠️ Doc **không chạy** ví dụ race (dù chỉ là counter): kết quả race *bất định*, sai số tuỳ máy/lần
> chạy, bài học không hơn gì thông tin trên. "An toàn là trên hết" — không tạo race có chủ đích trong
> tài liệu học tập.

### 5.1 Chế độ `-fsingle-threaded`

Mục [Single Threaded Builds](https://ziglang.org/documentation/0.17.1/#Single-Threaded-Builds):

> *"Zig has a compile option `-fsingle-threaded` which has the following effects: All Thread Local
> Variables are treated as regular Namespace Level Variables … `@import("builtin").single_threaded`
> becomes true …"*

Đã probe trên 0.17.0:

- `std.Thread.spawn` trong build single-threaded là **compile error**:

  ```
  error: Cannot spawn thread when building in single-threaded mode
      @compileError("Cannot spawn thread when building in single-threaded mode");
  ```

- Mọi `threadlocal var` bị xem như **biến toàn cục thường** (xem [`variables.md`](variables.md#43-thread-local-variables)).

---

## 6. Thread-local storage (TLS)

Đã trình bày sâu ở [`variables.md` — 4.3 Thread Local Variables](variables.md#43-thread-local-variables)
(quy tắc: chỉ container level, không được `const`, mỗi thread một bản riêng). Ở đây chỉ tô phần
**tương phản** bằng `c4_tls.zig`:

```zig
const std = @import("std");

threadlocal var tls_count: u32 = 0;   // mỗi luồng có một bản riêng

fn worker(id: usize, n: u32) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        tls_count += 1;   // chỉ sửa bản của chính luồng đang chạy
    }
    std.debug.print("thread {d}: tls_count = {d}\n", .{ id, tls_count });
}

pub fn main(init: std.process.Init) !void {
    _ = init;
    const n = 1000;

    var threads: [4]std.Thread = undefined;
    for (0..4) |i| {
        threads[i] = try std.Thread.spawn(.{}, worker, .{ i, n });
    }
    for (threads) |t| t.join();

    // Luồng chính chưa từng +=, nên bản của nó vẫn là 0
    // dù 4 thread con đã tăng mỗi bản lên 1000.
    std.debug.print("main      : tls_count = {d} (khong doi)\n", .{tls_count});
}
```

Output thật:

```
thread 3: tls_count = 1000
thread 0: tls_count = 1000
thread 1: tls_count = 1000
thread 2: tls_count = 1000
main      : tls_count = 0 (khong doi)
```

Nếu bỏ `threadlocal` để biến thành **global**, 4 thread cùng cộng vào *một ô nhớ* → main in ra 4000
(và là data race nếu không khoá). TLS chính là cách nói "mỗi luồng một bản — khỏi tranh chấp".

> 💡 Đó cũng là chiêu chống **false sharing** trong [`memory_model.md` — 9.5](memory_model.md#95-đa-luồng--false-sharing):
> dữ liệu riêng từng luồng nên nằm TLS để không cùng cache-line với luồng khác.

---

## 7. Bảng tóm tắt: dùng công cụ nào, khi nào

| Công cụ | Dùng khi | 0.17 phải nhớ |
|---|---|---|
| `std.Thread.spawn` + `join` | cần **nhiều việc chạy song song**, mỗi việc một luồng | trả `!Thread`; `SpawnConfig` chỉ có `stack_size` + `allocator`; join/detach tiêu thụ handle |
| `std.Io.Mutex` | critical section **đọc-ghi dữ liệu chia sẻ**, chấp nhận block | `.init`; hàm nhận `io`; `lock` cần `try` (hoặc `lockUncancelable`); luôn `defer unlock` |
| `std.Io.RwLock` | **nhiều reader / ít writer** | reader dùng `lockShared`/`unlockShared` |
| `std.Io.Condition` | một thread **chờ một điều kiện** | `wait(&cond, io, &mutex)` — phải kèm mutex |
| `std.Io.Semaphore` | **giới hạn tài nguyên / phiên**; producer-consumer | `wait`/`post` đều cần `io` |
| `std.atomic.Value(T)` / `@atomic*` | biến đếm, cờ, state nhỏ cần thao tác **nguyên tử**, không muốn block | builtin 0.17 đòi `comptime T` đầu tiên; order qua `std.builtin.AtomicOrder` |
| `threadlocal var` | dữ liệu **riêng per-thread**, tránh tranh chấp | container level, không `const`; `-fsingle-threaded` → thành global |
| `volatile` (MMIO) | đọc/ghi **thanh ghi phần cứng** (memory-mapped I/O) | **không** phải công cụ đồng bộ thread! chỉ cho MMIO |

---

## 8. Lỗi thường gặp (probe thật trên 0.17.0)

| Thông điệp lỗi (Zig 0.17.0) | Nguyên nhân |
|---|---|
| `error: expected ',' after field` (`async fn foo() void {}`) | `async` không còn là keyword từ 0.11 |
| `error: expected block or expression, found ';'` (`suspend;`) | `suspend` không còn là keyword |
| `error: expected ';' after statement` (`await nothing()`) | `await` không còn là keyword |
| `error: invalid builtin function: '@fence'` | `@fence` không phải builtin 0.17 |
| `error: root source file struct 'Thread' has no member named 'Mutex'` | API cũ `std.Thread.Mutex` đã bỏ → `std.Io.Mutex` |
| `error: root source file struct 'Thread' has no member named 'sleep'` | `std.Thread.sleep` đã bỏ → `std.Io.sleep(io, duration, clock)` |
| `error: root source file struct 'atomic' has no member named 'Order'` | ordering là `std.builtin.AtomicOrder` |
| `error: expected 5 arguments, found 4` (`@atomicRmw(&c, .Add, 1, .monotonic)`) | builtin 0.17 cần `comptime T` đầu: `@atomicRmw(u32, &c, …)` |
| `error: Cannot spawn thread when building in single-threaded mode` | build `-fsingle-threaded` không spawn thread được |
| `error: error union of type 'error{Canceled}!void' is ignored` … `consider using 'try', 'catch', or 'if'` | gọi `Mutex.lock(io)` quên `try` |
| **Deadlock** (không lỗi compile; tiến trình treo) | quên `unlock` trên mọi nhánh (dùng `defer`), hoặc khoá chéo 2 mutex A→B vs B→A. *Không probe* — chỉ mô tả, tránh treo máy |
| **Sai kết quả do data race** (không panic, số sai/không ổn định) | hai thread ghi cùng ô nhớ không đồng bộ. *Không probe* — bất định (mục 5) |
| **Atomic order sai** (không lỗi compile, không panic, logic sai khi chạy thật) | chọn order yếu cho việc cần truyền dữ liệu; phải `acquire`/`release`/`seq_cst` cho happens-before |

---

## 9. Nguồn & liên kết

**Tài liệu chính thức:**
- [Zig Language Reference 0.17.1 — Async Functions](https://ziglang.org/documentation/0.17.1/#Async-Functions)
  — stub chứa câu "async functions regressed with the release of 0.11.0"
- [Zig Language Reference 0.17.1 — Atomics](https://ziglang.org/documentation/0.17.1/#Atomics) +
  builtins [`@atomicLoad`](https://ziglang.org/documentation/0.17.1/#atomicLoad) /
  [`@atomicRmw`](https://ziglang.org/documentation/0.17.1/#atomicRmw) /
  [`@atomicStore`](https://ziglang.org/documentation/0.17.1/#atomicStore) /
  [`@cmpxchgStrong`](https://ziglang.org/documentation/0.17.1/#cmpxchgStrong) /
  [`@cmpxchgWeak`](https://ziglang.org/documentation/0.17.1/#cmpxchgWeak)
- [Zig Language Reference 0.17.1 — volatile](https://ziglang.org/documentation/0.17.1/#volatile) —
  "volatile is unrelated to concurrency and Atomics"
- [Zig Language Reference 0.17.1 — Single Threaded Builds](https://ziglang.org/documentation/0.17.1/#Single-Threaded-Builds)
  (`-fsingle-threaded`)
- [Zig Language Reference 0.17.1 — Illegal Behavior](https://ziglang.org/documentation/0.17.1/#Illegal-Behavior)
  (safety-checked vs unchecked ≈ UB)
- Proposal: [stackless coroutines as low-level primitives](https://github.com/ziglang/zig/issues/2647)

**Source std 0.17 đã đối chiếu trực tiếp:**
- `std/Thread.zig` — `spawn`, `join`, `detach`, `SpawnConfig` (`stack_size`/`allocator`), `getCpuCount`
- `std/Io.zig` — `Mutex`, `Condition`, `RwLock`, `Semaphore`, `Event`, `Clock`, `sleep`
- `std/atomic.zig` — `Value(T)`, `Mutex` (tryLock-only)
- `std/lang.zig` — `AtomicOrder`, `AtomicRmwOp`

**Các tài liệu của dự án (đọc chéo):**
1. [`variables.md`](variables.md) — mục 4.3 Thread Local Variables (`threadlocal`, quy tắc, single-threaded)
2. [`memory_model.md`](memory_model.md) — bức tranh bộ nhớ, cache-line & false sharing (9.5), `volatile` (4.5)
3. [`errors.md`](errors.md) — error union & `try`/`defer` (nền tảng đọc đúng `lock(io) → Cancelable!void`)
4. [`build_system.md`](build_system.md) — khi cần cấu hình build đa luồng / tắt safety check khi dev

---

*Tài liệu viết cho mục đích học tập; mọi đoạn trích quan trọng lấy từ nguồn chính thức và có link để
tự kiểm chứng. Mọi output trong doc đều chạy thật trên Zig 0.17.0 (macOS ARM64) — trên máy khác thứ
tự in thread có thể khác, nhưng các con số "8000 == 8000" và hành vi compile error là bản chất của
ngôn ngữ/std, không phụ thuộc máy.*
