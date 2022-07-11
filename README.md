# zigfd

Recursively find files and directories with a regex pattern. Inspired
by [fd](https://github.com/sharkdp/fd).

## ToDo

- [ ] Ability to ignore files (needed in `zig-walkdir`)
- [x] Execution of commands to run on search results
- [ ] Case (in)sensitive searches
- [ ] Exclude entries
- [ ] Follow symlinks
- [ ] Glob search

## Dependencies

Until `zig` has a package manager, this project will use Git
submodules to manage dependencies.

- [zig-walkdir](https://github.com/joachimschmidt557/zig-walkdir)
- [zig-regex](https://github.com/tiehuis/zig-regex)
- [zig-lscolors](https://github.com/ziglibs/lscolors)
- [zig-clap](https://github.com/Hejsil/zig-clap)

## Installation

```shell
$ git clone --recurse-submodules https://github.com/joachimschmidt557/zigfd
$ cd zigfd
$ zig build
```

## Command-line options

```
	-h, --help                     	Display this help and exit.
	-v, --version                  	Display version info and exit.
	-H, --hidden                   	Include hidden files and directories
	-p, --full-path                	Match the pattern against the full path instead of the file name
	-0, --print0                   	Separate search results with a null character
	   --show-errors              	Show errors which were encountered during searching
	-d, --max-depth <NUM>          	Set a limit for the depth
	-t, --type <type>...           	Filter by entry type
	-e, --extension <ext>...       	Additionally filter by a file extension
	-c, --color <auto|always|never>	Declare when to use colored output
	-x, --exec                     	Execute a command for each search result
	-X, --exec-batch               	Execute a command with all search results at once
```
