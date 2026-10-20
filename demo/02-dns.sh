#!/usr/bin/env bash
# Beat 2: nodes find each other through DNS (DNSCluster), then two more join.
#
#   docker compose up -d                 # tor1, fra1, sfo1
#   docker compose logs tor1 fra1 sfo1
#   docker compose up -d lhr1 sin1       # two more regions
source "$(dirname "$0")/lib/common.sh"

OUT=$CAPTURES/02-dns.txt
docker compose --profile more down >/dev/null 2>&1

shell up "docker compose up -d"
wait_for_cluster 2 tor1 fra1 sfo1
for svc in tor1 fra1 sfo1; do shell "logs-$svc" "docker compose logs --no-color $svc"; done

shell dns "docker compose exec tor1 getent ahostsv4 ticketing | awk '{print \$1}' | sort -u"
shell dns "docker compose exec tor1 dig +short ticketing"

since=$(iso_now)
sleep 1
shell more "docker compose up -d lhr1 sin1"
wait_for_cluster 4 tor1 fra1 sfo1 lhr1 sin1
for svc in tor1 lhr1; do shell "more-logs-$svc" "docker compose logs --no-color --since $since $svc"; done

remote tor1 <<'IN'
Node.list()
length(Node.list())
IN

header "$OUT" "02-dns: DNSCluster finds the nodes" "demo/02-dns.sh"
section "$OUT" "start three nodes" "$WORK/up.txt"
for svc in tor1 fra1 sfo1; do section "$OUT" "$svc logs" "$WORK/logs-$svc.txt"; done
section "$OUT" "what DNS returns for 'ticketing' (inside tor1)" "$WORK/dns.txt"
section "$OUT" "add two more regions" "$WORK/more.txt"
for svc in tor1 lhr1; do section "$OUT" "$svc logs after lhr1 and sin1 start" "$WORK/more-logs-$svc.txt"; done
section "$OUT" "docker compose exec tor1 bin/ticketing remote" "$WORK/tor1.txt"
cat "$OUT"
