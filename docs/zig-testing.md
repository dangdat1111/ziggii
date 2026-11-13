# Zig Test — Cách viết test cho dự án Zig

> Phiên bản xác minh: **Zig 0.17.0** (`zig version` → 0.17.0). Các ví dụ chính
> đã chạy qua `zig test` trên máy để kiểm chứng; dẫn chứng mã nguồn mở trích trực
> tiếp từ các repo (có link tại mục Tài liệu tham khảo).

---

## 1. Zig test là gì (tài liệu chính thức)

Theo [Zig Language Reference — Zig Test](https://ziglang.org/documentation/master/#toc-Zig-Test):

- `test "tên" { ... }` là **top-level declaration** (ngang hàng hàm/const), giống hàm với
  kiểu trả về ngầm định `anyerror!void` (không đổi được). Khi build không phải dạng test,
  các khối `test` bị loại khỏi nhị phân.
- `zig test file.zig` tạo một *test build*: dùng **default test runner** của std lib
  (`lib/compiler/test_runner.zig`) làm entry point, chạy mọi khối `test` và báo kết quả.
- Test đặt tên bằng **identifier** là *doctest* — vừa là tài liệu cho declaration, vừa được
  chạy kiểm chứng khi build test.

Ví dụ giới thiệu chính thức, chạy thử trên Zig 0.17.0:

```zig
const std = @import("std");

test "expect addOne adds one to 41" {
    // `expect` kiểm tra đối số là true, trả về error nếu false.
    try std.testing.expect(addOne(41) == 42);
    // `expectEqual` cho thông báo lỗi rõ ràng hơn nhiều.
    try std.testing.expectEqual(42, addOne(41));
}

test addOne {
    // Test đặt tên bằng identifier = doctest, dùng làm tài liệu cho `addOne`.
    try std.testing.expectEqual(42, addOne(41));
}

/// Hàm `addOne` cộng thêm 1 vào đối số.
fn addOne(number: i32) i32 {
    return number + 1;
}
```

Chạy `zig test testing_introduction.zig`:

```
1/2 testing_introduction.test.expect addOne adds one to 41...OK
2/2 testing_introduction.decltest.addOne...OK
All 2 tests passed.
```

Các tính năng chính của runner:

| Tính năng | Cách dùng |
| --- | --- |
| Lọc test | `zig test file.zig --test-filter [text]` |
| Bỏ qua test có điều kiện | `return error.SkipZigTest;` |
| Báo memory leak | cấp phát qua `std.testing.allocator` → runner tự báo leak |
| Fuzz tích hợp (≥ 0.15) | `try std.testing.fuzz(context, testFn, .{});` + `zig build test --fuzz` |
| Công cụ sinh dữ liệu fuzz | `std.testing.Smith` |

CSS quan trọng: **không có hàm `std.testing.addTests`** (đã kiểm chứng trên mã nguồn
`std/testing.zig`). Việc "gom test theo từng module/package" do `std.Build.addTest` trong
`build.zig` đảm nhiệm (xem mục 4).

---

## 2. Mã nguồn mở viết zig test như thế nào (dẫn chứng cụ thể)

### 2.1 Zig std lib — test ngay cạnh code, không thư mục test riêng

[`lib/std/hash_map.zig`](https://github.com/ziglang/zig/blob/master/lib/std/hash_map.zig):

```zig
test "basic usage" {
    var map = AutoHashMap(u32, u32).init(std.testing.allocator);
    defer map.deinit();
    // ... setUp dữ liệu ...
    try expectEqual(total, sum);
}

test "getOrPut allocation failure" {
    var map: std.StringHashMapUnmanaged(void) = .empty;
    try testing.expectError(error.OutOfMemory, map.getOrPut(std.testing.failing_allocator, "hello"));
}
```

Quan sát:

- Test **cùng file** với code; mở file bằng `const testing = std.testing;` để rút gọn gọi hàm.
- **Tên test mô tả hành vi**, kiểu "shrink still sets length when resizing is disabled".
- **`std.testing.allocator` + `defer deinit()`** — cách chuẩn để runner phát hiện memory leak.
- **`failing_allocator` + `expectError(error.OutOfMemory, ...)`** — test nhánh hết bộ nhớ;
  `checkAllAllocationFailures` để test cạn kiệt alloc từng bước một.
- Các hàm khẳng định đặc thù: `expectEqualSlices`, `expectEqualStrings`, `expectEqualSentinel`,
  `expectError`, `expectFmt`.

### 2.2 TigerBeetle — test inline, snapshot + fuzz có seed cố định

[`src/vsr.zig`](https://github.com/tigerbeetle/tigerbeetle/blob/main/src/vsr.zig) mở đầu bằng
khối **aggregator** — gom toàn bộ test của mọi file trong `src/`:

```zig
test {
    _ = @import("unit_tests.zig");
}
```

Bỏ test có điều kiện đúng chuẩn chính thức:

```zig
test "quorums" {
    if (constants.quorum_replication_max != 3) return error.SkipZigTest;
    // ...
    try std.testing.expectEqual(expect_replication[i], actual.replication);
}
```

- **Snapshot/golden test**: output chuẩn nằm ngay trong source, key bằng `@src()`, regenerate
  bằng biến môi trường `SNAP_UPDATE=1`.
- **Fuzz/randomized test với seed cố định** (chạy lại được, dùng cho CI): chạy một dãy seed
  như `[_]u64{ 34, 14, 158, ... }` trong `ArenaAllocator` khởi tạo từ `std.testing.allocator`.
- Bộ phận `src/unit_tests.zig` là một "quine" tự duyệt `src/` để cập nhật danh sách import test
  và báo lỗi nếu lệch (chỉ đạo `SNAP_UPDATE=1`).

### 2.3 Ghostty — inline test + bảo phủ mọi declaration + table-driven

[`src/main.zig`](https://github.com/ghostty-org/ghostty/blob/main/src/main.zig) gom toàn bộ
chương trình, gồm cả `refAllDecls` để đảm bảo mọi declaration được biên dịch/chạy:

```zig
test {
    std.testing.log_level = std.log.Level.err;
    _ = entrypoint;
    _ = @import("quirks_memset.zig");
}
```

Tại các module root (ví dụ `src/input.zig`):

```zig
test {
    std.testing.refAllDecls(@This());
}
```

**Table-driven test** điển hình ([`src/config/url.zig`](https://github.com/ghostty-org/ghostty/blob/main/src/config/url.zig)):

```zig
test "url regex" {
    const cases = [_]struct { input: []const u8, expect: []const u8 }{
        .{ .input = "hello https://example.com world", .expect = "https://example.com" },
        // ...
    };
    for (cases) |case| {
        // ...
        try testing.expectEqualStrings(case.expect, match);
    }
}
```

Ghostty tự viết **test runner server-mode chia shard** (`zig build test -Dtest-shards=N`) để
chạy song song bộ test Debug lớn — nhưng cốt lõi vẫn là khối `test "..."` + `std.testing`.

### 2.4 zap — test riêng file nhưng cùng ngôn ngữ khẳng định

zap để test ở `src/tests/` (khác std lib) nhưng **vẫn dùng `std.testing`**; mỗi file test thành
một binary test riêng vì test mạng phải chạy tuần tự (zap không xử lý chạy nhiều lần song song).
Test mạng **không mock**: mở listener thật trên `127.0.0.1:3020`, sinh thread client, khẳng định
trong callback ([`src/tests/test_recvfile.zig`](https://github.com/zigzap/zap/blob/master/src/tests/test_recvfile.zig)).

### 2.5 bun — ngoại lệ đáng nêu

Bun gần như không còn Zig test đơn vị (lớp logic đã chuyển sang Rust); test của họ là JS/TS chạy
bằng `bun:test` qua Node. Điều này củng cố quy tắc: **viết test bằng chính ngôn ngữ của code
đang test (Zig test cho code Zig)**, đừng dựa vào tầng khác.

### 2.6 Áp dụng ngay tại repo này (`ziggii`)

`zig build test` trong repo **chạy OK** (exit 0). Repo đã đi đúng convention:

- `src/root.zig` — test ngay cạnh hàm, tên mô tả:
  ```zig
  test "basic add functionality" {
      try std.testing.expect(add(3, 7) == 10);
  }
  ```
- `src/main.zig` — dùng `std.testing.allocator` + `defer list.deinit(gpa)` (comment trong code
  hướng dẫn thử bỏ dòng `defer` để xem zig báo leak) và fuzz test `std.testing.fuzz({}, testOne, .{})`
  với `std.testing.Smith`.
- `build.zig` — hai binary test (`mod_tests`, `exe_tests`) gom vào `b.step("test", ...)`.

---

## 3. Quy tắc chung khi viết zig test

> **Hãy coi test là bộ phận không thể tách rời của code: đặt test ngay cạnh code,
> khẳng định bằng `std.testing` với hàm càng đặc tả càng tốt, cấp phát heap bằng
> `std.testing.allocator` và giải phóng bằng `defer` để runner tự phát hiện memory
> leak, rồi chạy toàn bộ qua `zig build test`.**

Quy tắc này bao hàm 5 điểm bắt buộc — đều có mặt ở std lib, TigerBeetle, Ghostty, zap và `ziggii`:

1. **Inline test, không tách thư mục**: viết `test "mô tả" { ... }` ngay dưới hàm nó test trong
   cùng file (hàm public dùng tên identifier để thành doctest). Đây là convention đặc trưng
   của Zig — khác với `tests/` riêng của nhiều ngôn ngữ khác.
2. **Dùng hàm khẳng định đặc tả nhất của `std.testing`**: ưu tiên `expectEqual` hơn `expect`
   (lỗi dễ đọc hơn), rồi `expectEqualStrings`, `expectEqualSlices`, `expectError`, `expectFmt`.
   Không tự viết asset thủ công (ngoài helper riêng như `deepEqual` của Ghostty).
3. **Mọi cấp phát heap qua `std.testing.allocator` kèm `defer ...deinit()`** — đây là cách zig
   tự soi memory leak; thêm `failing_allocator` + `expectError(error.OutOfMemory, ...)` để cover
   nhánh lỗi alloc như std lib và TigerBeetle đang làm.
4. **Test hành vi thật, không mock**; logic phức tạp/ngẫu nhiên dùng property/fuzz test với seed
   cố định để tái lập được (TigerBeetle VOPR, `std.testing.fuzz` + `Smith`).
5. **Dây toàn bộ qua `build.zig`**: `std.Build.addTest(.{ .root_module = ... })` +
   `b.addRunArtifact(...)` (thiếu `addRunArtifact` thì test chỉ được biên dịch, không chạy), gom
   vào `b.step("test", ...)` để `zig build test` chạy hết; dùng `error.SkipZigTest` và
   `--test-filter` để loại/điều hướng.

**Khuôn mẫu (template) tối thiểu khi thêm một hàm mới vào repo này:**

```zig
/// Cộng hai số nguyên.
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test add {
    try std.testing.expectEqual(@as(i32, 42), add(40, 2));
}

test "add hoạt động với số âm" {
    try std.testing.expectEqual(@as(i32, -1), add(1, -2));
}
```

---

## 4. Dây test vào `build.zig`

Cách chuẩn theo [build system guide](https://ziglang.org/learn/build-system/) (đúng như
`ziggii/build.zig` đang dùng):

```zig
const mod_tests = b.addTest(.{ .root_module = mod });
const run_mod_tests = b.addRunArtifact(mod_tests);

const test_step = b.step("test", "Run tests");
test_step.dependOn(&run_mod_tests.step);
```

- Test executable **chỉ test một module một lúc** → mỗi module/artifact một
  `b.addTest` riêng (repo này có hai: module `ziggii` và module của `exe`).
- `zig build test -- <filter>` và `zig build --help` cho biết các cờ như
  `--test-timeout <ms>` và `--fuzz[=limit]`.
- Từ 0.15 còn `zig test-obj` / `emit_object` để build test ra object file (cho tình huống
  load như shared library), không cần link thành binary.

---

## 5. Tài liệu tham khảo

- [Zig Language Reference — Zig Test](https://ziglang.org/documentation/master/#toc-Zig-Test)
- [Zig Learn — Build System (mục Testing)](https://ziglang.org/learn/build-system/)
- [zig.guide — Running Tests](https://zig.guide/getting-started/running-tests/)
- [Release notes 0.14 — fuzzer tích hợp](https://ziglang.org/download/0.14.0/release-notes.html)
- [ziglang/zig — lib/std/hash_map.zig](https://github.com/ziglang/zig/blob/master/lib/std/hash_map.zig)
- [ziglang/zig — lib/std/testing.zig](https://github.com/ziglang/zig/blob/master/lib/std/testing.zig)
- [tigerbeetle/tigerbeetle — src/vsr.zig](https://github.com/tigerbeetle/tigerbeetle/blob/main/src/vsr.zig)
- [tigerbeetle/tigerbeetle — src/state_machine_fuzz.zig](https://github.com/tigerbeetle/tigerbeetle/blob/main/src/state_machine_fuzz.zig)
- [ghostty-org/ghostty — src/config/url.zig](https://github.com/ghostty-org/ghostty/blob/main/src/config/url.zig)
- [zigzap/zap — src/tests/test_recvfile.zig](https://github.com/zigzap/zap/blob/master/src/tests/test_recvfile.zig)
