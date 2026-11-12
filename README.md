# cosmoSys Architecture

Version **0.1.8-dirty** (experimental development).

Imported architecture items show a static image of their CAD piece. Click it
to open the interactive viewer. Sign in with permission to edit the item and
save CAD attachment views to save a shared default camera or named views.
The default camera is shared by all users; it is not a personal preference.

Reports automatically include that piece's default PNG after the description,
before fields and metadata, without adding a macro. The same image is used in
HTML, ODT, DOCX and PDF. Automatic report figures are at most 450 px high
(about 11.9 cm in print), preserving their aspect ratio and original PNG.
Opening the HTML report prepares missing captures one at a time. They are
saved only if you can edit the item and save CAD views; otherwise they remain
available on that page only. Exports wait for preparation to finish. Direct
server exports cannot render missing CAD captures and show a viewer link.
There is currently no per-item or report visibility setting.

Default figures use deliberate lazy initialization: opening a piece or an HTML
report prepares its default camera/PNG when no current capture exists. This
lets you generate a report without manually selecting a default view for every
piece first. Current saved figures are reused; missing or stale captures are
prepared on demand. With the required edit/save permissions this initialization
writes a shared view and PNG; without them the generated image stays on the page
only. You can subsequently replace the shared default in the interactive viewer.

Only camera and appearance are saved, not slider positions. Captures use the
model's default positions without changing the temporary pose you are viewing.
Saved cameras are not yet included in project snapshots or copies.

To reimport after removing an imported model's items, open its source item and
choose **Reset CAD import**. Confirm on the next page; the GLB/YAML attachments,
item identity, history and saved views are preserved. Reset is blocked while
children or linked items remain, including items moved elsewhere in the project
tree. Requires the same edit/import permissions as CAD import. Then select the
files again and run the preflight; reset does not import anything itself.

> **EXPERIMENTAL — opt-in:** This plugin is not part of the production core.
> Expect defects, incomplete features, performance limits and breaking changes.
> Do not install it if you require production-level stability and support.


`cosmosys_arch` adds an architecture/PBS project profile to cosmoSys. Its
`archNode` items form an unrestricted-depth parent/child hierarchy and carry a
native `arch_type` value (`complex`, `optical`, `mechanical`, `hardware`, or
`software`). There are no architecture links to requirements or test items yet;
traceability is deferred.

## Requirements

- Redmine 7.0.1
- [cosmoSys](https://github.com/cosmoBots/cosmoSys) 0.2.10 or later
- [cosmoSys Requirements](https://github.com/cosmoBots/cosmoSys_Req) 0.3.6 or later
- [cosmoSys CAD Preview](https://github.com/cosmoBots/cosmoSys_cad_preview) 0.1.8 or later

Architecture projects use the base cosmoSys trackers plus `archNode` and
`archDoF`; they do not enable requirement trackers.

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

Back up the database and files before migrating. Removing the CAD schema is
refused while it contains imported architecture data; do not use rollback as a
way to discard an existing model.


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

Attach an annotated GLB 2.0 to an item in an architecture project. Choose
**No YAML — use embedded GLB annotations** on the import screen. Unannotated
GLBs still require a YAML attachment.

Embedded controls use the `cosmosys.cad.controls` version 1 contract: a scene
root carries `extras.cosmosys_model` with `schema`, `version` and
`rotation_order: XYZ`; each controlled node carries a `cosmosys_controls`
mapping. Controls specify their own node, motion, local/global space, axis,
limits and step in glTF coordinates, degrees and metres. Default offsets are zero.
Unknown versions, duplicate keys and foreign/missing targets are rejected.
If YAML is supplied alongside embedded controls, both must agree. Conflicting
controls, rotation order or additional pose overrides block preflight instead
of silently choosing one source.

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
uses degrees; translation uses metres. Import rest/default is zero.

The node viewer isolates the selected subtree and offers its DoF sliders plus
reset. Slider poses are temporary and do not change the original GLB or saved
camera. Keep the imported model unchanged: updating an existing import to a new
CAD revision is not supported yet.

To save a camera, sign in and click the piece image. Adjust the view and choose
**Save as default** to use it on the item's detail page, or enter a name
and save a named view. The selector lists saved views; use **Restore view** to
return to one. Saving requires both item-editing and CAD attachment-view
permissions. Anonymous visitors can view public pieces but cannot save cameras.

The preflight starts with a collapsed tree and a CAD preview beside it. Click
a node name to isolate its complete geometric subtree, or highlight it in the
complete model with the context checkbox. Expand/collapse does not change
decisions. Inspection deliberately includes excluded/invisible nodes so they
can still be identified. Changed decisions disable confirmation until review
is repeated. Invalid atomic/control combinations remain editable with an error.
The preview endpoint uses the same editor permissions as the preflight and
does not require or create imported items. GET review links are read-only.

Use **Bulk selection** to match node names or CAD paths, optionally with a
case-insensitive regular expression such as `DIN|M3`. Preview the matches
before applying include/exclude/atomic or geometry-visibility decisions. An
exclusion applies to the whole subtree. Repeat review before importing; no
items are created by filtering. Invalid or overlong-running expressions leave
the decisions unchanged.

YAML can declare `rotation_order: YXZ` at model level, or override the order in
a node transform. The default is XYZ; the six intrinsic Euler orders are
accepted. Godot annotations normally need [YXZ](https://docs.godotengine.org/en/4.5/classes/class_node3d.html#class-node3d-property-rotation-order),
not Three.js's default XYZ. This changes the interpretation of Euler offsets,
not the original GLB quaternion, and does not change control-axis names.

Keep the GLB and any YAML annotation with the source item so project
snapshots and copies can include them. Parameter coupling, STEP import,
reimport/reconciliation and saved motion poses are not supported yet.

The current viewer/importer does not load `.blend` files directly. Keep Blender
as the editable source and export a GLB retaining node names and hierarchy.
When rest poses are corrected in Blender, remove matching compensations from
the YAML rather than applying them twice. Use a fresh import source for the new
GLB: reconciliation of an already imported model is not implemented yet.

## License

GPL-3.0, consistent with cosmoSys and cosmoSys-Req.
