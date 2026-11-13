cd ~/pse-support-lab
S=/mnt/c/Users/PAVADH~1/AppData/Local/Temp/claude/826a710d35881a30/23937c95-8af0-4f36-91d9-a214c709af15/scratchpad
summ='import sys,json
d=json.load(sys.stdin)
print("import status:",d["status"],"| invoices:",d["invoiceCount"],"| counts:",{k:v for k,v in d["statusCounts"].items() if v})
for i in d["invoices"]: print(" ",i["invoiceNumber"],i["status"],i["rejectedBy"],"errors:",i["errorCount"])'
{
echo "### 1) ORIGINAL file as the customer sent it"
curl -s -F file=@samples/ghaf-cafe-nov-2026.xlsx -F seller_id=6 localhost:8080/v1/imports > evidence/05-ghaf-original-upload.json
python3 -I -c "$summ" < evidence/05-ghaf-original-upload.json
echo
echo "### error detail of first invoice"
id=$(python3 -I -c 'import sys,json;print(json.load(sys.stdin)["invoices"][0]["id"])' < evidence/05-ghaf-original-upload.json)
curl -s localhost:8080/v1/invoices/$id | python3 -I -c 'import sys,json;d=json.load(sys.stdin);print(json.dumps(d.get("errors"),indent=1))'
echo
echo "### 2) same file with ONLY the dates changed to YYYY-MM-DD"
python3 -I $S/fixdates.py samples/ghaf-cafe-nov-2026.xlsx evidence/ghaf-cafe-nov-2026-dates-fixed.xlsx
curl -s -F file=@evidence/ghaf-cafe-nov-2026-dates-fixed.xlsx -F seller_id=6 localhost:8080/v1/imports > evidence/05-ghaf-fixed-upload.json
python3 -I -c "$summ" < evidence/05-ghaf-fixed-upload.json
} 2>&1 | tee evidence/05-ghaf-results.txt
