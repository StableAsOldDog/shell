#!/usr/bin/env python
# -*- coding: utf-8 -*-  
#use mutt to send mail, please config it
import os
import xlrd
import sys
data = xlrd.open_workbook('test.xls')
table = data.sheet_by_name(u'Sheet1')
mailNum = 4 # mailaddress in excel cell -1
 
nrows_num = table.nrows
ncols_num = table.ncols
res=[]
 
for nrows in range(nrows_num):
    for ncols in range(ncols_num):
         
        cell_value = table.cell(nrows,ncols).value
         
        if cell_value=='':
            cell_value='__'
            res.append(cell_value)
        elif isinstance(cell_value,unicode):
                cell_value=cell_value
                res.append(cell_value)
        elif isinstance(cell_value,float):
                cell_value = str(cell_value)
                cell_value = cell_value.decode('utf-8')
                res.append(cell_value)
        elif isinstance(cell_value,int):
                cell_value = str(cell_value)
                cell_value = cell_value.decode('utf-8')
                res.append(cell_value)
    res.append('|')
     
res = '</td><td>'.join(res)
res = res.split('|')
content = '<table>'
for i in range(len(res)-1):
    if i == 0:
        content = content+'<tr><td>'+res[i].strip('</td><td>')+'</td></tr>'
    else:
        print i
        os.system("cd . > /tmp/mytxt")
        content1 = content+'<tr><td>'+res[i].strip('</td><td>')+'</td></tr>'
        mail = str(table.cell(i,mailNum).value)
        content1 = content1+'</table>'
        output = open('/tmp/mytxt', 'w')
        output.write(content1.encode('UTF-8'))
        output.close()
        os.system("cat /tmp/mytxt | mutt -s 'excel' -e 'set content_type=\"text/html\"' "+mail)
