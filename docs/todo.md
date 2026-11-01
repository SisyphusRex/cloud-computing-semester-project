# To do

Work we need to do that isn't scheduled in the [implementation plan](implementation-plan.md) yet. Move an item there, or delete it, once it's picked up. Optional improvements are in the [wishlist](wishlist.md).

## Finish the backup setup

From the [record of the setup](milestones/m3_technical_review/azure-backup-setup.md):

1. Run `make cloud-pause`, and confirm it takes a backup first. After `make cloud-resume`, `kubectl -n li get cronjob backup` should show `SUSPEND` as `False`.

## Finish the Grafana setup

From the [Grafana Cloud plan](monitoring/grafana-cloud-plan.md#how-well-know-it-works):

1. Check that "Backups stored" on the dashboard catches up with `make cloud-restore ARGS="list"`. It lags by several hours: the 21:25 UTC backup on 2026-11-01 is in Azure, and the chart still showed 4 almost 2 hours later.
2. Run the forced failure in the [backup runbook](runbooks/backup-and-restore.md#check-the-protections), confirm `backup_failed` rises on the dashboard, and put the CronJob back. It emails the alert channel.
3. Confirm the charts resume after `make cloud-pause` and `make cloud-resume`, with no change in Grafana.
4. Run `make cloud-grafana-credentials` again, and confirm that the old credentials stop working and both data sources still pass.
5. Ask WMU IT to delete the ownerless Azure app `li-grafana`, client ID `43d8235c-798b-40c7-832c-89ac9abb73bb` ([why it exists](architecture_decision_records/0005-monitoring-on-grafana-cloud.md#consequences)). It has no owner, credentials or roles, so it's harmless.

## Test the onboarding guide

Have someone who hasn't worked on the project follow [onboarding.md](onboarding.md), and fix what trips them up.
