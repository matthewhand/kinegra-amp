#!/usr/bin/env python3
"""Regression for Android ignoring unsorted binary-manifest banner attributes."""
import struct
from patch_android_tv_manifest import insert_sorted_attribute, start_element, xml_attr
ids=[0x01010001,0x010103f4,0x010104f6,0x010103f2]
original=[xml_attr(9,0,0xffffffff,1,101),xml_attr(9,1,0xffffffff,0x12,0xffffffff),xml_attr(9,2,0xffffffff,0x12,0xffffffff)]
node=bytearray(start_element(7,original))
struct.pack_into('<H',node,30,2) # an existing special index must move with its attribute
banner=xml_attr(9,3,0xffffffff,1,0x7f06000c)
result=insert_sorted_attribute(bytes(node),banner,ids)
entries=[result[i:i+20] for i in range(36,len(result),20)]
assert [struct.unpack_from('<I',entry,4)[0] for entry in entries]==[0,3,1,2]
assert set(entries)==set(original+[banner])
assert struct.unpack_from('<H',result,30)[0]==3
assert struct.unpack_from('<H',result,28)[0]==4
assert struct.unpack_from('<I',result,4)[0]==len(result)
try: insert_sorted_attribute(result,banner,ids)
except ValueError:pass
else:raise AssertionError('duplicate banner accepted')
print('TV_BANNER_MANIFEST_ORDER_PASS')
