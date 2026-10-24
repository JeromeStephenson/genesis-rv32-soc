#!/usr/bin/env python3
"""
elf2hex.py - convert app.elf into imem.hex / dmem.hex for the RV32I SoC.

  imem.hex : words for region 0x00000000..  (PT_LOAD segments: .text/.rodata
             plus the .data LOAD image, i.e. what startup.S copies from)
  dmem.hex : words for region 0x80000000..  (PROGBITS sections whose VMA is
             in DMEM, i.e. .data initial values; .bss omitted = zeros)

Usage: elf2hex.py app.elf imem.hex dmem.hex IMEM_WORDS DMEM_WORDS
"""
import struct, sys

IMEM_BASE = 0x00000000
DMEM_BASE = 0x80000000
PT_LOAD, SHT_PROGBITS, SHF_ALLOC = 1, 1, 0x2

def die(msg):
    print("elf2hex: ERROR:", msg); sys.exit(1)

def main():
    if len(sys.argv) != 6:
        die("usage: elf2hex.py app.elf imem.hex dmem.hex IMEM_WORDS DMEM_WORDS")
    elf_path, imem_out, dmem_out = sys.argv[1:4]
    imem_words, dmem_words = int(sys.argv[4]), int(sys.argv[5])

    blob = open(elf_path, "rb").read()
    if blob[:4] != b"\x7fELF" or blob[4] != 1 or blob[5] != 1:
        die("not a little-endian ELF32 file")
    if struct.unpack_from("<H", blob, 18)[0] != 243:
        die("not a RISC-V ELF")

    e_phoff,  e_shoff  = struct.unpack_from("<II", blob, 28)
    e_phents, e_phnum  = struct.unpack_from("<HH", blob, 42)
    e_shents, e_shnum  = struct.unpack_from("<HH", blob, 46)

    # ---- IMEM image: from program headers (load addresses / LMA) ----
    imem_pl = []
    for i in range(e_phnum):
        t, off, vaddr, paddr, fsz, msz, fl, al = \
            struct.unpack_from("<8I", blob, e_phoff + i * e_phents)
        if t == PT_LOAD and fsz > 0 and paddr < DMEM_BASE:
            imem_pl.append((paddr, blob[off:off + fsz]))
    if not imem_pl:
        die("no loadable segment in IMEM region - check linker.ld")

    # ---- DMEM image: from section headers (runtime addresses / VMA) ----
    dmem_pl = []
    for i in range(e_shnum):
        st, sf, saddr, soff, ssize = \
            struct.unpack_from("<5I", blob, e_shoff + i * e_shents)
        if st == SHT_PROGBITS and (sf & SHF_ALLOC) and saddr >= DMEM_BASE and ssize:
            dmem_pl.append((saddr, blob[soff:soff + ssize]))

    write_hex(build(imem_pl, IMEM_BASE), imem_out, imem_words, "imem.hex")
    write_hex(build(dmem_pl, DMEM_BASE), dmem_out, dmem_words, "dmem.hex")

def build(pl, base):
    if not pl:
        return bytearray()
    img = bytearray(max(a - base + len(d) for a, d in pl))
    for a, d in pl:
        img[a - base:a - base + len(d)] = d
    return img

def write_hex(img, path, max_words, name):
    if len(img) % 4:
        img.extend(b"\x00" * (4 - len(img) % 4))
    words = len(img) // 4
    if words > max_words:
        die("%s = %d words exceeds memory depth %d words" % (name, words, max_words))
    with open(path, "w") as f:
        for i in range(0, len(img), 4):
            f.write("%08x\n" % int.from_bytes(img[i:i+4], "little"))
    print("%-9s: %5d words (%6d bytes) -> %s" % (name, words, len(img), path))

if __name__ == "__main__":
    main()
