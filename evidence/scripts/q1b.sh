cd ~/pse-support-lab
PSQL="docker compose exec -T postgres psql -U invoicely -d invoicely"
{
echo "## imports (final)"
$PSQL -c "select left(id::text,8) id, status, duration_ms, created_at::time(0) started from imports where seller_id=2 order by created_at;"
echo "## each invoice number: status per import (Nov file only)"
$PSQL -c "select invoice_number, string_agg(left(import_id::text,4)||':'||status, '  ' order by created_at) as history from invoices where seller_id=2 and created_at > '2026-11-01' group by 1 order by 1;"
echo "## the AE-BR-09 messages"
$PSQL -c "select invoice_number, left(import_id::text,4) imp, rejected_by, left(errors::text,160) from invoices where seller_id=2 and status='Rejected' order by created_at limit 4;"
echo "## timing of buyer lookups (prometheus avg)"
curl -s localhost:8080/metrics | grep -E 'participant_lookup.*(_sum|_count)'
} 2>&1 | tee evidence/01-oasis-db-state-final.txt
