
BIN := bitline
SRC_MAIN := src/main.nim
SRC_ALL := $(wildcard src/*.nim)

all: $(BIN)

$(BIN): $(SRC_ALL) Makefile
	nim c -d:nimDebugDlOpen -d:danger --debugger:native -o:$(BIN) $(SRC_MAIN)

release: $(BIN)
	strip $(BIN)
	scp $(BIN) ico@mdoos:~/div

clean:
	rm -f $(BIN)
