"""Pure, audited XM transformations. Input and original MongoDB are never mutated."""
import copy
import math
from datetime import datetime, timezone
from bson import ObjectId
from inventory_schema import build as inventory_build, CATALOG_SCHEMA, VEHICLE_SCHEMA, STOCK_SCHEMA
from sales_schema import schemas as sales_schemas


def orphan_cleanup(rows, metadata):
    relations = set()
    for fk in metadata.get('foreign_keys', []):
        child = fk['source_table'] if fk.get('source_schema','dbo') == 'dbo' else fk['source_schema']+'.'+fk['source_table']
        parent = fk['target_table'] if fk.get('target_schema','dbo') == 'dbo' else fk['target_schema']+'.'+fk['target_table']
        relations.add((child,fk['source_column'],parent,fk['target_column']))
    relations.update([
        ('KhachHang','IdXa','Xa','IdXa'),('Xe','IdHangXe','HangXe','IdHangXe'),
        ('XeMoi','IdXe','Xe','IdXe'),('XeCu','IdXe','Xe','IdXe'),('XeMoi','IdNhapHang','NhapHang','IdNhapHang'),
        ('HoaDonBan','IdKH','KhachHang','IdKH'),('HoaDonBan','IdXe','Xe','IdXe'),
        ('HoaDonMua','IdKh','KhachHang','IdKH'),('HoaDonMua','IdXe','Xe','IdXe'),
        ('SoNo','IdHoaDon','HoaDonBan','IdHoaDon'),('TraNo','IdSoNo','SoNo','IdSoNo'),
        ('CamDo','IdKhachHang','KhachHang','IdKH'),('TraNoCamDo','IdCamDo','CamDo','IdCamDo'),
        ('TraNoNhapHang','IdNhapHang','NhapHang','IdNhapHang'),('TraNoVayVon','IdVayVon','VayVon','IdVayVon'),
        ('TraNoCu','IdNoCu','NoCu','Id'),('NoCu','IdKH','KhachHang','IdKH'),
    ])
    removed=[]
    while True:
        invalid={}
        for child,field,parent,key in sorted(relations):
            if child not in rows or parent not in rows: continue
            normalize=(lambda v:str(v).strip()) if (child,field)==('NoCu','IdKH') else (lambda v:v)
            ids={normalize(r[key]) for r in rows[parent].values() if key in r}
            for oid,row in rows[child].items():
                value=row.get(field)
                if value is None or (isinstance(value,str) and not value.strip()): continue
                if normalize(value) not in ids: invalid.setdefault((child,oid),[]).append(f'{field} -> {parent}.{key}')
        if not invalid: break
        for (name,oid),reasons in invalid.items():
            removed.append({'collection':name,'document':rows[name].pop(oid),'reasons':reasons})
    return removed


def normalize(raw, metadata, progress=lambda message: None):
    rows=copy.deepcopy(raw)
    removed=orphan_cleanup(rows,metadata)
    progress(f'Đã dọn {len(removed)} bản ghi thiếu bản ghi cha')
    if 'SanPham' in rows or 'ChiTietHoaDonBan' in rows:
        raise ValueError('Nguồn SQL đã có cấu trúc chuyển đổi khác; cần đối chiếu trước khi sao chép.')
    for name in ['Xe','XeMoi','XeCu','HoaDonBan','HoaDonMua','NhapHang','KhachHang','Xa','SoNo','TraNo','NoCu']:
        rows.setdefault(name,{})
    new={r['IdXe'] for r in rows['XeMoi'].values()}
    used={r['IdXe'] for r in rows['XeCu'].values()}
    if new & used: raise ValueError('Có xe đồng thời thuộc xe mới và xe cũ.')
    renames={'Xe':{'IdXe':'IdSanPham','TenXe':'TenSanPham'},
             'XeMoi':{'IdXe':'IdSanPham'},'XeCu':{'IdXe':'IdSanPham'},
             'HoaDonBan':{'IdXe':'IdSanPham'},'HoaDonMua':{'IdXe':'IdSanPham'}}
    for name,fields in renames.items():
        for row in rows[name].values():
            if any(k in row for k in fields.values()): raise ValueError('Trùng trường dữ liệu sản phẩm nguồn.')
            for old,field in fields.items():
                if old in row: row[field]=row.pop(old)
            if name=='Xe':
                xid=row['IdSanPham']
                row.update(LoaiSanPham='xe_moi' if xid in new else 'xe_cu' if xid in used else 'chua_phan_loai',
                           DonViTinh='chiếc',QuanLyTonKho='tung_chiec')
    rows['SanPham']=rows.pop('Xe')
    rows,_=inventory_build(rows)
    progress('Đã chuẩn hóa sản phẩm, xe mới, xe cũ, phụ tùng và chi tiết đơn hàng')
    now=datetime.now(timezone.utc)
    for collection,source,ref,title,fields in [
        ('DoiTac','NoiNhap','IdDoiTac','TenDoiTac',['SoDienThoai','DiaChi','MaSoThue','NguoiDaiDien','GhiChu']),
        ('VanChuyen','NguoiCho','IdVanChuyen','TenVanChuyen',['SoDienThoai','BienSoXe','GhiChu']),
    ]:
        rows[collection]={}; names={}
        for row in rows['NhapHang'].values():
            value=row.get(source)
            if not isinstance(value,str) or not value.strip(): continue
            if value not in names:
                oid=str(ObjectId()); names[value]=oid
                rows[collection][oid]={'_id':oid,title:value.strip(),**{f:'' for f in fields},'TenNguon':value,
                    'Nguon':'NhapHang.'+source,'NgayTao':now,'CanBoSungThongTin':True}
            row[ref]=names[value]
    customers={r['IdKH']:r for r in rows['KhachHang'].values()}
    places={r['IdXa']:r.get('TenXa','') for r in rows['Xa'].values()}
    sellers={r['IdKh'] for r in rows['HoaDonMua'].values()}
    roles={str(r.get(field)).strip() for name,field in [('HoaDonBan','IdKH'),('CamDo','IdKhachHang'),('NoCu','IdKH')]
           for r in rows.get(name,{}).values()}
    for key in sorted(sellers):
        customer=customers[key]; oid=str(ObjectId())
        rows['DoiTac'][oid]={'_id':oid,'TenDoiTac':(customer.get('TenKhachHang') or '').strip() or f'Người bán #{key}',
            'SoDienThoai':customer.get('SoDienThoai') or '',
            'DiaChi':', '.join(str(v).strip() for v in [customer.get('DiaChiChiTiet'),places.get(customer.get('IdXa'))] if v is not None and str(v).strip()),
            'MaSoThue':'','NguoiDaiDien':'','GhiChu':'','IdKhachHangNguon':key,'Nguon':'HoaDonMua.IdKh','NgayTao':now}
        customer.update(IdDoiTac=oid,AnKhoiDanhSachKhachHang=str(key) not in roles)
        for purchase in rows['HoaDonMua'].values():
            if purchase.get('IdKh')==key: purchase['IdDoiTac']=oid
    progress('Đã tách đối tác, nhà cung cấp và vận chuyển')
    purchase_count=merge_purchases(rows)
    legacy_totals=0
    vehicle={r['IdXe']:r for r in rows['Xe'].values()}
    for order in rows['HoaDonBan'].values():
        price=vehicle.get(order.get('IdXe'),{}).get('GiaBan')
        if order.get('PhienBanBanHang') is None and valid_money(price) and float(price).is_integer():
            if order.get('TongTienHang') is None: order['TongTienHang']=int(price)
            if order.get('GiamGia') is None: order['GiamGia']=0
            if order.get('TongThanhToan') is None: order['TongThanhToan']=int(price)-order['GiamGia']
            legacy_totals+=1
    correction=correct_1826(rows)
    for name in ['DichVu','GiaoDichBanHang','GiaoDichNhapHang','ChiTietNhapHang','DanhMucThuChi']:
        rows.setdefault(name,{})
    for key,label,income in [
        ('product-cost','Chi phí sản phẩm',False),('customer-interest','Lãi khách hàng trả nợ',True),
        ('store-cost','Chi phí cửa hàng',False),('utilities','Điện nước',False),('salary','Lương nhân viên',False),
        ('transport','Vận chuyển',False),('other-income','Thu khác',True),('other-expense','Chi khác',False),
    ]:
        rows['DanhMucThuChi'].setdefault(key,{'_id':key,'TenDanhMuc':label,'ThuChi':income,'HoatDong':True})
    markers={key:{'_id':key,'verified':True,'AppliedAt':now} for key in [
        'product_schema_v2','business_directory_v1','seller_partners_v1','sales_schema_v3',
        'sales_debt_dates_v1','receipt_costs_v1','purchase_receipts_v1']}
    markers['source_schema']={'_id':'source_schema',**metadata}
    markers['purchase_receipts_v1']['purchase_count']=purchase_count
    report={'orphan_count':len(removed),'purchases_merged':purchase_count,'legacy_totals':legacy_totals,
            'order_1826':correction,'source_counts':{k:len(v) for k,v in raw.items()},'final_counts':{k:len(v) for k,v in rows.items()}}
    markers['settings_clone_v1']={'_id':'settings_clone_v1','AppliedAt':now,**report}
    rows['_sql_metadata']=markers
    progress(f'Đã gộp {purchase_count} đơn mua thành lô; đối chiếu tiền hàng và đơn #1826: {correction}')
    return rows,report,removed


def valid_money(value):
    return isinstance(value,(int,float)) and math.isfinite(value) and 0<=value<2**63


def merge_purchases(rows):
    rows.setdefault('ChiTietNhapHang',{});rows.setdefault('TraNoNhapHang',{})
    vehicle={r['IdXe']:r for r in rows['Xe'].values()}
    rid=max((r['IdNhapHang'] for r in rows['NhapHang'].values()),default=0)
    pid=max((r['IdTraNoNhapHang'] for r in rows['TraNoNhapHang'].values()),default=0)
    used=set()
    linked={r['IdXe'] for r in rows['XeMoi'].values() if r.get('IdNhapHang') is not None}
    for h in sorted(rows['HoaDonMua'].values(),key=lambda r:r['IdMua']):
        v=vehicle[h['IdXe']]; price=h.get('GiaBan'); source=h['IdMua']
        if not valid_money(price) or h['IdXe'] in used or v.get('IdNhapHang') is not None or h['IdXe'] in linked:
            raise ValueError(f'Đơn mua #{source} có giá hoặc liên kết lô cần đối chiếu.')
        used.add(h['IdXe']);rid+=1
        oid=f'legacy-purchase-{source}'
        rows['NhapHang'][oid]={'_id':oid,'IdNhapHang':rid,'IdMuaNguon':source,'NguonDuLieu':'HoaDonMua',
            'SoLuong':1,'SoTien':price,'SoTienDaTra':price,'SoTienConNo':0,'NgayNhap':h.get('NgayBan'),
            'IdDoiTac':h['IdDoiTac'],'NoiNhap':rows['DoiTac'][h['IdDoiTac']]['TenDoiTac'],'NguoiCho':'',
            'LoaiSanPham':'xe_moi' if v['TinhTrangXe']=='moi' else 'xe_cu','GhiChu':h.get('GhiChu') or '',
            'IdKhachHangNguon':h.get('IdKh'),'QuyUocThanhToan':'don_mua_cu_thanh_toan_du'}
        line_id=f'legacy-purchase-line-{source}'
        rows['ChiTietNhapHang'][line_id]={'_id':line_id,'IdNhapHang':rid,'IdMuaNguon':source,
            'IdSanPham':v['IdSanPham'],'IdXe':v['IdXe'],'TenSanPham':v.get('TenXe') or '',
            'SoLuong':1,'GiaNhap':price,'ChiPhi':[],'TongChiPhi':0}
        v['IdNhapHang']=rid
        if price>0:
            pid+=1;key=f'legacy-purchase-payment-{source}'
            rows['TraNoNhapHang'][key]={'_id':key,'IdTraNoNhapHang':pid,'IdNhapHang':rid,'IdMuaNguon':source,
                'SoTienTra':price,'NgayTra':h.get('NgayBan'),'SoCoNo':0,'GhiChu':'Chuyển đổi đơn mua cũ: mặc định thanh toán đủ theo yêu cầu',
                'NguonDuLieu':'HoaDonMua'}
    for n in ['HoaDonMua','ChiTietHoaDonMua']:
        rows['__source_'+n]=rows.pop(n)
    for row in rows['NhapHang'].values(): row.pop('HinhThucNhap',None)
    return len(used)


def correct_1826(rows):
    order=next((r for r in rows['HoaDonBan'].values() if r.get('IdHoaDon')==1826),None)
    if order is None: return 'không có trong nguồn'
    debts=[r for r in rows['SoNo'].values() if r.get('IdHoaDon')==1826]
    payments=[r for r in rows['TraNo'].values() if r.get('IdSoNo')==1829]
    history=sorted((r.get('IdTraNo'),r.get('SotienTra'),r.get('SoCoNo')) for r in payments)
    if order.get('IdKH')!=2926 or order.get('IdXe')!=2004 or len(debts)!=1 or debts[0].get('IdSoNo')!=1829 or history!=[(3554,0,9700000),(3669,9700000,0)]:
        return 'giữ nguyên: nguồn khác dữ liệu đã đối chiếu'
    vehicle=next((r for r in rows['Xe'].values() if r.get('IdXe')==2004),{})
    if vehicle.get('GiaBan')!=9700000:
        return 'giữ nguyên: giá bán nguồn đã thay đổi'
    debt=debts[0]
    if (debt.get('SoTienDaTra'),debt.get('SoTienConNo')) not in [(24200000,-6750000),(9700000,0)]:
        return 'giữ nguyên: số dư nguồn đã thay đổi'
    debt.update(SoTienDaTra=9700000,SoTienConNo=0)
    order.update(SoTienDaTra=9700000,SoTienConNo=0)
    return 'đã đối chiếu: trả đủ 9.700.000đ'


def validators():
    result={k:{'$jsonSchema':v} for k,v in [('SanPham',CATALOG_SCHEMA),('Xe',VEHICLE_SCHEMA),('TonKhoPhuTung',STOCK_SCHEMA)]}
    result.update(sales_schemas())
    for name,title,fields in [
        ('DoiTac','TenDoiTac',['SoDienThoai','DiaChi','MaSoThue','NguoiDaiDien','GhiChu']),
        ('VanChuyen','TenVanChuyen',['SoDienThoai','BienSoXe','GhiChu']),
    ]:
        result[name]={'$jsonSchema':{'bsonType':'object','required':['_id',title,*fields],
            'properties':{'_id':{'bsonType':'string'},title:{'bsonType':'string','minLength':1},**{f:{'bsonType':'string'} for f in fields}}}}

    cost={'$or':[{'ChiPhi':{'$exists':False},'TongChiPhi':{'$exists':False}}, {'$and':[
        {'$jsonSchema':{'required':['ChiPhi','TongChiPhi'],'properties':{
            'ChiPhi':{'bsonType':'array','items':{'bsonType':'object','required':['Ngay','SoTien','GhiChu'],'properties':{
                'Ngay':{'bsonType':'date'},'SoTien':{'bsonType':['int','long'],'minimum':0},'GhiChu':{'bsonType':'string'}}}},
            'TongChiPhi':{'bsonType':['int','long'],'minimum':0}}}},
        {'$expr':{'$eq':['$TongChiPhi',{'$sum':'$ChiPhi.SoTien'}]}}
    ]}]}
    for name in ['Xe','SanPham','ChiTietNhapHang']:
        result[name]={'$and':[result[name],cost]} if name in result else cost
    return result
