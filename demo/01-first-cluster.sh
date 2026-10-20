#!/usr/bin/env bash
# Beat 1: two nodes, one cookie, one ping.
#
# By hand, with Elixir installed, in two terminals:
#   iex --name fra1@127.0.0.1 --cookie box-office
#   iex --name tor1@127.0.0.1 --cookie box-office
#   iex(tor1@127.0.0.1)1> Node.ping(:"fra1@127.0.0.1")
#
# This script does the same inside a throwaway Elixir container, so all you
# need is Docker.
source "$(dirname "$0")/lib/common.sh"

OUT=$CAPTURES/01-first-cluster.txt
box=elixir-cluster-101
docker rm -f "$box" >/dev/null 2>&1 || true
docker run -d --rm --name "$box" -w /tmp "$ELIXIR_IMAGE" sleep infinity >/dev/null
trap 'docker rm -f "$box" >/dev/null 2>&1; rm -rf "$WORK"' EXIT

console fra1 docker exec -it "$box" iex --name fra1@127.0.0.1 --cookie box-office <<IN &
#!touch $(flag fra1-up)
#!wait $(flag tor1-done)
Node.list()
IN

console tor1 docker exec -it "$box" iex --name tor1@127.0.0.1 --cookie box-office <<IN
#!wait $(flag fra1-up)
Node.list()
Node.ping(:"fra1@127.0.0.1")
Node.list()
#!touch $(flag tor1-done)
IN
wait

header "$OUT" "01-first-cluster: two nodes, one cookie" \
  "demo/01-first-cluster.sh" \
  "or, in two terminals: iex --name fra1@127.0.0.1 --cookie box-office" \
  "                      iex --name tor1@127.0.0.1 --cookie box-office"
section "$OUT" "terminal 1: iex --name tor1@127.0.0.1 --cookie box-office" "$WORK/tor1.txt"
section "$OUT" "terminal 2: iex --name fra1@127.0.0.1 --cookie box-office" "$WORK/fra1.txt"
cat "$OUT"
