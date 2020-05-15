***************
* FLASH.ASM
* flash-ROM writer
*
* created : 31.08.96
*
****************

VERSION	equ "08"
Baudrate	EQU 62500
;;->BRKuser	    set 1
DEBUG	set 1

INFO_Y	EQU 40

	include <includes\hardware.inc>	   ; get hardware-names
****************
* macros       *
	include <macros\help.mac>
	include <macros\if_while.mac>
	include <macros\font.mac>
	include <macros\window.mac>
	include <macros\mikey.mac>
	include <macros\suzy.mac>
	include <macros\irq.mac>
	include <macros\debug.mac>
****************
* variables    *
	include <vardefs\debug.var>
	include <vardefs\help.var>
	include <vardefs\font.var>
	include <vardefs\window.var>
	include <vardefs\mikey.var>
	include <vardefs\suzy.var>
	include <vardefs\irq.var>
****************

 BEGIN_ZP
BlockCounter	ds 1
p_puffer	ds 2
check	ds 1
retries	ds 1
delayCount	ds 1
VBLcount	ds 1
seconds	ds 1
state	ds 1
 END_ZP

 BEGIN_ZP
_BG_Color	 ds 1
_FG_Color	 ds 1
_Invers	 ds 1	 ; $FF => inverted
_CurrX	 ds 1	 ; cursor X(0..79)
_CurrY	 ds 1	 ; cursor Y(0..16)
_TxtPtr	 ds 2
 END_ZP


 BEGIN_MEM
	ALIGN 4
screen0
	ds SCREEN.LEN

	ALIGN 256
puffer::
	ds 2048
crctab	ds 256
irq_vektoren
	ds 16

 END_MEM
	run LOMEM	; code directly after variables
****************
*     INIT     *
Start::
	START_UP	; Start-Label needed for reStart
	CLEAR_MEM
	CLEAR_ZP

	INITMIKEY
	INITSUZY

	SETRGB pal
	stz $fda1
	stz $fdb1
	stz $fdae
	INITIRQ irq_vektoren
	INITBRK
	SETIRQ 2,VBL
	SCRBASE screen0
	SET_MINMAX 0,0,160,102
	jsr InitCRC
IFD DEBUG
	jsr InstallLoader
ENDIF

contrl		equ %00011101	; even par
prescale	set 125000/Baudrate-1

IF prescale<256
	lda #prescale
	sta $fd10
	lda #%00011000
ELSE
	lda #prescale/2
	sta $fd10
	lda #%00011001
ENDIF
	sta $fd11
	lda #contrl|8
	sta $fd8c
.0
	bit $fd8c
	bvc .1
	lda $fd8d
	bra .0		; clear buffer
.1
****************
* CommandLoop  *
****************
MAX_COMMAND	EQU 7
sss:
	cli
clearScreen::
	CLS #1
	lda #CENTER_ADJUST
	sta CurrAjust
	INITFONT SMALLFNT,1,WHITE
	PRINT {"SRAM-Writer Ver. ",>VERSION,".",<VERSION,13},,1
	INITFONT LITTLEFNT
	PRINT {"Hardware/Idea: L.Baumstark",13},,1
	PRINT {"Software : B.Schick",13},,1
	INITFONT SMALLFNT
	lda #17
	sta CurrY
	lda #$E
	sta FG_Color
	stz BG_Color
	PRINT {"________________________",13},,1
	stz CurrAjust
	inc BG_Color
	lda #LIGHTBLUE
	sta FG_Color

	INITFONT LITTLEFNT
 if 0
	stz CurrX
	stz CurrY
	stz BlockCounter
	jsr SelectBlock
	ldx #0
.1	lda $FCb2
	jsr PrintHex
	inx
	bne .1
endif
CommandLoop::
.1
	stz state
.2
	jsr WaitSerialDebug
	bcs .99
	cmp #"C"
	bne .3
	sta state
	bra .2
.3
	ldx state
	beq .2
	sec
	sbc #"0"
	bmi .1
	cmp #MAX_COMMAND+1
	bge .1
	asl
	tax
	jsr doit
	bra CommandLoop
.99
	jmp clearScreen

doit
	jmp (commands,x)
dummy
	rts

commands
	dc.w SendCRCs	      ; "0"
	dc.w Write1Block      ; "1" write single block
	dc.w WriteFlash	      ; "2" write whole SRAM
	dc.w Hello	      ; "3" check if we`re already installed
	dc.w Read1Block	      ; "4" read block
	dc.w Clear1Block      ; "5" zero a block
	dc.w ReadPuffer	      ; "6" read last buffer

_CARD0 equ $FCB2
_CARD1 equ $FCB3

****************
* Hello
****************
Hello::
	lda #"6"		; why "6" ??
	jmp SendSerial
****************
* SendCRCs     *
***************
SendCRCs::
	stz BlockCounter
.0
	jsr SelectBlock
	lda size
	sta temp
	lda #0
	tay
.1
	  eor _CARD0
	  tax
	  lda crctab,x
	  sty $fdae
	  iny
	  bne .1
	  dec temp
	bne .1
	jsr SendSerial
	inc BlockCounter
	bne .0
	stz $fdae
	rts
****************
* Clear1Block  *
****************
Clear1Block::
	jsr WaitSerial	; get block #
	bcs .99	; got a break
	sta BlockCounter
	jsr WaitSerial	; get pattern
	bcs .99	; got a break
	pha
	jsr InfoClear
	pla
	jsr ClearBlock
	lda #$43
	jsr SendSerial
	clc
.99
	rts
****************
* ReadPuffer   *
****************
ReadPuffer:
	ldy #0
.1
	lda puffer,y
	jsr SendSerial
	iny
	bne .1
.2
	lda puffer+$100,y
	jsr SendSerial
	iny
	bne .2
.3
	lda puffer+$200,y
	jsr SendSerial
	iny
	bne .3
.4
	lda puffer+$300,y
	jsr SendSerial
	iny
	bne .4
	rts


****************
* Read1Block	*
****************
Read1Block::
        jsr WaitSerial  ; get blocksize
        bcs .99         ; got a break
	sta size
	jsr WaitSerial		; get block #
	bcs .99			; got a break
	sta BlockCounter
	jsr InfoRead		; print info
	jsr ReadBlock
	clc
.99
	rts
****************
* Write1Block  *
****************
Write1Block::
        jsr WaitSerial  ; get blocksize in 256byte chunks
        bcs .99         ; got a break
	sta size
	jsr WaitSerial		; get block #
	bcs .99			; got a break

Write1Block_wf
	sta BlockCounter
	jsr InfoLoad		; print info
	jsr LoadBlock
	bcs .99
	bra .1
.0
	lda #$24
	jsr SendSerial
	jsr WriteBlock
.1
        jsr CheckBlock
	bcc .0
	lda #$42
	jsr SendSerial
	clc
.99
	rts
****************
*  WriteFlash  *
* main-loop  *
WriteFlash::
	lda size
	jsr InfoSize
	stz BlockCounter
	lda #0+20
.0
	jsr Write1Block_wf
	bcs .99		; break
	lda BlockCounter
	inc
	bne .0
.6
	inc $fda0
	bra .6
.99
	rts
****************
*  ClearFlash  *
ClearFlash::
	stz BlockCounter
.0
	jsr SelectBlock
	ldx #4
	ldy #0
	lda #$ff
.1
	      sta _CARD1
	inc $fdb0
	iny
	bne .1
	dex
	bne .1
	inc BlockCounter
	bne .0
	stz $fdb0
	rts
****************
*  ClearBlock	*
****************
ClearBlock::
	jsr SelectBlock
	ldy size
	sty temp
	ldy #0
.1
	    sta _CARD1
	    sty $fdae
	    iny
	  bne .1
	  dec temp
	bne .1
	stz $fdae
	rts
****************
*  ReadBlock   *
****************
ReadBlock::
	jsr SelectBlock
	lda size
	sta temp
	ldy #0
.1
	    lda _CARD0
	    jsr SendSerial
	    sty $fdae
	    iny
	  bne .1
	  dec temp
	bne .1
	stz $fdae
	sec
	rts
****************
*  LoadBlock   *
LoadBlock::
	jsr SelectBlock
	sei

	MOVEI puffer,p_puffer
	lda size
	sta temp
	ldy #0
	stz check
.2	  lda $fcb0
	  bne .99
	  bit $fd8c
	  bvc .2

	  lda $fd8d
	  sta (p_puffer),y
	  sty $fdae
	  sta _CARD1

	  eor check
	  tax
	  lda crctab,x
	  sta check
	  iny
	bne .2
	inc p_puffer+1
	dec temp
	bne .2

.98
	cli
	stz $fdae
	jsr WaitSerial
	bcs .99
	cmp check
	beq .9

	lda check
	stz CurrX
	stz CurrY
	jsr _PrintHex
	inc retries
	lda retries
	jsr _PrintHex

	lda #$14		; ko
	jsr SendSerial
	bra LoadBlock		       ; load again

.9
	lda #$41
	jsr SendSerial		; ok
	clc
	rts

.99
	sec
	cli
	rts

****************
*  WriteBlock  *
WriteBlock::
	jsr SelectBlock
	lda size
	sta temp
	stz check
	ldy #0
.1	  lda puffer,y
	  sta _CARD1
	  eor check
	  tax
	  lda crctab,x
	  sta check
	  sty $fdae
	  iny
	bne .1
	dec temp
	beq .99
.2	  lda puffer+$100,y
	  sta _CARD1
	  eor check
	  tax
	  lda crctab,x
	  sta check
	  sty $fdae
	  iny
	bne .2
	dec temp
	beq .99
.3	  lda puffer+$200,y
	  sta _CARD1
	  eor check
	  tax
	  lda crctab,x
	  sta check
	  sty $fdae
	  iny
	bne .3
	dec temp
	beq .99
.4	  lda puffer+$300,y
	  sta _CARD1
	  eor check
	  tax
	  lda crctab,x
	  sta check
	  sty $fdae
	  iny
	bne .4
.99
	stz $fdae
	rts
****************
*  CheckBlock  *
* OUT: C = 1 => ok
*      C = 0 => ko
CheckBlock::
	jsr SelectBlock
	lda size
	lsr
	tax
	clc
	ldy #0
.1	  lda _CARD0
	  cmp puffer,y
	  bne .99
	  sty $fdae
	  iny
	bne .1

.2	  lda _CARD0
	  cmp puffer+$100,y
	  bne .99
	  sty $fdae
	  iny
	bne .2

	dex
	beq .98
.3	  lda _CARD0
	  cmp puffer+$200,y
	  bne .99
	  sty $fdae
	  iny
	bne .3

.4	  lda _CARD0
	  cmp puffer+$300,y
	  bne .99
	  sty $fdae
	  iny
	bne .4
.98
	sec
	stz $fdae
	rts

.99
	stz $fdae
	clc
	rts

;;->	lda size
;;->	    sta temp
;;->	    ldy #0
;;->	     tya
;;->.1		eor _CARD0
;;->		tax
;;->		lda crctab,x
;;->		sty $fdae
;;->		iny
;;->	      bne .1
;;->	      dec temp
;;->	    bne .1
;;->	    cmp check
;;->	    bne .9
;;->	    sec
;;->	    rts
;;->.9	    clc
;;->	    rts
****************
*  InfoSize    *
InfoSize::
	pha
	SET_XY 0,INFO_Y-10
	PRINT "Cardsize :",,1
	plx
	lda .1-2,x
	ldy .1-1,x
	jmp print
.1
	dc.w _128,_256,_512

_128	dc.b "128KB",0
_256	dc.b "256KB",0
_512	dc.b "512KB",0
****************
*  InfoClear	*
InfoClear::
	pha
	SET_XY 0,INFO_Y
	PRINT "Clearing block :	 ",,1
	SET_XY 110,INFO_Y
	lda BlockCounter
	jsr PrintHex
	PRINT " : ",,1
	pla
	jmp PrintHex

****************
*  InfoRead    *
InfoRead::
	pha
	SET_XY 0,INFO_Y
	PRINT "Reading block :	",,1
	SET_XY 110,INFO_Y
	pla
	jmp PrintHex
****************
*  InfoLoad    *
InfoLoad::
	pha
	SET_XY 0,INFO_Y
	PRINT "Loading block :	",,1
	SET_XY 110,INFO_Y
	pla
	bra PrintHex
****************
* InfoWriteOdd *
InfoWrite::
	SET_XY 0,INFO_Y
	LDAY Test
	jsr print
	rts
Test	dc.b  "Writing block :",0
****************
*   InfoCheck  *
InfoCheck::
	SET_XY 0,INFO_Y
	PRINT "Checking block :	     ",,1
	rts
****************
*   PrintHex   *
PrintHex::
_PrintHex::
	phx
	pha
	pha
	lsr
	lsr
	lsr
	lsr
	tax
	lda digits,x
	jsr PrintChar
	pla
	and #$f
	tax
	lda digits,x
	jsr PrintChar
	pla
	plx
	rts
digits	db "0123456789ABCDEF"
****************
*     VBL      *
VBL::
	lda delayCount
	beq .1
	inc $fdb0
	dec delayCount
.1
	dec VBLcount
	bpl .2
	lda #59
	sta VBLcount
	inc seconds
.2
//->	lda $fcb1
//->	    lsr
//->	    bcs .3
	END_IRQ
.3
	jmp Start

****************
*  SendSerial  *
SendSerial::
	bit $fd8c
	bpl SendSerial
	sta $fd8d	; send byte
.1
	lda #$20
	bit $fd8c
	beq .1
	lda $fd8d	; get echo

	rts

WaitSerial::
	sec
	inc $fda1
	lda $fcb0	; break it with any key
	bne .99
	bit $fd8c
	bvc WaitSerial
	lda $fd8d
	clc
.99
	stz $fda1
	rts

WaitSerialDebug::
	sec
//->	    inc $fda1
	lda $fcb0	; break it with any key
	bne .99
	bit $fd8c
	bvc WaitSerialDebug
	lda $fd8d
 IFD DEBUG
	jsr do_debug
	bcc WaitSerialDebug
 ENDIF
	clc
.99
	stz $fda1
	rts
****************
* InitCRC      *
****************
InitCRC:
	ldx #0
.0
	ldy #7
	txa
.crc1
	asl
	bcc .2
	eor #$95
.2
	dey
	bpl .crc1
	sta crctab,x
	dex
	bne .0
	rts
****************
* Select a block
****************
SelectBlockA::
	sta	BlockCounter
SelectBlock::
	pha
	phx
	phy
	lda _IOdat
	and #$fC
	tay
	ora #2
	tax
	lda BlockCounter
	SEC
	BRA SBL2
SLB0
	BCC SLB1
	STX $FD8B
	CLC
SLB1
	INX
	STX $FD87
	DEX
SBL2
	STX $FD87
	ROL
	STY $FD8B
	BNE SLB0

	lda _IOdat
	sta $fd8b
	ply
	plx
	pla
.exit
	RTS
****************
* INCLUDES
	include <includes\debug.inc>
	include <includes\window2.inc>
	include <includes\font.inc>
	include <includes\irq.inc>
	include <includes\font2.hlp>
****************
cls2::
	sta cls_color
	LDAY clsSCB
	jmp DrawSprite

clsSCB
	dc.b $c0,$90,$00
	dc.w 0,cls_data
	dc.w 0,30
	dc.w 160*$100,72*$100
cls_color
	dc.b 00

cls_data
	dc.b 2,$10,0

size	dc.b 8	; 1K blocks
pal	STANDARD_PAL
