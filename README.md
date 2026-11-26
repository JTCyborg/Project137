# Project137
АТМ турбо 2+ 1024 project


## External VGA adapter mode test

`vga_test.asm` is based on the Project132 test at commit
`c198e938490990f9704649284b7fea20bb08cc20`.

The test performs the ATM shadow-port unlock, enables the VGA software
aperture, checks the initial framebuffer readback, then sweeps all 13 packed
pixel modes supported by the 1 MiB adapter VRAM. It writes all 64 VRAM banks
for every mode and reports each mode and its theoretical pixel-value capacity
to debug port `#EF` (captured by `spectrum_out.txt`).

| Resolution | BPP | Maximum pixel values |
|---|---:|---:|
| 320x200 | 8 | 256 |
| 320x200 | 15 | 32,768 |
| 320x200 | 16 | 65,536 |
| 320x200 | 24 | 16,777,216 |
| 320x200 | 32 | 4,294,967,296 |
| 640x480 | 8 | 256 |
| 640x480 | 15 | 32,768 |
| 640x480 | 16 | 65,536 |
| 640x480 | 24 | 16,777,216 |
| 800x600 | 8 | 256 |
| 800x600 | 15 | 32,768 |
| 800x600 | 16 | 65,536 |
| 1024x768 | 8 | 256 |

Counts are the raw number of distinct packed pixel codes (2^BPP). For 32-BPP,
4,294,967,296 is the full 32-bit code space; if the adapter interprets the
format as XRGB with an unused top byte, the number of distinct RGB colours is
16,777,216 instead.

The source builds `vga_test.TRD` with `VGATEST.C` and `boot.B` using the
same SjASMPlus `SAVETRD` directives as the Project132 test.
