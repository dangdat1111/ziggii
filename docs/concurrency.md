# Async & Concurrency trong Zig — Threads, Atomics và Đồng bộ Tường minh

> Phiên bản xác minh: **Zig 0.17.0** (`zig version` → 0.17.0, cài qua homebrew), đối chiếu
> [Zig Language Reference 0.17.1 — Async Functions](https://ziglang.org/documentation/0.17.1/#Async-Functions),
> [— Atomics](https://ziglang.org/documentation/0.17.1/#Atomics), [— volatile](https://ziglang.org/documentation/0.17.1/#volatile),
> [— Single Threaded Builds](https://ziglang.org/documentation/0.17.1/#Single-Threaded-Builds)
> và source std của chính toolchain (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Thread.zig`,
> `atomic.zig`, `Io.zig`, `lang.zig`). Mọi ví dụ + output dưới đây **đều chạy thật** trên máy
> (scratch `/tmp/zigenum/concurrency/`), không dựng từ trí nhớ.
>
> ⚠️ **Đọc kỹ trước khi đi tiếp**: từ **Zig 0.11.0** trở đi, **async functions đã bị regression** —
> không còn là tính năng ngôn ngữ. Tài liệu này mở đầu bằng sự thật đó (mục 1), sau đó dạy đúng cách
> Zig 0.17 làm concurrency: **thread + atomics + đồng bộ tường minh** — không có `async/await`, không
> có runtime ngầm.

---

## Mục lục

1. [Sự thật đầu tiên: `async`/`await` KHÔNG còn trong Zig 0.17](#1-sự-thật-đầu-tiên-asyncawait-không-còn-trong-zig-017)
2. [Threads cơ bản: `spawn`, `join`, `detach`](#2-threads-cơ-bản-spawn-join-detach)
   - [2.1 `SpawnConfig` — stack & allocator](#21-spawnconfig--stack--allocator)
   - [2.2 `getCpuCount` và `sleep`](#22-getcpucount-và-sleep)
3. [Đồng bộ bậc cao: Mutex & bạn đồng hành](#3-đồng-bộ-bậc-cao-mutex--bạn-đồng-hành)
   - [3.1 `std.Io.Mutex` — vì `std.Thread.Mutex` đã biến mất](#31-stdiomutex--vì-stdthreadmutex-đã-biến-mất)
   - [3.2 Counter an toàn bằng Mutex — kết quả đúng như tuần tự](#32-counter-an-toàn-bằng-mutex--kết-quả-đúng-như-tuần-tự)
   - [3.3 Condition, RwLock, Semaphore, Event — 1 dòng mỗi loại](#33-condition-rwlock-semaphore-event--1-dòng-mỗi-loại)
4. [Atomics: đồng bộ "không cần runtime"](#4-atomics-đồng-bộ-không-cần-runtime)
   - [4.1 `std.atomic.Value(T)` — wrapper dùng hằng ngày](#41-stdatomicvaluet--wrapper-dùng-hằng-ngày)
   - [4.2 Bảng: cổng ordering trong 0.17](#42-bảng-cổng-ordering-trong-017)
   - [4.3 Builtins 0.17 — có thay đổi cú pháp!](#43-builtins-017--có-thay-đổi-cú-pháp)
   - [4.4 Ba cách làm counter atomically — chạy thật](#44-ba-cách-làm-counter-atomically--chạy-thật)
5. [Data race = Illegal Behavior (≈ undefined behavior)](#5-data-race--illegal-behavior--undefined-behavior)
   - [5.1 Chế độ `-fsingle-threaded`](#51-chế-độ--fsingle-threaded)
6. [Thread-local storage (TLS) — một biến, nhiều bản sao](#6-thread-local-storage-tls--một-biến-nhiều-bản-sao)
7. [Bảng tóm tắt: dùng công cụ nào, khi nào](#7-bảng-tóm-tắt-dùng-công-cụ-nào-khi-nào)
8. [Lỗi thường gặp (probe thật trên 0.17.0)](#8-lỗi-thường-gặp-probe-thật-trên-0170)
9. [Nguồn & liên kết](#9-nguồn--liên-kết)

---

## 1. Sự thật đầu tiên: `async`/`await` KHÔNG còn trong Zig 0.17

Mục [**Async Functions**](https://ziglang.org/documentation/0.17.1/#Async-Functions) của langref 0.17.1
chỉ còn là một **stub** (mục Atomics ở cùng một trang cũng vậy — `TODO: @atomic rmw`), với nội dung
duy nhất:

> *"**Async functions regressed with the release of 0.11.0.** The current plan is to reintroduce them
> as a lower level primitive that powers I/O implementations. Tracking issue: Proposal: stackless
> coroutines as low-level primitives."*

Dịch giữ ý: **"Async functions đã bị regression kể từ bản 0.11.0. Kế hoạch hiện tại là giới thiệu lại
chúng như một primitive cấp thấp làm nền cho các implementation I/O.** (Theo dõi qua proposal
'stackless coroutines as low-level primitives'.)"

Hệ quả trực tiếp của câu này: từ 0.11 trở đi, **không còn** cú pháp `async fn` / `await` / `suspend` /
`resume` / `nosuspend` / `anyframe` / `cancel` trong Zig. Chúng không còn là từ khoá, thậm chí
compiler còn không nhận ra chúng.

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

`error: expected ',' after field` — tức là `async` bị parser coi như một **tên field** bình thường
(chứ không phải từ khoá). Các probe tương tự:

```zig
suspend;                 // ❌
```

```
error: expected block or expression, found ';'
    suspend;
           ^
```

```zig
const x = await nothing();   // ❌
```

```
error: expected ';' after statement
    const x = await nothing();
                    ^~~~~~~
```

> 💡 Cả `suspend` lẫn `await` đều bị đối xử như **identifier** (tên biểu thức), nên trình thông dịch
> báo lỗi cú pháp chung thay vì "keyword has been removed". Điểm quan trọng với người học: đừng tìm
> `async` trong Zig hiện tại.

### 1.2 Vì sao? Triết lý "no hidden runtime" và bài học cho người học

Zig theo đuổi triết lý **"no hidden control flow"** /
**"you control concurrency explicitly"**: các vấn đề chi phối bộ nhớ (allocator, runtime, GC) và quyền
điều khiển luồng đều phải *tường minh*. Coroutine kiểu đầy đủ (`async fn` với `alloc_frame` tự cấp,
máy trạng thái giấu trong compiler, điểm suspension ẩn qua `await`) mang lại một **runtime coroutine
ngầm** — trái ngược tinh thần đó. Cách điều hành được chọn:

- **Loại bỏ** các từ khoá/nội dung async khỏi ngôn ngữ (đã làm từ 0.11).
- **Hướng tới** đưa lại sau này ở **tầng runtime/I/O thấp** (proposal stackless coroutines) để làm nền
  cho các thư viện I/O — chứ không phải để người dùng viết code thường ngày.

Hệ quả thực tế **cho bạn** ở Zig 0.17:

- Bạn làm concurrency bằng **kernel threads** (`std.Thread`) + **atomics** (`std.atomic`, các builtin
  `@atomic*`) + **đồng bộ tường minh** (mutex/condition/…). Không có "async/await để lướt trên runtime".
- Đa luồng là *chủ động*: `spawn` một thread là bạn yêu cầu OS cấp thread thật; tất cả phối hợp dữ
  liệu là do bạn viết rõ (mutex/atomic/threadlocal). Không gì xảy ra "ngầm" cả.

---

## 2. Threads cơ bản: `spawn`, `join`, `detach`

Thread trong Zig 0.17 nằm ở `std.Thread` (source `Thread.zig`) — đại diện **một kernel thread thật**.
API cốt lõi:

```zig
pub fn spawn(config: SpawnConfig, comptime function: anytype, args: anytype) SpawnError!Thread
pub fn join(self: Thread) void
pub fn detach(self: Thread) void
```

- `std.Thread.spawn(.{}, worker, .{ arg1, arg2, ... })` trả **`SpawnError!Thread`** → phải dùng `try`
  (lỗi error union bị bỏ qua sẽ không compile được).
- `join()` **chờ thread chạy xong và thu hồi tài nguyên**; con trỏ/handle bị tiêu thụ (sau khi `join`
  mà dùng lại `Thread` đó là undefined behavior).
- `detach()` **trả quyền** `join()`: thread tự dọn dẹp khi kết thúc — chỉ dùng khi bạn không cần đợi.

Ví dụ `c1_threads.zig` — spawn 4 thread, mỗi thread in id của nó, rồi main `join` cả 4:

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

> 💡 Chú ý **thứ tự in là ngẫu nhiên** — mỗi lần chạy một thứ tự khác nhau. Đó chính là bản chất của
> đa luồng: bạn **không** được giả định thứ tự thực thi giữa các thread.

### 2.1 `SpawnConfig` — stack & allocator

`SpawnConfig` trong 0.17 (đối chiếu `Thread.zig` dòng ~298) chỉ có **hai** field:

```zig
pub const SpawnConfig = struct {
    stack_size: usize = default_stack_size,   // mặc định 16 MiB (16 * 1024 * 1024)
    allocator: ?std.mem.Allocator = null,      // mặc định: OS cấp stack
};
```

> ⚠️ **Không còn field `detached`** trong 0.17 (API 0.14 có). Giờ muốn "fire and forget" thì gọi
> `thread.detach()` sau khi spawn.

Bạn có thể cấu hình stack nhỏ hơn để tiết kiệm bộ nhớ:

```zig
const t = try std.Thread.spawn(.{
    .stack_size = 1 * 1024 * 1024, // 1 MiB thay vì 16 MiB mặc định
}, worker, .{7});
t.join();
```

Output thật (`c1b_stack.zig`):

```
thread 7 on custom stack
done
```

> ⚠️ Stack 16 MiB là **giới hạn trên** theo mặc định; nếu hàm của bạn đệ quy sâu / cấp nhiều bộ nhớ
> stack thì nên tự nâng `stack_size`, nếu không có thể gặp stack overflow tại runtime.

### 2.2 `getCpuCount` và `sleep`

- `std.Thread.getCpuCount() CpuCountError!usize` — số lõi logic của máy (luôn ≥ 1). Trên máy chạy
  tài liệu này:

  ```
  cpu count = 10
  ```

- `std.Thread.sleep` — **đã bị bỏ** ở 0.17 (`error: no member named 'sleep'`). Thay vào đó là
  `std.Io.sleep(io, duration, clock) → Cancelable!void` (cần một `Io` và một `Io.Clock`):

  ```zig
  try std.Io.sleep(init.io, .{ .nanoseconds = 100 * std.time.ns_per_ms }, .real);
  ```

  hoặc `std.Io.Duration.fromMilliseconds(100)`. Các giá trị `Io.Clock` trong 0.17: `.real`, `.awake`,
  `.boot`, `.cpu_process`, `.cpu_thread`. Output thật:

  ```
  sleep 100ms...
  woke up
  ```

---

## 3. Đồng bộ bậc cao: Mutex & bạn đồng hành

### 3.1 `std.Io.Mutex` — vì `std.Thread.Mutex` đã biến mất

Nếu bạn học theo tài liệu/tutorial viết trước 0.17 và tìm `std.Thread.Mutex`, compiler sẽ thẳng tay từ
chối:

```zig
var m: std.Thread.Mutex = .{};
```

```
error: root source file struct 'Thread' has no member named 'Mutex'
```

Trong 0.17, các primitive đồng bộ **đã chuyển sang `std.Io`** — chúng cần một `Io` (nhân của tầng
I/O/đồng bộ hoàn toàn mới, thiết kế để làm nền cho concurrency tường minh). Bạn lấy `Io` ở `main` mới
kiểu `std.process.Init`, hoặc `std.testing.io` khi chạy test:

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;   // Io mặc định do runtime Zig dựng sẵn
    // …
}
```

`std.Io.Mutex` (source `Io.zig` ~dòng 1716) là `extern struct` với:

```zig
pub const Mutex = extern struct {
    pub const init: Mutex = .{ .state = .init(.unlocked) };

    pub fn lock(m: *Mutex, io: Io) Cancelable!void       // có thể bị cancel (error.Canceled)
    pub fn lockUncancelable(m: *Mutex, io: Io) void      // không tạo cancelation point
    pub fn tryLock(m: *Mutex) bool                        // không block; false nếu đang khoá
    pub fn unlock(m: *Mutex, io: Io) void
};
```

- Khởi tạo bằng **`var m: std.Io.Mutex = .init;`** (`.{}` sẽ lỗi "missing field" vì `state` không có
  default).
- `lock(io)` trả `error{Canceled}!void` nên **quên `try` sẽ không compile được**:

  ```
  error: error union of type 'error{Canceled}!void' is ignored
  note: consider using 'try', 'catch', or 'if'
  ```

  Trong ví dụ dưới đây ta dùng `lockUncancelable` (trả `void`) cho đơn giản.

> 💡 Bên cạnh đó còn `std.atomic.Mutex` (enum `{unlocked, locked}`) — một "mutex nhẹ" chỉ có
> `tryLock`/`unlock` (không có khoá block), dùng trong ngữ cảnh comptime/test. Với luồng thật hãy dùng
> `std.Io.Mutex`.

### 3.2 Counter an toàn bằng Mutex — kết quả đúng như tuần tự

`c2_mutex.zig`: 8 thread, mỗi thread tăng shared counter **1000 lần**. Không có mutex thì kết quả sẽ
sai vì `counter.* += 1` là *read-modify-write* không nguyên tử (xem mục 5). Có mutex, mọi thứ đúng như
tuần tự:

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

> ⚠️ Nếu bỏ dòng `m.lockUncancelable(io)`/`unlock` đi, kết quả sẽ thất thường (thường nhỏ hơn 8000)
> — đó là data race; Zig **không** bảo vệ bạn theo kiểu "runtime sẽ chặn", nó trả về **bất định**.
> Tài liệu này không chạy minh hoạ race (xem lý do ở [mục 5](#5-data-race--illegal-behavior--undefined-behavior))
> nhưng kết quả không-lock khác hẳn 8000 là điều bạn có thể tự thấy khi thử.

### 3.3 Condition, RwLock, Semaphore, Event — 1 dòng mỗi loại

Tất cả đều trong `std.Io` (0.17) và đều nhận `io` khi gọi:

| Công cụ | 0.17 (`std.Io`) | Cách dùng tối thiểu |
|---|---|---|
| **Condition** | `std.Io.Condition` | `wait(&cond, io, &mutex)` (chờ, giải phóng mutex); `signal(&cond, io)` đánh thức 1; `broadcast(&cond, io)` đánh thức tất cả |
| **RwLock** | `std.Io.RwLock` | `lock(&rw, io)`/`unlock(&rw, io)` — đọc-ghi độc quyền; `lockShared(&rw, io)`/`unlockShared(&rw, io)` — nhiều reader đồng thời |
| **Semaphore** | `std.Io.Semaphore` | `wait(&s, io)` giảm 1 (block nếu = 0); `post(&s, io)` tăng 1 — dùng để giới hạn tài nguyên / nhịp điệu |
| **Event** | `std.Io.Event` (enum `{unset, waiting, is_set}`) | `set(&ev, io)` bật cờ; `wait(&ev, io)` chờ đến khi set |

> 💡 Điểm chung để ghi nhớ: **mọi hạnh phúc đồng bộ trong 0.17 đều chảy qua một `Io`** — "no hidden
> runtime" nhưng vẫn có một *nhân điều phối* mà bạn phải cầm trên tay một cách tường minh.

---

## 4. Atomics: đồng bộ "không cần runtime"

### 4.1 `std.atomic.Value(T)` — wrapper dùng hằng ngày

`std.atomic.Value(T)` **có tồn tại trong 0.17** (như task dặn kiểm tra — kết quả: tồn tại). Đây là
struct generic bọc một biến `T` và cung cấp toàn bộ thao tác nguyên tử (đối chiếu `atomic.zig`):

```zig
var v = std.atomic.Value(u32).init(0);
v.store(5, .release);
const x = v.load(.acquire);
_ = v.fetchAdd(1, .monotonic);        // trả giá trị cũ, cộng nguyên tử
```

Các method có sẵn: `load`, `store`, `swap`, `cmpxchgWeak`, `cmpxchgStrong`, `fetchAdd`, `fetchSub`,
`fetchMin`, `fetchMax`, `fetchAnd`, `fetchNand`, `fetchOr`, `fetchXor`, `bitSet`, `bitReset`,
`bitToggle` — tất cả đều nhận tham số cuối là `comptime order`.

### 4.2 Bảng: cổng ordering trong 0.17

> ⚠️ **`std.atomic.Order` không tồn tại trong 0.17** (đã probe: `root source file struct 'atomic' has
> no member named 'Order'`). Enum ordering là **`std.builtin.AtomicOrder`** (alias `std.lang.AtomicOrder`;
> langref ghi nhận bằng `@import("std").lang.AtomicOrder`).

```zig
pub const AtomicOrder = enum {
    unordered,   // không ràng buộc thứ tự quanh nó — chỉ là thao tác "không tách rời"
    monotonic,   // thứ tự nhất quán toàn cục, nhưng không truyền đồng bộ dữ liệu khác
    acquire,     // cho load/rmw/cmpxchg: mọi thứ sau nó thấy dữ liệu của release trước đó
    release,     // cho store/rmw/cmpxchg: mọi thứ trước nó hiện diện cho acquire sau đó
    acq_rel,     // acquire + release (thường là rmw/cmpxchg)
    seq_cst,     // thứ tự tuần tự toàn cục — mạnh nhất, chậm nhất
};
```

Nói nôm na: `monotonic` cho **counter đếm thống kê** (kết quả cuối vẫn đúng), còn `acquire`/`release`
dùng để **truyền dữ liệu** giữa các thread (quan hệ happens-before).

### 4.3 Builtins 0.17 — có thay đổi cú pháp!

Các builtin nguyên tử trong langref 0.17.1 **đòi hỏi tham số `comptime T` tường minh ở đầu** (đổi so
với các tutorial 0.14 hay viết `@atomicRmw(&ptr, …)`). Nếu quên `T`:

```
error: expected 5 arguments, found 4
    _ = @atomicRmw(&c, .Add, 1, .monotonic);
```

Bốn builtin chính (T ∈ {pointer, bool, float, integer, enum, packed struct}):

```zig
@atomicLoad(comptime T: type, ptr: *const T, comptime ordering: AtomicOrder) T
@atomicStore(comptime T: type, ptr: *T, value: T, comptime ordering: AtomicOrder) void
@atomicRmw(comptime T: type, ptr: *T, comptime op: AtomicRmwOp, operand: T, comptime ordering: AtomicOrder) T
@cmpxchgStrong(comptime T: type, ptr: *T, expected_value: T, new_value: T,
               success_order: AtomicOrder, fail_order: AtomicOrder) ?T
@cmpxchgWeak(comptime T: type, ptr: *T, expected_value: T, new_value: T,
             success_order: AtomicOrder, fail_order: AtomicOrder) ?T
```

- `@atomicRmw` trả về **giá trị trước khi sửa**; `AtomicRmwOp` gồm `.Xchg .Add .Sub .And .Nand .Or .Xor
  .Max .Min`.
- `@cmpxchgStrong/Weak` trả `null` nếu *thành công* (giá trị hiện tại đúng bằng `expected`), trả `?T`
  của giá trị thực tế nếu *thất bại*. `Weak` có thể fail "hờ" ngay cả khi bằng nhau nhưng hiệu quả hơn
  trong retry loop; `Strong` bảo đảm thành công khi bằng nhau.
- Yêu cầu: alignment của `ptr` **≥ `@sizeOf(T)`**.
- > ❌ `@fence` **không phải builtin 0.17** (đã probe): `error: invalid builtin function: '@fence'`.
  Rào bộ nhớ thủ công không cần thiết — các thao tác `@atomicRmw`/`cmpxchg` với order mạnh đã đủ.

### 4.4 Ba cách làm counter atomically — chạy thật

`c3_atomics.zig` chạy **cùng một bài toán** (8 thread × 1000, cần đúng 8000) bằng **ba kỹ thuật khác
nhau**, không dùng mutex:

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
            old = actual; // ai đó đã ghi trước mình → thử lại với giá trị mới
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

(Phần `main` spawn/join 3 bộ thread y hệt nhau; kết quả in ra — output **thật**):

```
atomicRmw : 8000 == 8000
cmpxchg   : 8000 == 8000
Value(u32): 8000 == 8000
```

> 💡 Cách (2) là bản vẽ mẫu của **vô số thuật toán lock-free**: đọc giá trị hiện tại → thử
> `cmpxchg` → nếu thất bại thì nhận giá trị thực tế mới và **lặp**. Không bao giờ có thread nào phải
> "đi ngủ" (không cần mutex/futex), chỉ là tranh chấp tối đa vài vòng lặp ở mức CPU.

---

## 5. Data race = Illegal Behavior (≈ undefined behavior)

Zig **không có bộ nhớ bảo vệ tự động** cho dữ liệu chia sẻ. Mục [Illegal Behavior](https://ziglang.org/documentation/0.17.1/#Illegal-Behavior)
của langref phân loại hai loại "hành vi phạm pháp":

> *"Some Illegal Behavior is **safety-checked** … the compiler will insert safety checks … If it is,
> the safety check fails, which triggers a **panic**."*
>
> *"All other Illegal Behavior is **unchecked** … anything can happen: usually that will be some kind of
> **crash, but the optimizer is free to make Unchecked Illegal Behavior do anything, such as calling
> arbitrary functions or clobbering arbitrary data**. This is similar to the concept of 'undefined
> behavior' in some other languages."*

Dịch giữ ý: một phần Illegal Behavior được **safety-checked** (compiler chen kiểm tra → panic khi xảy
ra); phần còn lại là **unchecked** — "bất cứ điều gì cũng có thể xảy ra: thường là crash, nhưng
optimizer hoàn toàn có thể khiến nó gọi hàm bừa bãi hay xoá bừa dữ liệu. Đây tương tự khái niệm
*undefined behavior* ở các ngôn ngữ khác."

Một **data race** (hai thread truy cập cùng một bộ nhớ, ít nhất một bên ghi, không có đồng bộ) rơi vào
nhóm **unchecked Illegal Behavior** của Zig. Vì langref 0.17.1 không còn mục dành riêng cho
threads/races (concurrency nằm trong std), tài liệu này trình bày theo ngữ nghĩa đó và dấu rõ ở mức
"theo ngữ nghĩa Zig". Điều cần khắc cốt ghi tâm:

- Zig **sẽ không cảnh báo hay chặn** bạn — tuỳ cách compiler tối ưu, một race có thể cho ra kết quả
  sai, crash, hoặc hành vi bất khả dự đoán khác.
- Trách nhiệm đồng bộ hoàn toàn ở **bạn**: chọn mutex, atomic, threadlocal… cho phù hợp (bảng tổng ở
  [mục 7](#7-bảng-tóm-tắt-dùng-công-cụ-nào-khi-nào)).
- `volatile` **không** cứu data race: langref nhấn mạnh *"volatile is **unrelated** to concurrency and
  Atomics. If you see code that is using volatile for something other than **Memory Mapped
  Input/Output**, it is probably a bug."* — volatile chỉ dành cho MMIO/thiết bị, không phải công cụ
  đồng bộ thread (lưu ý này gắn với [`memory_model.md`](memory_model.md#45-volatile-allowzero-address-space)).

> ⚠️ Tài liệu này **không chạy** một ví dụ race (dù chỉ là counter): kết quả race là *bất định*, sai
> số tuỳ máy/tuỳ lần chạy, và bài học sẽ không khác gì thông tin trên. "An toàn là trên hết" — không
> tạo race có chủ đích trong doc học tập.

### 5.1 Chế độ `-fsingle-threaded`

Langref mục [Single Threaded Builds](https://ziglang.org/documentation/0.17.1/#Single-Threaded-Builds):

> *"Zig has a compile option `-fsingle-threaded` which has the following effects: All Thread Local
> Variables are treated as regular Namespace Level Variables … `@import("builtin").single_threaded`
> becomes true …"*

Trên 0.17.0, hệ quả thực tế đã **probe** được:

- `std.Thread.spawn` trong build single-threaded là **compile error**:

  ```
  error: Cannot spawn thread when building in single-threaded mode
      @compileError("Cannot spawn thread when building in single-threaded mode");
  ```

- Mọi `threadlocal var` bị xem như **biến toàn cục thường** (đã nói ở [`variables.md`](variables.md#43-thread-local-variables)):
  trong chương trình đơn luồng, mỗi luồng chỉ là "1 luồng", nên TLS ≈ global không còn ý nghĩa phân
  biệt.

---

## 6. Thread-local storage (TLS) — một biến, nhiều bản sao

Đã trình bày sâu ở [`variables.md` — 4.3 Thread Local Variables](variables.md#43-thread-local-variables)
(quy tắc: chỉ ở container level, không được `const`, mỗi thread một bản riêng). Ở đây chỉ tô đậm phần
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

Nếu bỏ `threadlocal` để biến thành **global**, cả 4 thread sẽ cộng vào *cùng một* ô nhớ → kết quả
main in ra sẽ là 4000 (và đó hẳn nhiên là một data race nếu không khoá). TLS chính là cách nói "mỗi
luồng một bản — khỏi tranh chấp".

> 💡 Đó cũng là chiêu chống **false sharing** trong [`memory_model.md` — 9.5](memory_model.md#95-đa-luồng--false-sharing):
> dữ liệu riêng từng luồng nên nằm trong TLS để không cùng cache-line với dữ liệu luồng khác.

---

## 7. Bảng tóm tắt: dùng công cụ nào, khi nào

| Công cụ | Dùng khi | 0.17 phải nhớ |
|---|---|---|
| `std.Thread.spawn` + `join` | cần **nhiều công việc chạy song song** mà mỗi việc là một luồng | trả `!Thread`; `SpawnConfig` chỉ có `stack_size` + `allocator`; join/detach tiêu thụ handle |
| `std.Io.Mutex` | critical section **đọc-ghi dữ liệu chia sẻ**, có thể block chờ | khởi tạo `.init`; mọi hàm nhận `io`; `lock` cần `try`, hoặc dùng `lockUncancelable`; luôn `defer unlock` |
| `std.Io.RwLock` | **nhiều reader / ít writer** — reader không cần loại trừ nhau | `lockShared`/`unlockShared` cho reader |
| `std.Io.Condition` | một thread **chờ một điều kiện** (có mutex làm "cột") | `wait(&cond, io, &mutex)`; phải kèm mutex |
| `std.Io.Semaphore` | **giới hạn số phiên/tài nguyên**; nhịp điệu producer/consumer | `wait`/`post` đều cần `io` |
| `std.atomic.Value(T)` / `@atomic*` | biến đếm, cờ, state nhỏ cần thao tác **nguyên tử**, không muốn block | 0.17 builtin đòi `comptime T` làm tham số đầu; order qua `std.builtin.AtomicOrder` |
| `threadlocal var` | dữ liệu **riêng per-thread** để khỏi tranh chấp | chỉ container level, không `const`, trong `-fsingle-threaded` thành global |
| `volatile` (MMIO) | đọc/ghi **thanh ghi phần cứng**, memory-mapped I/O | **không** phải công cụ đồng bộ thread! chỉ dùng cho MMIO |

---

## 8. Lỗi thường gặp (probe thật trên 0.17.0)

| Thông điệp lỗi (Zig 0.17.0) | Nguyên nhân |
|---|---|
| `error: expected ',' after field` (với `async fn foo() void {}`) | `async` không còn là keyword 0.11+ — đừng dùng cú pháp cũ |
| `error: expected block or expression, found ';'` (với `suspend;`) | `suspend` không còn là keyword |
| `error: expected ';' after statement` (với `await …`) | `await` không còn là keyword |
| `error: invalid builtin function: '@fence'` | `@fence` không phải builtin 0.17 (không cần thiết) |
| `error: root source file struct 'Thread' has no member named 'Mutex'` | API cũ `std.Thread.Mutex` đã bỏ → dùng `std.Io.Mutex` |
| `error: root source file struct 'Thread' has no member named 'sleep'` | `std.Thread.sleep` đã bỏ → dùng `std.Io.sleep(io, duration, clock)` |
| `error: root source file struct 'atomic' has no member named 'Order'` | ordering là `std.builtin.AtomicOrder`, không phải `std.atomic.Order` |
| `error: expected 5 arguments, found 4` (`@atomicRmw(&c, .Add, 1, .monotonic)`) | builtin 0.17 cần `comptime T` ở đầu: `@atomicRmw(u32, &c, …)` |
| `error: Cannot spawn thread when building in single-threaded mode` | build với `-fsingle-threaded` không spawn thread được |
| `error: error union of type 'error{Canceled}!void' is ignored` … `consider using 'try', 'catch', or 'if'` | gọi `Mutex.lock(io)` mà quên `try` |
| **Deadlock** (không phải lỗi compile; tiến trình treo) | quên `unlock` trên mọi nhánh (dùng `defer`), hoặc khoá chéo 2 mutex kiểu A→B vs B→A. *Không probe* vì sẽ treo máy — chỉ mô tả. |
| **Sai kết quả** do **data race** (không có panic, chỉ số sai/không ổn định) | hai thread ghi cùng ô nhớ không đồng bộ. *Không probe* — bất định (xem mục 5). |
| Atomic **order sai** (không lỗi compile, không panic, nhưng logic sai trong chương trình thật) | chọn `monotonic` cho việc cần truyền dữ liệu; phải dùng `acquire`/`release`/`seq_cst` cho happens-before |

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

**Source std 0.17 đã đối chiếu trực tiếp:**
- `std/Thread.zig` — `spawn`, `join`, `detach`, `SpawnConfig` (`stack_size`/`allocator`), `getCpuCount`
- `std/Io.zig` — `Mutex`, `Condition`, `RwLock`, `Semaphore`, `Event`, `Clock`, `sleep`, `Io.Mutex.Order` không có
- `std/atomic.zig` — `Value(T)`, `Mutex` (tryLock-only)
- `std/lang.zig` — `AtomicOrder`, `AtomicRmwOp`
- Proposal: [stackless coroutines as low-level primitives](https://github.com/ziglang/zig/issues/2647)
  (hướng tái thiết async)

**Các tài liệu của dự án (đọc chéo):**
1. [`variables.md`](variables.md) — mục 4.3 Thread Local Variables (`threadlocal`, quy tắc, single-threaded)
2. [`memory_model.md`](memory_model.md) — bức tranh bộ nhớ, cache-line & false sharing (mục 9.5), `volatile` (mục 4.5)
3. [`errors.md`](errors.md) — error union & `try`/`defer` (nền tảng để đọc đúng `lock(io) → Cancelable!void`)
4. [`build_system.md`](build_system.md) — nếu bạn cần cấu hình build đa luồng / tắt safety check (khi dev)

---

*Tài liệu viết cho mục đích học tập; mọi đoạn trích quan trọng lấy từ nguồn chính thức và có link để
tự kiểm chứng. Mọi output trong doc đều chạy thật trên Zig 0.17.0 (macOS ARM64) — trên máy khác thứ
tự in thread có thể khác, nhưng các con số "8000 == 8000" và hành vi compile error là bản chất của
ngôn ngữ/std, không phụ thuộc máy.*
