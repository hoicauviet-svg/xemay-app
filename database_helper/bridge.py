"""Database helper protocol: one JSON request, JSON events on stdout.

macOS sends the request on stdin. The Windows frozen executable does not
receive a redirected pipe, so it reads a temporary file path from argv and
deletes that file immediately. Credentials never appear in logs, reports,
or exception responses.
"""
import gzip
import hashlib
import json
import logging
import os
import re
import shutil
import sys
import uuid
from datetime import datetime, date, time
from decimal import Decimal
from pathlib import Path
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode, unquote
from bson import BSON, Decimal128, json_util
from pymongo import MongoClient
from normalization import normalize, validators
from sql_connection import parse_connection, sql_connection
from diagnostics import record_error
from cloud_sync import sync_cloud

logging.disable(logging.CRITICAL)


def emit(kind, **values):
    # Redirected Windows streams may use an ANSI encoding. JSON escapes keep
    # Vietnamese errors readable by Dart without crashing the helper itself.
    print(json.dumps({'event':kind, **values},ensure_ascii=True),flush=True)


def mongo_client(uri):
    if not uri.startswith(('mongodb://','mongodb+srv://')):raise ValueError('Chuỗi MongoDB phải bắt đầu bằng mongodb:// hoặc mongodb+srv://.')
    return MongoClient(uri,serverSelectionTimeoutMS=8000,connectTimeoutMS=5000,socketTimeoutMS=30000)


def query(cursor, statement):
    cursor.execute(statement)
    names=[d[0] for d in cursor.description]
    return [dict(zip(names,row)) for row in cursor.fetchall()]


def probe_mongo(uri):
    paths=[shutil.which('mongod'),'/opt/homebrew/bin/mongod','/usr/local/bin/mongod']
    installed=any(path and Path(path).is_file() for path in paths)
    client=mongo_client(uri)
    try:
        client.admin.command('ping')
        db=client.get_default_database('XM')
        db.list_collection_names()
        return {'installed':installed,'connected':True,'database':db.name}
    finally:client.close()


def source_snapshot(connection, folder, progress):
    cur=connection.cursor()
    cur.execute('SET TRANSACTION ISOLATION LEVEL SERIALIZABLE')
    if query(cur,'SELECT DB_NAME() AS name')[0]['name'].lower()!='xm':raise ValueError('Kết nối không trỏ tới database xm.')
    tables=query(cur,'SELECT object_id,SCHEMA_NAME(schema_id) AS schema_name,name FROM sys.tables WHERE is_ms_shipped=0 ORDER BY schema_id,name')
    columns=query(cur,'SELECT object_id,column_id,name,TYPE_NAME(user_type_id) AS type_name,max_length,precision,scale,is_nullable,is_identity FROM sys.columns WHERE object_id IN (SELECT object_id FROM sys.tables) ORDER BY object_id,column_id')
    indexes=query(cur,'SELECT i.object_id,i.index_id,i.name,i.is_unique,i.is_primary_key,i.has_filter,ic.key_ordinal,ic.is_descending_key,c.name AS column_name FROM sys.indexes i JOIN sys.index_columns ic ON i.object_id=ic.object_id AND i.index_id=ic.index_id JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id WHERE i.object_id IN (SELECT object_id FROM sys.tables) AND ic.key_ordinal>0 AND i.is_hypothetical=0 ORDER BY i.object_id,i.index_id,ic.key_ordinal')
    foreign_keys=query(cur,'SELECT fk.name,OBJECT_SCHEMA_NAME(fk.parent_object_id) AS source_schema,OBJECT_NAME(fk.parent_object_id) AS source_table,pc.name AS source_column,OBJECT_SCHEMA_NAME(fk.referenced_object_id) AS target_schema,OBJECT_NAME(fk.referenced_object_id) AS target_table,rc.name AS target_column FROM sys.foreign_keys fk JOIN sys.foreign_key_columns fkc ON fkc.constraint_object_id=fk.object_id JOIN sys.columns pc ON pc.object_id=fkc.parent_object_id AND pc.column_id=fkc.parent_column_id JOIN sys.columns rc ON rc.object_id=fkc.referenced_object_id AND rc.column_id=fkc.referenced_column_id')
    rows={}
    ident=lambda name:'['+name.replace(']',']]')+']'
    for index,table in enumerate(tables):
        name=table['name'] if table['schema_name']=='dbo' else table['schema_name']+'.'+table['name']
        if name.startswith(('system.','_')) or '\x00' in name:raise ValueError('Tên bảng nguồn không được hỗ trợ.')
        table['collection']=name;rows[name]={}
        pk=[i['column_name'] for i in indexes if i['object_id']==table['object_id'] and i['is_primary_key']]
        cur.execute('SELECT * FROM '+ident(table['schema_name'])+'.'+ident(table['name']))
        fields=[d[0] for d in cur.description];count=0
        bits={c['name'] for c in columns if c['object_id']==table['object_id'] and c['type_name'].lower()=='bit'}
        backup=folder/f'{index:03d}.jsonl.gz'
        with gzip.open(backup,'wt',encoding='utf-8') as stream:
            os.chmod(backup,0o600)
            while True:
                batch=cur.fetchmany(1000)
                if not batch:break
                for values in batch:
                    count+=1;row=dict(zip(fields,values));precision={}
                    if '_id' in row or '__sql_datetime_precision' in row:raise ValueError('Trùng trường dữ liệu dành riêng.')
                    for key,value in list(row.items()):
                        if isinstance(value,uuid.UUID):row[key]=str(value)
                        elif isinstance(value,date) and not isinstance(value,datetime):row[key]=datetime.combine(value,time())
                        elif isinstance(value,time):row[key]=value.isoformat()
                        elif isinstance(value,Decimal):row[key]=Decimal128(value)
                        elif isinstance(value,memoryview):row[key]=bytes(value)
                        elif isinstance(value,datetime) and value.microsecond%1000:precision[key]=value.isoformat(timespec='microseconds')
                    for key in bits:
                        if row.get(key) is not None:
                            if row[key] not in (0,1,True,False):raise ValueError('Trường bit không hợp lệ: '+name)
                            row[key]=bool(row[key])
                    if precision:row['__sql_datetime_precision']=precision
                    oid=row[pk[0]] if len(pk)==1 else '|'.join(json_util.dumps(row[k],sort_keys=True) for k in pk) if pk else count
                    if oid in rows[name]:raise ValueError('Trùng khóa chính nguồn: '+name)
                    row['_id']=oid;rows[name][oid]=row
                    stream.write(json_util.dumps(row,json_options=json_util.CANONICAL_JSON_OPTIONS,ensure_ascii=False)+'\n')
        table['row_count']=count;table['backup_file']=backup.name
        progress(f'Đã đọc bảng {name}: {count} dòng')
    connection.commit()
    metadata={'tables':tables,'columns':columns,'indexes':indexes,'foreign_keys':foreign_keys,
        'source_database':'xm','datetime_policy':'SQL wall-clock stored as BSON UTC date components; original sub-millisecond precision retained.',
        'sql_features':'Tables only; excludes views, procedures and functions.'}
    (folder/'sql-metadata.json').write_text(json_util.dumps(metadata,indent=2),encoding='utf-8')
    return rows,metadata


def digest_rows(rows):
    return hashlib.sha256(b''.join(sorted(BSON.encode(dict(sorted(row.items()))) for row in rows))).hexdigest()


def install_snapshot(db, rows, metadata, progress=lambda message:None):
    if db.list_collection_names():raise ValueError('Database mới không trống; dừng để tránh ghi đè.')
    definitions=validators()
    for name in sorted(set(rows)|set(definitions)):
        validator=definitions.get(name)
        collection=db.create_collection(name,**({'validator':validator,'validationLevel':'strict','validationAction':'error'} if validator else {}))
        documents=list(rows.get(name,{}).values())
        for offset in range(0,len(documents),1000):collection.insert_many(documents[offset:offset+1000],ordered=True)
        if digest_rows(collection.find({}))!=digest_rows(documents):raise ValueError('Đối chiếu dữ liệu không khớp: '+name)
        progress(f'Đã ghi và đối chiếu {name}: {len(documents)} dòng')
    for name,field in [('SanPham','IdSanPham'),('Xe','IdXe'),('TonKhoPhuTung','IdSanPham'),
        ('HoaDonBan','IdHoaDon'),('SoNo','IdSoNo'),('TraNo','IdTraNo'),('NhapHang','IdNhapHang'),('TraNoNhapHang','IdTraNoNhapHang')]:
        db[name].create_index(field,unique=True)
    db.SanPham.create_index('MaSanPham',unique=True)
    db.HoaDonBan.create_index('MaYeuCauLuu',unique=True,partialFilterExpression={'MaYeuCauLuu':{'$type':'string'}})
    db.ChiTietHoaDonBan.create_index([('IdHoaDon',1),('DongSo',1)],unique=True,partialFilterExpression={'DongSo':{'$exists':True}})
    for name,fields in [('Xe',['IdSanPham','TinhTrangXe','TinhTrang','IdNhapHang']),('SoNo',['IdHoaDon']),
        ('TraNo',['IdSoNo','NgayTra']),('NhapHang',['IdDoiTac','NgayNhap']),('TraNoNhapHang',['IdNhapHang']),
        ('CamDo',['IdKhachHang']),('TraNoCamDo',['IdCamDo']),('ChiTietNhapHang',['IdNhapHang','IdXe','IdSanPham'])]:
        for field in fields:db[name].create_index(field)
    # No historical interest is copied again into ThuChiKhac: SQL already has those vouchers.
    db['_sql_metadata'].update_one({'_id':'settings_clone_v1'},{'$set':{'installed_verified':True}})


def target_uri(uri, name):
    split=urlsplit(uri)
    options=parse_qsl(split.query,keep_blank_values=True)
    if '@' in split.netloc and not any(k.lower()=='authsource' for k,_ in options):
        options.append(('authSource',unquote(split.path.lstrip('/')) or 'admin'))
    return urlunsplit((split.scheme,split.netloc,'/'+name,urlencode(options),split.fragment))


def clone(request, connector=sql_connection):
    mongo=mongo_client(request['mongoUri'])
    mongo.admin.command('ping')
    base=mongo.get_default_database('XM').name
    name=re.sub('[^A-Za-z0-9_]','_',base)[:30]+'_import_'+datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid.uuid4().hex[:8]
    folder=Path(request['backupRoot'])/name
    folder.mkdir(mode=0o700,parents=True,exist_ok=False)
    progress=lambda message:emit('progress',message=message)
    connection=None
    try:
        connection=connector(request['sqlConnection'])
        raw,metadata=source_snapshot(connection,folder,progress)
        connection.close();connection=None
        transformed,report,removed=normalize(raw,metadata,progress)
        (folder/'removed-orphans.json').write_text(json_util.dumps(removed,indent=2),encoding='utf-8')
        install_snapshot(mongo[name],transformed,metadata,progress)
        uri=target_uri(request['mongoUri'],name)
        report.update(database=name,backup_directory=str(folder),verified=True,total_rows=sum(len(v) for v in transformed.values()))
        (folder/'migration-report.json').write_text(json_util.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
        return {'database':name,'mongoUri':uri,'report':report}
    finally:
        if connection is not None:connection.close()
        mongo.close()


def read_request():
    """Windows frozen builds do not receive a redirected stdin pipe."""
    if len(sys.argv)>1:
        path=Path(sys.argv[1])
        try:return path.read_text(encoding='utf-8-sig')
        finally:
            try:path.unlink()
            except OSError:pass
    return sys.stdin.readline()


def main():
    request={}
    try:
        request=json.loads(read_request())
        command=request['command']
        if command=='capabilities':
            emit('result',data={'protocolVersion':3,'commands':['probeMongo','probeSql','clone','checkSqlDriver','compareCloud','syncCloud']})
        elif command=='probeMongo':
            try:result=probe_mongo(request['mongoUri'])
            except Exception as error:
                record_error(error, request)
                paths=[shutil.which('mongod'),'/opt/homebrew/bin/mongod','/usr/local/bin/mongod']
                result={'installed':any(p and Path(p).is_file() for p in paths),'connected':False}
            emit('result',data=result)
        elif command=='checkSqlDriver':
            import mssql_python
            emit('result',data={'available':True,'version':mssql_python.__version__})
        elif command=='probeSql':
            connection=sql_connection(request['sqlConnection'])
            try:
                cur=connection.cursor();info=query(cur,'SELECT DB_NAME() AS name')
                if info[0]['name'].lower()!='xm':raise ValueError('Kết nối không trỏ tới database xm.')
                tables=query(cur,'SELECT COUNT(*) AS count FROM sys.tables WHERE is_ms_shipped=0')[0]['count']
                emit('result',data={'database':info[0]['name'],'tables':tables})
            finally:connection.close()
        elif command=='clone':emit('result',data=clone(request))
        elif command in ('syncCloud','compareCloud'):emit('result',data=sync_cloud(request, lambda message: emit('progress',message=message)))
        else:raise ValueError('Yêu cầu không được hỗ trợ.')
    except ValueError as error:
        path=record_error(error, request)
        emit('error',message=str(error),logFile=path);sys.exit(1)
    except Exception as error:
        original=error.__context__ or error
        path=record_error(error, request)
        message='Không hoàn tất được kết nối hoặc sao chép. Kiểm tra chuỗi kết nối, quyền truy cập và máy chủ; dữ liệu đang dùng được giữ nguyên.'
        if request.get('command')=='compareCloud' and (getattr(error,'timeout',False) or getattr(original,'timeout',False)):
            message='Quá thời gian so sánh (3 phút). Kiểm tra mạng và thử lại; dữ liệu đang dùng được giữ nguyên.'
        emit('error',code=type(original).__name__,logFile=path,message=message)
        sys.exit(1)

if __name__=='__main__':main()
