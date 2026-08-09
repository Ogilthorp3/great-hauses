# Head-to-Head — playing a friend

Two copies of Great Houses, one match. One player **hosts** (their instance is
authoritative and owns the board); the other **joins** by address. Godot 4
high-level multiplayer over `ENetMultiplayerPeer` — no third-party server, no
relay, nothing to run but the game.

---

## 1. How to play (the two-minute version)

**Both of you:** launch Great Houses → the Hall of Banners → pick your banner →
**Play a Friend**.

**Host (one of you):**

1. `Host a Match`
2. Pick a side — *You ride for White* / *Black* / *Let the gods decide*
3. `⚔ Open the Gates`
4. The panel prints the addresses to send. Read your friend **the top one**.

**Joiner (the other one):**

1. `Join a Match`
2. Type the address your friend read out (it is remembered for next time)
3. `⚔ Ride Out`

Both halls dress to the real matchup — your banner, their banner — and the
board opens with each of you seated behind your own army.

If something goes wrong you get a sentence, not an error code:
<!-- ip-allow: a quoted example of the game's own error text — documentation, not an endpoint -->
*"could not reach 100.72.4.11:7777 — is your friend's game open and waiting,
and are you both on the same Wi-Fi or the same tailnet?"*

---

## 2. Reachability — which address to send

The Host panel lists addresses **best option first**.

### (a) Same Wi-Fi — just works

The `192.168.x.y:7777` / `10.0.0.x:7777` line. Nothing to configure: both
machines are on one network and ENet finds its way. This is the case for two
people on the same couch.

### (b) Over the internet — Tailscale (by far the easiest real path)

Bert's machines are on the tailnet `tail7c6d11.ts.net` (see
`~/Projects/Claude_Code/tailnet/`). The Host panel shows the tailnet address as
`100.x.y.z:7777   (tailnet — works from anywhere)` — that CGNAT-range address
is the one to send. No port forwarding, no router change, no relay of ours.

The friend needs to be *on* the tailnet, one of two ways:

* **Share the node** (least invasive). Tailscale admin console → the hosting
  machine → *Share…* → send the link. Their device joins their own tailnet and
  can reach yours.
* **Invite them as a user** of `tail7c6d11.ts.net`.

> **One ACL line is required either way.** This tailnet is *default-deny with
> tag-based rules* (`tailnet/acl.hujson`): a guest device carries no tag, so it
> matches no `accept` rule and cannot reach port 7777 — the join would time out
> with the "could not reach" message even though Tailscale itself is up. Add to
> the `acls` block:
>
> ```jsonc
> // Great Houses head-to-head: a guest may reach the game port, nothing else.
> {
>   "action": "accept",
>   "src":    ["autogroup:shared"],        // or the invited user: ["friend@example.com"]
>   "dst":    ["tag:sanctum-admin:7777"],  // tag:sanctum-host if manoir is hosting
> },
> ```
>
> Apply it the usual way (`tailnet/apply-acl.sh`, or the admin console). Scope
> it to `:7777` — a guest node has no business anywhere else on the tailnet.
> Remove the rule when the game night is over.

### (c) Port forwarding — the fallback

If the friend will not install Tailscale: forward **UDP 7777** on the router
(Firewalla) to the hosting machine's LAN address, and send them your public IP
as `<public-ip>:7777`. ENet is UDP — forwarding TCP as well does no harm but is
not what carries the game. Change the port on both sides with `--net-port=` if
7777 is taken.

There is deliberately **no public relay**. If neither of you can reach the
other directly, use Tailscale.

---

## 3. What the rules are, online

| | |
|---|---|
| **Host authority** | The host's `ChessState` is the only board. Both players *request* moves; the host validates against its own legal-move list and either broadcasts the applied move or refuses it with a reason. A client cannot force an illegal move — `tests/test_net.gd` tries nine ways, and the live two-instance test tries two more over the wire. |
| **Cinematics** | A capture duel plays out on **both** screens. After every ply each side reports "I finished watching"; the turn does not advance until both have. A peer that hangs can delay the gate (25 s) but never freeze the match. |
| **Take-backs** | **Off.** There is no correct unilateral answer to rewinding the board under your opponent's hand, so the HUD button reads `↶ no take-backs online`, is disabled, and Cmd/Ctrl+Z is inert. |
| **Rematch** | Also off — a one-sided scene reload would strand the other player. The verdict card offers *Return to the Hall of Banners* to both. |
| **Disconnect** | Detected on both sides; a card says what happened in plain words and offers the Hall of Banners. No reconnect window in v1. |
| **Desync** | Every broadcast carries the FEN the ply must produce. If a board disagrees it stops and says so — a chess client must never diverge quietly. |

---

## 4. Command line (e2e, and quick LAN games)

```bash
# host, playing White, from a custom position
Godot --path . -- --net-host --net-side=white --net-house=winterfang \
                 --net-port=7777 --e2e-fen="<fen>"

# join
Godot --path . -- --net-join=127.0.0.1 --net-port=7777 --net-house=ashwyrm
```

`--net-side` is `white|black|random`. The **host's** `--e2e-fen` travels to the
joiner in the handshake: the host's position is the only position. A
command-line joiner retries the dial six times (the two processes are launched
seconds apart); the Hall's Join button does not — a human wants the error.

---

## 5. Tests

```bash
./test_e2e/run_net_e2e.sh      # THE gate: two real instances play a real game
./test_e2e/run_e2e.sh          # full suite; includes the net-suite + net-hall
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    -s res://tests/test_net.gd # protocol only, ~1 s
```

`run_net_e2e.sh` launches two Godot processes side by side, drives both through
the synthesized-input driver (real clicks on the real board), plays a scripted
game — *a normal move each way, a capture with the slow-motion duel, a
checkmate* — and then **diffs the FEN each instance printed after every ply**.
If the two boards ever disagreed by one move, the diff says so and the script
fails. Screenshots land in `test_e2e/artifacts/net-host/` and `net-join/`.

A green `tests/test_net.gd` proves the protocol. It does **not** prove that two
machines can play. That is what `run_net_e2e.sh` is for.

---

## 6. Files

| File | What it is |
|---|---|
| `src/net/net_protocol.gd` | Pure data + pure rules: wire shapes, move encode/decode, **the validator**, seating, addresses, the words every failure is reported in. No sockets, no scene tree — all of it headless-testable. |
| `src/net/net_ply_gate.gd` | The cinematic barrier: both sides ack a ply before the turn advances; stale acks dropped, a hung peer times out. |
| `src/net/net_match.gd` | The transport. Lives at `/root/NetMatch` so it survives the scene swap out of the Hall. ENet peer, RPCs, host authority, disconnect detection. |
| `src/main.gd` | Integrator: wires the Hall's panel to the socket, and the command-line path. |
| `src/ui/house_select.gd` | The *Play a Friend* panel (`Phase.NET`, appended last in the enum so the existing phase ids are untouched). |
| `src/game.gd` | Presentation: `player_color` (the player is no longer always White), network turn flow, the ack handshake, the disconnect card, take-backs disabled. |
| `src/session.gd` | Carries the seating chart across the scene swap. |
