"""Validate SQL connection strings and open a read-only SQL connection."""
import re


def parse_connection(value):
    """ODBC/ADO pairs, including quoted semicolons and escaped braces."""
    result={};index=0
    while index<len(value):
        while index<len(value) and (value[index].isspace() or value[index]==';'):index+=1
        if index==len(value):break
        end=value.find('=',index)
        if end<0: raise ValueError('Chuỗi SQL Server thiếu dấu =.')
        key=value[index:end].strip().lower();index=end+1
        while index<len(value) and value[index].isspace():index+=1
        text=''
        if index<len(value) and value[index] in "{\"'":
            quote=value[index];closing='}' if quote=='{' else quote;index+=1
            while index<len(value):
                ch=value[index];index+=1
                if ch==closing:
                    if index<len(value) and value[index]==closing:text+=closing;index+=1;continue
                    break
                text+=ch
            else:raise ValueError('Chuỗi SQL Server chưa đóng dấu bao giá trị.')
            while index<len(value) and value[index].isspace():index+=1
            if index<len(value) and value[index]!=';':raise ValueError('Chuỗi SQL Server không hợp lệ.')
        else:
            end=value.find(';',index)
            if end<0:end=len(value)
            text=value[index:end].strip();index=end
        if not key or key in result:raise ValueError('Chuỗi SQL Server có khóa trống hoặc trùng.')
        result[key]=text
    return result


def sql_connection(value):
    options=parse_connection(value)
    def pick(*keys,default=None):
        found=[options.pop(k) for k in keys if k in options]
        if len(found)>1:raise ValueError('Chuỗi SQL Server có thông số trùng tên.')
        return found[0] if found else default
    host=pick('server','data source','address','addr','network address')
    database=pick('database','initial catalog',default='xm')
    user=pick('user id','uid','user','username');password=pick('password','pwd')
    trusted=pick('trusted_connection','integrated security')
    if trusted is None:
        windows=False
    elif trusted.strip().lower() in ('true','yes','1','sspi'):
        windows=True
    elif trusted.strip().lower() in ('false','no','0'):
        windows=False
    else:
        raise ValueError('Trusted_Connection phải là True hoặc False.')
    if windows:
        if not host:raise ValueError('Nhập Server trong chuỗi SQL Server.')
        if user is not None or password is not None:
            raise ValueError('Xác thực Windows không dùng UID hoặc PWD. Hãy bỏ tên đăng nhập và mật khẩu SQL khỏi chuỗi kết nối.')
    elif not host or not user or password is None:
        raise ValueError('Nhập Server, User Id và Password trong chuỗi SQL Server.')
    if database.lower()!='xm':raise ValueError('Chuỗi SQL Server phải trỏ tới database xm.')
    driver=pick('driver')
    if driver and not re.fullmatch(r'ODBC Driver (17|18) for SQL Server',driver):raise ValueError('Driver SQL Server không được hỗ trợ.')
    result={'Server':host,'Database':database,
        'Encrypt':pick('encrypt',default='yes'),'TrustServerCertificate':pick('trustservercertificate',default='no'),
        'ApplicationIntent':'ReadOnly'}
    if windows:
        result['Trusted_Connection']='yes'
    else:
        result.update(UID=user,PWD=password)
    try:
        timeout=int(pick('connection timeout','connect timeout','timeout',default='15'))
    except (TypeError,ValueError):
        raise ValueError('Thời gian chờ SQL Server phải là số giây.') from None
    if not 1<=timeout<=120:raise ValueError('Thời gian chờ SQL Server phải từ 1 đến 120 giây.')
    if options:raise ValueError('Chuỗi SQL Server có thông số chưa hỗ trợ.')
    def escape(text):return '{'+str(text).replace('}','}}')+'}'
    import mssql_python
    try:
        return mssql_python.connect(';'.join(k+'='+escape(v) for k,v in result.items()),timeout=timeout)
    except Exception as error:
        text=str(error).lower()
        if '18456' in text or 'login failed' in text:
            if windows:
                raise ValueError('Tài khoản Windows đang chạy ứng dụng chưa đăng nhập được SQL Server. Kiểm tra quyền truy cập database xm của tài khoản này.') from None
            raise ValueError('Đăng nhập SQL Server không thành công. Kiểm tra tên đăng nhập và mật khẩu.') from None
        if 'openssl' in text or 'libssl' in text or 'libcrypto' in text:
            raise ValueError('Thiếu thư viện OpenSSL để kết nối SQL Server. Cài OpenSSL theo hướng dẫn của Microsoft.') from None
        raise RuntimeError('SQL connection failed') from None


