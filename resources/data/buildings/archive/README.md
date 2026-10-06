# Retired block-library buildings

`harbouroffice.json` and `warehouse.json` are preserved unchanged as design
references. They require the procedural construction blocks removed during the
Blender model migration and cannot currently be assembled.

Only JSON files directly under `resources/data/buildings/` belong to the active
building catalog. Keep these layouts in this archive until replacement land
models and valid blueprints exist. Do not restore the deleted ship block library
to make them load. The harbour continues to use its existing pad placeholders;
saved port geography and player saves are unaffected.

Explicitly opening an archived file still validates it and reports its missing
brick types. Archiving does not make unsupported layouts valid.
