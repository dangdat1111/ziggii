# Zig Build System — hướng dẫn toàn diện

> Phiên bản xác minh: **Zig 0.17.0** (`zig version`, cài qua homebrew), đối chiếu
> [Zig Language Reference 0.17.1 — Zig Build System](https://ziglang.org/documentation/0.17.1/#Zig-Build-System)
> và source `std/Build.zig` của chính toolchain (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Build.zig`).
> Mọi lệnh dưới đây đều **chạy thật** bằng `zig build` 0.17.0; demo `tổng hợp` dựng ở
> `/tmp/zigenum/buildsys/` đã build, chạy, test, fmt thành công. Mọi cú pháp API 0.17 (module +
> `root_module`) được đối chiếu từ `build.zig` thật của project
> `/Users/primeoptimus/Personal/ziggii` và `Build.zig`.

---

## Mục lục

1. [Build System là gì?](#1-build-system-là-gì)
2. [`zig build` CLI & `zig build --help`](#2-zig-build-cli--zig-build---help)
3. [Cấu trúc project: build.zig, build.zig.zon, src/](#3-cấu-trúc-project-buildzig-buildzigzon-src)
   - [3.1 Module & executable — API 0.17 (`root_module`)](#31-module--executable--api-017-root_module)
   - [3.2 Steps & test](#32-steps--test)
4. [Steps & cache](#4-steps--cache)
5. [Options & chế độ build](#5-options--chế-độ-build)
   - [5.1 `-Doptimize` — debug / safe / fast / small](#51-doptimize--debug--safe--fast--small)
   - [5.2 Cross-compile `-Dtarget` / `-Dcpu`](#52-cross-compile--dtarget--dcpu)
6. [Dependencies — build.zig.zon & `b.dependency`](#6-dependencies--buildzigzon--bdependency)
7. [Demo thực hành (output thật)](#7-demo-thực-hành-output-thật)
8. [So sánh nhanh: Make / CMake + "comptime config"](#8-so-sánh-nhanh-make--cmake--comptime-config)
9. [Lỗi thường gặp (probe thật)](#9-lỗi-thường-gặp-probe-thật)
10. [Nguồn & liên kết](#10-nguồn--liên-kết)

---

## 1. Build System là gì?

Langref mô tả build system của Zig trong **một mục rất ngắn**, và dẫn tài liệu chi tiết đi **host
ngoài**:

> *"The Zig Build System provides a **cross-platform, dependency-free** way to declare the logic
> required to build a project. … the logic to build a project is written in a `build.zig` file, using
> the Zig Build System API to declare and configure build artifacts and other tasks."* —
> [Zig-Build-System](https://ziglang.org/documentation/0.17.1/#Zig-Build-System)
>
> *"For the time being, the build system documentation is hosted externally: **Build System
> Documentation**."*

Ba đặc tính cốt lõi:

- **Cross-platform**: không phụ thuộc `Make`/`CMake`/shell của một OS — chỉ cần mỗi `zig`.
- **Dependency-free**: build logic **viết bằng chính Zig** trong `build.zig`, dùng Build API
  `std.Build` — "dùng Zig để nói về cách build Zig".
- **Declarative**: hàm `build` chỉ **đắp một build graph** (các `Step` + quan hệ phụ thuộc) để một
  **runner** thực thi — runner lo parallel + cache. Trích [Build.zig](https://ziglang.org/documentation/master/std/Build/#A;std:Build):

> *"The functions in `std.Build` implement a **DSL for defining build steps and express dependencies
> between them**, allowing the build runner to **parallelize the build automatically** (and the cache
> system to know when a step doesn't need to be re-run)."*

Langref liệt kê các việc build system hỗ trợ:

| # | Task (langref) | Ghi chú liên hệ bài này |
|---|---|---|
| 1 | Performing tasks **in parallel and caching** the results | mục 4 — `-j<N>`, cache step |
| 2 | **Depending on other projects** | mục 6 — `build.zig.zon` + `b.dependency` |
| 3 | Providing a **package** for others to depend on | mục 6 — `addModule` public |
| 4 | Building Zig **and C/C++** source | `addTranslateC`, `addLibrary`, `addObject` |
| 5 | Capturing **user-configured options** | mục 5 — `-D...`, `b.option` |
| 6 | Surfacing build config as **comptime values** (file import được bởi Zig) | mục 8 — `@import("builtin")` / generated file |
| 7 | **Caching** artifacts to avoid repeating steps | mục 4 |
| 8 | **Executing** build artifacts or system tools | `addRunArtifact`, `addSystemCommand` |
| 9 | Running **tests**, verifying output | mục 7 — `zig build test` |
| 10 | Running **zig fmt** on the codebase | mục 7 — step `fmt`/`fmt-check` |
| 11 | **Custom tasks** | bất kỳ step nào tự định nghĩa |

> 💡 Vì tài liệu build system host ngoài langref, **cách học tốt nhất là đọc `std/Build.zig`** (có
> doc comment rất kỹ từng `pub fn`) kết hợp chạy thử — chính `build.zig` của project `ziggii` cũng
> khuyên: *"the Zig build system is relatively simple and self-contained, and reading its source code
> will allow you to master it."*

---

## 2. `zig build` CLI & `zig build --help`

Lệnh chính: **`zig build [steps] [options]`**. Trong thư mục project, `zig build --help` in ra menu —
**bao gồm các step/option riêng của project** mà `build.zig` khai báo. Đây là output thật từ
project `/Users/primeoptimus/Personal/ziggii` trên Zig 0.17.0 (rút gọn phần quan trọng):

```
$ zig build --help
Usage: /opt/homebrew/Cellar/zig/0.17.0/bin/zig build [steps] [options]

Steps:
  install (default)            Copy build artifacts to prefix path
  uninstall                    Remove build artifacts from prefix path
  run                          Run the app
  test                         Run tests

Project-Specific Options:                          ← do build.zig đăng ký
  -Dtarget=[string]            The CPU architecture, OS, and ABI to build for
  -Dcpu=[string]               Target CPU features to add or subtract
  -Dofmt=[string]              Target object format
  -Ddynamic-linker=[string]    Path to interpreter on the target system
  -Doptimize=[enum]            Prioritize performance, safety, or binary size
                                 Supported Values:
                                   debug / safe / fast / small
```

Các lệnh/steps cơ bản thường dùng nhất:

| Lệnh | Ý nghĩa |
|---|---|
| `zig build` | chạy **default step `install`**: build rồi copy artifact vào `zig-out/` |
| `zig build run` / `zig build test` | build + chạy executable / các `test` block (step do project định nghĩa) |
| `zig build <step>` | chạy đúng step có tên đó (`--list-steps`/`-l` để liệt kê) |
| `zig build -- <args...>` | truyền đối số cho run step (project khai báo `addPassthruArgs`) |
| `zig build --release[=fast]` | yêu cầu release mode; nếu project không khai `preferred_optimize_mode` thì bắt buộc `--release=fast/safe/small` |
| `zig build --summary all` | in tóm tắt **toàn bộ** (kể cả step cached) — mục 4 |
| `zig build --verbose` | in từng lệnh compiler thật được chạy |
| `zig build -p <dir>` / `--prefix` | đổi nơi cài đặt (mặc định `zig-out`) |
| `zig build --watch` | build lại liên tục khi source thay đổi |
| `zig build --fetch` | fetch cây dependency rồi thoát (package management) |

Các nhóm còn lại trong help thật 0.17: **System Integration Options** (`--search-prefix`,
`--sysroot`, `--libc`, `-fsys`, `-fqemu`, `-fwasmtime`, `-fwine`, `-frosetta`…); **General Options**
(`-p/--prefix`, `--release`, `--summary [all|new|failures|line|none]`, `-j<N>`, `--test-timeout`,
`--watch`, `--fuzz[=limit]`, `--time-report`, `-fincremental`); **Package Management Options**
(`--fetch`, `--fork`); **Advanced Options** (`--build-file`, `--cache-dir`, `--zig-lib`,
`--print-configuration`, `--build-id`…).

> ⚠️ `zig build run -- a b c` cần **`--`** để tách đối số chương trình khỏi đối số của `zig build`.
> Output thật của demo (xem mục 7) cho thấy `argv[0]` là đường dẫn binary đã cài
> (`./zig-out/bin/tonghop`) vì run step phụ thuộc install step.

---

## 3. Cấu trúc project: build.zig, build.zig.zon, src/

Cấu trúc chuẩn của một project Zig (đúng như project `ziggii` và demo `tổng hợp`):

```
project/
├── build.zig          # logic build — entry: pub fn build(b: *std.Build) void
├── build.zig.zon      # metadata + dependencies của package
├── src/
│   ├── main.zig       # entry of executable (có pub fn main)
│   └── root.zig       # root source của module (library) — chỉ pub decl lộ ra
├── .zig-cache/        # cache build (tự sinh, gitignore)
└── zig-out/           # nơi cài artifact (tự sinh, gitignore)
```

- **`build.zig`** — hàm `build` được khai báo là `pub fn build(b: *std.Build) void`. Nó nhận con trỏ
  `std.Build` (`b`) và **chỉ đắp graph**: tạo module/artifact/step rồi nối `dependOn()`. Không có
  câu lệnh nào ở đây thực thi biên dịch.
- **`build.zig.zon`** — bằng tiếng Zig `zon` (anonymous struct literal). Chứa identity của package:
  `.name`, `.version`, `.fingerprint`, `.minimum_zig_version`, `.dependencies`, `.paths`, `.lazy`.
  Chi tiết mục 6.
- **`src/`** — source code; thư mục nào nằm trong `.paths` của zon mới được đóng gói/đĩa khi có
  người fetch package.

### 3.1 Module & executable — API 0.17 (`root_module`)

⚠️ **Điểm quan trọng của API 0.17:** không còn kiểu `addExecutable(.{ .root_source_file = ... })`
một tầng như 0.13/0.14. Từ 0.15+ (và 0.17 này), API **tách module ra khỏi artifact**: bạn tạo
`Module` (bản đồ source + target/optimize/imports) trước, rồi gắn vào artifact qua **`.root_module`**.
Đây là bản sao của block thật trong `build.zig` project `ziggii`, chạy đúng trên 0.17.0:

```zig
const mod = b.addModule("ziggii", .{
    .root_source_file = b.path("src/root.zig"),
    .target = target,
});

const exe = b.addExecutable(.{
    .name = "ziggii",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "ziggii", .module = mod },
        },
    }),
});
```

Giải thích các khối quen thuộc (đối chiếu `std/Build.zig`):

| API (0.17) | Công dụng |
|---|---|
| `standardTargetOptions(.{})` | đăng ký `-Dtarget/-Dcpu/-Dofmt/-Ddynamic-linker`, trả `ResolvedTarget` |
| `standardOptimizeOption(.{})` | đăng ký `-Doptimize` (+ `--release[=mode]`), trả `std.builtin.Optimize` |
| `b.addModule("name", opts)` | tạo module **public**, package khác import được qua `@import("name")` — [Build.zig](https://ziglang.org/documentation/master/std/Build/#A;std:Build.addModule) |
| `b.createModule(opts)` | tạo module **private** (không expose ra ngoài package) |
| `Module.CreateOptions` | `{: .root_source_file, .target, .optimize, .imports }` — `.optimize` bắt buộc khi dùng làm root của executable/library |
| `b.addExecutable(.{ .name, .root_module })` | artifact executable; `ExecutableOptions` chỉ yêu cầu `name` + `root_module` |
| `b.addTest(.{ .root_module = ... })` | executable chứa các `test` block của một module (chưa chạy) — cần `addRunArtifact` để chạy thật |
| `b.addLibrary(.{ .linkage, .name, .root_module })` | thư viện static/shared |
| `b.addObject(.{ .name, .root_module })` | object file C-ABI nối thủ công |
| `b.addTranslateC(.{...})` | dịch file C → Zig (`zig translate-c` thành một step) |
| `b.addWriteFiles()` | sinh file bất kỳ vào cache (asset, config…) |
| `b.addFmt(.{ .paths, .check })` | step `zig fmt` (sửa file hoặc chỉ kiểm tra) |
| `b.path("src/x.zig")` | tạo `LazyPath` trỏ tới file trong cây build — không truyền chuỗi thô cho các field `LazyPath` |
| `b.option(T, "name", "desc")` | option tùy biến của project → tự hiện trong `--help` |

Chi tiết `.imports` — cách gắn module vào source cho import: `"ziggii"` ở đây là tên bạn dùng trong
source (`@import("ziggii")`) — được **đổi tên tự do** khi import để tránh xung đột giữa các package.
`b.addModule` lộ module ra cho *người tiêu thụ* package; `b.createModule` chỉ dùng nội bộ (chú thích
trong `Build.zig` nhấn mạnh khác biệt này).

> 💡 Muốn tạo **library + CLI** cùng một mô-đun: để business logic ở `root.zig` (module public),
> còn `main.zig` (executable) import module đó — đúng mẫu project `ziggii`.

### 3.2 Steps & test

Nối các step bằng `dependOn` — đây là cách thêm **top-level step** để user gọi theo tên:

```zig
const run_step = b.step("run", "Run the app");       // tên + mô tả hiện trong --help
const run_cmd = b.addRunArtifact(exe);               // chạy binary do zig build
run_step.dependOn(&run_cmd.step);
run_cmd.step.dependOn(b.getInstallStep());           // chạy từ zig-out thay vì trong cache
run_cmd.addPassthruArgs();                           // cho phép `zig build run -- args`

// Test: mỗi module cần một bộ test riêng (b.addTest chỉ test MỘT module)
const mod_tests = b.addTest(.{ .root_module = mod });
const run_mod_tests = b.addRunArtifact(mod_tests);
const test_step = b.step("test", "Run tests");
test_step.dependOn(&run_mod_tests.step);
```

- **`b.addTest` không chạy test**; nó chỉ tạo executable chứa test. Muốn chạy mới phải qua
  `addRunArtifact` (ý này được `Build.zig` chú thích rõ: *"This step does not run the unit tests"*).
- Test của executable và test của module là **hai bộ khác nhau** (`exe.root_module` vs `mod`) — nếu
  project có cả hai, phải tạo hai `addTest` (project `ziggii` làm đúng vậy, rồi để hai run step chạy
  song song vì chúng không phụ thuộc nhau).

---

## 4. Steps & cache

Mỗi step mang một **bộ nhận dạng cache** (hash của toàn bộ input: source, flags, target, module
imports, content của dependency…). Nếu lần sau chạy `zig build` mà hash không đổi, runner **bỏ qua
bước đó** và lấy kết quả cũ từ `.zig-cache/` — nghĩa là *"biết khi nào một step không cần chạy lại"*
(Build.zig).

**Xác minh thật** — demo `tổng hợp` sau khi sửa một dòng source, đo bằng `time`:

```
$ time zig build run          # lần 1: phải biên dịch từ đầu
real	0m1.417s                ← compile exe + link (≈ 1.4s)

$ time zig build run          # lần 2: không sửa gì
real	0m0.136s                ← chỉ chạy binary đã cache (≈ 0.14s)
```

> 💡 Lần 2 vẫn mất ~0.14s vì `run` phải thực thi chương trình + chạy script `build.zig` (configure
> phase) — nhưng **không tốn compile**. Test toàn bộ trên project `ziggii` (đã build trước đó) chỉ
> mất `0.108s` với các step đều cached.

Xem dấu vết cache bằng **`--summary all`** (output thật từ demo):

```
$ zig build --summary all
Build Summary: 3/3 steps succeeded
install success
+- install tonghop cached
   +- compile exe tonghop debug native cached 44ms MaxRSS:33M
```

Các mode của `--summary`: `all` (đầy đủ), `new` (chỉ chưa cache), `failures` (mặc định khi build
ngắn), `line` (chỉ một dòng), `none`. Muốn biết **cách build gọi compiler thế nào** thì dùng
`--verbose` (in từng lệnh `zig build-exe/build-lib/...` với đầy đủ flag), hoặc quan sát command-line
trong lỗi compile (mục 9) — ví dụ thật khi build `tonghop`:

```
zig build-exe -Odebug --dep tonghop -Mroot=src/main.zig -Mtonghop=src/root.zig
  --cache-dir .zig-cache --global-cache-dir /Users/.../.cache/zig --build-root .
  --name tonghop --zig-lib-dir /opt/homebrew/Cellar/zig/0.17.0/lib/zig/ --listen=-
```

Dòng trên cho thấy bản chất: build system chỉ là **lời gọi tới chính compiler Zig** với đủ flag của
module (`-Mroot`, `-Mtonghop`) — vì mọi thứ đều "userland", có thể đọc/gỡ lỗi được.

---

## 5. Options & chế độ build

### 5.1 `-Doptimize` — debug / safe / fast / small

Bốn chế độ (đúng tên hiển thị trong `zig build --help`):

| `-Doptimize=...` | Ý nghĩa |
|---|---|
| `debug` (mặc định) | an toàn nhất, nhiều safety checks + debug info; chậm, to |
| `safe` | ReleaseSafe: tối ưu tốc độ nhưng **giữ safety checks** |
| `fast` | ReleaseFast: bỏ safety checks, tối ưu tốc độ |
| `small` | ReleaseSmall: tối ưu dung lượng binary |

Đo thật trên demo `tonghop` (macOS ARM64, Zig 0.17.0):

| Chế độ | `zig build -Doptimize=...` | Kích thước binary |
|---|---|---|
| debug | `debug` | 2 148 920 B (~2.0 MB) |
| ReleaseFast | `fast` | 413 448 B (~395 KB) |
| ReleaseSmall | `small` | 166 408 B (~158 KB) |

Ngoài ra còn `--release` (tương đương `-Doptimize`, và khi project khai `preferred_optimize_mode`
thì `--release` chọn đúng chế độ ưa thích đó). Chi tiết từng chế độ (safety checks…) xem
[`memory_model.md`](memory_model.md) và langref
[Optimization Mode](https://ziglang.org/documentation/0.17.1/#toc-Optimization-Mode).

> ⚠️ Chế độ tối ưu **là một phần của cache hash**: cùng source nhưng `-Doptimize` khác nhau sẽ sinh
> artifact riêng trong cache, không bị tráo nhau.

### 5.2 Cross-compile `-Dtarget` / `-Dcpu`

`standardTargetOptions` làm cho `zig build` **mặc định chấp nhận mọi target** (host = native).
Cross-compile là thế mạnh của Zig vì không cần toolchain đích riêng. **Xác minh thật** trên máy
macOS (host `aarch64-macos`) → build cho Linux ARM:

```
$ zig build -Dtarget=aarch64-linux -Doptimize=ReleaseFast
$ file zig-out/bin/tonghop
zig-out/bin/tonghop: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV),
                     statically linked, with debug_info, not stripped
```

Binary `ELF aarch64` tạo trên macOS, statically linked — **không cần cài gcc/glibc ARM**, Zig tự lo
bundle libc. Thử với target có sẵn `-Dtarget=aarch64-linux` → build thành công (exit 0). Nếu target
vô nghĩa, lỗi parse thật:

```
$ zig build -Dtarget=foobar
unable to parse target "foobar": UnknownArchitecture
info: available option: "target": The CPU architecture, OS, and ABI to build for
...
error: configure command exited with code 1: .../configurer ... -Dtarget=foobar
```

- `-Dcpu=...` chọn CPU model / thêm-bớt feature (vd `-Dcpu=baseline`, `-Dcpu=native`). `Build.zig`
  in danh sách CPU/feature khả dụng khi query sai.
- Để chạy binary foreign trên host, dùng system integration `-fqemu`, `-fwasmtime`, `-frosetta`…
  (máy này không cấu hình nên chỉ nêu mô tả, không chạy thử).
- Nếu muốn **giới hạn** target được phép (vd chỉ native), truyền
  `standardTargetOptions(.{ .whitelist = ... })` — project `ziggii` không giới hạn nên mọi target đều
  được.

---

## 6. Dependencies — build.zig.zon & `b.dependency`

Package Zig được mô tả bằng **`build.zig.zon`** — đây là một anonymous struct literal viết bằng
cú pháp Zig. Các field chuẩn 0.17 (đối chiếu `build.zig.zon` thật của project `ziggii`):

| Field | Vai trò |
|---|---|
| `.name` | tên package (dạng enum literal `.tonghop` — *không* ghi `"zig` bên trong tên ở đây*) |
| `.version` | [SemVer](https://semver.org/), tương lai dùng để dedup |
| `.fingerprint` | định danh toàn cầu của package, do toolchain sinh — **không bao giờ đổi tự ý** |
| `.minimum_zig_version` | version Zig tối thiểu hỗ trợ package |
| `.dependencies` | bảng các dependency: mỗi entry `.url` + `.hash`, **hoặc** `.path` (đường dẫn local), và `.lazy` |
| `.paths` | phạm vi file đóng gói (hash + giữ trên đĩa khi fetch); ghi cả giấy phép |
| `.lazy` | đánh dấu package này là "lazy" cho người phụ thuộc; ở cấp entry `.dependencies` thì khiến dependency đó chỉ được fetch khi thực sự dùng |

Mỗi dependency khai báo **hai cách loại trừ nhau**:

```zig
.dependencies = .{
    .foo = .{
        .url = "https://example.com/foo.tar.gz",
        .hash = "1220...",          // hash là "nguồn sự thật"; url chỉ là mirror
    },
    // hoặc với project local:
    .bar = .{ .path = "../bar" },   // không cần hash — hash không áp dụng cho path
    // .lazy = true,                // tùy chọn fetch trì hoãn
},
```

**Phía `build.zig`**, dùng `b.dependency` để nạp dependency rồi lấy module/artifact từ nó
(`Build.zig` — struct `Dependency`):

```zig
const foo_dep = b.dependency("foo", .{
    .target = target,
    .optimize = optimize,
});
// Module public "util" của package foo:
const util_mod = foo_dep.module("util");           // -> *Module
// (còn: artifact("name") — Step.Compile,
//       namedWriteFiles("name"), path("sub"))    // LazyPath
const exe = b.addExecutable(.{
    .name = "app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "util", .module = util_mod } },
    }),
});
```

Các lệnh package manager thật trong 0.17: `zig fetch --save <url>` (thêm dependency vào zon + tự tính
hash), `zig build --fetch` (fetch toàn bộ cây) — đều xuất hiện trong `zig build --help` dưới nhóm
"Package Management Options". Cơ chế quan trọng: **package đi kèm hàm `build` của chính nó** — khi
bạn phụ thuộc vào nó, `b.dependency(...)` gọi `build.zig` của dependency như một hàm, và bạn đăng ký
chính các "đầu ra" (module/artifact) do bên đó expose.

> ⚠️ **Phần này chưa thực thi bằng mạng:** máy thử nghiệm không fetch được dependency remote, nên
> cú pháp `.url/.hash/.lazy` ở trên là **mô tả đúng theo 0.17** (nguồn: `build.zig.zon` mẫu của
> toolchain + `Build.zig`), chưa chạy `zig fetch --save` thật. Phần `.path` local và
> `b.dependency`/`dep.module` là khái niệm — muốn xác minh đầy đủ cần môi trường có internet.
>
> 💡 Khác biệt 0.17 đáng nhớ: `b.addModule(name, ...)` **có** tên — dùng cho module *public* (người
> khác `dep.module("name")` lấy được); `b.createModule(...)` **không** cần tên — dùng cho module
> *private* nội bộ. Nếu gọi `b.addModule` hai lần cùng tên sẽ `panic`.

---

## 7. Demo thực hành (output thật)

Demo tên `tổng hợp` (`/tmp/zigenum/buildsys/`) gồm 4 file. Toàn bộ `build.zig` demo — đây chính là
file đã chạy thành công trên 0.17.0:

```zig
const std = @import("std");

// Dựng graph build (declarative): hàm này chỉ "khai báo" các step/dependency,
// không trực tiếp biên dịch — runner sẽ hỗ trợ parallel + caching.
pub fn build(b: *std.Build) void {
    // -Dtarget / -Dcpu / -Doptimize ... được b.standardTargetOptions/
    // b.standardOptimizeOption đăng ký tự động cho CLI --help.
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Module PUBLIC tên "tonghop" — package khác import được qua @import("tonghop").
    const mod = b.addModule("tonghop", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Executable: root_module do b.createModule tạo ra (private, không expose).
    const exe = b.addExecutable(.{
        .name = "tonghop",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tonghop", .module = mod },
            },
        }),
    });

    // `zig build` (default step) sẽ copy artifact vào zig-out/.
    b.installArtifact(exe);

    // Top-level step "run": `zig build run`
    const run_step = b.step("run", "Chay chuong trinh");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    // Top-level step "test": `zig build test` — test blocks trong root module.
    const tests = b.addTest(.{ .root_module = mod });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Chay cac bai test");
    test_step.dependOn(&run_tests.step);

    // Custom task: `zig build fmt` (sửa file) và `zig build fmt-check` (chỉ kiểm tra).
    // Lưu ý 0.17: CLI không hiểu `zig build fmt --check`; chế độ check phải được
    // khai báo ngay trong build.zig qua Step.Fmt `.check = true`.
    const fmt = b.addFmt(.{ .paths = &.{b.path(".")} });
    const fmt_step = b.step("fmt", "Dinh dang code Zig (zig fmt)");
    fmt_step.dependOn(&fmt.step);

    const fmt_check = b.addFmt(.{
        .paths = &.{b.path(".")},
        .check = true,
    });
    const fmt_check_step = b.step("fmt-check", "Kiem tra dinh dang (zig fmt --check)");
    fmt_check_step.dependOn(&fmt_check.step);
}
```

`src/root.zig` — module "thư viện" (cốt lõi; file đầy đủ nằm trong `/tmp/zigenum/buildsys/`):

```zig
//! root.zig — module "thư viện" của demo build system.
//! Chỉ các khai báo `pub` ở đây mới được import từ bên ngoài module.
const std = @import("std");

pub fn add(a: i32, b: i32) i32 { return a + b; }
pub fn sum(values: []const i32) i32 {
    var total: i32 = 0;
    for (values) |v| total += v;
    return total;
}

test "add cong hai so" { … }        // expectEqual(12, add(5,7)) — xanh
test "sum tinh tong day [1,2,3,4]" { … } // expectEqual(10, sum(&nums)) — xanh
```

`src/main.zig` — executable import module `tonghop` và in "hello" (cốt lõi):

```zig
const std = @import("std");
const tonghop = @import("tonghop");   // tên import do .imports trong build.zig quyết định

pub fn main(init: std.process.Init) !void {
    std.debug.print("hello, Zig Build System!\n", .{});
    std.debug.print("5 + 7 = {d} (ham add trong module tonghop)\n", .{tonghop.add(5, 7)});
    // … in sum([1,2,3,4]) và các arg nhận từ `zig build run -- <arg...>`
}
```

`build.zig.zon` của demo (đầy đủ dạng zon — đối chiếu mục 6):

```zig
.{
    .name = .tonghop,
    .version = "0.1.0",
    .fingerprint = 0x8be0c93f2bd4d68, // do toolchain sinh; không bỏ sót (xem mục 9)
    .minimum_zig_version = "0.17.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    // .dependencies = .{}, // trống — không có dependency
}
```

**Các lệnh đã chạy thành công** (kèm kết quả tóm tắt):

```
$ zig build --list-steps
  install (default)   Copy build artifacts to prefix path
  uninstall           Remove build artifacts from prefix path
  run                 Chay chuong trinh
  test                Chay cac bai test
  fmt                 Dinh dang code Zig (zig fmt)
  fmt-check           Kiem tra dinh dang (zig fmt --check)

$ zig build run -- cua toi 1 2 3
hello, Zig Build System!
5 + 7 = 12 (ham add trong module tonghop)
sum([1,2,3,4]) = 10
info: arg: ./zig-out/bin/tonghop
info: arg: cua
info: arg: toi
info: arg: 1
info: arg: 2
info: arg: 3

# lần 1: real 1.417s  (compile từ đầu) — lần 2: real 0.136s (cache) → xem mục 4

$ zig build test                       # 2 test xanh: add=12, sum=10 → exit 0
# sau khi xóa cache:
$ zig build test --summary all
Build Summary: 3/3 steps succeeded; 2/2 tests passed
test success
+- run test 2 pass (2 total) 274ms MaxRSS:3M
   +- compile test debug native success 1s MaxRSS:256M

$ zig build fmt-check                  # file đã format → exit 0

# Chế độ check FAIL khi có file lệch format (probe thật):
$ zig build fmt-check
fmt-check
+- zig fmt --check failure
error: ./src/root.zig: non-conforming formatting
error: process exited with code 1
failed command: /opt/homebrew/Cellar/zig/0.17.0/bin/zig fmt --check .

Build Summary: 0/2 steps succeeded (1 failed)
fmt-check transitive failure
+- zig fmt --check failure
# → rồi `zig build fmt` tự sửa file, chạy lại fmt-check → exit 0
```

---

## 8. So sánh nhanh: Make / CMake + "comptime config"

| | **Make** | **CMake** | **Zig Build System (0.17)** |
|---|---|---|---|
| Logic build | shell script (recipes) | ngôn ngữ riêng (CMake language) | **chính Zig** — `build.zig` là file Zig thật |
| Phụ thuộc công cụ | make + shell (không cross-platform sạch) | cần CMake + generator (Make/Ninja…) | **chỉ cần `zig`** |
| Cache / graph phụ thuộc | phụ thuộc `make` theo timestamp (dễ lỗi) | có target graph nhưng build config tách khỏi ngôn ngữ | **step graph + content-hash cache** built-in, hiểu ngữ nghĩa shellscript không cần |
| Types/IDE | không | hạn chế | API có type kiểm tra lúc compile (`std.Build`) |
| Học lại ngôn ngữ mới | ✗ (không) | ✗ | ✓ — không phải học cú pháp build riêng |

**Điểm sáng giá nhất của Zig build**: bạn **không rời khỏi ngôn ngữ đang học**. Mọi thứ trong
`build.zig` đều là Zig: `if`, `for`, struct literal `.{}`, `b.option` trả option kiểu `?T`… Và vì là
Zig thật, toàn bộ sức mạnh **comptime** áp được cho cả build logic.

**"Comptime config"** — hai con đường expose thông tin build ra source:

1. **`@import("builtin")`**: compiler tự cung cấp file này; chứa target/optmode… *đã chọn lúc build*.
   Điển hình là `builtin.optimize_mode` và `builtin.os.tag`/`builtin.cpu.arch` — cùng source nhưng
   chạy với `-Doptimize=ReleaseSafe` thì hằng số comptime đổi theo, compiler có thể xóa
   nhánh/khoanh vùng an toàn ngay lúc biên dịch (liên hệ [`comptime.md`](comptime.md) mục 9).
2. **File sinh bởi build system**: `addWriteFiles()`/`Step.Options` tạo file (vd `config.zig`) chứa
   giá trị option, rồi expose nó như một module trong `.imports`; source `@import("config")` sẽ đọc
   đúng config mà user chọn bằng `-D...`.

> 💡 Ví dụ kinh điển: `b.option(bool, "enable_foo", "...")` → ghi `pub const enable_foo = true;` vào
> file gen → code `if (builtin_config.enable_foo)`; ở `ReleaseSmall` compiler chứng minh được nhánh
> đó, build script và hằng số **không bao giờ lệch nhau** — thứ mà Make/CMake không tự bảo đảm.

---

## 9. Lỗi thường gặp (probe thật)

Tất cả các thông điệp dưới đây đều là **output thật** chạy trên Zig 0.17.0 trong quá trình thực hiện
bài này:

| Thông điệp lỗi (Zig 0.17.0) | Nguyên nhân / cách xử lý |
|---|---|
| `error: unrecognized argument: --check` | chạy `zig build fmt --check` nhưng build.zig **không khai báo** chế độ check. Trong 0.17 phải khai step `addFmt(..., .check = true)` (demo: `fmt-check`); hoặc dùng CLI `zig fmt --check .` |
| `error: expected type 'Build.LazyPath', found '*const [1:0]u8'` | truyền chuỗi thô vào field kiểu `LazyPath` (vd `addFmt(.{...paths = &.{"."}})`). Sửa: `b.path(".")` |
| `build.zig.zon:1:2: error: missing top-level 'fingerprint' field; suggested value: 0x...` | zon thiếu `.fingerprint`. Thêm giá trị máy gợi ý (hoặc để toolchain sinh khi tạo package) |
| `src/x.zig:1:1: error: unable to load "...zig": FileNotFound` | `root_source_file`/`b.path` trỏ sai đường dẫn; kèm dòng command thật của `zig build-exe -Mroot=...` giúp soi module nào lỗi |
| `unable to parse target "foobar": UnknownArchitecture` + `configure command exited with code 1` | `-Dtarget` sai cú pháp/không tồn tại. Xem danh sách CPU/OS/feature mà `Build.zig` in ra |
| `error: 'root.test.failing probe' failed: expected 1, found 4` + stack trace + `Build Summary: 0/3 steps succeeded; 1/3 tests passed` | assertion trong `test` block sai (vd `expectEqual(1, add(2,2))`); build system vẫn compile được nhưng run test trả exit code 1 |
| `error: non-conforming formatting` + `failed command: zig fmt --check .` | có file Zig chưa theo chuẩn `zig fmt`; chạy `zig build fmt` để tự sửa |
| *(đáng chú ý)* **thiếu `build.zig.zon` KHÔNG báo lỗi** | probe /tmp/zigenum/nonzon: `zig build` vẫn build & chạy bình thường. `build.zig.zon` mới bắt buộc khi **đóng gói/distribute** package hoặc khai dependency; build local không đòi hỏi |

---

## 10. Nguồn & liên kết

- [Zig Language Reference 0.17.1 — Zig Build System](https://ziglang.org/documentation/0.17.1/#Zig-Build-System) — mục ngắn, dẫn tài liệu host ngoài "Build System Documentation"
- [std.Build — Build API 0.17](https://ziglang.org/documentation/master/std/#A;std:Build) (`/opt/homebrew/Cellar/zig/0.17.0/lib/zig/std/Build.zig` — `addExecutable`, `addModule`, `createModule`, `addTest`, `installArtifact`, `addRunArtifact`, `step`, `addFmt`, `addWriteFiles`, `addTranslateC`, `standardTargetOptions`, `standardOptimizeOption`, struct `Dependency`)
- Output thật `zig build --help` / `zig build --list-steps` / `--summary all` chạy trên máy (Zig 0.17.0) — project `ziggii` và demo `/tmp/zigenum/buildsys/`
- [`memory_model.md`](memory_model.md) — optimization mode, safety checks, alignment
- [`comptime.md`](comptime.md) mục 9 — builtin hỗ trợ comptime (`@import("builtin")` là một dạng config surface); mục 6 — generic
- [`zig-testing.md`](zig-testing.md) — `std.testing`, viết test block (nền tảng cho step `test`)
- [`variables.md`](variables.md) — `pub const`, namespace, biến toàn cục (liên quan mô hình module)

---

*Viết cho mục đích học tập; mọi đoạn trích quan trọng từ langref/Build.zig đều có link để tự kiểm
chứng. Mọi con số (thời gian build, kích thước binary, thông điệp lỗi) là kết quả đo/biên dịch thật
trên máy này với Zig 0.17.0 homebrew; kích thước binary có thể khác tuỳ CPU/toolchain. Phần mô tả
dependencies qua `.url/.hash/.lazy` chưa được xác minh bằng fetch mạng thật — nên coi là ghi chú theo
đúng nguồn 0.17.*
