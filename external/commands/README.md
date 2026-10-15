# External CP/M commands

Place locally owned CP/M-80 command binaries in this directory before building
the 2D disk image.

Only files whose extension is `.COM` (case-insensitive) are copied into the
image.  Filenames must be valid CP/M 8.3 names.  Files are installed as user 0
files.

Example:

```sh
cp /path/to/PIP.COM external/commands/
cp /path/to/STAT.COM external/commands/
make image
```

The command binaries themselves are ignored by Git; only this README is
tracked.
