#!/bin/bash
#for centos, you can replace yum to your OS command.
 
#init
which lshw >/dev/null 2>&1 || yum install lshw -y >/dev/null
which ethtool >/dev/null 2>&1 || yum install ethtool -y >/dev/null
 
#get netconfig
for netConfig in $(sudo lshw -c network | grep "logical name" | awk '{print $3}');do
    netModel=$(sudo ethtool -i ${netConfig} | grep '^driver' | awk '{print $2}')
    ifconfig ${netConfig} down
    modprobe -r ${netModel}
    modprobe ${netModel}
    ifconfig ${netConfig} up
done
