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

        LD      HL,MsgAdapterInit
        CALL    DebugPrint

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

        CALL    VerifyFramebuffer
        OR      A
        JR      NZ,VgaTestFailed

        LD      HL,MsgReadbackPass
        CALL    DebugPrint

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
; framebuffer size. The repeating 00h..FFh pattern exercises all 256
; palette indices. SPACE advances to the next resolution.
; -------------------------------------------------------------------------
RunPackedModeSweep:
        LD      HL,MsgSweepStart
        CALL    DebugPrint
        LD      HL,PackedModeTable
        LD      (ModeTablePtr),HL
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

        LD      A,0
        LD      A,(ModeXLo)
        LD      E,A
        CALL    WriteVgaRegister
        LD      A,1
        LD      A,(ModeXHi)
        LD      E,A
        CALL    WriteVgaRegister
        LD      A,2
        LD      A,(ModeYLo)
        LD      E,A
        CALL    WriteVgaRegister
        LD      A,3
        LD      A,(ModeYHi)
        LD      E,A
        CALL    WriteVgaRegister
        LD      A,4
        LD      A,(ModeBpp)
        LD      E,A
        CALL    WriteVgaRegister
        LD      A,5
        LD      E,1
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
        CALL    PrintMaxColors

        CALL    FillModeVRAM
        CALL    WaitSpace

        LD      A,(ModeCount)
        DEC     A
        LD      (ModeCount),A
        JP      NZ,PackedModeNext
        LD      HL,MsgSweepDone
        CALL    DebugPrint
        RET

; Report the maximum number of distinct pixel values for the active bpp.
; This is the raw packed-pixel capacity: 2^BPP. For 32 bpp this includes
; all 32 stored bits (for example RGBA); RGB-only formats may use 24 bits.
PrintMaxColors:
        LD      A,(ModeBpp)
        CP      8
        JR      Z,PrintColors256
        CP      15
        JR      Z,PrintColors32768
        CP      16
        JR      Z,PrintColors65536
        CP      24
        JR      Z,PrintColors16777216
        CP      32
        JR      Z,PrintColors4294967296
        RET

PrintColors256:
        LD      HL,MsgColors256
        JR      PrintColors
PrintColors32768:
        LD      HL,MsgColors32768
        JR      PrintColors
PrintColors65536:
        LD      HL,MsgColors65536
        JR      PrintColors
PrintColors16777216:
        LD      HL,MsgColors16777216
        JR      PrintColors
PrintColors4294967296:
        LD      HL,MsgColors4294967296
PrintColors:
        CALL    DebugPrint
        RET

; Fill exactly the active 8-bpp framebuffer. Each byte is one
; palette index; the 256-byte pattern exercises indices 00h..FFh.
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


ModeTablePtr: DW 0
ModeCount:    DB 0
ModeXLo:      DB 0
ModeXHi:      DB 0
ModeYLo:      DB 0
ModeYHi:      DB 0
ModeBpp:      DB 0
ModeBankCount: DB 0
ModeLastBankBytes: DW 0

; Full 256-entry indexed-colour sweep. The adapter receives every index
; from 00h through FFh repeatedly across the active framebuffer.
ModePattern8:
        DB 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,143,144,145,146,147,148,149,150,151,152,153,154,155,156,157,158,159,160,161,162,163,164,165,166,167,168,169,170,171,172,173,174,175,176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,192,193,194,195,196,197,198,199,200,201,202,203,204,205,206,207,208,209,210,211,212,213,214,215,216,217,218,219,220,221,222,223,224,225,226,227,228,229,230,231,232,233,234,235,236,237,238,239,240,241,242,243,244,245,246,247,248,249,250,251,252,253,254,255
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
MsgBppSuffix:    DEFM " BPP - 256 COLOR INDEX RAMP",13,10,0
MsgSweepDone:    DEFM "STANDARD VGA MODE SWEEP DONE",13,10,0

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
