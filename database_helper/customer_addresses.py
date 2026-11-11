"""Flatten legacy customer addresses without losing the locality directory."""
import copy


def merged_address(detail, locality):
    address = str(detail or '').strip()
    place = str(locality or '').strip()
    if not place:
        return address
    if not address:
        return place
    if address.casefold() == place.casefold() or address.casefold().endswith(', ' + place.casefold()):
        return address
    return address + ', ' + place


def flatten_rows(rows):
    places = {r['IdXa']: r.get('TenXa') for r in rows.get('Xa', {}).values()}
    customers = rows.get('KhachHang', {})
    for customer in customers.values():
        if customer.get('IdXa') is not None and customer['IdXa'] not in places:
            raise ValueError(f"Khách hàng #{customer.get('IdKH')} thiếu xã tham chiếu; dữ liệu được giữ nguyên.")
    archive = rows.setdefault('_app_address_archive', {}) if rows.get('Xa') else None
    for place in rows.get('Xa', {}).values():
        key = 'Xa:' + str(place['_id'])
        archive.setdefault(key, {'_id': key, 'document': copy.deepcopy(place)})
    for customer in customers.values():
        if 'IdXa' in customer:
            customer['DiaChiChiTiet'] = merged_address(customer.get('DiaChiChiTiet'), places.get(customer.pop('IdXa')))
            customer.pop('DiaChiHienThi', None)
    rows.pop('Xa', None)


def migrate_database(db):
    names = db.list_collection_names()
    if 'Xa' not in names and db['KhachHang'].find_one({'IdXa': {'$exists': True}}) is None:
        return
    places = list(db['Xa'].find()) if 'Xa' in names else []
    legacy = list(db['KhachHang'].find({'IdXa': {'$exists': True}}))
    rows = {'Xa': {str(r['_id']): r for r in places}, 'KhachHang': {str(r['_id']): copy.deepcopy(r) for r in legacy}}
    flatten_rows(rows)
    for archived in rows.get('_app_address_archive', {}).values():
        db['_app_address_archive'].update_one({'_id': archived['_id']}, {'$setOnInsert': {'document': archived['document']}}, upsert=True)
    for old in legacy:
        updated = rows['KhachHang'][str(old['_id'])]
        result = db['KhachHang'].update_one(
            {'_id': old['_id'], 'IdXa': old.get('IdXa'), 'DiaChiChiTiet': old.get('DiaChiChiTiet')},
            {'$set': {'DiaChiChiTiet': updated['DiaChiChiTiet']}, '$unset': {'IdXa': '', 'DiaChiHienThi': ''}})
        if not result.acknowledged:
            raise ValueError('Chưa xác nhận cập nhật địa chỉ khách hàng.')
    if db['KhachHang'].find_one({'IdXa': {'$exists': True}}) is not None:
        raise ValueError('Địa chỉ đang thay đổi; danh mục xã được giữ nguyên. Hãy thử lại.')
    if 'Xa' in names:
        db.drop_collection('Xa')
