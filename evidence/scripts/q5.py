import zipfile, re, sys
z = zipfile.ZipFile(sys.argv[1])
ss = re.findall(r'<si>(.*?)</si>', z.read('xl/sharedStrings.xml').decode(), re.S)
ss = [re.sub('<[^>]+>', '', s) for s in ss]
for i in (1, 2, 3):
    name = f'xl/worksheets/sheet{i}.xml'
    sheet = z.read(name).decode()
    hdr = {}
    out = []
    for rn, body in re.findall(r'<row [^>]*r="(\d+)"[^>]*>(.*?)</row>', sheet, re.S):
        for m in re.finditer(r'<c r="([A-Z]+)(\d+)"([^>]*?)(?:/>|>(.*?)</c>)', body, re.S):
            col, r, attrs, inner = m.groups()
            t = re.search(r't="(\w+)"', attrs)
            t = t.group(1) if t else 'n'
            s = re.search(r's="(\d+)"', attrs)
            v = re.search(r'<v>(.*?)</v>', inner or '')
            if v: v = v.group(1)
            else:
                tt = re.search(r'<t[^>]*>(.*?)</t>', inner or '', re.S)
                v = tt.group(1) if tt else ''
            if t == 's' and v != '': v = ss[int(v)]
            if rn == '1': hdr[col] = v
            elif hdr.get(col, '').startswith(('Invoice issue date', 'Payment due date', 'Invoice number')):
                out.append(f'row {rn} {hdr[col]:22} cell_type={t:3} style={s.group(1) if s else None} value={v!r}')
    if any('Invoice number' in h for h in hdr.values()):
        print('sheet file:', name)
        print('\n'.join(out))
