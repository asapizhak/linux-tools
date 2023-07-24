[Taken from here](https://superuser.com/a/919026)

`unsquashfs -s`` did not have the capability of displaying the compression type used until this commit on 07 August 2009. This means that if you are running squashfs-tools 4.0 or older, you wouldn't be able to see the compression method used.

From this information, I derived a way to read the SquashFS 4.0 superblock to determine the compression method used (where $SQUASHFS is the path to your SquashFS file):

```bash
dd if=$SQUASHFS bs=1 count=2 skip=20 2>/dev/zero | od -An -tdI | xargs
```

Alternatively, here's a function for those who would like to type in the filename at the end of the line:

```bash
sqsh_comp_method(){ dd if="$1" bs=1 count=2 skip=20 2>/dev/zero|od -An -tdI | xargs;};sqsh_comp_method
```

You will get a number (between 1 and 6 as of SquashFS 4.4). You can match that number to the following table to see what compression method was used:



| # | Compression Method | Compatible Version |
|---|---|---|
| 1 | gzip               | 1.0 and newer      |
| 2 | lzma               | 4.1 and newer      |
| 3 | lzo                | 4.1 and newer      |
| 4 | xz                 | 4.2 and newer      |
| 5 | lz4                | 4.3 and newer      |
| 6 | zstd               | 4.4 and newer      |

[source](https://sourceforge.net/p/squashfs/code/ci/e38956b92f738518c29734399629e7cdb33072d3/tree/squashfs-tools/squashfs_fs.h#l275)

**Note**: looks like LZMA is deprecated, with no kernel support (proof?)

Note that the above dd command will only provide a reliable output if the file you specified had a SquashFS 4.0 superblock. The following command will output "Not SquashFS 4.0" if the file $SQUASHFS does not have the SquashFS 4.0 magic number:

```bash
if [[ "$(dd if="$SQUASHFS" bs=1 count=4 skip=28 2>/dev/zero | xxd -p)" != "04000000" ]] ; then echo -n "Not " ; fi ; echo "SquashFS 4.0"
```

## Explanation

In SquashFS 4.0 filesystems, the compression method is stored on the 21st and 22nd bytes of the superblock as a data type short. dd bs=1 count=2 skip=20 will retrieve the short, od -An -tdI will turn the short into a human-readable number, and xargs is just to get rid of the leading spaces.

Before SquashFS 4.0, there was only the gzip method.
