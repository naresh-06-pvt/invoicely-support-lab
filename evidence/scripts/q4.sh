cd ~/pse-support-lab
PSQL="docker compose exec -T postgres psql -U invoicely -d invoicely"
SENDER="0235:1006453719"
{
echo "## Sahara imports"
$PSQL -c "select left(id::text,8) id, status, invoice_count, created_at::time(0) from imports where seller_id=5 order by created_at;"
echo "## Sahara invoice status (today's batch = latest import)"
$PSQL -c "select status, count(*), count(*) filter (where asp_message_id <> '') with_asp_ref from invoices where seller_id=5 and import_id=(select id from imports where seller_id=5 order by created_at desc limit 1) group by 1;"
echo "## Submitted invoices: first 3 and their status history (what the portal shows)"
$PSQL -c "select i.invoice_number, e.status, e.detail, e.created_at::time(0) from invoices i join invoice_events e on e.invoice_id=i.id where i.seller_id=5 and i.status='Submitted' and i.invoice_number in (select invoice_number from invoices where seller_id=5 and status='Submitted' order by invoice_number limit 2) order by 1, e.created_at;"
echo "## ASP side: documents it holds for Sahara by status"
curl -s "localhost:8090/v1/documents?sender=$SENDER" | python3 -I -c 'import sys,json,collections;d=json.load(sys.stdin);print(len(d),"docs",dict(collections.Counter(x["status"] for x in d)))'
echo "## ASP log: rate limit lines for Sahara"
docker compose logs asp-mock 2>&1 | grep 'rate limit exceeded' | grep -c "$SENDER"
docker compose logs asp-mock 2>&1 | grep 'rate limit exceeded' | grep "$SENDER" | head -2 | cut -c1-260
echo "## api log: what the api logged for a 429 (note: info only, nothing after)"
docker compose logs api 2>&1 | grep '"status_code":429' | head -2 | cut -c1-260
echo "## asp metrics"
curl -s localhost:8090/metrics | grep -E '^asp_documents_total|^asp_requests_total\{endpoint="submit"'
echo "## try Retry submission on a stuck Submitted invoice"
id=$($PSQL -t -A -c "select id from invoices where seller_id=5 and status='Submitted' limit 1;")
curl -s -w '\nHTTP %{http_code}\n' -X POST localhost:8080/v1/invoices/$id/retry
echo "## try re-uploading the same file (what Daniel would do)"
curl -s -F file=@samples/sahara-medical-batch-1116.xlsx -F seller_id=5 localhost:8080/v1/imports | python3 -I -c 'import sys,json;d=json.load(sys.stdin);print(d["status"],{k:v for k,v in d["statusCounts"].items() if v})'
} 2>&1 | tee evidence/04-sahara-analysis.txt
