#!/usr/bin/env bash
# What compose.yaml's header promises, checked from inside the lab's own network and through
# docker exec, which is how the platform's terminal reaches the lab's Python: run by check.sh.
set -euo pipefail
: "${NET:?run through test/check.sh}"
: "${CID:?run through test/check.sh}"
probe() { docker run --rm --network "$NET" lab-check-probe bash -c "$1"; }
run() { docker exec "$CID" "$@"; }
# The chip is a plain simulation with no randomness, so every step prints the same each time.
# Trailing spaces are ignored.
expect() { # expect <name> <a whole line of the output>...
  local out; out=$(run python3 "steps/$1.py" | sed 's/ *$//'); shift
  for want in "$@"; do
    echo "$out" | grep -Fxq -- "$want" || { echo "missing '$want' in: $out" >&2; exit 1; }
  done
}

echo "- JupyterLab answers with no token to type"
probe '
set -eu
code=$(curl -s -o /dev/null -w "%{http_code}" http://jupyter:8888/lab)
[ "$code" = 200 ] || { echo "JupyterLab answered $code" >&2; exit 1; }
curl -fs http://jupyter:8888/api/contents | grep -q "start.ipynb" || { echo "no start.ipynb" >&2; exit 1; }
curl -fs -H "Host: someone-8888.example.com" -H "Origin: https://someone-8888.example.com" \
  http://jupyter:8888/api/kernelspecs | grep -q python3 || { echo "a proxied host is refused" >&2; exit 1; }
echo "- no way out to the internet"
if curl -s -m 4 -o /dev/null https://example.com; then echo "the lab reached the internet" >&2; exit 1; fi
'

echo "- the work folder holds the chip, the notebook and the step scripts"
run ls mcu.py start.ipynb steps/registers.py steps/bits.py steps/pins.py steps/pwm.py \
  steps/poll.py steps/interrupt.py >/dev/null

echo "- registers.py: seven registers, all zero after a reset"
expect registers \
  "registers after reset:" \
  "DDR  0b00000000  0x00    0" \
  "PORT 0b00000000  0x00    0" \
  "PIN  0b00000000  0x00    0" \
  "TCCR 0b00000000  0x00    0" \
  "TCNT 0b00000000  0x00    0" \
  "OCR  0b00000000  0x00    0" \
  "IFR  0b00000000  0x00    0"

echo "- bits.py: set, clear and toggle a bit"
expect bits \
  "start        PORT 0b00001010  0x0A   10" \
  "set bit 0    PORT 0b00001011  0x0B   11" \
  "clear bit 1  PORT 0b00001001  0x09    9" \
  "toggle bit 3 PORT 0b00000001  0x01    1" \
  "toggle again PORT 0b00001001  0x09    9" \
  "low four bits: 1001" \
  "bit 0 is 1"

echo "- pins.py: pin 0 as an output, and a blink of #.#.#.#."
expect pins \
  "pin 0 is an output:" \
  "DDR  0b00000001  0x01    1" \
  "PIN  0b00000001  0x01    1" \
  "#.#.#.#."

echo "- pwm.py: duty cycles of 25, 50 and 75 percent"
expect pwm \
  "compare 4 ####............ on 4 off 12 duty 25 %" \
  "compare 8 ########........ on 8 off 8 duty 50 %" \
  "compare 12 ############.... on 12 off 4 duty 75 %"

echo "- poll.py: one real press, but the polling loop counts 2 (the bounce)"
expect poll \
  "   2    1  yes" \
  "   3    0" \
  "   4    1  yes" \
  "one real press, but the loop counted 2"

echo "- interrupt.py: the handler is called at ticks 2 and 4, and 1 call is kept after the bounce is waited out"
expect interrupt \
  "handler called at tick 2" \
  "handler called at tick 4" \
  "handler calls: 2" \
  "calls kept after waiting out the bounce: 1"

echo "- the starter notebook runs from top to bottom inside the memory limit"
run jupyter nbconvert --to notebook --execute start.ipynb --output /tmp/ran.ipynb >/dev/null 2>&1 \
  || { echo "start.ipynb does not run" >&2; exit 1; }
echo "  ok"
