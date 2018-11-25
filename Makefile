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

all: sram_up

lynx_code.o: lynx_code.S sram.o

sram_up: sram_up.o lynx_code.o
	$(CC)  -s $< lynx_code.o -o $@

clean:
	rm -f *.o
	rm -f *~
