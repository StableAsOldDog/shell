#!/bin/bash
#获取当前解析的ip
nowip=`grep api.douban.com /etc/hosts |awk -F ' ' '{print $1}'`
#获取当前服务器ip
local_ip=$(ifconfig eth6 |grep 'inet addr' | awk -F '[ :]+' '{print $4}')
#echo ${nowip}
#开始测试当前ip
ping -c 3 ${nowip} > /dev/null
#当访问不可达时，开始更换ip
if [ $? == 1 ]
then
    #获取dns解析的ip总数
    api_ip_count=$(nslookup api.douban.com 8.8.8.8 |grep -v 8.8.8.8 |grep Address | awk -F ' ' '{print $2}' | wc -l)
    #将所有ip存入变量
    api_list=$(nslookup api.douban.com 8.8.8.8 |grep -v 8.8.8.8 |grep Address | awk -F ' ' '{print $2}')
    #设置检测ip失败计数
    failed_count=0
    #循环从解析的ip列表中读取ip
    for val in $(echo ${api_list})
    do
        #检测列表中的ip是否可达
        ping -c 3 ${val} > /dev/null
        #当可达时
        if [ $? == 0 ]
        then 
            #将ip存入变量
            setip=$val
            #echo ${setip}
            #更新host中的ip解析
            sed -i "s/${nowip} api.douban.com/${setip} api.douban.com/g" /etc/hosts
            #发送邮件通知ip更新成功
            echo "原解析的ip：${nowip}<br>现解析的ip：${setip}<br>$(date '+%Y-%m-%d %H:%M')" | mutt -s "访问豆瓣api地址更换" -e 'set content_type="text/html"' sevenfal@163.com
            #跳出循环
            break
        else
            #当ip检测不可达时，检测失败计数+1
            let failed_count+=1
            #echo $failed_count
            #当计数器大于等于解析获取的ip总数时
            if [ $failed_count >= $api_ip_count ]
            then
                #发送邮件告警所有ip均不可用
                echo "所有能解析的ip均无法访问！<br>已解析的ip列表：${api_list}<br>当前主机：${local_ip}<br>$(date '+%Y-%m-%d %H:%M')" | mutt -s "访问豆瓣api故障"  -e 'set content_type="text/html"' sevenfal@163.com
            fi
        fi
    done
fi
