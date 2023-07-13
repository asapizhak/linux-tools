
## Library files

### `lib_core.sh, lib_core_*`

- should not contain external code and command calls
- `lib_core_*` can only include (source) lib_core.sh itself
- `lib_core.sh` should not include anything

### `lib_*`

- can include (source) `lib_core*` files but not other `lib_*` stuff
- should contain minimal usage of external commands
- external commands should be as portable as possible if they are necessary
- if external commands are used, better check for their presence first and fail immediately if they are missing