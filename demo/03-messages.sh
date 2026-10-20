#!/usr/bin/env bash
# Beat 3: sending messages to a process on another node, and what happens when
# that node dies. Run after 02-dns.sh (needs a fresh BoxOffice on fra1).
#
#   docker compose exec tor1 bin/ticketing remote
#   tor1> fra1 = Ticketing.node(:fra1)
#   tor1> send({BoxOffice, fra1}, {:hold, 2, self()})
#   ...   (then, in another terminal: docker compose kill fra1)
source "$(dirname "$0")/lib/common.sh"

OUT=$CAPTURES/03-messages.txt

remote tor1 <<'IN'
fra1 = Ticketing.node(:fra1)
:erpc.call(fra1, Process, :whereis, [BoxOffice])
send({BoxOffice, fra1}, {:hold, 2, self()})
flush()
GenServer.call({BoxOffice, fra1}, {:hold, 2})
#!run docker compose kill fra1
#!sleep 1
Node.list()
GenServer.call({BoxOffice, fra1}, {:hold, 2})
GenServer.call({BoxOffice, fra1}, {:hold, 2}, 10_000)
try do
  GenServer.call({BoxOffice, fra1}, {:hold, 2})
catch
  :exit, _ -> {:error, :unavailable}
end
IN

header "$OUT" "03-messages: send, call, and a node that isn't there" "demo/03-messages.sh"
section "$OUT" "docker compose exec tor1 bin/ticketing remote" "$WORK/tor1.txt"
cat "$OUT"

# Bring fra1 back for the next beats.
docker compose up -d fra1 >/dev/null 2>&1
wait_for_cluster 4 tor1 fra1
