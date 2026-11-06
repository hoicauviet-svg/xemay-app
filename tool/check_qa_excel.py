from pathlib import Path
import json,re
from zipfile import ZipFile
from xml.etree import ElementTree as ET
from datetime import datetime,date
import sys
root=Path(sys.argv[1]);ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'};results=[]
def val(cell):
 if cell.attrib.get('t')=='inlineStr':return ''.join(cell.itertext())
 v=cell.find('s:v',ns)
 if v is None:return None
 n=float(v.text)
 return int(n) if n.is_integer() else n
for path in sorted(root.glob('*.xlsx')):
 period,kind=path.stem.split('-',1);report=json.loads((root/f'reports-{period}.json').read_text())['sections'][kind]
 with ZipFile(path) as z:
  assert z.testzip() is None
  for name in z.namelist():
   if name.endswith('.xml'):ET.fromstring(z.read(name))
  sheet=ET.fromstring(z.read('xl/worksheets/sheet1.xml'))
  assert not sheet.findall('.//s:f',ns),'Unexpected formula'
  data=sheet.find('s:sheetData',ns);rr=list(data)
  header=next(i for i,r in enumerate(rr) if [val(c) for c in r]==report['columns'])
  actual=rr[header+1:];assert len(actual)==len(report['rows']),(path,'row count')
  cells=0
  for ar,expected in zip(actual,report['rows']):
   assert len(ar)==len(expected)
   for column,c,e in zip(report['columns'],ar,expected):
    a=val(c)
    if column.startswith('Mã') and e is not None:e=str(e)
    if c.attrib.get('s')=='5' and isinstance(e,str):
     dt=datetime.fromisoformat(e.replace('Z','+00:00')).date();e=(dt-date(1899,12,30)).days-(1 if dt<date(1900,3,1) else 0)
    # XML strips illegal control chars intentionally, while retaining Vietnamese text.
    if isinstance(e,str):e=e.replace('\r\n','\n').replace('\r','\n');e=re.sub('[\x00-\x08\x0b\x0c\x0e-\x1f]','',e)
    assert a==e,(path,c.attrib.get('r'),a,e)
    cells+=1
  for label,expected in report['totals'].items():
   row=next(r for r in rr[:header] if len(r)>1 and val(r[0])==label)
   assert val(row[1])==expected,(path,'total',label)
  results.append({'file':path.name,'rows':len(actual),'cells':cells,'passed':True})
(root/'excel-independent-validation.json').write_text(json.dumps(results,indent=2))
print(f'PASS: {len(results)} Excel files, {sum(x["rows"] for x in results)} rows, {sum(x["cells"] for x in results)} cells and every summary total match JSON; valid XML/ZIP, no formulas.')
