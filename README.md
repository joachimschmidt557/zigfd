# zigfd

[![Build Status](https://travis-ci.org/joachimschmidt557/zigfd.svg?branch=master)](https://travis-ci.org/joachimschmidt557/zigfd)

Recursively find files and directories with a regex pattern. Inspired
by [fd](https://github.com/sharkdp/fd).

# ToDo

- [ ] Ability to ignore files (needed in `zig-walkdir`)
- [ ] Execution of commands to run on search results
- [ ] Case (in)sensitive searches

# Dependencies

Until `zig` has a package manager, I will use
[src](https://github.com/joachimschmidt557/src), a little POSIX shell
script which manages source dependencies.

- [zig-walkdir](https://github.com/joachimschmidt557/zig-walkdir)
- [zig-regex](https://github.com/tiehuis/zig-regex)
- [zig-lscolors](https://github.com/joachimschmidt557/zig-lscolors)
- [zig-clap](https://github.com/Hejsil/zig-clap)

# Installation

```shell
$ git clone https://github.com/joachimschmidt557/zigfd
$ cd zigfd
$ ./srcmgr update
$ zig build
```
