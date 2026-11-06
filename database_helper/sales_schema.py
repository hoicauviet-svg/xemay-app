"""Enable sales discounts/services without changing historical business records."""
from pathlib import Path
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import argparse, copy, gzip, hashlib, json, subprocess
from bson import BSON
from pymongo import MongoClient, ASCENDING

IDS = {'bsonType': ['int', 'long']}
MONEY = {'bsonType': ['int', 'long', 'double', 'decimal', 'null']}
NONNEG = {'bsonType': ['int', 'long'], 'minimum': 0}
TOTAL_FIELDS = ['TongTienHang', 'GiamGia', 'TongThanhToan', 'SoTienKhachDua', 'SoTienDaTra', 'SoTienConNo', 'TienThua']

def schemas():
    header = {'$and': [
        {'$jsonSchema': {'bsonType': 'object', 'required': ['IdHoaDon'], 'properties': {
            'IdHoaDon': IDS, 'IdKH': {'bsonType': ['int', 'long', 'null']},
            **{k: NONNEG for k in TOTAL_FIELDS}, 'NgayMua': {'bsonType': ['date', 'null']},
        }}},
        {'$or': [
            {'PhienBanBanHang': {'$exists': False}},
            {'$and': [
                {'PhienBanBanHang': 3},
                {'$jsonSchema': {'required': TOTAL_FIELDS + ['MaYeuCauLuu', 'NgayMua', 'TrangThaiLuu'], 'properties': {
                    'MaYeuCauLuu': {'bsonType': 'string'}, 'TrangThaiLuu': {'enum': ['dang_luu', 'da_luu']}}}},
                {'$expr': {'$and': [
                    {'$eq': ['$TongThanhToan', {'$subtract': ['$TongTienHang', '$GiamGia']}]},
                    {'$eq': ['$SoTienDaTra', {'$min': ['$SoTienKhachDua', '$TongThanhToan']}]},
                    {'$eq': ['$SoTienConNo', {'$subtract': ['$TongThanhToan', '$SoTienDaTra']}]},
                    {'$eq': ['$TienThua', {'$subtract': ['$SoTienKhachDua', '$SoTienDaTra']}]},
                ]}},
            ]},
        ]},
    ]}
    detail = {'$and': [
        {'$jsonSchema': {'bsonType': 'object', 'required': ['IdHoaDon', 'LoaiSanPham', 'SoLuong'], 'properties': {
            'IdHoaDon': IDS, 'IdSanPham': {'bsonType': ['int', 'long', 'null']},
            'IdXe': {'bsonType': ['int', 'long', 'null']}, 'IdDichVu': {'bsonType': ['string', 'null']},
            'LoaiSanPham': {'enum': ['xe', 'phu_tung', 'dich_vu']},
            'SoLuong': {'bsonType': ['int', 'long', 'decimal'], 'minimum': 0, 'exclusiveMinimum': True}, 'DonGia': MONEY,
        }, 'oneOf': [
            {'required': ['IdSanPham', 'IdXe'], 'properties': {'LoaiSanPham': {'enum': ['xe']}, 'IdSanPham': IDS, 'IdXe': IDS, 'SoLuong': {'enum': [1]}, 'IdDichVu': {'bsonType': 'null'}}},
            {'required': ['IdSanPham'], 'properties': {'LoaiSanPham': {'enum': ['phu_tung']}, 'IdSanPham': IDS, 'IdXe': {'bsonType': 'null'}, 'IdDichVu': {'bsonType': 'null'}}},
            {'required': ['IdDichVu'], 'properties': {'LoaiSanPham': {'enum': ['dich_vu']}, 'IdDichVu': {'bsonType': 'string', 'minLength': 1}, 'IdXe': {'bsonType': 'null'}, 'IdSanPham': {'bsonType': 'null'}}},
        ]}},
        {'$or': [
            {'PhienBanBanHang': {'$exists': False}},
            {'$and': [{'PhienBanBanHang': 3}, {'$jsonSchema': {'required': ['DonGia', 'ThanhTien', 'DongSo', 'TenSanPham'], 'properties': {'DonGia': NONNEG, 'ThanhTien': NONNEG, 'DongSo': IDS, 'TenSanPham': {'bsonType': 'string'}}}}, {'$expr': {'$eq': ['$ThanhTien', {'$multiply': ['$SoLuong', '$DonGia']}]}}]},
        ]},
    ]}
    service = {'$jsonSchema': {'bsonType': 'object', 'required': ['TenDichVu', 'MoTa', 'GiaTien'], 'properties': {
        '_id': {'bsonType': 'string'}, 'TenDichVu': {'bsonType': 'string', 'minLength': 1}, 'MoTa': {'bsonType': 'string'}, 'GiaTien': NONNEG,
    }}}
    journal = {'$jsonSchema': {'bsonType': 'object', 'required': ['_id', 'Payload', 'IdHoaDon', 'IdSoNo', 'IdTraNo', 'TrangThai', 'Buoc'], 'properties': {
        '_id': {'bsonType': 'string'}, 'Payload': {'bsonType': 'object'}, 'IdHoaDon': IDS, 'IdSoNo': IDS, 'IdTraNo': IDS,
        'TrangThai': {'enum': ['dang_xu_ly', 'hoan_tat', 'da_huy']}, 'Buoc': {'enum': ['giu_hang', 'hoan_tra', 'ghi_don', 'hoan_tat', 'da_huy']},
    }}}
    from upgrade_sale_debt_dates import with_debt_dates
    return {'HoaDonBan': with_debt_dates(header), 'ChiTietHoaDonBan': detail, 'DichVu': service, 'GiaoDichBanHang': journal}
