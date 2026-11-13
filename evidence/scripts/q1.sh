cd ~/pse-support-lab
PSQL="docker compose exec -T postgres psql -U invoicely -d invoicely"
{
echo "## imports for Oasis (seller 2)"
$PSQL -c "select left(id::text,8) id, status, row_count, invoice_count, duration_ms, created_at, completed_at from imports where seller_id=2 order by created_at;"
echo "## invoices per import and status"
$PSQL -c "select left(import_id::text,8) imp, status, count(*) from invoices where seller_id=2 group by 1,2 order by 1,2;"
echo "## duplicates rejected AE-BR-09"
$PSQL -c "select count(*) from invoices where seller_id=2 and status='Rejected';"
} 2>&1 | tee evidence/01-oasis-db-state.txt
echo "## api logs"
docker compose logs api --since 10m 2>&1 | grep -E 'import|restart|starting|error' | head -30 | tee evidence/01-oasis-api-logs.txt
docker inspect invoicely-lite-api-1 --format 'restarts={{.RestartCount}} oom={{.State.OOMKilled}} started={{.State.StartedAt}}'
cat evidence/01-api-mem-during-oasis.txt
