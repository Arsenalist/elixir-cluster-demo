#!/usr/bin/env bash
# Beat 5: :erpc. Ask every node a question at once, then route work for a show
# to the one node that owns it (rendezvous hashing), so two people racing for
# the last seat from two different regions can't both get it.
# Needs all five nodes up.
#
#   tor1> :erpc.multicall(nodes, Ticketing.Sales, :last_minute, [])
#   tor1> Ticketing.Shows.owner(26)        # same answer on every node
#   tor1> Ticketing.Shows.open(26, ["F12"]) # one seat left
#   tor1> Ticketing.Shows.hold(26, 1)      # at the same time as lhr1
source "$(dirname "$0")/lib/common.sh"

OUT=$CAPTURES/05-erpc.txt
SHOW=26 # owned by sfo1 (ticketing@10.0.1.13) when all five nodes are up

remote lhr1 <<IN &
Ticketing.Shows.owner($SHOW)
#!wait $(flag opened)
#!touch $(flag go)
Ticketing.Shows.hold($SHOW, 1)
IN

remote tor1 <<IN
nodes = Enum.sort([node() | Node.list()])
:erpc.multicall(nodes, Ticketing.Sales, :last_minute, [])
Ticketing.Shows.owner($SHOW)
Ticketing.Shows.open($SHOW, ["F12"])
#!touch $(flag opened)
#!wait $(flag go)
Ticketing.Shows.hold($SHOW, 1)
IN
wait

header "$OUT" "05-erpc: multicall, an owner per show, and the last seat" "demo/05-erpc.sh" \
  "Show $SHOW is owned by sfo1 (ticketing@10.0.1.13) with all five nodes up." \
  "The two holds run at (nearly) the same moment; which side wins varies run to run." \
  "Ticketing.Sales numbers are simulated (fixed per region)."
section "$OUT" "docker compose exec tor1 bin/ticketing remote" "$WORK/tor1.txt"
section "$OUT" "docker compose exec lhr1 bin/ticketing remote" "$WORK/lhr1.txt"
cat "$OUT"
