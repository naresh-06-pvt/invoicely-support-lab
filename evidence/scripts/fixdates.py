import zipfile, re, sys
src, dst = sys.argv[1], sys.argv[2]
zin = zipfile.ZipFile(src)
zout = zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED)
n = 0
for item in zin.infolist():
    data = zin.read(item.filename)
    if item.filename == 'xl/worksheets/sheet2.xml':
        s = data.decode()
        s, n = re.subn(r'>(\d{2})/(\d{2})/(\d{4})<', r'>\3-\2-\1<', s)
        data = s.encode()
    zout.writestr(item, data)
zout.close()
print('converted', n, 'date cells dd/mm/yyyy -> yyyy-mm-dd')
