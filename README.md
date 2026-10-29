# mdbtools-win-build-action

MDBTools cross-compiled for Windows with [Zig](https://ziglang.org/) and GitHub Action

Read the [mdbtools](https://github.com/mdbtools/mdbtools) guide about [build from source](https://github.com/mdbtools/mdbtools/blob/dev/README.md#from-source)

And windows build guide: [lsgunth/mdbtools-win](https://github.com/lsgunth/mdbtools-win)

## Build Info

> tweak: Replace `…`(U+2026) [Horizontal Ellipsis](https://unicode-table.com/cn/2026/)

| Name          | Description                           | Build Artifacts                                                                                                                                                                                        |
| ------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| build-zig.yml | Windows x86_64 cross-compile with Zig | [![Build Zig](https://github.com/liuxspro/mdbtools-win-build-action/actions/workflows/build-zig.yml/badge.svg)](https://github.com/liuxspro/mdbtools-win-build-action/actions/workflows/build-zig.yml) |

The workflow runs on Linux and builds mdbtools with the [`build.zig`](build.zig) in this repo:

```bash
zig build -Doptimize=ReleaseFast -Dtarget=x86_64-windows-gnu --prefix zig-out-windows
```

No MSYS2, autotools or GCC toolchain is needed: `build.zig` compiles libmdb with the bundled
fakeglib shim and generates the headers that `configure` would normally emit. libmdb is linked
statically, so the artifact (`mdbtools-build-win-x86_64`) contains only the `.exe` files and
`COPYING`, with no extra DLLs to ship.

Each `.exe` has [`mdbtools-win32.manifest`](mdbtools-win32.manifest) embedded, which declares
`activeCodePage = UTF-8`. Without it the CRT converts the UTF-16 command line to the ANSI code
page (e.g. CP936), so non-ASCII table/column names reach `main()` mangled; with it the process
ACP is 65001 and `argv` is UTF-8, matching what mdbtools expects. Requires Windows 10 1903+.

Workflow inputs (`workflow_dispatch`):

| Input          | Default  | Description                                              |
| -------------- | -------- | -------------------------------------------------------- |
| `zig-version`  | `0.17.0` | Zig release, or `master`                                 |
| `mdbtools-ref` | `v1.0.1` | mdbtools tag, branch or commit                           |
| `build-sql`    | `false`  | Also build `libmdbsql` + `mdb-sql` (installs bison/flex) |

## Test

The workflow has a second job, `test-mdbtools-win-zig`, that runs upstream's
[`test_script.sh`](test_script.sh) against the freshly built binaries on `windows-latest`.
It drives the utilities over the [mdbtestdata](https://github.com/mdbtools/mdbtestdata)
databases, including the non-ASCII `Umsätze` table — which only round-trips because of the
embedded UTF-8 manifest.

The job only needs the layout the script expects — `.exe` files in `src/util/` and the
databases in `test/data/` — so no mdbtools sources are cloned. To reproduce locally on
Windows (Git Bash):

```bash
mkdir -p src/util
git clone --depth 1 https://github.com/mdbtools/mdbtestdata.git test
cp path/to/zig-out-windows/bin/*.exe src/util/
cp path/to/test_script.sh .
bash test_script.sh -g
```

## History

This project used to build with MSYS2 (UCRT64) and autotools; that `build.yml` still exists in
older commits. It needed toolchain-specific patches (mingw `LOCALE_T` in `configure.ac`, the
`spawnv` define, the ellipsis fix in `fakeglib.c`) and broke whenever MSYS2's GCC moved forward.
