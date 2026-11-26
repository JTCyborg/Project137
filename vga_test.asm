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

        CALL    SpectrumShowInitialMode

        ; 3DEh: software mode = 1, aperture enable = 1, bank 0.
        LD      BC,$03DE
        LD      A,$03
        OUT     (C),A

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

        CALL    RunPackedModeSweep
        CALL    RunDac256Test

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
        LD      A,(ModeBpp)
        LD      E,A
        LD      A,4
        CALL    WriteVgaRegister
        LD      E,1
        LD      A,5
        CALL    WriteVgaRegister

        LD      HL,MsgModePrefix
        CALL    DebugPrint
        LD      A,(ModeXHi)
        CALL    DebugHexByte
        LD      A,(ModeXLo)
        CALL    DebugHexByte
        LD      A,'x'
        OUT     ($EF),A
        LD      A,(ModeYHi)
        CALL    DebugHexByte
        LD      A,(ModeYLo)
        CALL    DebugHexByte
        LD      A,' '
        OUT     ($EF),A
        LD      A,(ModeBpp)
        CALL    DebugHexByte
        LD      HL,MsgBppSuffix
        CALL    DebugPrint

        CALL    SpectrumShowMode
        CALL    FillModeVRAM
        CALL    SpectrumShowWriteComplete
        CALL    WaitSpace

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

; Fill exactly the active 8-bpp framebuffer. Each byte is one palette
; index; use only initialized EGA palette entries 0..7.
; Only banks containing visible pixels are touched.
FillModeVRAM:
        XOR     A
        LD      (CurrentBank),A
ModeFillBank:
        LD      A,(CurrentBank)
        LD      BC,$03DF
        OUT     (C),A
        LD      HL,$C000
        LD      DE,ModePattern8
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
        LD      A,(DE)
        INC     DE
        LD      (HL),A
        INC     HL
        LD      A,D
        CP      HIGH ModePattern8End
        JR      NZ,ModePatternReady
        LD      A,E
        CP      LOW ModePattern8End
        JR      NZ,ModePatternReady
        LD      DE,ModePattern8
ModePatternReady:
        DEC     BC
        LD      A,B
        OR      C
        JR      NZ,ModeFillByte
        LD      A,(CurrentBank)
        INC     A
        LD      (CurrentBank),A
        LD      B,A
        LD      A,(ModeBankCount)
        CP      B
        JR      NZ,ModeFillBank
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
        LD      HL,Dac332Palette
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
        LD      HL,Dac332Palette
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


; Text shown on the Spectrum screen for each VGA mode.
ModeLabelTable:
        DW ModeLabel01,ModeLabel02,ModeLabel03,ModeLabel04,ModeLabel05
        DW ModeLabel06,ModeLabel07,ModeLabel08,ModeLabel09
ModeLabel01: DEFM "MODE 01 OF 09",13,"RESOLUTION: 320x200",13,"COLOR: 8 BPP / 16 EGA COLORS",13,"VRAM: 64000 BYTES",13,13,0
ModeLabel02: DEFM "MODE 02 OF 09",13,"RESOLUTION: 320x240",13,"COLOR: 8 BPP / 8 EGA COLORS",13,"VRAM: 76800 BYTES",13,13,0
ModeLabel03: DEFM "MODE 03 OF 09",13,"RESOLUTION: 512x384",13,"COLOR: 8 BPP / 8 EGA COLORS",13,"VRAM: 196608 BYTES",13,13,0
ModeLabel04: DEFM "MODE 04 OF 09",13,"RESOLUTION: 640x200",13,"COLOR: 8 BPP / 8 EGA COLORS",13,"VRAM: 128000 BYTES",13,13,0
ModeLabel05: DEFM "MODE 05 OF 09",13,"RESOLUTION: 640x350",13,"COLOR: 8 BPP / 8 EGA COLORS",13,"VRAM: 224000 BYTES",13,13,0
ModeLabel06: DEFM "MODE 06 OF 09",13,"RESOLUTION: 640x400",13,"COLOR: 8 BPP / 8 EGA COLORS",13,"VRAM: 256000 BYTES",13,13,0
ModeLabel07: DEFM "MODE 07 OF 09",13,"RESOLUTION: 640x480",13,"COLOR: 8 BPP / 8 EGA COLORS",13,"VRAM: 307200 BYTES",13,13,0
ModeLabel08: DEFM "MODE 08 OF 09",13,"RESOLUTION: 800x600",13,"COLOR: 8 BPP / 8 EGA COLORS",13,"VRAM: 480000 BYTES",13,13,0
ModeLabel09: DEFM "MODE 09 OF 09",13,"RESOLUTION: 1024x768",13,"COLOR: 8 BPP / 8 EGA COLORS",13,"VRAM: 786432 BYTES",13,13,0

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
MsgSweepStart:   DEFM "STANDARD VGA MODE SWEEP START",13,10,0
MsgModePrefix:   DEFM "MODE ",0
MsgBppSuffix:    DEFM " BPP - 8 EGA COLOR PATTERN",13,10,0
MsgSweepDone:    DEFM "STANDARD VGA MODE SWEEP DONE",13,10,0
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
ScreenNextHint: DEFM "PRESS SPACE FOR NEXT MODE",13,"WAITING FOR SPACE...",0
ScreenAllDone: DEFM "ALL 9 VGA MODES + 256 DAC",13,13,"TEST COMPLETE",0
ScreenDacHeading: DEFM "256-COLOR VGA DAC TEST",13,13,0
ScreenDacWriting: DEFM "PALETTE: RGB332 / 256 ENTRIES",13,"FRAMEBUFFER: 320x200 / 8 BPP",13,"STATUS: PROGRAMMING + READBACK",0
ScreenDacPassed: DEFM "PALETTE: 256 RGB COLORS",13,"DAC READBACK: PASS (768 BYTES)",0
ScreenDacFailed: DEFM "DAC READBACK: FAIL",13,"CHECK PORTS 3C7h / 3C9h",0

Dac332Palette:
        DB $00,$00,$00,$00,$00,$15,$00,$00,$2A,$00,$00,$3F,$00,$09,$00,$00
        DB $09,$15,$00,$09,$2A,$00,$09,$3F,$00,$12,$00,$00,$12,$15,$00,$12
        DB $2A,$00,$12,$3F,$00,$1B,$00,$00,$1B,$15,$00,$1B,$2A,$00,$1B,$3F
        DB $00,$24,$00,$00,$24,$15,$00,$24,$2A,$00,$24,$3F,$00,$2D,$00,$00
        DB $2D,$15,$00,$2D,$2A,$00,$2D,$3F,$00,$36,$00,$00,$36,$15,$00,$36
        DB $2A,$00,$36,$3F,$00,$3F,$00,$00,$3F,$15,$00,$3F,$2A,$00,$3F,$3F
        DB $09,$00,$00,$09,$00,$15,$09,$00,$2A,$09,$00,$3F,$09,$09,$00,$09
        DB $09,$15,$09,$09,$2A,$09,$09,$3F,$09,$12,$00,$09,$12,$15,$09,$12
        DB $2A,$09,$12,$3F,$09,$1B,$00,$09,$1B,$15,$09,$1B,$2A,$09,$1B,$3F
        DB $09,$24,$00,$09,$24,$15,$09,$24,$2A,$09,$24,$3F,$09,$2D,$00,$09
        DB $2D,$15,$09,$2D,$2A,$09,$2D,$3F,$09,$36,$00,$09,$36,$15,$09,$36
        DB $2A,$09,$36,$3F,$09,$3F,$00,$09,$3F,$15,$09,$3F,$2A,$09,$3F,$3F
        DB $12,$00,$00,$12,$00,$15,$12,$00,$2A,$12,$00,$3F,$12,$09,$00,$12
        DB $09,$15,$12,$09,$2A,$12,$09,$3F,$12,$12,$00,$12,$12,$15,$12,$12
        DB $2A,$12,$12,$3F,$12,$1B,$00,$12,$1B,$15,$12,$1B,$2A,$12,$1B,$3F
        DB $12,$24,$00,$12,$24,$15,$12,$24,$2A,$12,$24,$3F,$12,$2D,$00,$12
        DB $2D,$15,$12,$2D,$2A,$12,$2D,$3F,$12,$36,$00,$12,$36,$15,$12,$36
        DB $2A,$12,$36,$3F,$12,$3F,$00,$12,$3F,$15,$12,$3F,$2A,$12,$3F,$3F
        DB $1B,$00,$00,$1B,$00,$15,$1B,$00,$2A,$1B,$00,$3F,$1B,$09,$00,$1B
        DB $09,$15,$1B,$09,$2A,$1B,$09,$3F,$1B,$12,$00,$1B,$12,$15,$1B,$12
        DB $2A,$1B,$12,$3F,$1B,$1B,$00,$1B,$1B,$15,$1B,$1B,$2A,$1B,$1B,$3F
        DB $1B,$24,$00,$1B,$24,$15,$1B,$24,$2A,$1B,$24,$3F,$1B,$2D,$00,$1B
        DB $2D,$15,$1B,$2D,$2A,$1B,$2D,$3F,$1B,$36,$00,$1B,$36,$15,$1B,$36
        DB $2A,$1B,$36,$3F,$1B,$3F,$00,$1B,$3F,$15,$1B,$3F,$2A,$1B,$3F,$3F
        DB $24,$00,$00,$24,$00,$15,$24,$00,$2A,$24,$00,$3F,$24,$09,$00,$24
        DB $09,$15,$24,$09,$2A,$24,$09,$3F,$24,$12,$00,$24,$12,$15,$24,$12
        DB $2A,$24,$12,$3F,$24,$1B,$00,$24,$1B,$15,$24,$1B,$2A,$24,$1B,$3F
        DB $24,$24,$00,$24,$24,$15,$24,$24,$2A,$24,$24,$3F,$24,$2D,$00,$24
        DB $2D,$15,$24,$2D,$2A,$24,$2D,$3F,$24,$36,$00,$24,$36,$15,$24,$36
        DB $2A,$24,$36,$3F,$24,$3F,$00,$24,$3F,$15,$24,$3F,$2A,$24,$3F,$3F
        DB $2D,$00,$00,$2D,$00,$15,$2D,$00,$2A,$2D,$00,$3F,$2D,$09,$00,$2D
        DB $09,$15,$2D,$09,$2A,$2D,$09,$3F,$2D,$12,$00,$2D,$12,$15,$2D,$12
        DB $2A,$2D,$12,$3F,$2D,$1B,$00,$2D,$1B,$15,$2D,$1B,$2A,$2D,$1B,$3F
        DB $2D,$24,$00,$2D,$24,$15,$2D,$24,$2A,$2D,$24,$3F,$2D,$2D,$00,$2D
        DB $2D,$15,$2D,$2D,$2A,$2D,$2D,$3F,$2D,$36,$00,$2D,$36,$15,$2D,$36
        DB $2A,$2D,$36,$3F,$2D,$3F,$00,$2D,$3F,$15,$2D,$3F,$2A,$2D,$3F,$3F
        DB $36,$00,$00,$36,$00,$15,$36,$00,$2A,$36,$00,$3F,$36,$09,$00,$36
        DB $09,$15,$36,$09,$2A,$36,$09,$3F,$36,$12,$00,$36,$12,$15,$36,$12
        DB $2A,$36,$12,$3F,$36,$1B,$00,$36,$1B,$15,$36,$1B,$2A,$36,$1B,$3F
        DB $36,$24,$00,$36,$24,$15,$36,$24,$2A,$36,$24,$3F,$36,$2D,$00,$36
        DB $2D,$15,$36,$2D,$2A,$36,$2D,$3F,$36,$36,$00,$36,$36,$15,$36,$36
        DB $2A,$36,$36,$3F,$36,$3F,$00,$36,$3F,$15,$36,$3F,$2A,$36,$3F,$3F
        DB $3F,$00,$00,$3F,$00,$15,$3F,$00,$2A,$3F,$00,$3F,$3F,$09,$00,$3F
        DB $09,$15,$3F,$09,$2A,$3F,$09,$3F,$3F,$12,$00,$3F,$12,$15,$3F,$12
        DB $2A,$3F,$12,$3F,$3F,$1B,$00,$3F,$1B,$15,$3F,$1B,$2A,$3F,$1B,$3F
        DB $3F,$24,$00,$3F,$24,$15,$3F,$24,$2A,$3F,$24,$3F,$3F,$2D,$00,$3F
        DB $2D,$15,$3F,$2D,$2A,$3F,$2D,$3F,$3F,$36,$00,$3F,$36,$15,$3F,$36
        DB $2A,$3F,$36,$3F,$3F,$3F,$00,$3F,$3F,$15,$3F,$3F,$2A,$3F,$3F,$3F
Dac332PaletteEnd:

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
