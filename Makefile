# fixwval — build / test / demo via GnuCOBOL (cobc)
COBC    ?= cobc
COBFLAGS = -x -free
PREFIX  ?= /usr/local

BINS = fixwval fwmode

.PHONY: all build test demo install clean

all: build

build: $(BINS)

fixwval: fixwval.cob
	$(COBC) $(COBFLAGS) -o $@ $<

fwmode: fwmode.cob
	$(COBC) $(COBFLAGS) -o $@ $<

test: build
	bash tests/run.sh

demo: build
	bash demos/run_all.sh

install: build
	mkdir -p $(PREFIX)/bin
	cp fixwval $(PREFIX)/bin/fixwval
	cp fwmode  $(PREFIX)/bin/fwmode

clean:
	rm -f $(BINS) *.o a.out
