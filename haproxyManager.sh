#!/bin/bash
[[ "$EUID" -ne '0' ]] && echo "Error:This script must be run as root!" && exit 1
haproxypath='/etc/haproxy'
haproxyprofile=${haproxypath}/haproxy.cfg
backendpath=${haproxypath}/backend
domainhost='inputyourdomainhere'
mkdir -p ${backendpath}
 
#check time s
SLEEPT=30
nameserver1=8.8.8.8
nameserver2=8.8.4.4
 
which nslookup >/dev/null 2>&1 || yum install bind-utils -y
which tcping >/dev/null 2>&1 || (
  yum install epel-release -y
  yum install tcping -y
)
 
function AlertSend() {
  #alert message code
  echo "$1"
}
function echo_red() {
  echo -e "\033[41;37m$1\033[0m"
}
function echo_green() {
  echo -e "\033[32m$1\033[0m"
}
function echo_yellow() {
  echo -e "\033[33m$1\033[0m"
}
function status() {
  case $1 in
  ON)
    echo_yellow "WUP"
    ;;
  OFF)
    echo "OK"
    ;;
  ERR)
    echo_red "Resolv Failed"
    ;;
  DOWN)
    echo_red "Dis Con"
    ;;
  *)
    echo_red "ERROR？"
    ;;
  esac
}
 
function backendQuery() {
  #echo backendQuery
  for portsfile in ${backendpath}/*; do
    echo_green "\n==>\t${portsfile##*/}"
    echo -e "\tid\tdomain\t\t\tport\tIP\t\tweight\tstatu"
    (grep -v '^$' ${portsfile} | cat -n) | while read portline; do
      dp=$(echo $portline | awk -F '|' '{print $1}' | awk '{print $2}')
      dip=$(echo $portline | awk -F '|' '{print $2}')
      echo -e "\t$(echo $portline | awk -F '|' '{print $1}' | awk '{print $1}')\t${dp%%:*}\t${dp##*:}\t$([ "${dip}" == "" ] && echo -e '空\t' || echo ${dip})\t$(echo $portline | awk -F '|' '{print $3}')\t$(status $(echo $portline | awk -F '|' '{print $4}'))"
    done
  done
}
 
function backendCheck() {
  #echo backendCheck
  for portsfile in ${backendpath}/*; do
    (grep -vn '^$' ${portsfile}) | while read portline; do
      domain=$(echo $portline | awk -F '|' '{print $1}' | awk -F ':' '{print $2}')
      dip=$(echo $portline | awk -F '|' '{print $2}')
      newIP=$(nslookup $domain $nameserver1 | grep 'Address:' | grep -v "$nameserver1" | tail -n1 | awk '{print $NF}')
      port=$(echo $portline | awk -F '|' '{print $1}' | awk -F ':' '{print $3}')
      if [ "$dip" != "$newIP" ]; then
        id=$(echo $portline | awk -F '|' '{print $1}' | awk -F ':' '{print $1}')
        weight=$(echo $portline | awk -F '|' '{print $3}')
        sed -i "${id}a${domain}:${port}|${newIP}|${weight}|ON" $portsfile && sed -i "${id}d" $portsfile
        if [ $? != 0 ]; then
          LocalIP=$(curl -s http://ipv4.icanhazip.com)
          AlertSend "#warning ${HOSTNAME} ${LocalIP} : ${portsfile##*/} 's backend ${domain} resolve ${newIP},when check domain"
        fi
      fi
    done
  done
}
 
function backendInstall() {
  [[ "$EUID" -ne '0' ]] && echo "Error:This script must be run as root!" && exit 1
  echo "[Unit]
Description=haproxyManager
After=network-online.target
Wants=network-online.target
 
[Service]
WorkingDirectory=/etc/haproxy
EnvironmentFile=
ExecStart=/bin/bash /etc/haproxy/haproxy_manager.sh -s
Restart=always
RestartSec=30
 
[Install]
WantedBy=multi-user.target " >/lib/systemd/system/haproxym.service
  if [ $? != 0 ]; then
    echo_red "install to service failed!"
    exit 1
  fi
  systemctl enable haproxym
  if [ $? != 0 ]; then
    echo_red "enable startup service failed!"
    exit 1
  fi
  systemctl start haproxym
  if [ $? != 0 ]; then
    echo_red "start service failed!"
    exit 1
  fi
}
 
function backendWriteProfile() {
  mkdir -p ${haproxypath}/cfgback
  cp ${haproxypath}/haproxy.cfg ${haproxypath}/cfgback/haproxy.cfg.$(date "+%Y%m%d%H%M%S")
  case $1 in
  dns)
    doway=$1
    ;;
  ip)
    doway=$1
    ;;
  *)
    optionError "$1"
    ;;
  esac
 
  echo "global
    #log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     $(($(ulimit -n)/2))
    user        haproxy
    group       haproxy
    daemon
defaults
    mode                    tcp
    #log                     global
    #option                  tcplog
    #option                  dontlognull
    #option http-server-close
    #option forwardfor      except 127.0.0.0/8
    option                  redispatch
    maxconn     $(($(ulimit -n)/2))
    retries                 3
    #timeout http-request    10s
    timeout queue           1m
    timeout connect         360s
    timeout client          10m
    timeout server          10m
    #timeout http-keep-alive 10s
    #timeout check           10s
 
listen admin_status
    bind 0.0.0.0:1189
    mode http
    stats refresh 30s
    stats uri  /whatever
    stats auth admin:yourpasswd
    #stats hide-version
    stats admin if TRUE
resolvers mydns
    nameserver dns1 8.8.8.8:53
    nameserver dns2 8.8.4.4:53
    resolve_retries       3
    timeout retry         2s
    hold valid           10s
" >${haproxyprofile}
  for portsfile in ${backendpath}/*; do
    echo -e "\nlisten ${portsfile##*/}" >>${haproxyprofile}
    echo "    bind *:${portsfile##*/}" >>${haproxyprofile}
    echo "    balance source" >>${haproxyprofile}
    (grep -vn '^$' ${portsfile} | grep -E 'ON|OFF') | while read portline; do
      domain=$(echo $portline | awk -F '|' '{print $1}' | awk -F ':' '{print $2}')
      dip=$(echo $portline | awk -F '|' '{print $2}')
      port=$(echo $portline | awk -F '|' '{print $1}' | awk -F ':' '{print $3}')
      weight=$(echo $portline | awk -F '|' '{print $3}')
      if [ "$doway" == "dns" ]; then
        echo "    server ${domain%%.*}:${port} ${domain}:${port} maxconn 20480 weight ${weight} rise 2 fall 3 check inter 2000 resolvers mydns" >>${haproxyprofile}
      elif [ "$doway" == "ip" ]; then
        echo "    server ${domain}:${port} ${dip}:${port} maxconn 20480 weight ${weight} rise 2 fall 3 check inter 2000" >>${haproxyprofile}
      fi
    done
  done
}
 
function backendProfileReload() {
  (grep -v '^$' ${haproxyprofile}) | while read profileline; do
    #port
    if $(echo $profileline | grep -qE '^listen [0-9]{3,4}$'); then
      port=$(echo $profileline | awk '{print $2}')
      cd . >${backendpath}/${port}
    fi
    #server
    if $(echo $profileline | grep 'server ' | grep -q ' weight '); then
      if $(echo $profileline | awk -F '[ :]+' '{print $2}' | grep -q "${domainhost}"); then
        echo "$(echo $profileline | awk -F '[ :]+' '{print $2":"$5"|"$4"|"$9"|OFF"}')" >>${backendpath}/${port}
      else
        echo "$(echo $profileline | awk -F '[ :]+' '{print $4":"$5"|"$4"|"$9"|OFF"}')" >>${backendpath}/${port}
      fi
    fi
  done
}
 
function backendService() {
  while true; do
    backendQuery
    sleep $SLEEPT
  done
}
 
function optionError() {
  if [[ "$1" != 'error' ]]; then echo -ne "\nInvaild option: '$1'\n\n"; fi
  echo -e "Usage:"
  echo -e "\t-c/--check\t Check all domain's ip in the backend file, if changes, set ON label, plan to reload haproxy."
  echo -e "\t-q/--query\t Display the status of all the backend profile."
  echo -e "\t-i/--install\t Install $(basename $0) into service on CENTOS 7."
  echo -e "\t-s/--service\t Do check every $SLEEPT seconds. You can change this time by edit \$SLEEPT in $(basename $0)."
  exit 1
}
 
while [[ $# -ge 1 ]]; do
  case $1 in
  -c | --check)
    shift
    backendCheck
    ;;
  -q | --query)
    shift
    backendQuery
    ;;
  -i | --install)
    shift
    backendInstall
    ;;
  -s | --service)
    shift
    backendService
    ;;
  -w | --write)
    #write config to haproxy.cfg
    shift
    if [ 1"$1" == 1"" ]; then
      doway=dns
    elif [ "$1" == "dns" ]; then
      doway=dns
    elif [ "$1" == "ip" ]; then
      doway=ip
    else
      optionError "$1"
    fi
    backendWriteProfile "$1"
    shift
    ;;
  -r | --reload)
    #load config from haproxy.cfg
    shift
    backendProfileReload
    ;;
  *)
    optionError
    ;;
  esac
done
