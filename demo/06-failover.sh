#!/usr/bin/env bash
# Beat 6: the Reminders singleton fails over when its node dies.
# Starts a fresh five-node cluster (so Reminders begins on fra1), kills fra1,
# and measures how long until another node has re-registered it.
#
#   tor1> :global.whereis_name(Ticketing.Reminders) |> node()
#   $ docker compose kill fra1
#   tor1> :global.whereis_name(Ticketing.Reminders) |> node()
#
# RUNS=3 demo/06-failover.sh repeats the measurement (the capture is from run 1).
source "$(dirname "$0")/lib/common.sh"

OUT=$CAPTURES/06-failover.txt
RUNS=${RUNS:-1}
ALL=(tor1 fra1 sfo1 lhr1 sin1)

# HH:MM:SS.mmm -> milliseconds since midnight
ms() { python3 -c "import sys; h,m,s=sys.argv[1].split(':'); print(int((int(h)*3600+int(m)*60+float(s))*1000))" "$1"; }

fresh_cluster() {
  docker compose --profile more down >/dev/null 2>&1
  docker compose up -d >/dev/null 2>&1
  wait_for_cluster 2 tor1 fra1 sfo1
  docker compose up -d lhr1 sin1 >/dev/null 2>&1
  wait_for_cluster 4 "${ALL[@]}"
  sleep 6 # past SINGLETON_START_DELAY_MS, so every manager is watching fra1's copy
}

for run in $(seq 1 "$RUNS"); do
  fresh_cluster
  rm -f "$WORK"/tor1.* "$WORK"/logs-*.txt

  remote tor1 <<'IN'
:global.whereis_name(Ticketing.Reminders) |> node()
:global.whereis_name(Ticketing.Reminders) |> node() |> Ticketing.Cluster.region_of()
#!run docker compose kill fra1
#!sleep 2
:global.whereis_name(Ticketing.Reminders) |> node()
:global.whereis_name(Ticketing.Reminders) |> node() |> Ticketing.Cluster.region_of()
IN

  # When we ran `docker compose kill` (host clock) ...
  killed=$(python3 -c "import datetime as d,sys; print(d.datetime.fromtimestamp(int(sys.argv[1])/1000, d.timezone.utc).strftime('%H:%M:%S.%f')[:-3])" "$(cat "$WORK/tor1.raw.run-at")")
  # ... and when fra1 actually died, according to Docker (same clock as the containers).
  died=$(docker inspect "$(docker compose ps -a -q fra1)" --format '{{.State.FinishedAt}}' | sed -E 's/.*T([0-9:]+\.[0-9]{3}).*/\1/')
  down=$(docker compose logs --no-color tor1 | grep '(fra1) down' | tail -1 | awk '{print $3}')
  winner=""
  for svc in tor1 sfo1 lhr1 sin1; do
    if docker compose logs --no-color "$svc" | grep -q 'Reminders started'; then winner=$svc; fi
  done
  started=$(docker compose logs --no-color "$winner" | grep 'Reminders started' | tail -1 | awk '{print $3}')
  result="run $run: kill issued $killed, fra1 exited $died, tor1 logged it down $down, Reminders started on $winner $started. Kill command to new registration: $(($(ms "$started") - $(ms "$killed"))) ms; nodedown to new registration: $(($(ms "$started") - $(ms "$down"))) ms"
  echo "$result"

  if [ "$run" = 1 ]; then
    shell logs-tor1 "docker compose logs --no-color tor1 | tail -3"
    [ "$winner" != tor1 ] && shell "logs-$winner" "docker compose logs --no-color $winner | tail -3"
    header "$OUT" "06-failover: the singleton moves when its node dies" "demo/06-failover.sh" \
      "Measured: $result"
    section "$OUT" "docker compose exec tor1 bin/ticketing remote" "$WORK/tor1.txt"
    section "$OUT" "tor1 logs" "$WORK/logs-tor1.txt"
    [ "$winner" != tor1 ] && section "$OUT" "$winner logs (the new owner)" "$WORK/logs-$winner.txt"
  fi
done
cat "$OUT"
