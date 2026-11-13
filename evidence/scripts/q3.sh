cd ~/pse-support-lab
PSQL="docker compose exec -T postgres psql -U invoicely -d invoicely"
{
echo "## Al Noor: today's import, status per invoice with portal totals"
$PSQL -c "select invoice_number, status, total_excl_vat net, total_vat vat, total_incl_vat gross_stored, round((total_excl_vat+total_vat)::numeric,2) net_plus_vat, round((total_incl_vat-(total_excl_vat+total_vat))::numeric,2) diff from invoices where seller_id=4 and import_id=(select id from imports where seller_id=4 order by created_at desc limit 1) order by invoice_number;"
echo "## ASP rejection text for a rejected one"
$PSQL -t -A -c "select invoice_number||' -> '||errors::text from invoices where seller_id=4 and status='Rejected' and rejected_by='asp' order by created_at desc limit 1;"
echo "## Per-line arithmetic of every Al Noor invoice from the latest import (payload sent to ASP)"
$PSQL -t -A -c "select payload::text from invoices where seller_id=4 and import_id=(select id from imports where seller_id=4 order by created_at desc limit 1) order by invoice_number;" > /tmp/alnoor_payloads.txt
python3 -I - <<'PY'
import json
from decimal import Decimal, ROUND_HALF_UP
def r2(x): return float(Decimal(repr(x)).quantize(Decimal('0.01'), rounding=ROUND_HALF_UP))
print(f"{'invoice':16} {'lines':>5} {'sum net':>10} {'sum vat':>9} {'net+vat':>10} {'sent gross':>11} {'diff':>6}  qty x price (3dp price)")
for ln in open('/tmp/alnoor_payloads.txt'):
    ln = ln.strip()
    if not ln: continue
    p = json.loads(ln); L = p['lines']; T = p['totals']
    net = sum(l['netAmount'] for l in L); vat = sum(l['vatAmount'] for l in L)
    sample = '; '.join(f"{l['quantity']}x{l['unitPrice']}={l['quantity']*l['unitPrice']:.5f}->{l['netAmount']}" for l in L[:2])
    print(f"{p['invoiceNumber']:16} {len(L):5} {net:10.2f} {vat:9.2f} {net+vat:10.2f} {T['taxInclusiveAmount']:11.2f} {T['taxInclusiveAmount']-(r2(net)+r2(vat)):6.2f}  {sample}")
PY
} 2>&1 | tee evidence/03-alnoor-analysis.txt
