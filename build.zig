// Alternative build script for MDB Tools using the Zig build system.
//
// This builds libmdb (and, when requested, the SQL engine) plus the command
// line utilities, without autotools. By default it uses the bundled
// "fakeglib" shim, so no GLib is required.
//
// Usage:
//   zig build                          # build everything into zig-out/
//   zig build -Doptimize=ReleaseFast
//   zig build -Dtarget=aarch64-linux-musl
//   zig build -Dtarget=x86_64-windows-gnu   # PE32+ console executables,
//                                          # with mdbtools-win32.manifest
//                                          # embedded (ACP becomes UTF-8)
//   zig build -Dglib=true              # use system GLib via pkg-config
//   zig build -Dsql=true               # also build libmdbsql + mdb-sql
//                                      # (mdb-sql falls back to its own
//                                      #  readline stub when not linked)
//
// On Termux the native target resolves to aarch64-linux-android, and Zig does
// not ship bionic headers/libs, so this script automatically falls back to a
// static musl build in that case.
//
// NOTE: The Zig 0.17.0 package in Termux currently crashes with SIGILL for the
// `zig build` subcommand itself (even `zig build --help` in an empty directory),
// so build-zig.sh uses `zig cc` directly instead.

const std = @import("std");

const version = "1.0.1";

// Windows converts the UTF-16 command line to the narrow argv handed to main()
// using the process ANSI code page, so a name like "Umsätze" would be mangled on
// e.g. CP936 systems. Embedding a manifest that declares activeCodePage = UTF-8
// turns the ACP into 65001 before the CRT runs, so argv arrives as UTF-8 bytes
// (which is what mdbtools expects). Requires Windows 10 1903 or newer.
const windows_manifest = "mdbtools-win32.manifest";

const libmdb_sources = [_][]const u8{
    "src/libmdb/backend.c",
    "src/libmdb/catalog.c",
    "src/libmdb/data.c",
    "src/libmdb/dump.c",
    "src/libmdb/file.c",
    "src/libmdb/iconv.c",
    "src/libmdb/index.c",
    "src/libmdb/like.c",
    "src/libmdb/map.c",
    "src/libmdb/money.c",
    "src/libmdb/options.c",
    "src/libmdb/props.c",
    "src/libmdb/rc4.c",
    "src/libmdb/sargs.c",
    "src/libmdb/stats.c",
    "src/libmdb/table.c",
    "src/libmdb/version.c",
    "src/libmdb/worktable.c",
    "src/libmdb/write.c",
};

const util_sources = [_][]const u8{
    "src/util/mdb-array.c",
    "src/util/mdb-count.c",
    "src/util/mdb-export.c",
    "src/util/mdb-header.c",
    "src/util/mdb-import.c",
    "src/util/mdb-json.c",
    "src/util/mdb-parsecsv.c",
    "src/util/mdb-prop.c",
    "src/util/mdb-queries.c",
    "src/util/mdb-schema.c",
    "src/util/mdb-tables.c",
    "src/util/mdb-ver.c",
};

const common_cflags = [_][]const u8{
    "-D_GNU_SOURCE",
    "-std=gnu11",
    // The bundled debug tools are not built by default, but keep clang's
    // newer defaults from turning old-style C into hard errors.
    "-Wno-error=incompatible-pointer-types",
    "-Wno-error=implicit-int",
    "-Wno-error=implicit-function-declaration",
};

const unix_feature_cflags = [_][]const u8{
    "-DHAVE_ICONV=1",
    "-DHAVE_FMEMOPEN=1",
    "-DHAVE_GMTIME_R=1",
    "-DHAVE_STRPTIME=1",
    "-DHAVE_VASPRINTF=1",
    "-DHAVE_ATTRIBUTE_ALIAS=1",
    "-DTLS=__thread",
    "-DICONV_CONST=",
};

const windows_feature_cflags = [_][]const u8{
    // mingw-w64 has no iconv/fmemopen/strptime; mdbtools has fallbacks for all
    // three (Windows locale conversion, error for mdb_open_buffer, etc.).
    "-DHAVE_GMTIME_R=1",
    "-DHAVE_VASPRINTF=1",
    "-DHAVE_ATTRIBUTE_ALIAS=1",
    "-DTLS=__thread",
    "-DICONV_CONST=",
};

const unix_cflags = common_cflags ++ unix_feature_cflags;
const windows_cflags = common_cflags ++ windows_feature_cflags;

pub fn build(b: *std.Build) void {
    var target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (target.result.abi == .android) {
        target = b.resolveTargetQuery(.{
            .cpu_arch = target.result.cpu.arch,
            .os_tag = .linux,
            .abi = .musl,
        });
        std.debug.print("note: native target is Android/bionic; building static musl binaries instead\n", .{});
    }

    const is_windows = target.result.os.tag == .windows;

    const use_glib = b.option(bool, "glib", "Use system GLib (via pkg-config) instead of the bundled fakeglib") orelse false;
    const want_sql = b.option(bool, "sql", "Build the SQL engine (requires pre-generated src/sql/parser.c and src/sql/lexer.c)") orelse false;

    if (want_sql) {
        const have_parser = fileExists(b, "src/sql/parser.c");
        const have_lexer = fileExists(b, "src/sql/lexer.c");
        if (!have_parser or !have_lexer) {
            b.default_step.dependOn(&b.addFail(
                "SQL engine requested with -Dsql=true, but src/sql/parser.c and " ++
                    "src/sql/lexer.c do not exist. Generate them first (bison/flex), " ++
                    "or run ./configure && make in src/sql.",
            ).step);
            return;
        }
    }

    // ---------------------------------------------------------------- headers
    //
    // include/mdbtools.h and include/mdbver.h are generated by configure in
    // the autotools build. Generate equivalent headers here.
    const gen = b.addWriteFiles();
    const mdbtools_h = gen.add("mdbtools.h", renderTemplate(b, "include/mdbtools.h.in", &.{
        .{ .from = "@HAVE_ICONV_H@", .to = if (is_windows) "0" else "1" },
        .{ .from = "@HAVE_XLOCALE_H@", .to = "0" },
        .{ .from = "@GLIB_INCLUDE_HEADER@", .to = if (use_glib) "glib.h" else "mdbfakeglib.h" },
        .{ .from = "@LOCALE_T@", .to = if (is_windows) "_locale_t" else "locale_t" },
    }));
    _ = gen.add("mdbver.h", renderTemplate(b, "include/mdbver.h.in", &.{
        .{ .from = "@PACKAGE@", .to = "mdbtools" },
        .{ .from = "@VERSION@", .to = version },
    }));

    const cflags: []const []const u8 = if (is_windows) &windows_cflags else &unix_cflags;

    // ----------------------------------------------------------------- libmdb
    const libmdb_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    libmdb_mod.addIncludePath(b.path("include"));
    libmdb_mod.addIncludePath(gen.getDirectory());
    libmdb_mod.addCSourceFiles(.{
        .files = &libmdb_sources,
        .flags = cflags,
    });
    if (!use_glib) {
        libmdb_mod.addCSourceFiles(.{
            .files = &.{"src/libmdb/fakeglib.c"},
            .flags = cflags,
        });
    } else {
        addPkgConfig(b, libmdb_mod, "glib-2.0");
    }

    const libmdb = b.addLibrary(.{
        .name = "mdb",
        .linkage = .static,
        .root_module = libmdb_mod,
    });
    b.installArtifact(libmdb);
    b.getInstallStep().dependOn(&b.addInstallHeaderFile(mdbtools_h, "mdbtools.h").step);
    if (!use_glib) {
        b.getInstallStep().dependOn(&b.addInstallHeaderFile(b.path("include/mdbfakeglib.h"), "mdbfakeglib.h").step);
    }

    const want_sql_lib = want_sql;

    var libmdbsql: ?*std.Build.Step.Compile = null;
    if (want_sql_lib) {
        const sql_mod = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        sql_mod.addIncludePath(b.path("include"));
        sql_mod.addIncludePath(gen.getDirectory());
        sql_mod.addCSourceFiles(.{
            .files = &.{ "src/sql/mdbsql.c", "src/sql/parser.c", "src/sql/lexer.c" },
            .flags = cflags,
        });
        sql_mod.linkLibrary(libmdb);
        if (use_glib) addPkgConfig(b, sql_mod, "glib-2.0");

        const lib = b.addLibrary(.{
            .name = "mdbsql",
            .linkage = .static,
            .root_module = sql_mod,
        });
        b.installArtifact(lib);
        b.getInstallStep().dependOn(&b.addInstallHeaderFile(b.path("include/mdbsql.h"), "mdbsql.h").step);
        libmdbsql = lib;
    }

    // ------------------------------------------------------------------ utils
    for (util_sources) |source| {
        const name = std.fs.path.stem(source);
        const exe = makeUtil(b, target, optimize, cflags, gen, libmdb, name, &.{source});
        b.installArtifact(exe);
    }

    if (libmdbsql) |sqllib| {
        const exe = makeUtil(b, target, optimize, cflags, gen, libmdb, "mdb-sql", &.{"src/util/mdb-sql.c"});
        exe.root_module.linkLibrary(sqllib);
        b.installArtifact(exe);
    }
}

fn makeUtil(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    cflags: []const []const u8,
    gen: *std.Build.Step.WriteFile,
    libmdb: *std.Build.Step.Compile,
    name: []const u8,
    sources: []const []const u8,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addIncludePath(b.path("include"));
    mod.addIncludePath(gen.getDirectory());
    mod.addCSourceFiles(.{
        .files = sources,
        .flags = cflags,
    });
    mod.linkLibrary(libmdb);
    return b.addExecutable(.{
        .name = name,
        .root_module = mod,
        .win32_manifest = if (target.result.os.tag == .windows) b.path(windows_manifest) else null,
    });
}

const Replacement = struct { from: []const u8, to: []const u8 };

fn renderTemplate(
    b: *std.Build,
    path: []const u8,
    replacements: []const Replacement,
) []u8 {
    const allocator = b.allocator;
    const io = b.graph.io;
    var contents = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1 << 20)) catch |err| {
        std.debug.panic("unable to read {s}: {s}", .{ path, @errorName(err) });
    };
    for (replacements) |replacement| {
        contents = std.mem.replaceOwned(u8, allocator, contents, replacement.from, replacement.to) catch |err| {
            std.debug.panic("out of memory while rendering {s}: {s}", .{ path, @errorName(err) });
        };
    }
    return contents;
}

fn fileExists(b: *std.Build, path: []const u8) bool {
    std.Io.Dir.cwd().access(b.graph.io, path, .{}) catch return false;
    return true;
}

/// Translate `pkg-config --cflags/--libs` output into module settings.
fn addPkgConfig(b: *std.Build, mod: *std.Build.Module, package: []const u8) void {
    const cflags = b.run(&.{ "pkg-config", "--cflags", package });
    var it = std.mem.tokenizeAny(u8, cflags, " \t\n");
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-I")) {
            mod.addIncludePath(.{ .cwd_relative = arg[2..] });
        }
    }

    const libs = b.run(&.{ "pkg-config", "--libs", package });
    it = std.mem.tokenizeAny(u8, libs, " \t\n");
    while (it.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "-L")) {
            mod.addLibraryPath(.{ .cwd_relative = arg[2..] });
        } else if (std.mem.startsWith(u8, arg, "-l")) {
            mod.linkSystemLibrary(arg[2..], .{});
        } else if (std.mem.eql(u8, arg, "-pthread")) {
            mod.linkSystemLibrary("pthread", .{});
        }
    }
}
