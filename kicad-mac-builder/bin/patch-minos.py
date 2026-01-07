#!/usr/bin/env python3
"""
Directly patches the LC_BUILD_VERSION minos field in a Mach-O binary.

This is a fallback for when vtool segfaults on certain files.  It performs a
surgical 4-byte write at the exact offset of the minos field, leaving
everything else (including the SDK version) untouched.

Usage: patch-minos.py <major>.<minor> <binary>
  e.g. patch-minos.py 12.0 /path/to/libfoo.dylib
"""

import struct
import sys
import os

MH_MAGIC_64 = 0xFEEDFACF
LC_BUILD_VERSION = 0x32
PLATFORM_MACOS = 1


def encode_version(version_str):
    parts = version_str.split(".")
    major = int(parts[0])
    minor = int(parts[1]) if len(parts) > 1 else 0
    patch = int(parts[2]) if len(parts) > 2 else 0
    return (major << 16) | (minor << 8) | patch


def patch_minos(filepath, target_version_str):
    target_packed = encode_version(target_version_str)

    with open(filepath, "r+b") as f:
        magic = struct.unpack("<I", f.read(4))[0]
        if magic != MH_MAGIC_64:
            print(f"  skip (not MH_MAGIC_64): {filepath}", file=sys.stderr)
            return False

        # mach_header_64: magic(4) cputype(4) cpusubtype(4) filetype(4)
        #                 ncmds(4) sizeofcmds(4) flags(4) reserved(4) = 32 bytes
        f.seek(16)
        ncmds = struct.unpack("<I", f.read(4))[0]

        offset = 32  # start of load commands
        for _ in range(ncmds):
            f.seek(offset)
            cmd, cmdsize = struct.unpack("<II", f.read(8))

            if cmd == LC_BUILD_VERSION:
                # build_version_command layout:
                #   cmd(4) cmdsize(4) platform(4) minos(4) sdk(4) ntools(4)
                platform = struct.unpack("<I", f.read(4))[0]
                if platform == PLATFORM_MACOS:
                    minos_offset = offset + 12  # cmd(4) + cmdsize(4) + platform(4)
                    current_minos = struct.unpack("<I", f.read(4))[0]

                    cur_major = (current_minos >> 16) & 0xFFFF
                    tgt_major = (target_packed >> 16) & 0xFFFF
                    cur_minor = (current_minos >> 8) & 0xFF
                    tgt_minor = (target_packed >> 8) & 0xFF

                    if cur_major > tgt_major or (cur_major == tgt_major and cur_minor > tgt_minor):
                        f.seek(minos_offset)
                        f.write(struct.pack("<I", target_packed))
                        return True
                    return False  # already OK

            offset += cmdsize

    return False


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <major.minor> <binary>", file=sys.stderr)
        sys.exit(1)

    target = sys.argv[1]
    binary = sys.argv[2]

    if not os.path.isfile(binary):
        print(f"Error: {binary} not found", file=sys.stderr)
        sys.exit(1)

    try:
        patched = patch_minos(binary, target)
        if patched:
            print(f"    patched (binary fallback): {os.path.basename(binary)}")
        sys.exit(0)
    except Exception as e:
        print(f"Error patching {binary}: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
