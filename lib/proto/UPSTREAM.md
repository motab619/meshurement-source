# Vendored Meshtastic protobufs

The `.proto` and `.options` files here are copied **unmodified** from
<https://github.com/meshtastic/protobufs>, licensed GPL-3.0 (see `LICENSE`
beside this file), © Meshtastic LLC. The `*.pb*.dart` files are generated
from them and are not hand-edited.

| | |
|---|---|
| Upstream tag | `v2.8.2` (firmware 2.8.2; earlier: v2.7.26 until 2026-11-10) |
| Upstream commit | `ffd5ad428da6db4a7ddfe62e06548718cc2603e0` (2026-10-28) |
| protoc | 36.2 (libprotoc 36.2) |
| protoc_plugin | 22.5.0, for the `protobuf` ^4.2 Dart runtime |
| Generated | 2026-11-10 |

To regenerate (e.g. for a new firmware release), check out the upstream tag
and run `tool/gen_protos.sh <protoc-bin-dir> <protobufs-checkout>`, then update
this table. `nanopb.proto` is kept for reference only; its Dart isn't
generated because no Meshtastic message depends on it at runtime.

Meshtastic® is a registered trademark of Meshtastic LLC. Meshurement is not
affiliated with or endorsed by Meshtastic LLC.
