# mdbtools-win-build-action

MDBTools built for Windows using MSYS2 and Github Action

Read the [mdbtools](https://github.com/mdbtools/mdbtools) guide about [build from source](https://github.com/mdbtools/mdbtools/blob/dev/README.md#from-source)

And windows build guide: [lsgunth/mdbtools-win](https://github.com/lsgunth/mdbtools-win)

## Build Info

> tweak: Replace `…`(U+2026) [Horizontal Ellipsis](https://unicode-table.com/cn/2026/)

| Name             | Discription  | Build Artifacts                                              |
| ---------------- | ------------ | ------------------------------------------------------------ |
| build_UCRT64.yml | UCRT64 Build | [![Build UCRT64](https://github.com/liuxsdev/mdbtools-win-build-action/actions/workflows/build_UCRT64.yml/badge.svg)](https://github.com/liuxsdev/mdbtools-win-build-action/actions/workflows/build_UCRT64.yml) |

## Test

TODO

```bash
git clone https://github.com/mdbtools/mdbtestdata.git test
```

## Other

When GCC was upgraded to version 12, build errors started appearing, so I tried downgrading from GCC 12 to 11.3.

Refer to this issue: [Cannot downgrade from GCC 12 to 11.3 #11730](https://github.com/msys2/MINGW-packages/issues/11730)

This website [https://repo.msys2.org/mingw/](https://repo.msys2.org/mingw/) contains old version packages

> 似乎不是gcc版本的问题, 现在gcc 13也能正常编译

### UCRT64 build fails

[Fix windows GH action (#399) · mdbtools/mdbtools@0b96eca (github.com)](https://github.com/mdbtools/mdbtools/commit/0b96ecaff1c543feb39b7e855fa61e6651a01203) this seems cause MSYS2 UCRT64 build fails

see
[Add option to disable spawnv define by JorisGoosen · Pull Request #301 · WizardMac/ReadStat (github.com)](https://github.com/WizardMac/ReadStat/pull/301)

### Links

[Setup MSYS2 · Actions](https://github.com/marketplace/actions/setup-msys2)
