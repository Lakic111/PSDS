CC     ?= gcc
CFLAGS ?= -std=c99 -Wall -Wextra -Werror -O1

test_logic: test_logic.c ../app/ncc_logic.c ../app/ncc_logic.h
	$(CC) $(CFLAGS) -o $@ test_logic.c ../app/ncc_logic.c

.PHONY: run clean
run: test_logic
	./test_logic

clean:
	rm -f test_logic test_logic.exe
