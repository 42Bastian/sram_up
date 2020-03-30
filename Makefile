CFLAGS=-Os -fomit-frame-pointer

.SUFFIXES: .asc .obj .S .asm

%.o: %.asm
	lyxass  $<

.obj.asc:
	bin2asc < $*.obj >$@

.c.o:
	$(CC) $(CFLAGS) -c $<
.S.o:
	$(CC) -c $< -o $@

all: sram_up flash_up

lynx_code.o: lynx_code.S sram.o

flash_code.o: flash_code.S flashcard.o

sram_up: sram_up.o lynx_code.o
	$(CC)  -s $< lynx_code.o -o $@

flash_up: flash_up.o flash_code.o
	$(CC)  -s $< flash_code.o -o $@

clean:
	rm -f *.o
	rm -f *~
