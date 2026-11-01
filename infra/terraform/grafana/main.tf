# The dashboard only (docs/monitoring/grafana-cloud-plan.md). Its data sources,
# li-gcp and li-azure, are created by scripts/cloud-grafana-credentials.sh: a
# grafana_data_source would put their credentials in state.

resource "grafana_folder" "this" {
  title = "Lecture Indexer"
}

resource "grafana_dashboard" "this" {
  folder      = grafana_folder.this.uid
  config_json = file("${path.module}/dashboards/lecture-indexer.json")
}
