# Angst 'n Anchors

A maritime trading game. You start with a busted skiff and some pocket money. The sea is already busy with ships that aren't yours. You intend to change that.

"Angst" is a real English word — borrowed from German, fully absorbed. It means low-grade dread, anxiety, the feeling that things could go wrong at any moment. That's the texture of being a small operator in a world where bigger players have already carved up the routes.

> **Repo note:** The Godot project was recently reset to a minimal shell while design is preserved here. Implementation tasks live in [`TASKBOARD.md`](TASKBOARD.md).

---

## The Core Loop

Ports buy things and sell things. Your job is to be in the right place with the right cargo at the right price.

That's it. That's the game.

Every port has two lists: what it **exports** (has surplus of, will sell cheap) and what it **imports** (needs, will pay well for). You buy low, sail, sell high. The catch is that everyone else is doing the same thing — and most of them started before you.

No production simulation. No animated lumber mills out in the forest. No supply chains to manage at the industrial level. The port just has fish. The other port just wants fish. You connect them.

---

## What It Feels Like

**Euro Truck Simulator on water.** Early game is hands-on and physical. You are in the boat. You feel every delivery. You sail the route yourself, watch the fuel gauge, check the weather. The world is large and the ocean has real distance. A run to the far mainland takes time. That time matters.

**A living world you're entering late.** When you start, established shipping companies are already running the major routes. The contract board already has deals posted that you can't afford or don't have the rep to take. Big haulers pass you in open water. You are not the protagonist of this world — yet. You're an interloper, picking up scraps and looking for the angle nobody else has found.

**Relaxing with a current of dread underneath.** Most of the time, sailing is calm. The sea is beautiful. A good run is satisfying in a quiet way. But you have a contract with a deadline. Your hull took a hit in last night's weather. A rival just undercut your standing order with Port Aldra. The angst is always there — not loud, just present.

---

## The World

A large, hand-crafted map. Geography is fixed and learnable — knowing the map is a real advantage.

- **Mainland ports** — high volume, competitive, long queues. Big money and big companies. Hard to break in early.
- **Island settlements** — smaller, underserved, lower volume but better margins for anyone willing to make the trip. Some only reachable in calm weather.
- **Open sea lanes** — weather matters. Storms slow you, damage hulls, close passages. The short route isn't always the right one.
- **Distance is real** — fuel is a cost. Far runs need planning.

---

## Ports & Trade

Each port has a character. Some are industrial, some are fishing villages, some are military installations, some are just a dock and a guy with a clipboard.

Every port has:
- **Exports** — goods it produces or stockpiles that it sells. Price reflects supply (flood the market and the price drops).
- **Imports** — goods it needs and will buy. Price reflects demand (starve a port and they'll pay more).

Prices shift with supply and demand. A port you've been reliably supplying for two weeks will pay you better than one you've never visited. A port that just got undercut by a rival company is suddenly desperate.

You don't need to understand how the fish got to the dock. You just need to know the dock has fish, and that someone across the water will pay for it.

---

## The Contract Board

Beyond free trading, there's a live board of posted deals. A scrolling, updating list of real opportunities and real obligations.

**Types:**
- **Spot offer** — "80 units of Salted Fish at Port Verde, 19cr/unit, valid 2 days." Take it or leave it.
- **Delivery contract** — "Deliver 500 units of Timber to Ironhold by Day 40. Penalty: 4,000cr if missed." Binding.
- **Supply agreement** — "Supply Port Valenza with 200 units of Grain per week for 8 weeks at 24cr/unit." Long-term, locks your capacity.
- **Tender** — port authority posts a job, companies bid. Credibility matters as much as price.

**Consequences:**
- Signed contracts appear in your ledger. They don't go away.
- Miss a deadline: financial penalty and reputation damage.
- Reputation opens or closes access. A port that doesn't trust you won't offer you anything good.
- A port that relies on you becomes a relationship.

---

## A World Already in Motion

You don't build the world. You enter it.

When you start the game, other shipping companies are already running routes, holding contracts, and occupying the good berths. You'll see their ships on the water. You'll see their names on contracts you can't touch yet. The economy doesn't pause for you.

This isn't hostile — it's just true. The opportunity is to find the gaps they're not covering: the island no one's bothering with, the cargo type the big operators consider too small-margin, the route that's slightly too risky for a company that has something to lose.

Rival companies grow and shrink. They win and overextend. They hold routes you want. Eventually, you can outcompete them, undercut them, poach their captains, or buy them out entirely. But they were there first.

---

## Progression Arc

### Early — One Boat, One Captain (You)
You have a skiff. You walk the dock, talk to the merchant, check the contract board. You take whatever pays. You load cargo, you sail, you unload. You do it again. You watch the credits climb.

### Middle — Small Fleet
You buy a second hull. You hire someone to run it. Suddenly you have two problems instead of one — payroll, coordination, scheduling. You start taking contracts that require reliability, not just availability. You have routes. You're on the map.

### Late — Shipping Company
Your name is on the contract board. Rivals notice you. Port authorities have opinions about you. You have a logistics coordinator managing captains who manage crew. You personally sail when you want to, not because you have to. You're speculating on market gaps. You're looking at which rival company to acquire.

No win state. No end screen. The sea does not run out of cargo.

---

## The "Doing" Layer

Even with a full fleet, the hands-on game should stay compelling:

- **First person on foot** — walk the dock, talk to the merchant, read the board.
- **3rd-person boat** — feel the momentum, the wake, the weather. Not floaty. Physical.
- **Fuel stops** — plan refuelling on long runs. Running dry at sea is a bad day.
- **Hull condition** — damage accumulates. Bad weather, age, collisions. Schedule dry dock or your boat degrades under you.
- **Weather routing** — storms are on a forecast. Delay or push through. Your call.
- **Rival encounters** — not combat. A rival ship racing you to a port takes the spot price. You can negotiate, cut a deal, or race.

---

## Captains & Crew

Real characters, not stat blocks:

**Captains** have navigation skill, negotiation skill, reliability, risk tolerance, salary expectations, and loyalty. They gain experience. A captain you promoted from deckhand is more loyal than a hired veteran. A veteran costs more and may leave.

**Crew** (per ship): deckhands (load speed), engineers (maintenance cost), navigators (captain support or promotion track).

---

## Tone

Mostly calm. The sailing is peaceful. The routes become familiar. There's a satisfaction to a smooth run.

But you have a contract with a deadline. You checked the forecast and it's not good. A rival just took a berth at Port Aldra before you got there. Your best captain is being courted by Velmoor Shipping. Your hull needs repairs you can't quite afford yet.

The angst is not a mechanic. It's a texture. It lives in the gap between how things are going and how they could go wrong.

---

## Technical Rules

- **All in-world models are built from code.** No imported meshes. BoxMesh, CylinderMesh, PlaneMesh — materials from colour, roughness, metallic values. Style is muted, functional, not cartoonish.
- Built in **Godot 4.6**, Forward Plus renderer, Jolt Physics.
- GDScript throughout.

---

## Build Guardrails

- Build slowly. Small validated steps. No jumping to full systems in one pass.
- Reusable foundations over one-off scripts. If a mechanic recurs (NPC interaction, dialogue, interaction prompts), build it generically first.
- **No imported visual assets for in-world models.**
- Simple readable architecture. No premature optimisation.
- The **starting island** is a tutorialized sandbox that introduces core mechanics before scale systems.

---

## Starting Island First (phased scope)

1. **Phase A — Spatial onboarding.** Clean spawn, readable landmarks, walkable dock. Teach movement and world readability only.
2. **Phase B — Interaction foundation.** Reusable `focus → prompt → interact` system. Powers NPCs, boards, cargo, everything.
3. **Phase C — NPC conversation.** Generic dialogue runner, simple branching, reusable data format. First NPC uses the shared system, not a custom one-off.
4. **Phase D — First mechanic handoff.** Dialogue leads to a first action: look at the board, understand a trade, do a simple pickup/dropoff. Thin content, validated flow.

---

## Implementation Status

**Run:** `scenes/islands/starting_island.tscn` — procedural island, ocean plane, first-person character only. No menu, HUD, dock, traders, or autoloads yet. `MeshBuilder` for terrain boxes.

Godot **4.6**, Jolt. See **TASKBOARD.md** for next steps. Everything above is the design target.
