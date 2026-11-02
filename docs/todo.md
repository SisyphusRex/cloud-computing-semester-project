# To do

Work we need to do that isn't scheduled in the [implementation plan](implementation-plan.md) yet. Move an item there, or delete it, once it's picked up. Optional improvements are in the [wishlist](wishlist.md).

## Finish the Grafana setup

From the [Grafana Cloud plan](monitoring/grafana-cloud-plan.md#how-well-know-it-works):

1. Check that "Backups stored" on the dashboard catches up with `make cloud-restore ARGS="list"`. It lags by several hours: the 21:25 UTC backup on 2026-11-01 is in Azure, and the chart still showed 4 almost 2 hours later.
