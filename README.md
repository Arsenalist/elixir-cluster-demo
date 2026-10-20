# elixir-cluster-demo

A tiny Phoenix app, `ticketing`, running as a five-node Erlang cluster in Docker
Compose. It's the companion repo for the zarar.dev video on clustering Elixir:
connecting nodes, finding them with DNS, sending messages between them,
PubSub, `:erpc`, giving every show an owner with rendezvous hashing, and a
cluster-wide singleton that moves when its node dies.

Each node pretends to be in a different region: `tor1`, `fra1`, `sfo1`, `lhr1`,
`sin1`. They're all on your laptop, but the code doesn't know that.

There's no database. The sales numbers in `Ticketing.Sales` are simulated
(fixed per region) so the demo output is reproducible.

## What's in here

```
lib/ticketing.ex                   Ticketing.region/0, Ticketing.node(:fra1)
lib/ticketing/cluster.ex           logs "node ticketing@10.0.1.12 (fra1) joined" / "down"
lib/ticketing/box_office.ex        one GenServer per node, registered as BoxOffice
lib/ticketing/shows.ex             owner(show_id) by rendezvous hashing, hold/2 runs on the owner
lib/ticketing/sales.ex             simulated per-node numbers for :erpc.multicall
lib/ticketing/reminders.ex         the cluster singleton, {:global, Ticketing.Reminders}
lib/ticketing/singleton_manager.ex starts the singleton or monitors whoever has it
rel/env.sh.eex                     node naming (ticketing@<ip>) + opt-in hardening
.iex.exs                           region in the prompt: tor1>
Dockerfile, docker-compose.yml     one image, five nodes on 10.0.1.0/24
demo/                              one script per beat of the video
captures/                          real terminal output from those scripts
```

## Prerequisites

- Docker (with Compose v2).
- `expect` and `python3` to run the scripts in `demo/` (both ship with macOS).
- Elixir only if you want to run the app or tests outside Docker
  (`mise install` reads `mise.toml`).

## Run it

```sh
docker compose up -d --build        # tor1, fra1, sfo1
docker compose logs -f              # watch them find each other
docker compose up -d lhr1 sin1      # add two more regions

docker compose exec tor1 bin/ticketing remote
tor1> Node.list()

docker compose --profile more down  # stop everything (lhr1/sin1 are in the "more" profile)
```

How the nodes find each other: every service has the network alias
`ticketing`, so Docker's DNS returns all their IPs for that name. Each node is
named `ticketing@<its ip>` (see `rel/env.sh.eex`) and runs
[DNSCluster](https://dns-cluster.hexdocs.pm/DNSCluster.html) with
`DNS_CLUSTER_QUERY=ticketing`, which polls DNS and connects to any
`ticketing@<ip>` it isn't connected to yet. That's the stock Phoenix setup;
`lib/ticketing/application.ex` and `config/runtime.exs` are as generated.

## The demos

Each script runs one beat end to end, drives real IEx sessions with `expect`,
and writes what the terminal showed to `captures/`. Run them in order: 01 needs
nothing, 02 starts the cluster, 03 to 05 use it, 06 starts a fresh one.

| Script | What it shows | Capture |
| --- | --- | --- |
| `demo/01-first-cluster.sh` | Two plain `iex --name ... --cookie box-office` nodes, `Node.ping/1`, `Node.list/0` | `captures/01-first-cluster.txt` |
| `demo/02-dns.sh` | `docker compose up -d`, join logs, what DNS returns, adding `lhr1` and `sin1` | `captures/02-dns.txt` |
| `demo/03-messages.sh` | `send/2` and `GenServer.call/3` to `{BoxOffice, fra1}`, then the same with fra1 killed | `captures/03-messages.txt` |
| `demo/04-pubsub.sh` | Subscribe on three nodes, broadcast once from tor1 | `captures/04-pubsub.txt` |
| `demo/05-erpc.sh` | `:erpc.multicall/4`, `Shows.owner/1`, two regions racing for the last seat | `captures/05-erpc.txt` |
| `demo/06-failover.sh` | Kill fra1, watch `Ticketing.Reminders` move (`RUNS=3` to time it repeatedly) | `captures/06-failover.txt` |

Or by hand, from a remote console (`docker compose exec tor1 bin/ticketing remote`):

```elixir
# 03: messages
fra1 = Ticketing.node(:fra1)
send({BoxOffice, fra1}, {:hold, 2, self()})
flush()
GenServer.call({BoxOffice, fra1}, {:hold, 2})

# 04: pubsub (subscribe on another node first)
Phoenix.PubSub.subscribe(Ticketing.PubSub, "shows")
Phoenix.PubSub.broadcast(Ticketing.PubSub, "shows", {:sold_out, 42})

# 05: erpc and an owner per show
:erpc.multicall([node() | Node.list()], Ticketing.Sales, :last_minute, [])
Ticketing.Shows.owner(26)            # same node, whichever node you ask
Ticketing.Shows.open(26, ["F12"])    # one seat left
Ticketing.Shows.hold(26, 1)          # {:ok, seat: "F12"}, then {:error, :sold_out}

# 06: the singleton
:global.whereis_name(Ticketing.Reminders) |> node()
```

A few things you'll notice:

- **A call to a node that just died times out before it says "nodedown".**
  Calling `{BoxOffice, fra1}` makes Erlang try to reconnect, and connecting to
  an address with nothing behind it takes up to 7 seconds (`net_setuptime`).
  The default 5 second `GenServer.call` gives up first. Either way, wrap remote
  calls you can live without.
- **Which node takes over the singleton is a race.** Every surviving
  `SingletonManager` tries to start it and `:global` lets exactly one win. In our
  runs it was `lhr1` or `sin1`, about 1 ms after the node went down.
- **fra1 starts with the singleton on purpose.** On a cold start the nodes boot
  before they've found each other, so each would start its own copy and
  `:global` would kill all but a random one when they meet. For a predictable
  demo, fra1 tries immediately and the others wait 5 seconds
  (`SINGLETON_START_DELAY_MS`).

## Security

The demo uses the cookie `box-office`. Don't.

- **The cookie is not security.** It's a shared password sent during a
  handshake over a plain TCP connection, and anyone who has it can run any code
  on any node (that's what `:erpc` is). Use a long random value
  (`openssl rand -base64 48`) from your secret store, never commit it, and
  treat it like a root password anyway.
- **Keep EPMD (4369) and the distribution port private.** Nothing outside your
  private network should reach them. `rel/env.sh.eex` has commented-out lines
  that bind EPMD to the private interface (`ERL_EPMD_ADDRESS`), bind
  distribution to it too (`inet_dist_use_interface`), and pin distribution to
  port 9100 (`inet_dist_listen_min/max`) so a firewall rule can allow exactly
  4369 and 9100 between nodes.
- **Encrypt it if the network isn't yours.** Erlang distribution is plaintext
  by default. Over anything you don't fully control, use
  [distribution over TLS](https://www.erlang.org/doc/apps/ssl/ssl_distribution.html)
  (`-proto_dist inet_tls`) or a private network/VPN (WireGuard, a VPC).

More in the EEF Security WG's
[distribution hardening guide](https://security.erlef.org/secure_coding_and_deployment_hardening/distribution.html).

## Further reading

- [DNSCluster](https://dns-cluster.hexdocs.pm/DNSCluster.html)
- [Phoenix.PubSub](https://phoenix-pubsub.hexdocs.pm/Phoenix.PubSub.html)
- [`:erpc`](https://www.erlang.org/doc/apps/kernel/erpc.html) and
  [`:global`](https://www.erlang.org/doc/apps/kernel/global.html)
- [Distributed Erlang](https://www.erlang.org/doc/system/distributed.html)
- [EEF: Distribution hardening](https://security.erlef.org/secure_coding_and_deployment_hardening/distribution.html)
- Johanna Larsson's series, which this repo leans on heavily:
  - [Elixir Cluster 101](https://jola.dev/posts/elixir-cluster-101)
  - [Distributed rate limiter with HRW in Elixir](https://jola.dev/posts/distributed-ratelimiter-with-hrw)
    (the `Shows.owner/1` idea)
  - [Cluster singleton pattern](https://jola.dev/posts/cluster-singleton-pattern)
    (the `SingletonManager` idea)
  - Her ElixirConf EU 2025 talk: https://www.youtube.com/watch?v=FDD_qIT1uyw

## Tests

```sh
mix deps.get && mix test
```

## License

MIT, see [LICENSE](LICENSE).
