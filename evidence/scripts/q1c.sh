cd ~/pse-support-lab
PSQL="docker compose exec -T postgres psql -U invoicely -d invoicely"
{
echo "## Oasis November invoice numbers (no suffix = the three uploads I replayed through the portal): final state per import"
$PSQL -c "select invoice_number, string_agg(left(import_id::text,4)||':'||status, '  ' order by created_at) history, count(*) filter (where status='Accepted') accepted_times from invoices where seller_id=2 and invoice_number ~ '^OBS-2611-00[0-9]$' group by 1 order by 1;"
echo "## ASP side: documents received from Oasis with those numbers (accepted vs rejected)"
curl -s "localhost:8090/v1/documents?sender=0235:1003182746" | python3 -I -c '
import sys,json,collections,re
d=json.load(sys.stdin)
c=collections.Counter((x["invoiceNumber"],x["status"]) for x in d if re.fullmatch(r"OBS-2611-00\d",x["invoiceNumber"]))
for k in sorted(c): print(" ",k,c[k])
print("  total docs from Oasis at ASP:",len(d))'
echo "## the three imports"
$PSQL -c "select left(id::text,8) id, status, duration_ms, created_at::time(0) from imports where seller_id=2 and created_at::date='2026-11-13' order by created_at limit 3;"
} 2>&1 | tee evidence/01-oasis-final-state.txt
