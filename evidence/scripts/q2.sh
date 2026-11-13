cd ~/pse-support-lab
PSQL="docker compose exec -T postgres psql -U invoicely -d invoicely"
{
echo "## make load output"; tail -25 evidence/02-make-load-output.txt
echo; echo "## sampler (every ~6s): api memory + restart count"; cat evidence/02-load-sampler.txt
echo; echo "## container state now"
docker inspect invoicely-lite-api-1 --format 'api: restarts={{.RestartCount}} oom={{.State.OOMKilled}} exit={{.State.ExitCode}} started={{.State.StartedAt}}'
docker inspect invoicely-lite-asp-mock-1 --format 'asp-mock: restarts={{.RestartCount}} oom={{.State.OOMKilled}} started={{.State.StartedAt}}'
echo; echo "## api log: startups"
docker compose logs api 2>&1 | grep -E '"api starting"|workers started' | cut -c1-200
echo; echo "## invoices by seller/status"
$PSQL -c "select s.name, i.status, count(*) from invoices i join sellers s on s.id=i.seller_id group by 1,2 order by 1,2;"
echo "## stuck Validated older than 5 min"
$PSQL -c "select s.name, count(*), min(i.updated_at) from invoices i join sellers s on s.id=i.seller_id where i.status='Validated' and i.updated_at < now()-interval '5 minutes' group by 1;"
echo "## stuck Submitted"
$PSQL -c "select s.name, count(*), min(i.updated_at) from invoices i join sellers s on s.id=i.seller_id where i.status='Submitted' group by 1;"
} 2>&1 | tee evidence/02-load-results.txt
