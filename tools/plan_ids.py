"""Entity ids for structure_plan_v1, made globally unique.

WHY THIS EXISTS. `StructurePlan` keeps six collections — walls, decks, stairs,
edges, items, pieces — and a single id space across all of them. `entity_by_id`,
`entity_kind_by_id` and `remove_entity` all walk the collections in order and
return the FIRST match, so a duplicate id does not error: it silently resolves to
the wrong entity. An editor selecting a piece gets the item that shares its
number; deleting it deletes the item.

Every generator here hand-assigned ids from a range it picked for itself, and the
ranges overlapped. Measured before this module existed:

  probe_piece_trawler      51 duplicates — all 43 piece placements collided with
                           items, one wall collided with an edge, and seven items
                           collided with each other. 0 of 43 pieces were
                           addressable by id.
  probe_trawler_bulwark     8 duplicates
  probe_trawler_bow_bulwark 8 duplicates

Nothing caught it, because every check the fixtures had asked about geometry.
`tests/plan_entity_id_test.gd` is the check that now holds them to it, and this
module is what the generators call so they can pass it.
"""

## The collection order StructurePlan._collections() walks, and therefore the
## order that decides which entity a duplicate id would have resolved to.
COLLECTIONS = ["walls", "decks", "stairs", "edges", "items", "pieces"]


def renumber(plan, start=1):
    """Assign every entity a fresh sequential id, in collection order.

    Returns the plan, mutated in place. Relative order within a collection is
    preserved, so a fixture's diff after this is a clean renumbering rather than
    a reshuffle.

    `host.id` references are remapped through the same map. No shipped fixture
    uses hosting yet, so that path is unexercised — it is here because a
    renumbering that silently broke host references would be a far worse bug
    than the one this module fixes, and it costs five lines to be correct.
    """
    mapping = {}
    next_id = start
    for name in COLLECTIONS:
        for entity in plan.get(name, []):
            old = entity.get("id")
            entity["id"] = next_id
            ## Last writer wins for a duplicate, which matches nothing in
            ## particular — but a duplicate id had no well-defined referent to
            ## begin with, which is the whole problem. Hosting off a fixture
            ## that had duplicates was already broken.
            mapping[old] = next_id
            next_id += 1

    for entity in plan.get("items", []):
        host = entity.get("host")
        if isinstance(host, dict) and host.get("id") in mapping:
            host["id"] = mapping[host["id"]]
    return plan


def duplicate_ids(plan):
    """{id: [collection, ...]} for every id used more than once. Empty is good."""
    seen = {}
    for name in COLLECTIONS:
        for entity in plan.get(name, []):
            seen.setdefault(entity.get("id"), []).append(name)
    return {i: where for i, where in seen.items() if len(where) > 1}
