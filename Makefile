
BIN := bitline
SRC_MAIN := src/main.nim
SRC_ALL := $(wildcard src/*.nim)

all: $(BIN)

$(BIN): $(SRC_ALL) Makefile
	nim c -d:danger --gc:arc --debugger:native -o:$(BIN) $(SRC_MAIN)

clean:
	rm -f $(BIN)
