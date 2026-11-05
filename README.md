# cosmoSys Architecture

Version **0.1.3** (development prototype).

> **EXPERIMENTAL — opt-in:** This plugin is not part of the production core.
> Expect defects, incomplete features, performance limits and breaking changes.
> Do not install it if you require production-level stability and support.

Historical migration data access uses ActiveRecord for database portability.
The dependency minimums below select the matching base and Requirements fixes.

`cosmosys_arch` adds an architecture/PBS project profile to cosmoSys. Its
`archNode` items form an unrestricted-depth parent/child hierarchy and carry a
native `arch_type` value (`complex`, `optical`, `mechanical`, `hardware`, or
`software`). There are no architecture links to requirements or test items yet;
traceability is deferred.

## Requirements

- Redmine 7.0.1
- [cosmoSys](https://github.com/cosmoBots/cosmoSys) 0.2.8 or later
- [cosmoSys Requirements](https://github.com/cosmoBots/cosmoSys_Req) 0.3.5 or later
- [cosmoSys CAD Preview](https://github.com/cosmoBots/cosmoSys_cad_preview) 0.1.3 or later
  (development `model_controls.js` module).

The requirement plugin is an explicit dependency for the shared workflow and
future modular traceability work. The Architecture project profile does not
enable requirement trackers: new PBS projects receive the base cosmoSys
trackers—including `csNegative`—plus `archNode` and `archDoF`.

## Installation

Install `cosmosys`, `cosmosys_req` and the CAD plugins. Clone this repository as
`plugins/cosmosys_zarch` so Redmine's alphabetical loader registers it after
its dependencies. Its registered plugin ID remains `cosmosys_arch`.
Then run migrations in dependency order:

```sh
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=cosmosys
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=cosmosys_req
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=cosmosys_arch
```

The local workspace Compose mounts this plugin under a late-sorting directory
name because Redmine loads plugin initializers alphabetically; its registered
plugin ID remains `cosmosys_arch`.

Create a project with the **Product architecture (PBS)** profile. It uses
`csInfo` as the structural root, allows architecture nodes under other
architecture nodes at any depth, and consolidates positive completion like
requirements. The `archNode` tracker copies its default status and workflow
from `csRq`. The native type field is available in item forms, details,
searches, and reports, and is registered in the ODS/snapshot/copy field
contract. Architecture-node labels use persistent CSIDs in hierarchy,
dependency, and combined diagrams; non-diagram references retain chapter
presentation. A dedicated architecture ODS template with a visible/editable
`arch_type` column remains to be added.

## CAD architecture prototype

Attach a GLB 2.0 and its YAML annotation to an item in an architecture project.
The CAD import action opens a read-only preflight. Each node can be included,
excluded with its entire subtree, or treated as an atomic component. An atomic
subtree containing controls must be expanded before importing those controls.
Geometry visibility is independent from item/report visibility.

Confirmation creates structural items and separate `archDoF` items. Several
rotation and translation controls may belong to one structural item. A DoF
always acts on its immediate structural parent; there is no independent target
property. Creating or moving it under another architecture node updates its
model binding automatically. A DoF cannot be a root or a child of an info item.
Limits, default, axis, local/global space and step are native fields. Rotation
uses degrees; translation uses metres. YAML rest/default is zero.

The node viewer isolates the selected subtree and offers its DoF sliders plus
reset. Slider poses are temporary, not saved as report poses. It reuses the
upstream viewer unchanged, with generic controls supplied by our CAD plugin.
Architecture opts out of editorial report tools only for its preflight and
temporary model views; it does not override or hide the CAD integration's
report-tool partial in ordinary attachment/embedded viewers.
The original GLB remains untouched; a cached derivative adds per-file node
indices for viewer binding. Re-export/synchronization needs stable identities
in a future iteration; indices are not cross-version UUIDs.

The preflight starts with a collapsed tree and a CAD preview beside it. Click
a node name to isolate its complete geometric subtree, or highlight it in the
complete model with the context checkbox. Expand/collapse does not change
decisions. Inspection deliberately includes excluded/invisible nodes so they
can still be identified. Changed decisions disable confirmation until review
is repeated. Invalid atomic/control combinations remain editable with an error.
The preview endpoint uses the same editor permissions as the preflight and
does not require or create imported items. GET review links are read-only.

YAML can declare `rotation_order: YXZ` at model level, or override the order in
a node transform. The default is XYZ; the six intrinsic Euler orders are
accepted. Godot annotations normally need [YXZ](https://docs.godotengine.org/en/4.5/classes/class_node3d.html#class-node3d-property-rotation-order),
not Three.js's default XYZ. This changes the interpretation of Euler offsets,
not the original GLB quaternion, and does not change control-axis names.

Migration 002 uses only Rails schema/ActiveRecord APIs. Rollback refuses to
discard populated CAD architecture data. Snapshot/copy fields include model
configuration and remap model CSIDs. The restored hierarchy identifies each
DoF's controlled node, with parent validation after restore.
Keep the model's GLB/YAML attachments together with its source item.

Future formulas/connectors will express dependencies between parameters and
subordinate DoFs (for example, a leaf opening driving piston motions). They
will not redirect one object's DoF to another object. These dependencies and
YAML export of manually edited controls are not implemented yet.

Initial evaluation focuses on NRT (26 nodes, four controls). Its minimal YAML
comes from `main.yaml`; original gallery annotations are preserved. BancoIFU
is deferred: the collapsed tree/preview is implemented, but that large model
has not been validated. STEP, Blender conversion, PORIS/MQTT,
reimport/reconciliation and persistent poses are not implemented. Blender is
a possible annotation/rest-pose authoring tool; do not apply its corrected
rest pose and old YAML offsets together without reviewing the convention.

The current viewer/importer does not load `.blend` files directly. Keep Blender
as the editable source and export a GLB retaining node names and hierarchy.
When rest poses are corrected in Blender, remove matching compensations from
the YAML rather than applying them twice. Use a fresh import source for the new
GLB: reconciliation of an already imported model is not implemented yet.

## License

GPL-3.0, consistent with cosmoSys and cosmoSys-Req.
