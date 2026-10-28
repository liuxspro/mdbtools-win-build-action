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

Workflow inputs (`workflow_dispatch`):

| Input          | Default  | Description                                              |
| -------------- | -------- | -------------------------------------------------------- |
| `zig-version`  | `0.17.0` | Zig release, or `master`                                 |
| `mdbtools-ref` | `v1.0.1` | mdbtools tag, branch or commit                           |
| `build-sql`    | `false`  | Also build `libmdbsql` + `mdb-sql` (installs bison/flex) |

## Test

TODO

```bash
git clone https://github.com/mdbtools/mdbtestdata.git test
```

## History

This project used to build with MSYS2 (UCRT64) and autotools; that `build.yml` still exists in
older commits. It needed toolchain-specific patches (mingw `LOCALE_T` in `configure.ac`, the
`spawnv` define, the ellipsis fix in `fakeglib.c`) and broke whenever MSYS2's GCC moved forward.
