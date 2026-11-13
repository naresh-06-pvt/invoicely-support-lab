cd ~/pse-support-lab
q() { echo "### $1"; curl -s -G localhost:9090/api/v1/query --data-urlencode "query=$1" | python3 -I -c 'import sys,json;d=json.load(sys.stdin);[print(" ",r["metric"],r["value"][1]) for r in d["data"]["result"]]'; }
{
echo "Prometheus queries run at $(date -u +%FT%TZ) (container time)"
q 'max_over_time(container_memory_working_set_bytes{container_label_com_docker_compose_service="api"}[40m])/1024/1024'
q 'container_memory_working_set_bytes{container_label_com_docker_compose_service="api"}/1024/1024'
q 'changes(container_start_time_seconds{container_label_com_docker_compose_service="api"}[40m])'
q 'sum by (code) (invoicely_asp_responses_total)'
q 'asp_documents_total'
q 'histogram_quantile(0.95, sum by (le) (rate(invoicely_import_duration_seconds_bucket[40m])))'
q 'invoicely_participant_lookup_duration_seconds_sum{result="registered"} / invoicely_participant_lookup_duration_seconds_count{result="registered"}'
q 'invoicely_queue_depth'
} 2>&1 | tee evidence/00-prometheus-queries.txt
