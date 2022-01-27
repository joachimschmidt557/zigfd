# zigfd

Recursively find files and directories with a regex pattern. Inspired
by [fd](https://github.com/sharkdp/fd).

# ToDo

- [ ] Ability to ignore files (needed in `zig-walkdir`)
- [ ] Execution of commands to run on search results
- [ ] Case (in)sensitive searches

# Dependencies

Until `zig` has a package manager, this project will use Git
submodules to manage dependencies.

- [zig-walkdir](https://github.com/joachimschmidt557/zig-walkdir)
- [zig-regex](https://github.com/tiehuis/zig-regex)
- [zig-lscolors](https://github.com/ziglibs/zig-lscolors)
- [zig-clap](https://github.com/Hejsil/zig-clap)

# Installation

```shell
$ git clone --recurse-submodules https://github.com/joachimschmidt557/zigfd
$ cd zigfd
$ zig build
```
