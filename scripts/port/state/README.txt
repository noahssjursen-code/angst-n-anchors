CUSTOM PORT DATA FOUNDATION

CustomPortState is a scene-free RefCounted document and command simulator.
It does not register an autoload, replace CompanyService/WorldGateway, write
captain saves, operate real cranes or transact with the multiplayer database.
Those live adapters must use the existing authority seam. The independent
showcase consumes this document to build its visuals and exercise the rules.

Create/load:
  state = CustomPortState.from_dict(document, expected_world, asset_catalog)
  state.validation_errors  # refuse injection if nonempty
  state.to_dict()          # detached JSON-safe snapshot
  state.derived_berths()   # derived from placed quay edges and bollards

The asset_catalog is keyed by asset_id and is supplied by the authority.
Geometry, layers, support and crane reach cannot be changed by placement
attributes. Authored copies equal to the catalog are accepted. Cosmetic and
link attributes survive saves. Unrecognized assets are rejected.

Positions and plots are port-local metres. origin_m identifies the world
anchor. Placement Y=0 means the fixed deck plane, whose height above sea level
is deck_height_above_sea_m. origin_m[1] is already the deck's world Y; do not
add the deck height to it again. This world's sea Y=-1.5 and the workshop's
2m deck therefore has origin Y=0.5. The actual-world import boundary checks
that relation and rejects a different plane before replacing active state.
The scene-free model remains usable with other explicit world datums.
Both the workshop importer and custom-port world streamer use
custom_port_world_policy.gd for that actual-world plane check. They also call
CustomPortVesselProjection.validate_snapshot() before installing a document.
For records carrying a prebuilt_id, declared hull dimensions, installed holds,
securing beds and supported cargo must match that real blueprint; carried and
reserved cargo must fit the actual components without losing small remainders.
Unknown prebuilts and missing/forged installed evidence reject. Abstract records
without prebuilt_id remain available to data simulations, with no rendered ship
promised. A lower overall scenario mass ceiling is allowed; container beds still
have no authored safe mass rating, so their finite scenario ceiling is explicit.
origin_m and world identity are immutable; only a
trusted authority terrain survey may extend water coverage. Construction uses CustomPortPlacementRules for
support, overlap and shared height. Platform tiles rotate in 90 degree steps;
their authored diagonal edges also accept props rotated in 45 degree steps.
Exact footprint polygons, not their bounding squares, determine coverage.
Geometry must fit
the union of purchased plots, including gaps and holes between plots.
Optional support_depth_m is a positive finite metre value capped at 4096;
the editor derives it from the seabed rather than a user-selectable deck height.

Berths are projections, not manually entered slots. CustomPortBerths derives
them from adjacent bollards along exposed straight platform edges. It checks
surveyed water coverage, approach width, draft, clearance, conflicting berths,
and crane reach to both the vessel and the linked store. No depth survey means
the berth is visible for inspection but cannot accept a vessel.

Command envelope:
  {command_id, expected_revision, actor_company_id, kind, payload}

Later arrival of a known fleet record:
  kind: admit_vessel
  payload: {vessel_id}
  trusted authority_context: {vessel_records: {vessel_id: complete_vessel}}
Only the reference is accepted from the command. Construction, owner and cargo
come from the supplied authority projection; a prebuilt must still match its
installed fitout. The actor must own that vessel. An already-known or already
docked vessel rejects; admission never occupies a berth or creates payment.
The result uses the same revision, durable receipt and replayable event rules.
A real backend must resolve this context from its existing fleet authority and
commit any custody changes atomically. This is not a client fleet-creation API.
CustomPortTestVisitors supplies explicit empty scenario projections only while
ShipyardPlaytestMode is active, for testing a harbour built from scratch.

Kinds and payloads:
  rename_port          {name} (port owner only; stable id and contents)
  place_asset          {placement:{id,asset_id,position_m,yaw_degrees,attributes}}
  remove_asset         {placement_id,expected_placement?}
  transform_asset      {placement_id,expected_placement,position_m,yaw_degrees,support_depth_m?}
  edit_assets          {operations:[{kind:place_asset|remove_asset|transform_asset,payload}]}
  buy_plot             {plot_id}
  refresh_water_survey  {} (trusted context only; see below)
  configure_store      {store_id,changes:{name?,public_loading?,public_unloading?,accepted_commodities?}}
  admit_vessel         {vessel_id} (trusted existing fleet projection; see above)
  dock                 {vessel_id,berth_id}
  undock               {vessel_id}
  reserve_cargo        {store_id,vessel_id,lot_id,quantity,reservation_id?}
  cancel_reservation   {reservation_id}
  load_cargo           {reservation_id}
  unload_cargo         {store_id,vessel_id,lot_id,quantity}

  state.apply(command, authority_context={})

Results contain ok, code, revision, events, account_changes and snapshot.
Success includes result and applied_revision. Failure includes details.
A failed command changes nothing and publishes nothing. A successful command
increments one revision. A repeated command_id with identical meaning replays
the receipt, without repeating events or account changes. Different meaning
under an already-used id is rejected. Numeric JSON round trips are normalized.
Receipts persist in the document; production retention belongs to the existing
authority command/transaction store, not an unbounded client save log.

Renaming publishes a single scalar name change in its event. Replay accepts
that field only on rename_port; other mutable fields retain their array shape.
Names are trimmed, nonempty, at most 80 characters and contain no control
characters. Identity, coordinates, ownership, cargo and construction never
change when the display name changes. Existing nameless documents still load.

Cargo stores and supplied vessel projections contain capacity_kg, lots and
optional capacity_units. A lot has id, commodity_id, quantity, unit_mass_kg,
attributes. Quantity is kg when unit_mass_kg=1 for bulk, or count for individual
containers. attributes.whole_units=true, attributes.indivisible=true or a
nonempty container_type each require whole-number quantities. Set
attributes.slots_per_unit=1 for one slot or 2 for a configured two-slot item.
Slot units are capacity accounting, not proof that a particular physical
40-foot container fits a vessel's deck. Production placement must also run
the game's existing ContainerUnit/CargoSlotPad footprint rules.

Reservations hold finite source stock and destination mass/slot capacity.
Competing vessels cannot oversubscribe either. Loading moves the exact reserved
lot, preserving its identity and attributes. Unloading checks commodity access
and destination capacity. The owner operates private stores; other companies
require public_loading/public_unloading. These flags permit transfer in the
isolated simulation; they are not a market sale or payment authorization.
No command mints stock. Empty lots are removed; goods are never silently lost.

Catch lots retain their species, size, quality, caught time/position and other
attributes. specimen=true means one indivisible fish, even if its quantity is
expressed as kilograms rather than quantity=1 with an individual unit mass.
The complete lot must transfer together and its ID cannot exist in two inventories.
Ordinary non-specimen catch remains divisible. Transactions cannot leave a
fragment at or below CatchLot's 0.1kg physical-component threshold. Invalid
known catch metadata is rejected before reconstruction can clamp it silently.
Installed catch tanks are simulated using CatchHoldState for both carried and
reserved goods: an individual fish must fit in a single tank, while bulk catch
can spread across tanks. Shore stock uses the same metadata and identity checks.
These rules preserve existing valid JSON; previously invalid split-specimen or
physically disappearing records reject instead of inventing or hiding fish.
Catch IDs must already be canonical rather than colliding after whitespace
trimming. Recorded catch positions must remain finite in the game's vector
representation. Quantity rounding is measured in mass so a tiny count of heavy
units cannot erase a substantial remainder.
Focused checks: tests/custom_port_catch_data_test.tscn (65 checks).

Typed cargo projections optionally add accepted_handling_modes (the existing
container/general/bulk/catch/liquid vocabulary), handling_capacity_kg, and
accepted_container_types. Each handling mode's mass is checked independently,
including reservations. A spare fish tank does not grant container or bulk capacity.
Container type is checked before slot count: two separate 20ft beds cannot
accept a 40ft box merely because its slot count is two.

When cargo_holds is present, bulk cargo must also fit the installed compartments.
CustomPortVesselProjection.bulk_hold_plan() uses the existing BulkHoldState rules
in the authored cargo_holds order, with each hold's id, handling_mode and
capacity_kg. One compartment cannot mix commodities or consignments, even with
spare aggregate capacity. attributes.consignment_id identifies the shipment;
when absent it defaults to the lot id, matching the vessel presenter. A shipment
may span holds, and separate lots of the same commodity and consignment may share
a hold. The planned contents must preserve all mass, including small remainders
that the existing physical hold rules would otherwise discard.

Manifest validation, combined loading reservations and the final load command
all apply these rules. Incompatible commands return bulk_compartments_exceeded
without moving stock; malformed installed-hold metadata returns invalid_cargo_holds.
Import/replay also reject impossible manifests or reservations. Real one-hold and
two-hold reconstruction tests compare each installed hold's complete state with
the data plan, including hold identity/order, commodity, consignment and mass.

This uses existing schema-1 fields; no new assignment field or save migration is
required. Previously accepted documents containing impossible installed-hold cargo
now fail validation instead of silently hiding cargo. Older abstract simulation
records with no cargo_holds field retain aggregate capacity checks; they do not
claim a verified physical fitout. An explicit empty cargo_holds array provides
no bulk compartments. The real prebuilt adapter always supplies installed holds.

CustomPortVesselProjection.from_prebuilt() adapts real imported layouts without
instantiating scenes. Hull dimensions come from ImportedHullCatalog. Installed
catch tanks contribute the existing 600kg limit; supported cargo beds follow
ImportedDraftVessel mounting positions; bulk holds retain existing 40t/120t
limits. It includes each bed/hold's local position and stable id. Raised,
rotated, unsupported or duplicated beds do not create extra capacity. This
adapter is for trusted imported layouts in this isolated lab, not a replacement
for the production vessel blueprint validation/capability service.

Runtime container pads currently have no authored mass rating. The adapter
therefore requires an explicit scenario mass ceiling for container cargo and
labels that source in the record; it does not claim a derived safe deadweight.
With no ceiling supplied, container mass capacity is zero. Other capacities
are derived from the same configured components used by the actual presets.

An asset's catalog attached_store definition creates an EMPTY store atomically
with place_asset. Its id is store:<placement id>, and its capacity and handling
come from the catalog. It starts private. Removing a bundle requires an empty
unreserved store and removes both records in one event. Undo may pass
restore_empty_stores to restore the previous empty identity/restrictions; it
cannot restore stock, broaden catalog handling or exceed catalog capacity.
Independent stores on assets without an attached-store definition remain
protected from implicit removal.

configure_store is owner-only and whitelists the fields shown above. It cannot
change capacities or handling/container types. Commodity restrictions must be
compatible with catalog storage limits and known resource ids. Known ids come
from CommodityCatalog, the existing port's lots/accepted lists, and optional
trusted context.commodity_ids for additional goods. A restriction cannot strand
existing goods or revoke a visitor's active loading reservation. Public loading
and unloading are separate permissions. No market/payment logic is implied.

The native CustomPortInspector Storage tab edits these same fields. A host must
explicitly set_storage_admin_actor(owner_company_id) to enable owner controls;
the default is read-only. This is an isolated workshop role, not authentication.
Berth/cargo actions retain their selected vessel company's actor. Capacity and
handling are shown read-only with separate fish/bulk/container labels.

Catalog-attached stores are also bounded during snapshot import: exactly one
store per installed yard, no larger capacity and no broader handling/type lists.
Stored goods must satisfy the current commodity filter. ISO20ft/40ft cargo uses
one/two slot units respectively; custom attributes cannot make it occupy zero.
Cargo access requires a reachable crane with the explicit handling mode. The
load/unload result and event receipt identify the selected crane_id, store_id
and vessel_id so animation follows the service actually authorized.

Plot buying is an isolated transaction proposal. authority_context contains:
  accounts: {company_id:{balance_nok}}
  plot_offers: {plot_id:{rect_m,world,available,price_nok,owner_company_id?}}
The offer must be free, in the same world, and share an actual edge with an
owned plot. The command ignores prices sent in its payload and rejects an
insufficient balance. account_changes returns old/new balance and delta.
The caller must persist account changes and port state in the SAME transaction
before acknowledging/publishing. This helper itself changes neither the real
company account nor the global property registry.

refresh_water_survey requires trusted authority_context.water_survey:
  {port_id,world,for_revision,regions:[{rect_m:[x,z,w,d],depth_m}]}
Its command payload must be empty. The context must match the port, exact world
and current revision; a client cannot choose depths in a command. New regions
append to existing coverage. Identical cells deduplicate; different depths for
an existing cell or partially overlapping cells reject atomically. A survey
cannot delete older coverage or move an occupied berth. Terrain adapters should
survey newly acquired coastal plots and their approach apron, skip existing
covered cells, and send the complete trusted result only after sampling ends.

Each successful event contains the changed record collections and its durable
receipt. replay_event(event) is for trusted authority events on a read model:
it rejects revision gaps, wrong port ids, invalid results and immutable-world
changes. Only refresh_water_survey events may include water_regions, and they
must retain previous cells. It is not a client mutation endpoint; event transport
must authenticate the authority rather than trusting a caller-supplied kind.
Snapshots plus ordered events
reconstruct the exact data state without meshes, physics, timing or RNG.

All numeric state values use Godot's full-precision JSON wire representation at
the authority boundary. This normalizes integer/float spellings, negative zero,
and computed doubles which its parser otherwise moves by one ULP on first
reload. It does not coarsely round geometry, quantities or custom attributes.
Saved snapshots, command fingerprints and replay consume that same form.

Run isolated verification:
  Godot --headless --path <game> res://tests/custom_port_data_test.tscn -- --shipyard-playtest
Optional evidence output:
  --port-data-output=<absolute JSON path>
The output contains a complete initial document, catalog, dock/load/depart
events and final document suitable for replay or an independent visual client.

Construction controller (scripts/port/building/custom_port_editor.gd):
  configure(state,catalog,actor_company_id)
  preview(asset_id,local_cursor:Vector3,yaw_degrees) -> {ok,placement,errors,message}
  preview_world(asset_id,world_cursor:Vector3,yaw_degrees)
  place(preview), place_asset(asset_id,local_cursor,yaw), remove(placement_id)
  begin_edit(), end_edit(), undo(), undo_count()
  changed(result) signal after successful construction or undo.

The controller uses the same state commands. It never restores an old snapshot
for undo: a paint stroke becomes one inverse edit_assets command at the current
revision. A visiting ship or active handling reservation can block undo; the
attempt then changes nothing and remains retryable. Expected placement records
stop undo from removing a replacement subsequently created by another writer.
Docking, cargo and company transactions are never rolled back by editor undo.

Foundations use footprint grids (4x4, 8x4 and rotated variants), all Y=0.
Fenders/coping snap to exposed straight or diagonal edges and face the water;
bollards use an inward supported offset. Four-metre wall pieces connect at
end sockets. Hover caches use the state revision and snapped placement, so
moving the pointer inside one cell does not repeatedly validate a whole port.
Final placement always runs full authority validation.

For cargo-only commands, previously validated construction geometry is reused
only when all construction, world, water and store-metadata inputs are identical.
Dynamic stock, permissions, packing, reservations and occupancy are always
checked. A fresh document import always validates the entire construction.
See docs/custom-port-command-performance.txt for measured costs and boundaries.

Historical custom-port fishing fixtures used catch:N for installed catch holds.
Physical projection accepts that exact legacy spelling for insulated_catch_tank
fitouts and resolves it to the actual tank_N component identifier, without
rewriting the saved document. New projections use tank_N. Capacity, position,
type and all remaining installed evidence must still match the real prebuilt.
This compatibility does not create an arbitrary hold-ID alias mechanism.

Berth and exposed-edge projections are cached from the successful full validation
at the committed revision. Accessors return copies, and speculative previews
cannot replace those committed projections. Decorative hover uses nearby exact
support/overlap checks even with a docked vessel; platform and bollard changes
still validate occupied berth topology. Full placement validation uses a spatial
broad phase but retains exact polygon intersections and all authority checks.

Editor verification:
  Godot --headless --path <game> res://tests/custom_port_editor_test.tscn -- --shipyard-playtest

Native inspector callback verification:
  Godot --headless --path <game> res://tests/custom_port_inspector_test.tscn -- --shipyard-playtest
Add --capture-port-storage with a graphical run to archive the Storage tab in
the user's machine-screenshot folder.
