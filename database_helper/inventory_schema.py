"""Normalize XM into common products, individual vehicles and quantity stock.

Run once. Backs up the whole database, checks for concurrent changes, and
verifies every expected document before writing the completion marker.
"""
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
from collections import Counter
import gzip
import hashlib
import json
import subprocess
from bson import BSON
from pymongo import MongoClient, UpdateOne

ROOT=Path(__file__).resolve().parent
MONEY={'bsonType':['double','decimal','int','long','null']}
ID={'bsonType':['int','long']}
CATALOG_SCHEMA={'bsonType':'object',
 'required':['IdSanPham','MaSanPham','TenSanPham','LoaiSanPham','QuanLyTonKho','DonViTinh'],
 'properties':{'IdSanPham':ID,'MaSanPham':{'bsonType':'string'},'TenSanPham':{'bsonType':'string'},
  'LoaiSanPham':{'enum':['xe','phu_tung']},'QuanLyTonKho':{'enum':['tung_chiec','so_luong']},
  'DonViTinh':{'bsonType':'string'},'GiaBanThamKhao':MONEY},
 'oneOf':[
  {'properties':{'LoaiSanPham':{'enum':['xe']},'QuanLyTonKho':{'enum':['tung_chiec']}}},
  {'properties':{'LoaiSanPham':{'enum':['phu_tung']},'QuanLyTonKho':{'enum':['so_luong']}}}]
}
VEHICLE_SCHEMA={'bsonType':'object','required':['IdXe','IdSanPham','TinhTrangXe'],
 'properties':{'IdXe':ID,'IdSanPham':ID,'TinhTrangXe':{'enum':['moi','cu','chua_xac_dinh']},
  'GiaNhap':MONEY,'GiaBan':MONEY}}
STOCK_SCHEMA={'bsonType':'object','required':['IdSanPham','SoLuongTon'],
 'properties':{'IdSanPham':ID,'SoLuongTon':{'bsonType':['int','long','decimal'],'minimum':0},
  'GiaVonThamKhao':MONEY}}


def line_schema(invoice_key):
 return {'bsonType':'object','required':[invoice_key,'IdSanPham','LoaiSanPham','SoLuong'],
  'properties':{invoice_key:ID,'IdSanPham':ID,'IdXe':{'bsonType':['int','long','null']},
   'LoaiSanPham':{'enum':['xe','phu_tung']},
   'SoLuong':{'bsonType':['int','long','decimal'],'exclusiveMinimum':True,'minimum':0},
   'DonGia':MONEY},
  'oneOf':[
   {'required':['IdXe'],'properties':{'LoaiSanPham':{'enum':['xe']},'IdXe':ID,'SoLuong':{'enum':[1]}}},
   {'properties':{'LoaiSanPham':{'enum':['phu_tung']},'IdXe':{'bsonType':'null'}}}]}


def digest(doc):
 return hashlib.sha256(BSON.encode(dict(sorted(doc.items())))).hexdigest()


def build(before):
 expected={name:{oid:dict(doc) for oid,doc in docs.items()} for name,docs in before.items()}
 old=expected.pop('SanPham')
 catalog={};vehicles={};group_ids={};vehicle_to_product={}
 condition={'xe_moi':'moi','xe_cu':'cu','chua_phan_loai':'chua_xac_dinh'}
 for oid,source in sorted(old.items()):
  if source['IdSanPham']!=oid or source['LoaiSanPham'] not in condition:
   raise RuntimeError('Unexpected source identity or product type')
  key=(source.get('IdHangXe'),source['TenSanPham'])
  if key not in group_ids:
   pid=len(group_ids)+1;group_ids[key]=pid
   catalog[pid]={'_id':pid,'IdSanPham':pid,'MaSanPham':f'XE-{pid:06d}',
    'TenSanPham':source['TenSanPham'],'IdHangXe':source.get('IdHangXe'),
    'LoaiSanPham':'xe','QuanLyTonKho':'tung_chiec','DonViTinh':'chiếc',
    'GiaBanThamKhao':None,'TrangThaiDanhMuc':'can_ra_soat',
    'NguonGomNhom':'Trung chinh xac IdHangXe va TenSanPham; khong gom gan dung'}
  pid=group_ids[key];vehicle_to_product[oid]=pid
  vehicle=dict(source)
  vehicle['IdXe']=vehicle.pop('IdSanPham');vehicle['IdSanPham']=pid
  vehicle['TenXe']=vehicle.pop('TenSanPham')
  vehicle['LoaiSanPhamNguon']=vehicle.pop('LoaiSanPham')
  vehicle['TinhTrangXe']=condition[vehicle['LoaiSanPhamNguon']]
  vehicles[oid]=vehicle
 expected['SanPham']=catalog;expected['Xe']=vehicles
 for name in ['XeMoi','XeCu','HoaDonBan','HoaDonMua']:
  for doc in expected[name].values():
   xid=doc.pop('IdSanPham');doc['IdXe']=xid
   if name in ['HoaDonBan','HoaDonMua']:
    doc['IdSanPham']=vehicle_to_product[xid]
 for header,detail,key,price_field in [
  ('HoaDonBan','ChiTietHoaDonBan','IdHoaDon','GiaBan'),
  ('HoaDonMua','ChiTietHoaDonMua','IdMua','GiaBan')]:
  expected[detail]={}
  for oid,doc in expected[header].items():
   source_price=vehicles[doc['IdXe']].get(price_field) if header=='HoaDonBan' else doc.get(price_field)
   expected[detail][oid]={'_id':oid,key:doc[key],'IdSanPham':doc['IdSanPham'],
    'IdXe':doc['IdXe'],'LoaiSanPham':'xe','SoLuong':1,
    'DonGia':None,'DonGiaNguon':source_price,'TrangThaiGia':'can_doi_soat',
    'NguonDonGia':'Xe.GiaBan' if header=='HoaDonBan' else 'HoaDonMua.GiaBan',
    'NguonChuyenDoi':'product_schema_v2'}
 expected['TonKhoPhuTung']={}
 return expected,vehicle_to_product

