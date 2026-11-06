"""Require payment/interest dates for newly marked credit sales; preserve history."""
from pathlib import Path
from datetime import datetime, timezone
from zoneinfo import ZoneInfo
import argparse, copy, gzip, hashlib, json, subprocess
from pymongo import MongoClient


def with_debt_dates(validator):
    if 'PhienBanNgayCongNo' in repr(validator): return copy.deepcopy(validator)
    return {'$and': [copy.deepcopy(validator),
        {'$jsonSchema': {'properties': {'NgayHen': {'bsonType': ['date', 'null']}, 'NgayTinhLai': {'bsonType': ['date', 'null']}}}},
        {'$or': [
            {'PhienBanNgayCongNo': {'$exists': False}},
            {'$and': [
                {'PhienBanNgayCongNo': 1},
                {'$or': [
                    {'SoTienConNo': 0},
                    {'$and': [
                        {'SoTienConNo': {'$gt': 0}},
                        {'$jsonSchema': {'required': ['IdKH', 'NgayMua', 'NgayHen', 'NgayTinhLai'], 'properties': {
                            'IdKH': {'bsonType': ['int', 'long']}, 'NgayMua': {'bsonType': 'date'},
                            'NgayHen': {'bsonType': 'date'}, 'NgayTinhLai': {'bsonType': 'date'},
                        }}},
                        {'$expr': {'$and': [{'$gte': ['$NgayHen', '$NgayMua']}, {'$gte': ['$NgayTinhLai', '$NgayMua']}]}}
                    ]},
                ]}
            ]}
        ]}
    ]}

