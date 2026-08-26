#!/usr/bin/env bash
# Direktan gcc build + run za test_logic, bez oslanjanja na `make`
# (na ovoj masini `make` puca sa "Cannot create temporary file in C:\WINDOWS\").
# Radi iz bilo kog radnog direktorijuma -- putanje su relativne na lokaciju skripte.
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CC="${CC:-gcc}"
CFLAGS="${CFLAGS:--std=c99 -Wall -Wextra -Werror -O1}"

OUT="$DIR/test_logic"
"$CC" $CFLAGS -o "$OUT" "$DIR/test_logic.c" "$DIR/../app/ncc_logic.c"
BUILD_STATUS=$?
if [ $BUILD_STATUS -ne 0 ]; then
    exit $BUILD_STATUS
fi

"$OUT"
exit $?
