#!/bin/bash
################包含常用function


################解析ip
dns_server=8.8.8.8
function get_ip()
{
    local ip
    ip=$(nslookup $1 $dns_server | grep Address |grep -v $dns_server | awk -F ' ' '{print $2}')
    echo  $ip
}

################记录日志和打印信息
#是否开起手动执行调试模式
echo_on=0 #0/1 关闭/开启 日志显示
#log path
log_on=1 #0/1 关闭/开启 日志记录
log_path=${path_self}/iptables_mysql.log
function echo_()
{
    if [ "$log_on" == "1" ];then echo $(date +'%y-%m-%d %H:%M:%S') $1 >> ${log_path};fi
    if [ "$echo_on" == "1" ];then echo $(date +'%Y-%m-%d %H:%M:%S') $1;fi
}

#################获取外网ip
function get_WAN_ip()
{
  curl -s http://ipv4.icanhazip.com
}
