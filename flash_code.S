	.text
	.globl sram_lynx
	.globl _sram_lynx
	.align 4
sram_lynx:
_sram_lynx:
	.incbin "flashcard.o"
