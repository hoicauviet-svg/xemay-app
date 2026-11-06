"""Independent Python audit; does not use Dart report calculators or change application data."""
from pathlib import Path
from pymongo import MongoClient
from bson import json_util
from collections import Counter,defaultdict
from datetime import datetime,timezone
from decimal import Decimal,ROUND_HALF_UP
import json,sys,math
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
name=sys.argv[2]
c=MongoClient('mongodb://127.0.0.1:27017',serverSelectionTimeoutMS=5000);db=c[name]
names=['HoaDonBan','ChiTietHoaDonBan','Xe','SoNo','NhapHang','SanPham','TonKhoPhuTung','NoCu','VayVon','CamDo','TraNoCamDo','ThuChiKhac','KhachHang','DichVu','ChiTietNhapHang','DoiTac','VanChuyen','Xa','TraNo','TraNoNhapHang','TraNoCu','TraNoVayVon']
src={n:list(db[n].find()) for n in names}
(out/'source.json').write_text(json_util.dumps(src))
checks=[];issues=[]
def check(id,actual,expected):
 checks.append(dict(case=id,actual=actual,expected=expected,passed=actual==expected))
def rows(n):return src[n]
def total(rs,key):
 vals=[r.get(key) for r in rs]
 return sum(vals) if all(isinstance(v,(int,float)) and math.isfinite(v) for v in vals) else None
for n,field in [('HoaDonBan','IdHoaDon'),('Xe','IdXe'),('NhapHang','IdNhapHang'),('KhachHang','IdKH'),('TraNo','IdTraNo'),('CamDo','IdCamDo'),('VayVon','IdVayVon')]:
 cnt=Counter(r.get(field) for r in rows(n) if r.get(field) is not None)
 check(n+' unique IDs',sum(v-1 for v in cnt.values()),0)
issues.extend({'kind':'batch_balance','id':r['IdNhapHang'],'total':r.get('SoTien'),'paid':r.get('SoTienDaTra'),'due':r.get('SoTienConNo')} for r in rows('NhapHang') if all(isinstance(r.get(k),(int,float)) for k in ['SoTien','SoTienDaTra','SoTienConNo']) and r['SoTien']!=r['SoTienDaTra']+r['SoTienConNo'])
issues.extend({'kind':'pawn_abnormal_monthly_rate','id':r.get('IdCamDo'),'rate':r.get('LaiSuat')} for r in rows('CamDo') if r.get('TrangThai') is False and r.get('NgayPhanTram') is False and isinstance(r.get('LaiSuat'),(float,int)) and r['LaiSuat']>100)
for n,field in [('TonKhoPhuTung','SoLuongTon'),('SoNo','SoTienConNo'),('NhapHang','SoTienConNo'),('VayVon','TongConNo'),('NoCu','SoCoNo')]:
 bad=[r for r in rows(n) if isinstance(r.get(field),(int,float)) and r[field]<0]
 issues.extend({'kind':'negative_balance','collection':n,'id':str(r.get('_id')),'value':r[field]} for r in bad)
# Each detail must have a parent. Archived orphan rows are not in these collections.
for child,fk,parent,pk in [('ChiTietHoaDonBan','IdHoaDon','HoaDonBan','IdHoaDon'),('ChiTietNhapHang','IdNhapHang','NhapHang','IdNhapHang'),('TraNo','IdSoNo','SoNo','IdSoNo'),('TraNoNhapHang','IdNhapHang','NhapHang','IdNhapHang'),('TraNoCamDo','IdCamDo','CamDo','IdCamDo'),('TraNoVayVon','IdVayVon','VayVon','IdVayVon')]:
 ids={r.get(pk) for r in rows(parent)}
 orphan=[r for r in rows(child) if r.get(fk) not in ids]
 check(child+' parent links',len(orphan),0)
# Independently validate current GUI fixtures; no legacy rows edited.
vehicles={r['TenXe']:r for r in rows('Xe') if str(r.get('TenXe','')).startswith('QA_FULL_1105_')}
for n in ['QA_FULL_1105_N1','QA_FULL_1105_N2','QA_FULL_1105_U1']:
 check(n+' exists',n in vehicles,True)
if 'QA_FULL_1105_N1' in vehicles:
 v=vehicles['QA_FULL_1105_N1'];check('UI N1 expense sum',sum(x['SoTien'] for x in v.get('ChiPhi',[])),500000);check('UI N1 expense cached',v.get('TongChiPhi'),500000)
for kind,rs,key in [('pawn principal',rows('TraNoCamDo'),'TienGoc'),('cash income',[r for r in rows('ThuChiKhac') if r.get('ThuChi') is True],'SoTien'),('cash expense',[r for r in rows('ThuChiKhac') if r.get('ThuChi') is False],'SoTien')]:
 if any(r.get(key) is None for r in rs):issues.append({'kind':'missing_amounts','source':kind,'count':sum(r.get(key) is None for r in rs)})
# Compare simple report projections independently for each period.
for period in ['all','november','today']:
 f=out/('reports-'+period+'.json')
 if not f.exists():continue
 report=json.loads(f.read_text())['sections']
 def inperiod(v):
  if period=='all':return True
  return isinstance(v,datetime) and (v.year,v.month)==(2026,11) and (period!='today' or v.day==5)
 mapping=[('cash','Thu','ThuChiKhac','SoTien','NgayThang',lambda r:r.get('ThuChi') is True),('cash','Chi','ThuChiKhac','SoTien','NgayThang',lambda r:r.get('ThuChi') is False),('receipts','Tiền nhập','NhapHang','SoTien','NgayNhap',lambda r:True),('receipts','Đã trả của lô','NhapHang','SoTienDaTra','NgayNhap',lambda r:True),('receipts','Còn nợ của lô','NhapHang','SoTienConNo','NgayNhap',lambda r:True),('pawn','Tiền cho vay','CamDo','SoTienVay','NgayVay',lambda r:True),('pawnCollections','Gốc đã thu','TraNoCamDo','TienGoc','NgayTra',lambda r:True),('pawnCollections','Lãi thực thu','TraNoCamDo','LaiThu','NgayTra',lambda r:True),('fundingRepayments','Trả gốc','TraNoVayVon','SoTienTraGoc','NgayTra',lambda r:True),('fundingRepayments','Trả lãi','TraNoVayVon','SoTienTraLai','NgayTra',lambda r:True),('oldDebtRepayments','Tiền trả nợ','TraNoCu','SoTienTra','NgayTra',lambda r:True),('oldDebtRepayments','Lãi thực thu','TraNoCu','LaiThu','NgayTra',lambda r:True),('supplierRepayments','Số tiền trả','TraNoNhapHang','SoTienTra','NgayTra',lambda r:True)]
 for section,label,n,field,date,pred in mapping:
  expected=total([r for r in rows(n) if pred(r) and inperiod(r.get(date))],field)
  check(period+' '+section+' '+label,report[section]['totals'].get(label),expected)
 # Vehicle stock is a present balance, unaffected by period.
 for condition,label in [('moi','Xe mới'),('cu','Xe cũ')]:
  vv=[v for v in rows('Xe') if v.get('TinhTrang') is True and not v.get('DangNhapHang') and not v.get('GiuChoBanHang') and v.get('TinhTrangXe')==condition]
  rr=next(r for r in report['stock']['rows'] if r[0]==label)
  check(period+' '+label+' stock quantity',rr[1],len(vv));check(period+' '+label+' stock value',rr[2],total(vv,'GiaNhap'))
 # Every child report row must sum to its reported aggregate for simple sources.
 for section,key,index in [('cash','Thu',4),('cash','Chi',4),('supplierRepayments','Số tiền trả',4),('fundingRepayments','Trả gốc',4),('fundingRepayments','Trả lãi',5)]:
  rs=report[section]['rows'];rs=[r for r in rs if section!='cash' or r[2]==key]
  values=[r[index] for r in rs];want=sum(values) if all(isinstance(v,(int,float)) for v in values) else None
  check(period+' row sum '+section+' '+key,report[section]['totals'].get(key),want)
(out/'independent-audit.json').write_text(json.dumps({'database':name,'checks':checks,'issues':issues},ensure_ascii=False,indent=2,default=str))
print(json.dumps({'checks':len(checks),'failed':sum(not x['passed'] for x in checks),'source_issues':len(issues),'abnormalPawnRates':[x for x in issues if x['kind']=='pawn_abnormal_monthly_rate']},ensure_ascii=False))
