# Shared helpers for the demo scripts. Sourced, not run.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
CAPTURES=$ROOT/captures
mkdir -p "$CAPTURES"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Same image the release is built on, used for the plain-iex demo.
ELIXIR_IMAGE=hexpm/elixir:1.20.0-erlang-28.5.0.2-debian-trixie-20260610-slim

# console <name> <command...>   (IEx input on stdin)
# Types each stdin line into an interactive session and saves what the screen
# showed to $WORK/<name>.txt.
console() {
  local name=$1
  shift
  cat >"$WORK/$name.in"
  expect "$ROOT/demo/lib/console.exp" "$WORK/$name.raw" "$WORK/$name.in" "$@" >/dev/null
  python3 "$ROOT/demo/lib/clean.py" "$WORK/$name.raw" >"$WORK/$name.txt"
}

# remote <service>   (IEx input on stdin)
# A remote console on a running node, like `docker compose exec tor1 bin/ticketing remote`.
remote() { console "$1" docker compose exec "$1" bin/ticketing remote; }

# shell <name> <command>
# Runs a shell command and records it as "$ command" followed by its output.
shell() {
  { echo "\$ $2"; sh -c "$2" 2>&1; } >>"$WORK/$1.txt"
}

# Wall-clock time with milliseconds, UTC (the containers log in UTC).
now() { python3 -c 'import datetime as d; print(d.datetime.now(d.timezone.utc).strftime("%H:%M:%S.%f")[:-3])'; }
iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Barrier files for syncing parallel sessions.
flag() { echo "$WORK/flag-$1"; }

# Wait until every node logs that it has joined the expected number of peers.
wait_for_cluster() {
  local want=$1
  shift
  for _ in $(seq 1 60); do
    local ok=1
    for svc in "$@"; do
      n=$(docker compose exec -T "$svc" bin/ticketing rpc 'IO.puts(length(Node.list()))' 2>/dev/null || echo 0)
      [ "$n" = "$want" ] || ok=0
    done
    [ $ok = 1 ] && return 0
    sleep 1
  done
  echo "cluster never reached $want peers" >&2
  return 1
}

# header <file> <title> <reproduce...>
header() {
  local file=$1 title=$2
  shift 2
  {
    echo "# $title"
    echo "# Captured $(date -u +%Y-%m-%d) from a real run. Reproduce with:"
    for line in "$@"; do echo "#   $line"; done
    echo
  } >"$file"
}

# section <file> <label> <transcript-file>
section() {
  { echo "=== $2 ==="; cat "$3"; echo; } >>"$1"
}
