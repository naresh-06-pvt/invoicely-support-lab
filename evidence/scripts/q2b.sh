cd ~/pse-support-lab
PSQL="docker compose exec -T postgres psql -U invoicely -d invoicely"
{
echo "## docker events for api container (oom / die / restart) since start"
docker events --since 40m --until 0s --filter container=invoicely-lite-api-1 --filter event=oom --filter event=die --filter event=kill --filter event=restart --filter event=start --format '{{.Time}} {{.Action}} exitCode={{index .Actor.Attributes "exitCode"}} oom={{index .Actor.Attributes "oomKilled"}}' 2>&1 | while read t rest; do echo "$(date -u -d @$t +%T) $rest"; done
echo
echo "## last api log lines before 1st restart (16:23:30-16:23:41)"
docker compose logs api --no-log-prefix 2>&1 | awk -F'"time":"' '{split($2,a,"\""); if (a[1] >= "2026-11-13T16:23:33" && a[1] <= "2026-11-13T16:23:41") print}' | tail -6 | cut -c1-260
echo
echo "## eviction of SourceCache anywhere in code?"
grep -rn "sources\.\|entries\[" services/api --include=*.go | grep -v _test
grep -n "delete(" services/api/internal/importer/sources.go || echo "no delete() in sources.go -> entries are never removed"
echo
echo "## web proxy 502/504 count"
docker compose logs web 2>&1 | grep -c '"status":502'; docker compose logs web 2>&1 | grep -c '"status":504'
docker compose logs web 2>&1 | grep '"status":502' | head -2 | cut -c1-300
echo
echo "## imports left Processing (killed mid-way)"
$PSQL -c "select status,count(*) from imports group by 1;"
echo "## invoices left in Parsed (never validated) per seller"
$PSQL -c "select s.name,count(*) from invoices i join sellers s on s.id=i.seller_id where i.status='Parsed' group by 1;"
echo "## asp responses by code (api view)"
curl -s localhost:8080/metrics | grep -E '^invoicely_asp_responses|^invoicely_submit' | head
echo "## asp 429 count + asp-mock restarts"
docker compose logs asp-mock 2>&1 | grep -c 'rate limit exceeded'
} 2>&1 | tee evidence/02-restart-analysis.txt
