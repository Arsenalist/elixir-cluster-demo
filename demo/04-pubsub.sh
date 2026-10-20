#!/usr/bin/env bash
# Beat 4: Phoenix.PubSub across the cluster. Three nodes subscribe, tor1
# broadcasts once, every subscriber gets it. Needs all five nodes up.
#
#   fra1> Phoenix.PubSub.subscribe(Ticketing.PubSub, "shows")
#   tor1> Phoenix.PubSub.broadcast(Ticketing.PubSub, "shows", {:sold_out, 42})
#   fra1> flush()
source "$(dirname "$0")/lib/common.sh"

OUT=$CAPTURES/04-pubsub.txt
subscribers=(fra1 sfo1 lhr1)

for svc in "${subscribers[@]}"; do
  remote "$svc" <<IN &
Phoenix.PubSub.subscribe(Ticketing.PubSub, "shows")
#!touch $(flag "ready-$svc")
#!wait $(flag broadcast)
flush()
IN
done

remote tor1 <<IN
#!wait $(flag ready-fra1)
#!wait $(flag ready-sfo1)
#!wait $(flag ready-lhr1)
Phoenix.PubSub.broadcast(Ticketing.PubSub, "shows", {:sold_out, 42})
#!touch $(flag broadcast)
IN
wait

header "$OUT" "04-pubsub: one broadcast, every subscriber" "demo/04-pubsub.sh"
for svc in "${subscribers[@]}"; do
  section "$OUT" "docker compose exec $svc bin/ticketing remote (subscribe)" "$WORK/$svc.txt"
done
section "$OUT" "docker compose exec tor1 bin/ticketing remote (broadcast)" "$WORK/tor1.txt"
cat "$OUT"
