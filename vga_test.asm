; =========================================================================
; PROJECT137 — ATM TURBO 2+ EXTERNAL VGA ADAPTER STANDARD MODE TEST
; Based on the proven ATM startup/ROM trampoline from Project112.
; Target adapter: Project131 ISA VGA/SVGA software interface.
;
; Test:
;   - unlock ATM shadow ports through TR-DOS ROM
;   - enable VGA software mode + 16 KiB aperture
;   - program 640x480 RGB565 through 3E0h/3E1h
;   - fill 614400 bytes of linear VRAM through 38 aperture banks
;   - read back bytes from bank 0 and the last framebuffer bank
;   - report results on port EF (spectrum_out.txt)
;
; Expected image: eight-colour RGB565 vertical bars.
; =========================================================================

        DEVICE ZXSPECTRUM128
        EMPTYTRD "vga_test.TRD"

        ORG     $8000

VgaTestEntry:
        DI
        LD      SP,$BFFF

        LD      HL,MsgBuild
        CALL    DebugPrint
        LD      HL,MsgStart
        CALL    DebugPrint

        CALL    OpenATMShadowPorts

        ; Select standard Spectrum screen page 5 before drawing status text.
        XOR     A
        LD      BC,$7FFD
        OUT     (C),A
        CALL    SpectrumShowStartup
        LD      HL,ScreenShadowReady
        CALL    SpectrumShowStatus

        LD      HL,MsgAdapterInit
        CALL    DebugPrint

        ; Enable the adapter before running any engine tests.
        ; 3DEh: software mode = 1, aperture enable = 1, bank 0.
        LD      BC,$03DE
        LD      A,$03
        OUT     (C),A

        ; Run 2D engine tests first, before framebuffer and palette sweeps.
        CALL    Run2DAcceleratorTest
        OR      A
        JP      NZ,AccelTestFailed

        CALL    SpectrumShowInitialMode

        ; Configure packed-pixel 640x480 RGB565:
        ; XRES = 0280h, YRES = 01E0h, BPP = 16, ENABLE = 1.
        LD      A,0
        LD      E,$80
        CALL    WriteVgaRegister
        LD      A,1
        LD      E,$02
        CALL    WriteVgaRegister
        LD      A,2
        LD      E,$E0
        CALL    WriteVgaRegister
        LD      A,3
        LD      E,$01
        CALL    WriteVgaRegister
        LD      A,4
        LD      E,16
        CALL    WriteVgaRegister
        LD      A,5
        LD      E,1
        CALL    WriteVgaRegister

        LD      HL,MsgModeSet
        CALL    DebugPrint

        CALL    Fill640x480x16

        LD      HL,MsgFrameWritten
        CALL    DebugPrint
        CALL    SpectrumShowInitialWriteComplete

        CALL    VerifyFramebuffer
        OR      A
        JR      NZ,VgaTestFailed

        LD      HL,MsgReadbackPass
        CALL    DebugPrint

        ; Palette/resolution matrix is deliberately the final test group.
        CALL    RunPackedModeSweep

        LD      HL,MsgReady
        CALL    DebugPrint

VgaTestIdle:
        HALT
        JR      VgaTestIdle

VgaTestFailed:
        LD      HL,MsgReadbackFail
        CALL    DebugPrint
VgaTestFailedIdle:
        HALT
        JR      VgaTestFailedIdle

; -------------------------------------------------------------------------
; ATM Turbo 2+ shadow-port unlock, copied from the working Project112 flow.
; TR-DOS ROM entry #3D2F calls OUT (C),A at #2A53.
; -------------------------------------------------------------------------
OpenATMShadowPorts:
        LD      BC,ShadowPortsOpened
        PUSH    BC
        LD      BC,$2A53
        PUSH    BC
        LD      BC,$0177
        LD      A,$C3
        JP      $3D2F
ShadowPortsOpened:
        RET

; A = indexed VGA register, E = value.
WriteVgaRegister:
        LD      BC,$03E0
        OUT     (C),A
        LD      A,E
        INC     C
        OUT     (C),A
        RET

; -------------------------------------------------------------------------
; Fill the 640x480x16 framebuffer.
; Size = 614400 bytes = 37 full 16 KiB banks + 8192 bytes in bank 37.
; The aperture C000h-FFFFh is switched with port 3DFh.
; -------------------------------------------------------------------------
Fill640x480x16:
        XOR     A
        LD      (CurrentBank),A

FillBankLoop:
        LD      A,(CurrentBank)
        LD      BC,$03DF
        OUT     (C),A

        LD      HL,$C000
        LD      DE,ColorPattern
        LD      A,(CurrentBank)
        CP      37
        JR      Z,FillLastHalfBank
        LD      BC,$4000
        JR      FillBankBytes

FillLastHalfBank:
        LD      BC,$2000

FillBankBytes:
        LD      A,(DE)
        INC     DE
        LD      (HL),A
        INC     HL

        ; Repeat the 128-byte RGB565 colour-bar sequence.
        PUSH    AF
        LD      A,D
        CP      HIGH ColorPatternEnd
        JR      NZ,PatternPointerReady
        LD      A,E
        CP      LOW ColorPatternEnd
        JR      NZ,PatternPointerReady
        LD      DE,ColorPattern
PatternPointerReady:
        POP     AF

        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,FillBankBytes

        LD      A,(CurrentBank)
        INC     A
        LD      (CurrentBank),A
        CP      38
        JR      NZ,FillBankLoop
        RET

; -------------------------------------------------------------------------
; Readback checks:
; bank 0 starts with 00 00 1F 00 E0 07 FF 07.
; bank 37 starts at linear offset 37*4000h = 5E000h.
; The final byte of the 640x480 framebuffer is bank 37 offset 1FFFh = FF.
; Return A=0 on success, A=1 on mismatch.
; -------------------------------------------------------------------------
VerifyFramebuffer:
        XOR     A
        LD      BC,$03DF
        OUT     (C),A

        LD      HL,$C000
        ; First eight pixels are black: bytes 0..15 must be zero.
        LD      A,(HL)
        OR      A
        JR      NZ,VerifyFailed
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,VerifyFailed

        ; Pixel 8 begins the blue RGB565 bar: 1F 00.
        LD      HL,$C010
        LD      A,(HL)
        CP      $1F
        JR      NZ,VerifyFailed
        INC     HL
        LD      A,(HL)
        OR      A
        JR      NZ,VerifyFailed

        LD      A,37
        LD      BC,$03DF
        OUT     (C),A
        LD      HL,$DFFF
        LD      A,(HL)
        CP      $FF
        JR      NZ,VerifyFailed

        XOR     A
        RET

VerifyFailed:
        LD      A,1
        RET


; -------------------------------------------------------------------------
; Sweep the nine requested standard PC display resolutions.
; Each mode uses 8-bpp indexed pixels and writes exactly its visible
; framebuffer size. Use only the adapter's initialized EGA palette
; entries 0..7, matching the proven Project132 test pattern.
; SPACE advances to the next resolution.
; -------------------------------------------------------------------------
RunPackedModeSweep:
        LD      HL,MsgSweepStart
        CALL    DebugPrint
        LD      HL,PackedModeTable
        LD      (ModeTablePtr),HL
        LD      HL,ModeLabelTable
        LD      (ModeLabelPtr),HL
        LD      A,9
        LD      (ModeCount),A

; Outer loop: increase resolution only after all four palette sizes pass.
PackedModeNext:
        LD      HL,(ModeTablePtr)
        LD      A,(HL)
        INC     HL
        LD      (ModeXLo),A
        LD      A,(HL)
        INC     HL
        LD      (ModeXHi),A
        LD      A,(HL)
        INC     HL
        LD      (ModeYLo),A
        LD      A,(HL)
        INC     HL
        LD      (ModeYHi),A
        LD      A,(HL)
        INC     HL
        LD      (ModeBpp),A
        LD      A,(HL)
        INC     HL
        LD      (ModeBankCount),A
        LD      A,(HL)
        INC     HL
        LD      (ModeLastBankBytes),A
        LD      A,(HL)
        INC     HL
        LD      (ModeLastBankBytes+1),A
        LD      (ModeTablePtr),HL

        CALL    ConfigureCurrentMode
        CALL    SpectrumShowMode

        XOR     A
        LD      (PaletteLevel),A

; Inner loop: 2, 4, 16 and 256 DAC entries at this resolution.
PackedPaletteNext:
        CALL    SelectPaletteParameters
        CALL    ProgramDacPalette

        ; Legacy DAC writes disable VBE in the adapter model.
        ; Re-apply this resolution's indexed 8-bpp mode before VRAM access.
        CALL    ConfigureCurrentMode

        LD      HL,MsgPaletteLevel
        CALL    DebugPrint
        LD      A,(PaletteLevel)
        CALL    DebugHexByte
        LD      HL,MsgPaletteSuffix
        CALL    DebugPrint

        ; Verify the DAC before touching the framebuffer. This keeps all
        ; DAC read-index/component activity out of the post-render phase.
        CALL    SelectPaletteParameters
        CALL    VerifyDacPalette
        OR      A
        JR      NZ,PackedPaletteFailed

        CALL    FillModeVRAM

        LD      HL,MsgPalettePass
        CALL    DebugPrint
        CALL    SpectrumShowWriteComplete
        CALL    WaitSpace

        LD      A,(PaletteLevel)
        INC     A
        LD      (PaletteLevel),A
        CP      4
        JR      NZ,PackedPaletteNext

        LD      A,(ModeCount)
        DEC     A
        LD      (ModeCount),A
        JP      NZ,PackedModeNext

        LD      HL,MsgSweepDone
        CALL    DebugPrint
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenAllDone
        CALL    SpectrumPrint
        RET

PackedPaletteFailed:
        LD      HL,MsgPaletteFail
        CALL    DebugPrint
        CALL    SpectrumShowDacFail
        CALL    WaitSpace
        RET

; Initialize only the entries used by the 2D smoke test.
; DAC components are six-bit values. Index 01 = blue, E3 = orange, FF = white.
Program2DTestPalette:
        LD      BC,$03C8
        XOR     A
        OUT     (C),A
        LD      BC,$03C9
        XOR     A
        OUT     (C),A
        OUT     (C),A
        OUT     (C),A

        LD      BC,$03C8
        LD      A,1
        OUT     (C),A
        LD      BC,$03C9
        LD      A,$00
        OUT     (C),A
        LD      A,$00
        OUT     (C),A
        LD      A,$3F
        OUT     (C),A

        LD      BC,$03C8
        LD      A,$E3
        OUT     (C),A
        LD      BC,$03C9
        LD      A,$3F
        OUT     (C),A
        LD      A,$20
        OUT     (C),A
        XOR     A
        OUT     (C),A

        LD      BC,$03C8
        LD      A,$FF
        OUT     (C),A
        LD      BC,$03C9
        LD      A,$3F
        OUT     (C),A
        OUT     (C),A
        OUT     (C),A
        RET

; -------------------------------------------------------------------------
; 2D gradient test. One dedicated accelerator command (CMD=4) interpolates
; the 8-bpp palette index from 00h to FFh across a 320x200 rectangle.
; No CPU framebuffer writes and no per-column command loop are used.
; Returns A=0 on success, A=1 on accelerator/readback failure.
; -------------------------------------------------------------------------
Run2DGradientTest:
        LD      HL,Msg2DGradientStart
        CALL    DebugPrint
        CALL    SpectrumShow2DGradientStart

        LD      A,3
        LD      (PaletteLevel),A
        CALL    SelectPaletteParameters
        CALL    ProgramDacPalette
        CALL    ConfigureCurrentMode

        LD      HL,AccelGradientRegs
        LD      A,AccelGradientRegsEnd-AccelGradientRegs
        CALL    WriteAccelRegisterTable

        ; CMD 4: interpolate colour 00h -> FFh across 320 pixels.
        LD      A,0
        LD      E,4
        CALL    WriteAccelRegister
        CALL    CheckAccelDone
        OR      A
        JP      NZ,Run2DGradientStatusFailed

        ; Read back first, midpoint (x=160 -> 80h), and last pixel.
        XOR     A
        LD      BC,$03DF
        OUT     (C),A
        LD      HL,$C000
        LD      A,(HL)
        OR      A
        JP      NZ,Run2DGradientReadbackFailed
        LD      HL,$C0A0
        LD      A,(HL)
        CP      $80
        JP      NZ,Run2DGradientReadbackFailed
        LD      HL,$C13F
        LD      A,(HL)
        CP      $FF
        JP      NZ,Run2DGradientReadbackFailed

        ; Verify the first and last pixels of the final scanline.
        ; Linear offsets 63680 and 63999 are in bank 3.
        LD      A,3
        LD      BC,$03DF
        OUT     (C),A
        LD      HL,$F8C0             ; bank 3 + offset 63680
        LD      A,(HL)
        OR      A
        JP      NZ,Run2DGradientReadbackFailed
        LD      HL,$F9FF             ; bank 3 + offset 63999
        LD      A,(HL)
        CP      $FF
        JP      NZ,Run2DGradientReadbackFailed

        LD      HL,Msg2DGradientPass
        CALL    DebugPrint
        CALL    SpectrumShow2DGradientPass
        CALL    WaitSpace
        XOR     A
        RET

Run2DGradientStatusFailed:
        ; Preserve the adapter's diagnostic status before printing.
        LD      BC,$03E2
        LD      A,1
        OUT     (C),A
        INC     C
        IN      A,(C)
        CP      $81
        JR      Z,Run2DGradientVbeDisabled
        CP      $82
        JR      Z,Run2DGradientBadRect
        CP      $83
        JR      Z,Run2DGradientBadAddress
        CP      $84
        JR      Z,Run2DGradientBadCommand
        CP      $80
        JR      Z,Run2DGradientGenericError
        CP      0
        JR      Z,Run2DGradientZeroStatus
        CP      1
        JR      Z,Run2DGradientUnexpectedDone
        LD      HL,Msg2DGradientUnknownStatus
        JR      Run2DGradientReportStatus
Run2DGradientGenericError:
        LD      HL,Msg2DGradientGenericError
        JR      Run2DGradientReportStatus
Run2DGradientZeroStatus:
        LD      HL,Msg2DGradientZeroStatus
        JR      Run2DGradientReportStatus
Run2DGradientUnexpectedDone:
        LD      HL,Msg2DGradientUnexpectedDone
        JR      Run2DGradientReportStatus
Run2DGradientVbeDisabled:
        LD      HL,Msg2DGradientVbeDisabled
        JR      Run2DGradientReportStatus
Run2DGradientBadRect:
        LD      HL,Msg2DGradientBadRect
        JR      Run2DGradientReportStatus
Run2DGradientBadAddress:
        LD      HL,Msg2DGradientBadAddress
        JR      Run2DGradientReportStatus
Run2DGradientBadCommand:
        LD      HL,Msg2DGradientBadCommand
Run2DGradientReportStatus:
        CALL    DebugPrint
        ; Print the exact status byte read from accelerator register 01h.
        LD      BC,$03E2
        LD      A,1
        OUT     (C),A
        INC     C
        IN      A,(C)
        CALL    DebugHexByte
        LD      A,13
        OUT     ($EF),A
        LD      A,10
        OUT     ($EF),A
        JP      Run2DGradientFailCommon

Run2DGradientReadbackFailed:
Run2DGradientFailed:
        LD      HL,Msg2DGradientFail
        CALL    DebugPrint
Run2DGradientFailCommon:
        CALL    SpectrumShow2DGradientFail
        CALL    WaitSpace
        LD      A,1
        RET

AccelGradientRegs:
        DB $02,$00
        DB $08,$00,$09,$00,$0A,$00,$0B,$00 ; destination base = 0
        DB $0E,$40,$0F,$01                 ; destination pitch = 320
        DB $14,$00,$15,$00                 ; x = 0
        DB $16,$00,$17,$00                 ; y = 0
        DB $18,$40,$19,$01                 ; width = 320
        DB $1A,$C8,$1B,$00                 ; height = 200
        DB $1C,$00,$1D,$00,$1E,$00,$1F,$00 ; start colour = 00000000h
        DB $20,$FF,$21,$00,$22,$00,$23,$00 ; end colour = 000000FFh
AccelGradientRegsEnd:

; -------------------------------------------------------------------------
; Project131-compatible 2D accelerator smoke test.
; Uses 320x200x8bpp so the complete 64,000-byte framebuffer is in banks 0..3.
; Tests solid fill, VRAM-to-VRAM BitBLT, Bresenham line and status/readback.
; Returns A=0 on success, A=1 on failure.
; -------------------------------------------------------------------------
Run2DAcceleratorTest:
        LD      HL,Msg2DStart
        CALL    DebugPrint
        CALL    SpectrumShow2DStart

        ; The adapter powers up with a zeroed DAC. Program visible colours
        ; before the first 8-bpp test, then restore VBE mode (DAC writes
        ; switch the adapter to legacy software mode).
        CALL    Program2DTestPalette

        ; Select 320x200x8bpp.
        LD      A,320&255
        LD      (ModeXLo),A
        LD      A,320>>8
        LD      (ModeXHi),A
        LD      A,200&255
        LD      (ModeYLo),A
        XOR     A
        LD      (ModeYHi),A
        CALL    ConfigureCurrentMode

        ; SOLID FILL: destination (20,20), 100x60, colour E3h.
        LD      HL,AccelFillRegs
        LD      A,AccelFillRegsEnd-AccelFillRegs
        CALL    WriteAccelRegisterTable
        LD      A,0
        LD      E,1
        CALL    WriteAccelRegister
        CALL    CheckAccelDone
        OR      A
        RET     NZ

        ; BITBLT: copy the filled rectangle to (140,20).
        LD      HL,AccelBlitRegs
        LD      A,AccelBlitRegsEnd-AccelBlitRegs
        CALL    WriteAccelRegisterTable
        LD      A,0
        LD      E,2
        CALL    WriteAccelRegister
        CALL    CheckAccelDone
        OR      A
        RET     NZ

        ; LINE: draw from (0,0) to (319,199), colour FFh.
        LD      HL,AccelLineRegs
        LD      A,AccelLineRegsEnd-AccelLineRegs
        CALL    WriteAccelRegisterTable
        LD      A,0
        LD      E,3
        CALL    WriteAccelRegister
        CALL    CheckAccelDone
        OR      A
        RET     NZ

        ; Read back the source and copied destination pixels in bank 0.
        XOR     A
        LD      BC,$03DF
        OUT     (C),A
        LD      HL,$D914             ; 20*320 + 20 + C000h
        LD      A,(HL)
        CP      $E3
        JP      NZ,AccelReadbackFail
        LD      HL,$D98C             ; 20*320 + 140 + C000h
        LD      A,(HL)
        CP      $E3
        JP      NZ,AccelReadbackFail

        ; The final line pixel is linear offset 63999 = bank 3:3A00? 
        ; Bank 3 aperture address = C000h + (63999 - 49152) = F9FFh.
        LD      A,3
        LD      BC,$03DF
        OUT     (C),A
        LD      HL,$F9FF
        LD      A,(HL)
        CP      $FF
        JP      NZ,AccelReadbackFail

        LD      HL,Msg2DPass
        CALL    DebugPrint
        CALL    SpectrumShow2DPass
        CALL    WaitSpace

        ; Follow the primitive smoke test with a 256-colour gradient
        ; generated by the dedicated 2D gradient-fill command.
        CALL    Run2DGradientTest
        OR      A
        RET     NZ
        CALL    RunTextModeTest
        RET

; Restore the standard 16-colour VGA/EGA DAC palette (6-bit RGB).
; This keeps the text-mode colour test independent of the preceding
; programmable 256-entry gradient test.
ProgramStandardEgaPalette:
        LD      BC,$03C8
        XOR     A
        OUT     (C),A
        LD      BC,$03C9
        LD      HL,StandardEgaPalette
        LD      D,48
StandardEgaPaletteWrite:
        LD      A,(HL)
        OUT     (C),A
        INC     HL
        DEC     D
        JR      NZ,StandardEgaPaletteWrite
        RET

StandardEgaPalette:
        ; RGB triples, DAC range 00h..3Fh.
        DB $00,$00,$00, $00,$00,$2A, $00,$2A,$00, $00,$2A,$2A
        DB $2A,$00,$00, $2A,$00,$2A, $2A,$15,$00, $2A,$2A,$2A
        DB $15,$15,$15, $15,$15,$3F, $15,$3F,$15, $15,$3F,$3F
        DB $3F,$15,$15, $3F,$15,$3F, $3F,$3F,$15, $3F,$3F,$3F

; IBM VGA mode 3 CRTC timing. Indexed register/value pairs.
; CR11 is written with bit 7 clear to unlock vertical timing registers.
TextCrtcMode3:
        ; Unlock protected CRTC registers before changing horizontal timing.
        DB $11,$0E
        DB $00,$5F, $01,$4F, $02,$50, $03,$82
        DB $04,$54, $05,$80, $06,$BF, $07,$1F
        DB $09,$0F, $0A,$0D, $0B,$0E, $0C,$80
        DB $0D,$00, $0E,$00, $0F,$00, $10,$9C
        DB $12,$8F, $13,$28, $14,$00, $15,$96
        DB $16,$B9, $17,$A3, $18,$FF

; -------------------------------------------------------------------------
; VGA text-mode test: 80x25, character plane 0, attribute plane 1.
; Uses the adapter's bank-6 text aperture (C000h-C7CFh).
; Scrolls rows 1..24 to rows 0..23, clears row 24, then verifies
; character and attribute readback through the VGA plane read map.
; -------------------------------------------------------------------------
RunTextModeTest:
        LD      HL,MsgTextStart
        CALL    DebugPrint
        CALL    SpectrumShowTextStart

        ; The preceding 256-colour gradient test leaves a custom DAC ramp.
        ; Restore the standard 16-colour VGA palette before testing text
        ; attributes, which are expected to use the conventional EGA colours.
        CALL    ProgramStandardEgaPalette

        ; Program the VGA CRTC for a real 80-column, 25-row mode 3
        ; timing (720x400, 9-dot characters, 16 scanlines per row).
        ; The adapter must derive text geometry from these registers;
        ; the renderer must not invent a default column count.
        LD      HL,TextCrtcMode3
        LD      D,24
        LD      BC,$03D4
TextCrtcWrite:
        LD      A,(HL)
        OUT     (C),A
        INC     HL
        INC     C
        LD      A,(HL)
        OUT     (C),A
        INC     HL
        DEC     C
        DEC     D
        JR      NZ,TextCrtcWrite

        ; Text lives in Spectrum bridge bank 6 (plane offset 18000h).
        ; CRTC[1E].A0 adds MA16, so start 8000h resolves to 18000h
        ; before PCem's four-byte interleaved display-address conversion.
        LD      BC,$03D4
        LD      A,$1E
        OUT     (C),A
        INC     C
        LD      A,$A0
        OUT     (C),A


        ; Select 9-dot VGA text characters (Sequencer Clocking Mode bit 0 = 0).
        LD      BC,$03C4
        LD      A,1
        OUT     (C),A
        INC     C
        XOR     A
        OUT     (C),A

        ; Select legacy VGA text mode: sequencer memory mode 06h,
        ; graphics-controller misc register 0Eh (B8000 text mapping).
        LD      BC,$03C4
        LD      A,4
        OUT     (C),A
        INC     C
        LD      A,$06
        OUT     (C),A

        LD      BC,$03CE
        LD      A,6
        OUT     (C),A
        INC     C
        LD      A,$0E
        OUT     (C),A

        ; Configure planar write mode 0 and full byte mask.
        LD      A,5
        DEC     C
        OUT     (C),A
        INC     C
        XOR     A
        OUT     (C),A
        LD      A,8
        DEC     C
        OUT     (C),A
        INC     C
        LD      A,$FF
        OUT     (C),A
        LD      A,4
        DEC     C
        OUT     (C),A
        INC     C
        XOR     A
        OUT     (C),A
        LD      A,3
        DEC     C
        OUT     (C),A
        INC     C
        XOR     A
        OUT     (C),A
        LD      A,1
        DEC     C
        OUT     (C),A
        INC     C
        XOR     A
        OUT     (C),A
        LD      A,0
        DEC     C
        OUT     (C),A
        INC     C
        XOR     A
        OUT     (C),A

        ; Text aperture occupies bank 6 (linear VRAM offset 18000h).
        LD      BC,$03DF
        LD      A,6
        OUT     (C),A

        ; Clear 2000 character cells in plane 0 with spaces.
        LD      BC,$03C4
        LD      A,2
        OUT     (C),A
        INC     C
        LD      A,1
        OUT     (C),A
        LD      HL,$C000
        LD      BC,2000
        LD      D,' '
TextClearChars:
        LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,TextClearChars

        ; Initialize all attributes in plane 1 to light grey on black.
        LD      BC,$03C4
        LD      A,2
        OUT     (C),A
        INC     C
        LD      A,2
        OUT     (C),A
        LD      HL,$C000
        LD      BC,2000
        LD      D,$07
TextClearAttrs:
        LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,TextClearAttrs

        ; Populate several rows with distinct attributes.
        LD      A,$0F
        LD      (TextAttribute),A
        LD      HL,TextLine0
        LD      DE,$C000
        CALL    TextWriteString
        LD      A,$0B
        LD      (TextAttribute),A
        LD      HL,TextLine1
        LD      DE,$C050
        CALL    TextWriteString
        LD      A,$0A
        LD      (TextAttribute),A
        LD      HL,TextLine2
        LD      DE,$C0A0
        CALL    TextWriteString
        LD      A,$0E
        LD      (TextAttribute),A
        LD      HL,TextLine3
        LD      DE,$C0F0
        CALL    TextWriteString
        LD      A,$0C
        LD      (TextAttribute),A
        LD      HL,TextLine4
        LD      DE,$C140
        CALL    TextWriteString

        LD      A,$0F
        LD      (TextAttribute),A
        LD      HL,TextLine5
        LD      DE,$C190
        CALL    TextWriteString

        ; Draw all sixteen VGA foreground colours on a blue background.
        ; Row 6 is intentionally below the existing sample text so the
        ; subsequent scroll moves this colour ramp to row 5.
        CALL    TextWriteColorRamp

        ; Scroll both VGA text planes up by one 80-character row.
        ; Read plane 0 and write plane 0.
        LD      BC,$03C4
        LD      A,2
        OUT     (C),A
        INC     C
        LD      A,1
        OUT     (C),A
        LD      BC,$03CE
        LD      A,4
        OUT     (C),A
        INC     C
        XOR     A
        OUT     (C),A
        LD      HL,$C050
        LD      DE,$C000
        LD      BC,1920
        LDIR

        ; Read plane 1 and write plane 1.
        LD      BC,$03C4
        LD      A,2
        OUT     (C),A
        INC     C
        LD      A,2
        OUT     (C),A
        LD      BC,$03CE
        LD      A,4
        OUT     (C),A
        INC     C
        LD      A,1
        OUT     (C),A
        LD      HL,$C050
        LD      DE,$C000
        LD      BC,1920
        LDIR

        ; Clear the newly exposed bottom row.
        LD      BC,$03C4
        LD      A,2
        OUT     (C),A
        INC     C
        LD      A,1
        OUT     (C),A
        LD      HL,$C780
        LD      BC,80
        LD      D,' '
TextClearBottomChars:
        LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,TextClearBottomChars

        LD      BC,$03C4
        LD      A,2
        OUT     (C),A
        INC     C
        LD      A,2
        OUT     (C),A
        LD      HL,$C780
        LD      BC,80
        LD      D,$07
TextClearBottomAttrs:
        LD      (HL),D
        INC     HL
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,TextClearBottomAttrs

        LD      A,$0A
        LD      (TextAttribute),A
        LD      HL,TextScrollPassed
        LD      DE,$C780
        CALL    TextWriteString

        ; Verify that old row 1 moved to row 0 in both planes.
        LD      BC,$03CE
        LD      A,4
        OUT     (C),A
        INC     C
        XOR     A
        OUT     (C),A
        LD      A,($C000)
        CP      '8'
        JP      NZ,TextModeFailed

        LD      BC,$03CE
        LD      A,4
        OUT     (C),A
        INC     C
        LD      A,1
        OUT     (C),A
        LD      A,($C000)
        CP      $0B
        JP      NZ,TextModeFailed

        ; Verify the newly written bottom line.
        LD      BC,$03CE
        LD      A,4
        OUT     (C),A
        INC     C
        XOR     A
        OUT     (C),A
        LD      A,($C780)
        CP      'S'
        JP      NZ,TextModeFailed

        ; Verify the colour ramp survived the scroll in both VGA planes.
        ; It moved from row 6 (C1E0h) to row 5 (C190h).
        LD      BC,$03CE
        LD      A,4
        OUT     (C),A
        INC     C
        XOR     A
        OUT     (C),A
        LD      A,($C190)
        CP      'A'
        JP      NZ,TextModeFailed
        LD      A,($C19F)
        CP      'P'
        JP      NZ,TextModeFailed

        LD      BC,$03CE
        LD      A,4
        OUT     (C),A
        INC     C
        LD      A,1
        OUT     (C),A
        LD      A,($C190)
        CP      $10
        JP      NZ,TextModeFailed
        LD      A,($C197)
        CP      $17
        JP      NZ,TextModeFailed
        LD      A,($C19F)
        CP      $1F
        JP      NZ,TextModeFailed

        LD      HL,MsgTextPass
        CALL    DebugPrint
        CALL    SpectrumShowTextPass
        CALL    WaitSpace
        XOR     A
        RET

TextModeFailed:
        LD      HL,MsgTextFail
        CALL    DebugPrint
        CALL    SpectrumShowTextFail
        CALL    WaitSpace
        LD      A,1
        RET

; HL = zero-terminated string, DE = text-cell offset in bank 6.
; Writes the character to plane 0 and its attribute to plane 1.
TextWriteString:
        LD      A,(HL)
        OR      A
        RET     Z
        PUSH    AF
        LD      BC,$03C4
        LD      A,2
        OUT     (C),A
        INC     C
        LD      A,1
        OUT     (C),A
        POP     AF
        LD      (DE),A
        LD      BC,$03C4
        LD      A,2
        OUT     (C),A
        INC     C
        LD      A,2
        OUT     (C),A
        LD      A,(TextAttribute)
        LD      (DE),A
        INC     HL
        INC     DE
        JP      TextWriteString

; Writes A..P with foreground colours 0..15 on blue background.
; VGA attribute byte = 10h..1Fh; the complete ramp is 16 cells wide.
TextWriteColorRamp:
        LD      BC,$03C4
        LD      A,2
        OUT     (C),A
        INC     C
        LD      A,1
        OUT     (C),A
        LD      HL,$C1E0
        LD      B,16
        LD      A,'A'
TextColorChars:
        LD      (HL),A
        INC     HL
        INC     A
        DJNZ    TextColorChars

        LD      BC,$03C4
        LD      A,2
        OUT     (C),A
        INC     C
        LD      A,2
        OUT     (C),A
        LD      HL,$C1E0
        LD      B,16
        LD      A,$10
TextColorAttrs:
        LD      (HL),A
        INC     HL
        INC     A
        DJNZ    TextColorAttrs
        RET

AccelReadbackFail:
        LD      HL,Msg2DReadbackFail
        CALL    DebugPrint
        CALL    SpectrumShow2DFail
        CALL    WaitSpace
        LD      A,1
        RET

; HL points to register/value pairs; A is the byte count.
WriteAccelRegisterTable:
        LD      (AccelPairCount),A
WriteAccelRegisterTableLoop:
        LD      A,(HL)
        INC     HL
        LD      E,(HL)
        INC     HL
        PUSH    HL
        CALL    WriteAccelRegister
        POP     HL
        LD      A,(AccelPairCount)
        SUB     2
        LD      (AccelPairCount),A
        JR      NZ,WriteAccelRegisterTableLoop
        RET

; A = accelerator register index, E = value.
WriteAccelRegister:
        LD      BC,$03E2
        OUT     (C),A
        LD      A,E
        INC     C
        OUT     (C),A
        RET

; Returns A=0 when status register reports DONE (1), otherwise A=1.
CheckAccelDone:
        LD      BC,$03E2
        LD      A,1
        OUT     (C),A
        INC     C
        IN      A,(C)
        CP      1
        JR      NZ,CheckAccelFailed
        XOR     A
        RET
CheckAccelFailed:
        LD      A,1
        RET

; Register tables: index,value pairs. All addresses are byte offsets in VRAM.
AccelFillRegs:
        DB $02,$00                 ; ROP COPY
        DB $08,$00,$09,$00,$0A,$00,$0B,$00 ; destination base = 0
        DB $0E,$40,$0F,$01         ; destination pitch = 320
        DB $14,20,$15,0,$16,20,$17,0
        DB $18,100,$19,0,$1A,60,$1B,0
        DB $1C,$E3,$1D,0,$1E,0,$1F,0
AccelFillRegsEnd:

AccelBlitRegs:
        DB $02,$00
        DB $0C,$40,$0D,$01         ; source pitch = 320
        DB $0E,$40,$0F,$01         ; destination pitch = 320
        DB $10,20,$11,0,$12,20,$13,0
        DB $14,140,$15,0,$16,20,$17,0
        DB $18,100,$19,0,$1A,60,$1B,0
AccelBlitRegsEnd:

AccelLineRegs:
        DB $02,$00
        DB $0E,$40,$0F,$01         ; destination pitch = 320
        DB $14,0,$15,0,$16,0,$17,0
        DB $1C,$FF,$1D,0,$1E,0,$1F,0
        DB $20,63,$21,1,$22,199,$23,0 ; endpoint (319,199)
AccelLineRegsEnd:

AccelTestFailed:
        LD      HL,Msg2DFail
        CALL    DebugPrint
AccelTestFailedIdle:
        HALT
        JR      AccelTestFailedIdle

; Re-apply the currently selected packed-pixel 8-bpp resolution.
ConfigureCurrentMode:
        LD      A,(ModeXLo)
        LD      E,A
        LD      A,0
        CALL    WriteVgaRegister
        LD      A,(ModeXHi)
        LD      E,A
        LD      A,1
        CALL    WriteVgaRegister
        LD      A,(ModeYLo)
        LD      E,A
        LD      A,2
        CALL    WriteVgaRegister
        LD      A,(ModeYHi)
        LD      E,A
        LD      A,3
        CALL    WriteVgaRegister
        LD      A,8
        LD      E,A
        LD      A,4
        CALL    WriteVgaRegister
        LD      A,1
        LD      E,A
        LD      A,5
        CALL    WriteVgaRegister
        RET

; Palette table entry: count (word), index mask (byte), DAC source stride
; beyond RGB (word). The RGB332 source table contains 256 evenly ordered
; entries, so each smaller palette samples the full colour range.
SelectPaletteParameters:
        LD      HL,PaletteConfigTable
        LD      A,(PaletteLevel)
        OR      A
        JR      Z,PaletteConfigFound
        LD      B,A
PaletteConfigSkip:
        LD      DE,5
        ADD     HL,DE
        DJNZ    PaletteConfigSkip
PaletteConfigFound:
        LD      A,(HL)
        INC     HL
        LD      (PaletteRemaining),A
        LD      (PaletteCount),A
        LD      A,(HL)
        INC     HL
        LD      (PaletteRemaining+1),A
        LD      (PaletteCount+1),A
        LD      A,(HL)
        INC     HL
        LD      (PaletteMask),A
        LD      A,(HL)
        INC     HL
        LD      (PaletteStride),A
        LD      A,(HL)
        LD      (PaletteStride+1),A
        RET

; Program the selected number of DAC entries sampled from the 256-step HSV hue ramp.
ProgramDacPalette:
        LD      HL,DacHuePalette
        LD      DE,(PaletteStride)
        XOR     A
        LD      (DacIndex),A
ProgramDacPaletteLoop:
        LD      A,(DacIndex)
        LD      BC,$03C8
        OUT     (C),A
        LD      BC,$03C9
        LD      A,(HL)
        INC     HL
        OUT     (C),A
        LD      A,(HL)
        INC     HL
        OUT     (C),A
        LD      A,(HL)
        INC     HL
        OUT     (C),A
        ADD     HL,DE
        LD      A,(DacIndex)
        INC     A
        LD      (DacIndex),A
        PUSH    HL
        CALL    DecPaletteRemaining
        POP     HL
        JR      NZ,ProgramDacPaletteLoop
        RET

DecPaletteRemaining:
        LD      HL,(PaletteRemaining)
        DEC     HL
        LD      (PaletteRemaining),HL
        LD      A,H
        OR      L
        RET

; Fill the framebuffer with a full-width horizontal hue gradient.
; Palette entries are sampled evenly from the first to last hue.
; A 16-bit accumulator spreads palette transitions uniformly across each row.
FillModeVRAM:
        XOR     A
        LD      (CurrentBank),A
        LD      (DacIndex),A
        LD      HL,0
        LD      (GradientAccumulator),HL
        LD      (ModeXCounter),HL
ModeFillBank:
        LD      A,(CurrentBank)
        LD      BC,$03DF
        OUT     (C),A
        LD      HL,$C000
        LD      A,(CurrentBank)
        LD      B,A
        LD      A,(ModeBankCount)
        DEC     A
        CP      B
        JR      NZ,ModeFillFullBank
        LD      BC,(ModeLastBankBytes)
        JR      ModeFillCountReady
ModeFillFullBank:
        LD      BC,$4000
ModeFillCountReady:
ModeFillByte:
        LD      A,(DacIndex)
        LD      (HL),A
        INC     HL
        PUSH    HL

        ; Advance the X coordinate and detect the end of the scanline.
        LD      HL,(ModeXCounter)
        INC     HL
        LD      (ModeXCounter),HL
        PUSH    HL
        LD      A,(ModeXLo)
        LD      E,A
        LD      A,(ModeXHi)
        LD      D,A
        OR      A
        SBC     HL,DE
        POP     HL
        JR      NZ,ModeGradientAdvance

        ; Restart the gradient at the beginning of every scanline.
        LD      HL,0
        LD      (ModeXCounter),HL
        LD      (GradientAccumulator),HL
        XOR     A
        LD      (DacIndex),A
        JR      ModePatternAdvanceDone

ModeGradientAdvance:
        ; Bresenham-style distribution: add palette count per pixel and
        ; advance the DAC index whenever the accumulator reaches width.
        LD      HL,(GradientAccumulator)
        LD      DE,(PaletteCount)
        ADD     HL,DE
        LD      DE,(ModeXLo)
        OR      A
        SBC     HL,DE
        JR      C,ModeGradientHold
        LD      (GradientAccumulator),HL
        LD      A,(DacIndex)
        INC     A
        LD      (DacIndex),A
        JR      ModePatternAdvanceDone
ModeGradientHold:
        ADD     HL,DE
        LD      (GradientAccumulator),HL

ModePatternAdvanceDone:
        POP     HL
        DEC     BC
        LD      A,B
        OR      C
        JP      NZ,ModeFillByte
        LD      A,(CurrentBank)
        INC     A
        LD      (CurrentBank),A
        LD      B,A
        LD      A,(ModeBankCount)
        CP      B
        JP      NZ,ModeFillBank
        RET

; Read back every programmed DAC entry, including all RGB components.
; Return A=0 on success, A=1 on mismatch.
VerifyDacPalette:
        LD      HL,DacHuePalette
        LD      DE,(PaletteStride)
        XOR     A
        LD      (DacIndex),A
VerifyDacPaletteLoop:
        LD      A,(DacIndex)
        LD      BC,$03C7
        OUT     (C),A
        LD      BC,$03C9
        IN      A,(C)
        CP      (HL)
        JR      NZ,VerifyDacPaletteFailed
        INC     HL
        IN      A,(C)
        CP      (HL)
        JR      NZ,VerifyDacPaletteFailed
        INC     HL
        IN      A,(C)
        CP      (HL)
        JR      NZ,VerifyDacPaletteFailed
        INC     HL
        ADD     HL,DE
        LD      A,(DacIndex)
        INC     A
        LD      (DacIndex),A
        PUSH    HL
        CALL    DecPaletteRemaining
        POP     HL
        JR      NZ,VerifyDacPaletteLoop
        XOR     A
        RET
VerifyDacPaletteFailed:
        LD      A,1
        RET

RunDac256Test:
        LD      HL,MsgDacStart
        CALL    DebugPrint
        CALL    SpectrumShowDacStart
        LD      A,0
        LD      E,64
        CALL    WriteVgaRegister
        LD      A,1
        LD      E,1
        CALL    WriteVgaRegister
        LD      A,2
        LD      E,200
        CALL    WriteVgaRegister
        LD      A,3
        LD      E,0
        CALL    WriteVgaRegister
        LD      A,4
        LD      E,8
        CALL    WriteVgaRegister
        LD      A,5
        LD      E,1
        CALL    WriteVgaRegister
        CALL    ProgramDac332

        ; DAC writes use ports 3C8h/3C9h. In the Project131 adapter model,
        ; writes to legacy VGA ports clear vbe_enabled. Re-apply the packed
        ; 320x200x8 mode AFTER programming the DAC, before touching VRAM.
        LD      A,0
        LD      E,64
        CALL    WriteVgaRegister
        LD      A,1
        LD      E,1
        CALL    WriteVgaRegister
        LD      A,2
        LD      E,200
        CALL    WriteVgaRegister
        LD      A,3
        LD      E,0
        CALL    WriteVgaRegister
        LD      A,4
        LD      E,8
        CALL    WriteVgaRegister
        LD      A,5
        LD      E,1
        CALL    WriteVgaRegister

        CALL    FillDacFramebuffer
        CALL    VerifyDac332
        OR      A
        JR      NZ,DacTestFailed
        LD      HL,MsgDacPass
        CALL    DebugPrint
        CALL    SpectrumShowDacPass
        CALL    WaitSpace
        RET
DacTestFailed:
        LD      HL,MsgDacFail
        CALL    DebugPrint
        CALL    SpectrumShowDacFail
        CALL    WaitSpace
        RET

ProgramDac332:
        LD      HL,DacHuePalette
        XOR     A
        LD      (DacIndex),A
DacWriteLoop:
        LD      A,(DacIndex)
        LD      BC,$03C8
        OUT     (C),A
        LD      BC,$03C9
        LD      A,(HL)
        INC     HL
        OUT     (C),A
        LD      A,(HL)
        INC     HL
        OUT     (C),A
        LD      A,(HL)
        INC     HL
        OUT     (C),A
        LD      A,(DacIndex)
        INC     A
        LD      (DacIndex),A
        JR      NZ,DacWriteLoop
        RET

FillDacFramebuffer:
        XOR     A
        LD      (CurrentBank),A
        LD      (DacIndex),A
DacFillBank:
        LD      A,(CurrentBank)
        LD      BC,$03DF
        OUT     (C),A
        LD      HL,$C000
        LD      A,(CurrentBank)
        CP      3
        JR      Z,DacFillLastBank
        LD      BC,$4000
        JR      DacFillCountReady
DacFillLastBank:
        LD      BC,14848
DacFillCountReady:
DacFillByte:
        LD      A,(DacIndex)
        LD      (HL),A
        INC     HL
        INC     A
        LD      (DacIndex),A
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,DacFillByte
        LD      A,(CurrentBank)
        INC     A
        LD      (CurrentBank),A
        CP      4
        JR      NZ,DacFillBank
        RET

VerifyDac332:
        LD      HL,DacHuePalette
        XOR     A
        LD      (DacIndex),A
DacReadLoop:
        LD      A,(DacIndex)
        LD      BC,$03C7
        OUT     (C),A
        LD      BC,$03C9
        IN      A,(C)
        CP      (HL)
        JR      NZ,DacVerifyFailed
        INC     HL
        IN      A,(C)
        CP      (HL)
        JR      NZ,DacVerifyFailed
        INC     HL
        IN      A,(C)
        CP      (HL)
        JR      NZ,DacVerifyFailed
        INC     HL
        LD      A,(DacIndex)
        INC     A
        LD      (DacIndex),A
        JR      NZ,DacReadLoop
        XOR     A
        RET
DacVerifyFailed:
        LD      A,1
        RET

SpectrumShow2DStart:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,Screen2DHeading
        CALL    SpectrumPrint
        LD      HL,Screen2DRunning
        CALL    SpectrumPrint
        RET
SpectrumShow2DGradientStart:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,Screen2DGradientHeading
        CALL    SpectrumPrint
        LD      HL,Screen2DGradientRunning
        CALL    SpectrumPrint
        RET

SpectrumShowTextStart:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenTextHeading
        CALL    SpectrumPrint
        LD      HL,ScreenTextRunning
        CALL    SpectrumPrint
        RET
SpectrumShowTextPass:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenTextHeading
        CALL    SpectrumPrint
        LD      HL,ScreenTextPassed
        CALL    SpectrumPrint
        RET
SpectrumShowTextFail:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenTextHeading
        CALL    SpectrumPrint
        LD      HL,ScreenTextFailed
        CALL    SpectrumPrint
        RET

SpectrumShow2DGradientPass:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,Screen2DGradientHeading
        CALL    SpectrumPrint
        LD      HL,Screen2DGradientPassed
        CALL    SpectrumPrint
        RET

SpectrumShow2DGradientFail:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,Screen2DGradientHeading
        CALL    SpectrumPrint
        LD      HL,Screen2DGradientFailed
        CALL    SpectrumPrint
        RET

SpectrumShow2DPass:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,Screen2DHeading
        CALL    SpectrumPrint
        LD      HL,Screen2DPassed
        CALL    SpectrumPrint
        RET
SpectrumShow2DFail:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,Screen2DHeading
        CALL    SpectrumPrint
        LD      HL,Screen2DFailed
        CALL    SpectrumPrint
        RET

SpectrumShowDacStart:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenDacHeading
        CALL    SpectrumPrint
        LD      HL,ScreenDacWriting
        CALL    SpectrumPrint
        RET
SpectrumShowDacPass:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenDacHeading
        CALL    SpectrumPrint
        LD      HL,ScreenDacPassed
        CALL    SpectrumPrint
        LD      HL,ScreenNextHint
        CALL    SpectrumPrint
        RET
SpectrumShowDacFail:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenDacHeading
        CALL    SpectrumPrint
        LD      HL,ScreenDacFailed
        CALL    SpectrumPrint
        RET

SpectrumPrint:
        LD      A,(HL)
        OR      A
        RET     Z
        INC     HL
        CP      13
        JP      Z,SpectrumPrintNewLine
        CP      32
        JR      C,SpectrumPrint
        CP      128
        JR      NC,SpectrumPrint
        PUSH    HL
        SUB     32
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,Font88_132
        ADD     HL,DE
        LD      (SpectrumFontPtr),HL
        XOR     A
        LD      (SpectrumGlyphLine),A
SpectrumGlyphLoop:
        LD      HL,(SpectrumFontPtr)
        LD      A,(HL)
        LD      (SpectrumGlyphByte),A
        INC     HL
        LD      (SpectrumFontPtr),HL

        ; Same bitmap address calculation as Project112 RenderGlyph_Standard112.
        LD      A,(SpectrumCursorY)
        ADD     A,A
        ADD     A,A
        ADD     A,A
        LD      B,A
        LD      A,(SpectrumGlyphLine)
        ADD     A,B
        LD      B,A
        LD      A,B
        AND     $C0
        RRCA
        RRCA
        RRCA
        LD      C,A
        LD      A,B
        AND     $07
        OR      C
        OR      $40
        LD      H,A
        LD      A,B
        AND     $38
        RLCA
        RLCA
        LD      L,A
        LD      A,(SpectrumCursorX)
        OR      L
        LD      L,A
        LD      A,(SpectrumGlyphByte)
        LD      (HL),A

        LD      A,(SpectrumGlyphLine)
        INC     A
        LD      (SpectrumGlyphLine),A
        CP      8
        JR      NZ,SpectrumGlyphLoop

        ; Same attribute-cell calculation as Project112.
        LD      A,(SpectrumCursorY)
        LD      L,A
        LD      H,0
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        ADD     HL,HL
        LD      DE,$5800
        ADD     HL,DE
        LD      A,(SpectrumCursorX)
        ADD     A,L
        LD      L,A
        JR      NC,SpectrumAttrAddressReady
        INC     H
SpectrumAttrAddressReady:
        LD      A,$47
        LD      (HL),A

        LD      A,(SpectrumCursorX)
        INC     A
        CP      32
        JR      C,SpectrumCursorXReady
        XOR     A
        LD      (SpectrumCursorX),A
        LD      A,(SpectrumCursorY)
        INC     A
        CP      24
        JR      C,SpectrumCursorYReady
        XOR     A
SpectrumCursorYReady:
        LD      (SpectrumCursorY),A
        POP     HL
        JP      SpectrumPrint
SpectrumCursorXReady:
        LD      (SpectrumCursorX),A
        POP     HL
        JP      SpectrumPrint

SpectrumPrintNewLine:
        XOR     A
        LD      (SpectrumCursorX),A
        LD      A,(SpectrumCursorY)
        INC     A
        CP      24
        JR      C,SpectrumNewLineYReady
        XOR     A
SpectrumNewLineYReady:
        LD      (SpectrumCursorY),A
        JP      SpectrumPrint

SpectrumClear:
        XOR     A
        LD      (SpectrumCursorX),A
        LD      (SpectrumCursorY),A
        ; Clear the 6144-byte bitmap.
        LD      HL,$4000
        LD      DE,$4001
        LD      BC,$17FF
        LD      (HL),A
        LDIR
        ; Initialize all 768 attributes.
        LD      HL,$5800
        LD      DE,$5801
        LD      BC,$02FF
        LD      A,$07
        LD      (HL),A
        LDIR
        RET

SpectrumShowStartup:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenStarting
        CALL    SpectrumPrint
        RET

; HL points to a zero-terminated status string.
SpectrumShowStatus:
        PUSH    HL
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        POP     HL
        CALL    SpectrumPrint
        RET

SpectrumShowInitialMode:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenInitialMode
        CALL    SpectrumPrint
        LD      HL,ScreenInitialTestRunning
        CALL    SpectrumPrint
        LD      HL,ScreenWriteRunning
        CALL    SpectrumPrint
        RET

SpectrumShowInitialWriteComplete:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenInitialMode
        CALL    SpectrumPrint
        LD      HL,ScreenInitialTestRunning
        CALL    SpectrumPrint
        LD      HL,ScreenWritePassed
        CALL    SpectrumPrint
        RET

SpectrumShowMode:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenModeHeading
        CALL    SpectrumPrint
        ; Fetch and advance the pointer in the mode-label pointer table.
        LD      HL,(ModeLabelPtr)
        LD      A,(HL)
        LD      E,A
        INC     HL
        LD      A,(HL)
        LD      D,A
        INC     HL
        LD      (ModeLabelPtr),HL
        EX      DE,HL
        CALL    SpectrumPrint
        LD      HL,ScreenTestRunning
        CALL    SpectrumPrint
        LD      HL,ScreenWriteRunning
        CALL    SpectrumPrint
        RET

SpectrumShowWriteComplete:
        CALL    SpectrumClear
        LD      HL,ScreenTitle
        CALL    SpectrumPrint
        LD      HL,ScreenModeHeading
        CALL    SpectrumPrint
        ; Re-read the just-consumed mode label without advancing the table.
        LD      HL,(ModeLabelPtr)
        DEC     HL
        DEC     HL
        LD      A,(HL)
        LD      E,A
        INC     HL
        LD      A,(HL)
        LD      D,A
        EX      DE,HL
        CALL    SpectrumPrint
        LD      HL,ScreenTestRunning
        CALL    SpectrumPrint
        LD      HL,ScreenWritePassed
        CALL    SpectrumPrint
        LD      HL,ScreenNextHint
        CALL    SpectrumPrint
        RET

; Wait for SPACE so every resolution and its complete colour ramp
; remains visible until the user is ready for the next mode.
WaitSpace:
        LD      BC,$7FFE
WaitSpacePress:
        IN      A,(C)
        AND     1
        JR      NZ,WaitSpacePress
WaitSpaceRelease:
        IN      A,(C)
        AND     1
        JR      Z,WaitSpaceRelease
        RET

DebugHexByte:
        PUSH    AF
        RRCA
        RRCA
        RRCA
        RRCA
        CALL    DebugHexNibble
        POP     AF
        CALL    DebugHexNibble
        RET
DebugHexNibble:
        AND     $0F
        ADD     A,'0'
        CP      '9'+1
        JR      C,DebugHexOut
        ADD     A,7
DebugHexOut:
        OUT     ($EF),A
        RET

; -------------------------------------------------------------------------
; Port EF text logger (ASCII bytes, same convention as Project112).
; -------------------------------------------------------------------------
DebugPrint:
        LD      A,(HL)
        OR      A
        RET     Z
        OUT     ($EF),A
        INC     HL
        JR      DebugPrint

CurrentBank: DB 0
TextAttribute: DB $07
AccelPairCount: DB 0
GradientIndex: DB 0
GradientX: DW 0


ModeLabelPtr: DW 0
DacIndex: DB 0
SpectrumCursorX: DB 0
SpectrumCursorY: DB 0
SpectrumGlyphLine: DB 0
SpectrumGlyphByte: DB 0
SpectrumFontPtr: DW 0
ModeTablePtr: DW 0
ModeCount:    DB 0
ModeXLo:      DB 0
ModeXHi:      DB 0
ModeYLo:      DB 0
ModeYHi:      DB 0
ModeBpp:      DB 0
ModeBankCount: DB 0
ModeLastBankBytes: DW 0
PaletteLevel: DB 0
PaletteMask: DB 0
PaletteRemaining: DW 0
PaletteCount: DW 0
PaletteStride: DW 0
GradientAccumulator: DW 0
ModeXCounter: DW 0

; Sixteen initialized EGA palette indices, each repeated twice.
; Project132 also uses EGA entry 15 as white for its on-screen banner.
ModePattern8:
        DB $00,$00,$01,$01,$02,$02,$03,$03,$04,$04,$05,$05,$06,$06,$07,$07
        DB $08,$08,$09,$09,$0A,$0A,$0B,$0B,$0C,$0C,$0D,$0D,$0E,$0E,$0F,$0F
ModePattern8End:

; Standard PC display resolutions, all tested in 8-bpp indexed colour.
; Entry: X low, X high, Y low, Y high, BPP, bank count, last-bank bytes.
; Framebuffer sizes are <= 1 MiB.
PackedModeTable:
        DB 320&255,320>>8,200&255,200>>8,8,4,14848&255,14848>>8
        DB 320&255,320>>8,240&255,240>>8,8,5,11264&255,11264>>8
        DB 512&255,512>>8,384&255,384>>8,8,12,0,64
        DB 640&255,640>>8,200&255,200>>8,8,8,14336&255,14336>>8
        DB 640&255,640>>8,350&255,350>>8,8,14,11008&255,11008>>8
        DB 640&255,640>>8,400&255,400>>8,8,16,10240&255,10240>>8
        DB 640&255,640>>8,480&255,480>>8,8,19,12288&255,12288>>8
        DB 800&255,800>>8,600&255,600>>8,8,30,4864&255,4864>>8
        DB 1024&255,1024>>8,768&255,768>>8,8,48,0,64


; Palette levels: 2, 4, 16 and 256 entries. Palette data is sequential:
; first 16 entries are a conventional EGA palette, then RGB332 ramp.
PaletteConfigTable:
        ; Count, index mask, extra source-byte skip after each RGB triplet in the HSV ramp.
        ; Samples include both ends of the 256-step hue ramp.
        DW 2
        DB 1
        DW 762
        DW 4
        DB 3
        DW 252
        DW 16
        DB 15
        DW 48
        DW 256
        DB 255
        DW 0

; Text shown on the Spectrum screen for each VGA mode.
ModeLabelTable:
        DW ModeLabel01,ModeLabel02,ModeLabel03,ModeLabel04,ModeLabel05
        DW ModeLabel06,ModeLabel07,ModeLabel08,ModeLabel09
ModeLabel01: DEFM "MODE 01 OF 09",13,"RESOLUTION: 320x200",13,"COLOR: 8 BPP / INDEXED PALETTE",13,"VRAM: 64000 BYTES",13,13,0
ModeLabel02: DEFM "MODE 02 OF 09",13,"RESOLUTION: 320x240",13,"COLOR: 8 BPP / INDEXED PALETTE",13,"VRAM: 76800 BYTES",13,13,0
ModeLabel03: DEFM "MODE 03 OF 09",13,"RESOLUTION: 512x384",13,"COLOR: 8 BPP / INDEXED PALETTE",13,"VRAM: 196608 BYTES",13,13,0
ModeLabel04: DEFM "MODE 04 OF 09",13,"RESOLUTION: 640x200",13,"COLOR: 8 BPP / INDEXED PALETTE",13,"VRAM: 128000 BYTES",13,13,0
ModeLabel05: DEFM "MODE 05 OF 09",13,"RESOLUTION: 640x350",13,"COLOR: 8 BPP / INDEXED PALETTE",13,"VRAM: 224000 BYTES",13,13,0
ModeLabel06: DEFM "MODE 06 OF 09",13,"RESOLUTION: 640x400",13,"COLOR: 8 BPP / INDEXED PALETTE",13,"VRAM: 256000 BYTES",13,13,0
ModeLabel07: DEFM "MODE 07 OF 09",13,"RESOLUTION: 640x480",13,"COLOR: 8 BPP / INDEXED PALETTE",13,"VRAM: 307200 BYTES",13,13,0
ModeLabel08: DEFM "MODE 08 OF 09",13,"RESOLUTION: 800x600",13,"COLOR: 8 BPP / INDEXED PALETTE",13,"VRAM: 480000 BYTES",13,13,0
ModeLabel09: DEFM "MODE 09 OF 09",13,"RESOLUTION: 1024x768",13,"COLOR: 8 BPP / INDEXED PALETTE",13,"VRAM: 786432 BYTES",13,13,0

ColorPattern:
        ; Eight RGB565 colours, each repeated for eight adjacent pixels.
        ; This makes eight visible bars, repeated across the 640-pixel row.
        DB $00,$00, $00,$00, $00,$00, $00,$00, $00,$00, $00,$00, $00,$00, $00,$00
        DB $1F,$00, $1F,$00, $1F,$00, $1F,$00, $1F,$00, $1F,$00, $1F,$00, $1F,$00
        DB $E0,$07, $E0,$07, $E0,$07, $E0,$07, $E0,$07, $E0,$07, $E0,$07, $E0,$07
        DB $FF,$07, $FF,$07, $FF,$07, $FF,$07, $FF,$07, $FF,$07, $FF,$07, $FF,$07
        DB $00,$F8, $00,$F8, $00,$F8, $00,$F8, $00,$F8, $00,$F8, $00,$F8, $00,$F8
        DB $1F,$F8, $1F,$F8, $1F,$F8, $1F,$F8, $1F,$F8, $1F,$F8, $1F,$F8, $1F,$F8
        DB $E0,$FF, $E0,$FF, $E0,$FF, $E0,$FF, $E0,$FF, $E0,$FF, $E0,$FF, $E0,$FF
        DB $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF, $FF,$FF
ColorPatternEnd:

MsgBuild:        DEFM "P137 VGA TEST ATM710",13,10,0
MsgStart:        DEFM "ATM EXTERNAL VGA ADAPTER TEST START",13,10,0
MsgAdapterInit:  DEFM "VGA SOFTWARE MODE ON",13,10,0
MsgModeSet:      DEFM "MODE 640X480 RGB565 SET",13,10,0
MsgFrameWritten: DEFM "VRAM 614400 BYTES WRITTEN",13,10,0
MsgReadbackPass: DEFM "VRAM READBACK PASS",13,10,0
MsgReadbackFail: DEFM "VRAM READBACK FAIL",13,10,0
MsgReady:        DEFM "VGA TEST COMPLETE - CHECK VGA WINDOW",13,10,0
MsgSweepStart:   DEFM "VGA RESOLUTION/PALETTE MATRIX START",13,10,0
MsgModePrefix:   DEFM "MODE ",0
MsgBppSuffix:    DEFM " BPP - INDEXED DAC PALETTE",13,10,0
MsgSweepDone:    DEFM "ALL RESOLUTIONS AND PALETTES DONE",13,10,0
Msg2DStart:       DEFM "2D ENGINE: FILL / BITBLT / LINE",13,10,0
Msg2DPass:        DEFM "2D ENGINE PASS: FILL BITBLT LINE READBACK",13,10,0
Msg2DFail:        DEFM "2D ENGINE COMMAND FAILED",13,10,0
Msg2DReadbackFail: DEFM "2D ENGINE VRAM READBACK FAIL",13,10,0
Msg2DGradientStart: DEFM "2D ENGINE: 256-COLOR GRADIENT START",13,10,0
MsgTextStart: DEFM "VGA TEXT MODE: 80X25 OUTPUT + SCROLL START",13,10,0
MsgTextPass: DEFM "VGA TEXT PASS: SCROLL + 16 COLORS + PLANE READBACK",13,10,0
MsgTextFail: DEFM "VGA TEXT MODE FAIL: OUTPUT OR SCROLL READBACK",13,10,0
TextLine0: DEFM "PROJECT137 - VGA TEXT MODE TEST",0
TextLine1: DEFM "80x25 CHARACTERS / 16 FOREGROUND COLOURS",0
TextLine2: DEFM "PLANE 0 STORES CHARACTER CODES",0
TextLine3: DEFM "PLANE 1 STORES COLOUR ATTRIBUTES",0
TextLine4: DEFM "SCROLL TEST: THIS LINE MOVES UP",0
TextLine5: DEFM "16 FOREGROUND COLORS ON BLUE",0
TextScrollPassed: DEFM "SCROLL COMPLETE - PASS",0
Msg2DGradientPass: DEFM "2D ENGINE PASS: 256-COLOR GRADIENT + READBACK",13,10,0
Msg2DGradientFail: DEFM "2D ENGINE 256-COLOR GRADIENT FAIL",13,10,0
Msg2DGradientVbeDisabled: DEFM "2D GRADIENT ERROR: VBE DISABLED (81)",13,10,0
Msg2DGradientBadRect: DEFM "2D GRADIENT ERROR: INVALID RECTANGLE (82)",13,10,0
Msg2DGradientBadAddress: DEFM "2D GRADIENT ERROR: INVALID VRAM ADDRESS (83)",13,10,0
Msg2DGradientBadCommand: DEFM "2D GRADIENT ERROR: UNSUPPORTED COMMAND (84)",13,10,0
Msg2DGradientUnknownStatus: DEFM "2D GRADIENT ERROR: UNKNOWN STATUS",13,10,0
Msg2DGradientGenericError: DEFM "2D GRADIENT ERROR: GENERIC ERROR (80)",13,10,0
Msg2DGradientZeroStatus: DEFM "2D GRADIENT ERROR: ZERO STATUS (00)",13,10,0
Msg2DGradientUnexpectedDone: DEFM "2D GRADIENT ERROR: STATUS DONE BUT CHECK FAILED (01)",13,10,0
MsgPaletteLevel: DEFM "PALETTE LEVEL ",0
MsgPaletteSuffix: DEFM " (2/4/16/256 COLOR GRADIENT)",13,10,0
MsgPalettePass:  DEFM "DAC READBACK PASS",13,10,0
MsgPaletteFail:  DEFM "DAC READBACK FAIL",13,10,0
; Retained for the standalone legacy DAC routine below (not called by main).
MsgDacStart:     DEFM "256-ENTRY RGB332 DAC PROGRAMMING",13,10,0
MsgDacPass:      DEFM "256-ENTRY DAC READBACK PASS",13,10,0
MsgDacFail:      DEFM "256-ENTRY DAC READBACK FAIL",13,10,0


ScreenTitle:       DEFM "PROJECT137 - VGA ADAPTER TEST",13,13,0
ScreenStarting:    DEFM "STARTING VGA TEST...",13,13,0
ScreenShadowReady: DEFM "ATM SHADOW PORTS OPENED",13,13,0
ScreenModeHeading: DEFM "ACTIVE VGA MODE:",13,13,0
ScreenInitialMode: DEFM "INITIAL TEST 640x480",13,"COLOR: 16 BPP / RGB565",13,13,0
ScreenInitialTestRunning: DEFM "TEST: WRITE FRAMEBUFFER",13,"VRAM: 614400 BYTES",13,0
ScreenTestRunning: DEFM "TEST: WRITE FRAMEBUFFER",13,0
ScreenWriteRunning: DEFM "STATUS: WRITING - PLEASE WAIT",13,13,0
ScreenWritePassed: DEFM "STATUS: WRITE COMPLETE",13,13,0
ScreenNextHint: DEFM "PRESS SPACE FOR NEXT TEST",13,"WAITING FOR SPACE...",0
ScreenAllDone: DEFM "9 RESOLUTIONS x 4 PALETTES",13,13,"TEST COMPLETE",0
Screen2DHeading: DEFM "VGA 2D ACCELERATOR TEST",13,13,0
Screen2DRunning: DEFM "SOLID FILL: 100x60",13,"BITBLT: 100x60",13,"LINE: 0,0 TO 319,199",13,"STATUS: RUNNING",0
Screen2DPassed: DEFM "SOLID FILL: PASS",13,"BITBLT: PASS",13,"LINE: PASS",13,"VRAM READBACK: PASS",13,13,"PRESS SPACE",0
Screen2DGradientHeading: DEFM "VGA 2D 256-COLOR GRADIENT",13,13,0
Screen2DGradientRunning: DEFM "DAC: 256 HUE ENTRIES",13,"2D GRADIENT FILL: ONE COMMAND",13,"FRAMEBUFFER: 320x200x8",13,"STATUS: RUNNING",0
Screen2DGradientPassed: DEFM "2D GRADIENT FILL: PASS",13,"2D GRADIENT COMMAND: 1",13,"VRAM ENDPOINTS: PASS",13,13,"PRESS SPACE",0
Screen2DGradientFailed: DEFM "2D GRADIENT FAILED",13,"CHECK 3E2h / 3E3h",0
ScreenTextHeading: DEFM "VGA 80x25 TEXT MODE",13,13,0
ScreenTextRunning: DEFM "PLANES: CHARACTER + ATTRIBUTE",13,"SCROLL: 1 ROW UP",13,"STATUS: RUNNING",0
ScreenTextPassed: DEFM "TEXT OUTPUT: PASS",13,"SCROLL UP: PASS",13,"16 FOREGROUND COLORS: PASS",13,"PLANE READBACK: PASS",13,13,"PRESS SPACE",0
ScreenTextFailed: DEFM "TEXT MODE / SCROLL FAILED",13,"CHECK VGA PLANAR ACCESS",0
Screen2DFailed: DEFM "2D ACCELERATOR TEST FAILED",13,"CHECK PORTS 3E2h / 3E3h",0
ScreenDacHeading: DEFM "INDEXED VGA PALETTE TEST",13,13,0
ScreenDacWriting: DEFM "PALETTE: 2/4/16/256 COLORS",13,"PATTERN: HORIZONTAL HUE GRADIENT",13,"STATUS: PROGRAMMING + READBACK",0
ScreenDacPassed: DEFM "PALETTE: 256 RGB COLORS",13,"DAC READBACK: PASS (768 BYTES)",0
ScreenDacFailed: DEFM "DAC PALETTE READBACK: FAIL",13,"CHECK PORTS 3C7h / 3C9h",0

DacHuePalette:
        DB $3F,$00,$00,$3F,$01,$00,$3F,$03,$00,$3F,$04,$00,$3F,$06,$00,$3F,$07,$00,$3F,$09,$00,$3F,$0A,$00
        DB $3F,$0C,$00,$3F,$0D,$00,$3F,$0F,$00,$3F,$10,$00,$3F,$12,$00,$3F,$13,$00,$3F,$15,$00,$3F,$16,$00
        DB $3F,$18,$00,$3F,$19,$00,$3F,$1B,$00,$3F,$1C,$00,$3F,$1E,$00,$3F,$1F,$00,$3F,$20,$00,$3F,$22,$00
        DB $3F,$23,$00,$3F,$25,$00,$3F,$26,$00,$3F,$28,$00,$3F,$29,$00,$3F,$2B,$00,$3F,$2C,$00,$3F,$2E,$00
        DB $3F,$2F,$00,$3F,$31,$00,$3F,$32,$00,$3F,$34,$00,$3F,$35,$00,$3F,$37,$00,$3F,$38,$00,$3F,$3A,$00
        DB $3F,$3B,$00,$3F,$3D,$00,$3F,$3E,$00,$3F,$3F,$00,$3D,$3F,$00,$3C,$3F,$00,$3A,$3F,$00,$39,$3F,$00
        DB $37,$3F,$00,$36,$3F,$00,$34,$3F,$00,$33,$3F,$00,$31,$3F,$00,$30,$3F,$00,$2E,$3F,$00,$2D,$3F,$00
        DB $2B,$3F,$00,$2A,$3F,$00,$28,$3F,$00,$27,$3F,$00,$25,$3F,$00,$24,$3F,$00,$22,$3F,$00,$21,$3F,$00
        DB $20,$3F,$00,$1E,$3F,$00,$1D,$3F,$00,$1B,$3F,$00,$1A,$3F,$00,$18,$3F,$00,$17,$3F,$00,$15,$3F,$00
        DB $14,$3F,$00,$12,$3F,$00,$11,$3F,$00,$0F,$3F,$00,$0E,$3F,$00,$0C,$3F,$00,$0B,$3F,$00,$09,$3F,$00
        DB $08,$3F,$00,$06,$3F,$00,$05,$3F,$00,$03,$3F,$00,$02,$3F,$00,$00,$3F,$00,$00,$3F,$01,$00,$3F,$02
        DB $00,$3F,$04,$00,$3F,$05,$00,$3F,$07,$00,$3F,$08,$00,$3F,$0A,$00,$3F,$0B,$00,$3F,$0D,$00,$3F,$0E
        DB $00,$3F,$10,$00,$3F,$11,$00,$3F,$13,$00,$3F,$14,$00,$3F,$16,$00,$3F,$17,$00,$3F,$19,$00,$3F,$1A
        DB $00,$3F,$1C,$00,$3F,$1D,$00,$3F,$1F,$00,$3F,$20,$00,$3F,$21,$00,$3F,$23,$00,$3F,$24,$00,$3F,$26
        DB $00,$3F,$27,$00,$3F,$29,$00,$3F,$2A,$00,$3F,$2C,$00,$3F,$2D,$00,$3F,$2F,$00,$3F,$30,$00,$3F,$32
        DB $00,$3F,$33,$00,$3F,$35,$00,$3F,$36,$00,$3F,$38,$00,$3F,$39,$00,$3F,$3B,$00,$3F,$3C,$00,$3F,$3E
        DB $00,$3F,$3F,$00,$3E,$3F,$00,$3C,$3F,$00,$3B,$3F,$00,$39,$3F,$00,$38,$3F,$00,$36,$3F,$00,$35,$3F
        DB $00,$33,$3F,$00,$32,$3F,$00,$30,$3F,$00,$2F,$3F,$00,$2D,$3F,$00,$2C,$3F,$00,$2A,$3F,$00,$29,$3F
        DB $00,$27,$3F,$00,$26,$3F,$00,$24,$3F,$00,$23,$3F,$00,$21,$3F,$00,$20,$3F,$00,$1F,$3F,$00,$1D,$3F
        DB $00,$1C,$3F,$00,$1A,$3F,$00,$19,$3F,$00,$17,$3F,$00,$16,$3F,$00,$14,$3F,$00,$13,$3F,$00,$11,$3F
        DB $00,$10,$3F,$00,$0E,$3F,$00,$0D,$3F,$00,$0B,$3F,$00,$0A,$3F,$00,$08,$3F,$00,$07,$3F,$00,$05,$3F
        DB $00,$04,$3F,$00,$02,$3F,$00,$01,$3F,$00,$00,$3F,$02,$00,$3F,$03,$00,$3F,$05,$00,$3F,$06,$00,$3F
        DB $08,$00,$3F,$09,$00,$3F,$0B,$00,$3F,$0C,$00,$3F,$0E,$00,$3F,$0F,$00,$3F,$11,$00,$3F,$12,$00,$3F
        DB $14,$00,$3F,$15,$00,$3F,$17,$00,$3F,$18,$00,$3F,$1A,$00,$3F,$1B,$00,$3F,$1D,$00,$3F,$1E,$00,$3F
        DB $20,$00,$3F,$21,$00,$3F,$22,$00,$3F,$24,$00,$3F,$25,$00,$3F,$27,$00,$3F,$28,$00,$3F,$2A,$00,$3F
        DB $2B,$00,$3F,$2D,$00,$3F,$2E,$00,$3F,$30,$00,$3F,$31,$00,$3F,$33,$00,$3F,$34,$00,$3F,$36,$00,$3F
        DB $37,$00,$3F,$39,$00,$3F,$3A,$00,$3F,$3C,$00,$3F,$3D,$00,$3F,$3F,$00,$3F,$3F,$00,$3E,$3F,$00,$3D
        DB $3F,$00,$3B,$3F,$00,$3A,$3F,$00,$38,$3F,$00,$37,$3F,$00,$35,$3F,$00,$34,$3F,$00,$32,$3F,$00,$31
        DB $3F,$00,$2F,$3F,$00,$2E,$3F,$00,$2C,$3F,$00,$2B,$3F,$00,$29,$3F,$00,$28,$3F,$00,$26,$3F,$00,$25
        DB $3F,$00,$23,$3F,$00,$22,$3F,$00,$20,$3F,$00,$1F,$3F,$00,$1E,$3F,$00,$1C,$3F,$00,$1B,$3F,$00,$19
        DB $3F,$00,$18,$3F,$00,$16,$3F,$00,$15,$3F,$00,$13,$3F,$00,$12,$3F,$00,$10,$3F,$00,$0F,$3F,$00,$0D
        DB $3F,$00,$0C,$3F,$00,$0A,$3F,$00,$09,$3F,$00,$07,$3F,$00,$06,$3F,$00,$04,$3F,$00,$03,$3F,$00,$01
DacHuePaletteEnd:

; Exact 768-byte font from Project112/src/font88.bin.
Font88_132:
        DB      $00,$00,$00,$00,$00,$00,$00,$00,$00,$08,$08,$08,$08,$00,$08,$00
        DB      $00,$00,$00,$14,$14,$00,$00,$00,$0C,$14,$3E,$14,$3E,$18,$28,$00
        DB      $08,$3E,$28,$1C,$0A,$3E,$08,$00,$00,$38,$28,$3C,$1E,$0A,$0E,$00
        DB      $00,$0E,$08,$0C,$16,$14,$0E,$00,$00,$00,$00,$08,$08,$00,$00,$00
        DB      $04,$08,$08,$08,$08,$08,$04,$00,$08,$04,$04,$04,$04,$04,$08,$00
        DB      $00,$00,$2A,$1C,$1C,$2A,$00,$00,$00,$08,$08,$3E,$08,$08,$00,$00
        DB      $00,$00,$00,$08,$08,$00,$00,$00,$00,$00,$00,$0C,$00,$00,$00,$00
        DB      $00,$00,$00,$08,$00,$00,$00,$00,$02,$04,$04,$0C,$08,$08,$10,$00
        DB      $00,$0C,$12,$1A,$12,$12,$0C,$00,$00,$18,$08,$08,$08,$08,$1C,$00
        DB      $00,$1C,$02,$02,$04,$08,$1E,$00,$00,$1C,$02,$02,$0C,$02,$1E,$00
        DB      $00,$04,$0C,$0C,$14,$1E,$04,$00,$00,$1E,$10,$1C,$02,$02,$1C,$00
        DB      $00,$0E,$18,$10,$1E,$12,$0E,$00,$00,$1E,$02,$04,$04,$04,$08,$00
        DB      $00,$0C,$12,$12,$0C,$12,$1E,$00,$00,$1C,$12,$1E,$02,$06,$1C,$00
        DB      $00,$00,$08,$00,$00,$08,$00,$00,$00,$08,$00,$00,$08,$08,$00,$00
        DB      $00,$00,$02,$1C,$18,$06,$00,$00,$00,$00,$1E,$00,$1E,$00,$00,$00
        DB      $00,$00,$10,$0E,$06,$18,$00,$00,$00,$1C,$0C,$08,$08,$00,$08,$00
        DB      $00,$0C,$12,$16,$16,$10,$0C,$00,$00,$0C,$0C,$0C,$0C,$1E,$12,$00
        DB      $00,$1C,$12,$12,$1C,$12,$1E,$00,$00,$0E,$10,$10,$10,$10,$0E,$00
        DB      $00,$1C,$12,$12,$12,$12,$1C,$00,$00,$1E,$10,$10,$1E,$10,$1E,$00
        DB      $00,$1E,$10,$10,$1E,$10,$10,$00,$00,$0E,$10,$10,$16,$12,$0E,$00
        DB      $00,$12,$12,$12,$1E,$12,$12,$00,$00,$1C,$08,$08,$08,$08,$1C,$00
        DB      $00,$0C,$04,$04,$04,$04,$1C,$00,$00,$12,$14,$18,$14,$14,$12,$00
        DB      $00,$10,$10,$10,$10,$10,$1E,$00,$00,$12,$1E,$1E,$1E,$12,$12,$00
        DB      $00,$12,$1A,$1A,$16,$16,$12,$00,$00,$0C,$12,$12,$12,$12,$0C,$00
        DB      $00,$1E,$12,$1E,$10,$10,$10,$00,$0C,$12,$12,$12,$12,$0C,$02,$00
        DB      $00,$3C,$24,$38,$2C,$24,$22,$00,$00,$0E,$10,$1C,$06,$02,$1E,$00
        DB      $00,$3E,$08,$08,$08,$08,$08,$00,$00,$12,$12,$12,$12,$12,$0C,$00
        DB      $00,$12,$12,$0C,$0C,$0C,$0C,$00,$00,$22,$22,$2A,$14,$14,$14,$00
        DB      $00,$12,$0C,$0C,$0C,$0C,$12,$00,$00,$22,$14,$08,$08,$08,$08,$00
        DB      $00,$1E,$04,$04,$08,$08,$1E,$00,$0C,$08,$08,$08,$08,$08,$0C,$00
        DB      $10,$08,$08,$0C,$04,$04,$02,$00,$0C,$04,$04,$04,$04,$04,$0C,$00
        DB      $00,$00,$00,$0C,$12,$00,$00,$00,$00,$00,$00,$3E,$00,$00,$00,$00
        DB      $00,$00,$00,$08,$00,$00,$00,$00,$00,$00,$1E,$1E,$12,$1E,$00,$00
        DB      $10,$10,$10,$1C,$12,$12,$1C,$00,$00,$00,$0C,$10,$10,$0C,$00,$00
        DB      $02,$02,$02,$0E,$12,$12,$0E,$00,$00,$00,$0E,$1E,$10,$0E,$00,$00
        DB      $06,$08,$08,$1E,$08,$08,$08,$00,$00,$0E,$12,$12,$0E,$02,$1C,$00
        DB      $10,$10,$10,$1E,$12,$12,$12,$00,$08,$00,$00,$18,$08,$08,$1C,$00
        DB      $04,$00,$00,$0C,$04,$04,$04,$1C,$10,$10,$10,$16,$1C,$1C,$16,$00
        DB      $18,$08,$08,$08,$08,$08,$0E,$00,$00,$00,$3E,$2A,$2A,$2A,$00,$00
        DB      $00,$00,$1E,$12,$12,$12,$00,$00,$00,$00,$0C,$12,$12,$0C,$00,$00
        DB      $00,$1C,$12,$12,$1C,$10,$10,$00,$00,$0E,$12,$12,$0E,$02,$02,$00
        DB      $00,$00,$1C,$10,$10,$10,$00,$00,$00,$00,$1E,$1C,$02,$1E,$00,$00
        DB      $00,$08,$1E,$08,$08,$0E,$00,$00,$00,$00,$12,$12,$12,$1E,$00,$00
        DB      $00,$00,$12,$0C,$0C,$0C,$00,$00,$00,$00,$22,$2A,$1C,$14,$00,$00
        DB      $00,$00,$1E,$0C,$0C,$1E,$00,$00,$00,$12,$0C,$0C,$08,$08,$18,$00
        DB      $00,$00,$1E,$0C,$08,$1E,$00,$00,$0C,$08,$08,$10,$08,$08,$0C,$00
        DB      $08,$08,$08,$08,$08,$08,$08,$08,$18,$08,$08,$04,$08,$08,$18,$00
        DB      $00,$00,$00,$1E,$00,$00,$00,$00,$1E,$12,$12,$12,$12,$12,$1E,$00
ProgramEnd:

; =========================================================================
; TR-DOS BASIC loader. Loads VGATEST.C at 8000h and starts it.
; =========================================================================
        ORG     $B000
CLEAR       EQU $FD
LOAD        EQU $EF
CODE        EQU $AF
REM         EQU $EA
RANDOMIZE   EQU $F9
USR         EQU $C0
OUT_CMD     EQU $DF
VAL         EQU $B0

basic_loader:
        DB      0,10
        DW      l10_len
l10:    DB      OUT_CMD, "239", $0E, $00, $00, $EF, $00, $00, ",", "1", $0E, $00, $00, $01, $00, $00, ":", CLEAR, "32767", $0E, $00, $00, $7F, $FF, $00, $0D
l10_len EQU     $-l10

        DB      0,20
        DW      l20_len
l20:    DB      RANDOMIZE, USR, "15619", $0E, $00, $00
        DW      15619
        DB      0, $3A, REM, $3A, "LOAD ", 34, "VGATEST", 34, " CODE 32768", $0D
l20_len EQU     $-l20

        DB      0,30
        DW      l30_len
l30:    DB      RANDOMIZE, USR, "32768", $0E, $00, $00
        DW      32768
        DB      $0D
l30_len EQU     $-l30

        DB      $80
basic_loader_end:

        SAVETRD "vga_test.TRD","boot.B",basic_loader,basic_loader_end-basic_loader,10
        SAVETRD "vga_test.TRD","VGATEST.C",$8000,ProgramEnd-$8000
