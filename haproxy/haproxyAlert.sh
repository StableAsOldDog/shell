#!/bin/bash
#centos7
path0='/etc/haproxy/alert'
if [ ! -d ${path0} ]; then mkdir -p ${path0}; fi

function tgSend() {
  echo $1
}

#you pass in haproxy.cfg
haproxypass=$(grep 'stats auth' /etc/haproxy/haproxy.cfg | awk -F ' ' '{print $3}')
#you listen port in haproxy.cfg
haproxyStatus="http://127.0.0.1:1151/"

downPorts=$(curl -s "${haproxyStatus}" -u "$haproxypass" | grep Backend | grep '>DOWN<' | awk -F '[ ="/]+' '{print $9}')

/usr/bin/systemctl status haproxy >/dev/null 2>&1
if [ $? == 0 ];then #haproxy ok
  for port in $(echo $downPorts); do #try to find down port
  #if exist down port
    if [ $(grep -v '^#' ${path0}/${port} | wc -l) == 3 ]; then #if down after 3 minutes
      tgSend "#$HOSTNAME port: ${port} down for 3 minutes!"
      echo 1 >>${path0}/${port}
    else #replus minutes
      echo 1 >>${path0}/${port}
    fi
  done


  for alerted in ${path0}/*;do #check down time
    if ! $(echo $downPorts | grep -q ${alerted##*/});then #if port up
      if [ $(grep -v '^#' ${alerted} | wc -l) -ge 3 ]; then #if down after 3 times
        tgSend "$HOSTNAME 的 ${alerted##*/} recovered after $(grep -v '^#' ${alerted} | wc -l) minutes" && if [ -f ${alerted} ];then rm -f ${alerted};fi
      else
        if [ -f ${alerted} ];then rm -f ${alerted};fi
      fi
    fi
  done


  if [ -f ${path0}/down ]; then #if process status down
    if [ $(grep -v '^#' ${path0}/down | wc -l) -ge 2 ]; then #send alert after 2 times
      tgSend "#$HOSTNAME haproxy recovered after $(grep -v '^#' ${path0}/down | wc -l) minutes!"
    else
      rm -f ${path0}/down
    fi
  fi
else  #haproxy status error
  if [ ! -f ${path0}/down ];then #start once
    /usr/bin/systemctl start haproxy
  fi
  if [ $(grep -v '^#' ${path0}/down | wc -l) -ge 2 ]; then #restart at the second time
    /usr/bin/systemctl restart haproxy
  fi
  if [ $(grep -v '^#' ${path0}/down | wc -l) == 1 ]; then #alert at once
    tgSend "$HOSTNAME haproxy down for $(grep -v '^#' ${path0}/down | wc -l) minutes"
  fi
  echo 1 >> ${path0}/down
fi

