#!/bin/bash
wiki_key=XXXX #此处为redmine用户的key
redmine_url=192.168.2.248 #redmine服务器地址，可改为域名
ver_txt=version.txt #线上前端版本文件名称
path0=$(cd "$(dirname "$0")";pwd)
cd ${path0}
today=$(date '+%Y-%m-%d')
#curl超时(秒)
curl_time=8
#获取版本号超过以下字符数判定为失败
failed_num=25
#邮件头部
mail_on=${path0}/mail_on
cd . > ${mail_on}
#邮件样式
mail_head=$(cat<<EOF
<style type="text/css">
table.dataintable {
	margin-top:15px;
	border-collapse:collapse;
	border:1px solid #aaa;
	width:100%;
	}
table.dataintable th {
	vertical-align:baseline;
	padding:5px 15px 5px 6px;
	background-color:#3F3F3F;
	border:1px solid #3F3F3F;
	text-align:left;
	color:#fff;
	}
table.dataintable td {
	vertical-align:text-top;
	padding:6px 15px 6px 6px;
	border:1px solid #aaa;
	}
table.dataintable tr:nth-child(odd) {
	background-color:#F5F5F5;
}
table.dataintable tr:nth-child(even) {
	background-color:#fff;
}
</style>
本次更新如下地区系统：<br><table class="dataintable"><thead><tr><th>地区</th><th>业务</th><th>Wiki版本</th><th>version</th><th>线上版本</th><th>version</th></tr></thead><tbody>
EOF
)
mail_foot="</tbody></table>更新时间：$today"
mail_list="sevenfal@163" ##mail通知地址，多个用,隔开

#各系统获取版本api路径 开发提供的后端程序获取版本api路径
#XX: /XX/api/pub/app/version
 

################记录日志和打印信息
#是否开起手动执行调试模式 #0/1 关闭/开启 日志显示
echo_on=1
#是否记录日志信息 #0/1 关闭/开启 日志记录
log_on=1
log_path=${path0}/logs/wiki_update_$(date +'%Y-%m-%d').log
mkdir -p ${path0}/logs
#调试显示
function echo_()
{
    if [ "$echo_on" == "1" ];then echo -e "$(date +'%Y-%m-%d %H:%M:%S')\t$1";fi
}
#日志记录
function log_()
{
    if [ "$log_on" == "1" ];then echo -e "$(date +'%Y-%m-%d %H:%M:%S')\t$1">> ${log_path};fi
    if [ "$echo_on" == "1" ];then echo -e "$(date +'%Y-%m-%d %H:%M:%S')\t$1";fi
}


#去除尾部多余的^M符号
function tr_()
{
    echo $1 | tr -d "\015"
}


#################get versions.xml#
#创建处理文件夹
mkdir -p ${path0}/wiki_urls

#获取业务系统版本文件的函数
function get_wiki(){
    if  [ ! -n "$2" ] ;then echo "Usage: get_wiki wiki_name wiki_url";return 1;fi
    local wiki_name=$1
    local wiki_url=$2
    eval ${wiki_name}=${wiki_url}
    curl --connect-timeout $curl_time --silent -X GET "$wiki_url?key=$wiki_key" | tr -d "\015" > ${path0}/wiki_urls/${wiki_name}.xml
}

#获取业务系统的版本号及总wiki文件
#地址需要在redmine中找到对应version 的url
function get_wiki_page(){
    if [ "$echo_on" == "1" ];then echo "获取versions.xml: XX ";fi
    get_wiki "XX" "http://${redmine_url}/projects/XX/versions.xml"
    get_wiki "XX1" "http://${redmine_url}/projects/XX1/versions.xml"
 
    # 系统及部署版本汇总.xml 即redmine中记录版本信息的wiki地址
    echo_ "获取\t系统及部署版本汇总.xml"
    curl --connect-timeout $curl_time --silent -X GET "http://${redmine_url}/projects/oss-all/wiki/系统及部署版本汇总.xml?key=${wiki_key}" |tr -d "\015" > all_wiki.xml
}

#从前端获取版本号
function getver_from_front(){
    curl --connect-timeout $curl_time -k --silent ${1}${2} | grep Version | awk -F ':' '{print $2}' | sed 's# ##g'
}

#从api获取版本号
function GetVer_From_API(){
    local api_temp
    api_temp=$(curl --connect-timeout $curl_time -k -H 'Accept: text/html' --silent ${1}${2})
    echo $api_temp
}

#获取所有文件
get_wiki_page
# read -p "get_wiki_page"

#逐行显示行号读取wiki文件
cat -n ${path0}/all_wiki.xml | while read line
do
    unset mail_body
    #获取更新开关
    control=$(tr_ "$line" | awk -F '|' '{print $6}' | sed 's#_\. ##g' | sed 's# ##g' | grep -w -E 'on|off')
    #获取当前处理的地区
    title_head=$(tr_ "$line" | awk -F ' ' '{print $2}')
    if [ "$title_head" == "h2." ];then
        title=$(tr_ "$line" | awk -F ' ' '{print $3}')
        log_ "\n\n-----------start------------"
        log_ "检测\t$title 版本是否有更新……"
    fi
    #echo $control
        #tr_ "$line"
    #开始处理开关出于on状态的行
    if [ "$control" == "on" -o "$control" == "off" ];then
        #获取当前处理行号 eg.1
        line_num=$(tr_ "$line" | awk -F ' ' '{print $1}')
        # echo $line_num
        #获取当前行中的url eg.https://hunan.zbglxt.com/iportal/
        line_url=$(tr_ "$line" | awk -F '|' '{print $3}' | sed 's# ##g')
        #获取当前行中的版本号 eg.version#874
        old_ver=$(tr_ "$line" | awk -F '|' '{print $4}' | sed 's# ##g')
        #获取当然行中的日期
        line_date=$(tr_ "$line" | awk -F '|' '{print $5}' | sed 's# ##g')
        #如果wiki中不为version#784的形式填写，则置为0
        echo $old_ver | grep -q version
        if [ "$?" == 1 ];then
            old_ver_num=0
        else
            old_ver_num=$(echo $old_ver | awk -F '#' '{print $2}')
        fi
        
        #从url中获取当前的业务名称 eg.iportal
        line_app=$(tr_ "$line_url" | awk -F '/' '{print $4}')
        
        #南宁采购特殊处理
        log_ "INFO\t检测: $title 中的 $line_app"
        if [ "$line_app" == "pro" ];then line_url=${line_url%/*};line_url=${line_url%/*}/;fi
        
        #根据业务系统处理获取版本号的方式
        case ${line_app} in
            #以下从从前端获取
            XX3)
                line_ver=$(getver_from_front "${line_url}" "${ver_txt}") 
            ;;
            XX4)
                line_ver=$(getver_from_front "${line_url}" "${ver_txt}") 
            ;;
            #以下均由后端api获取，如果地区当前版本不支持api获取，则不处理
            XX)
                line_url=${line_url%/*}
                line_url=${line_url%/*}
                api_set="/XX/api/pub/app/version"
                line_ver=$(GetVer_From_API "${line_url}" "${api_set}")
            ;;
            XX1)
                line_url=${line_url%/*}
                line_url=${line_url%/*}
                api_set="/XX1/api/pub/app/version"
                line_ver=$(GetVer_From_API "${line_url}" "${api_set}")
            ;;
        esac
        
        #业务系统版本号来源的url从自身作为变量的值中获取
        eval wiki_url='${'${line_app}'}'
        
        #从url获取链接失败时记录，一般是偶发请求失败，或者线上业务挂了
        if [ "s$line_ver" == "s" ];then
            log_ "ERROR\t地区: $title 链接 ${line_url}, 获取版本号失败！"
            #修改尾部的on为off
            sed -i "${line_num}s/on\([^-]*-*\)$/off\1/" ${path0}/all_wiki.xml
        else
            #当然业务系统名称过滤多余符号
            app_name=$(tr_ "${line_app}")
            #当前业务系统版本
            app_ver=$(tr_ "${line_ver}")
            if [ ${#app_ver} -gt $failed_num ];then
				app_ver="??"
			fi
            #当前业务系统url
            app_url=$(tr_ "${line_url}")
            #当前业务系统的wiki本地版本汇总文件
            wiki_path=${path0}/wiki_urls/${app_name}.xml
            
            #查找匹配版本汇总文件中当前版本所在行数 以<id>、</id>和<name>、</name>作为分隔符换行
            #沙雕XX教学专用grep -i忽略大小写，线上获取为 xx-V9.9.4，redmine中为 XX-V9.9.4
            #（eg.  使用 sed 's#</id>#ver\n#g' | sed 's#<id>#\n#g' | sed 's#</name>#name\n#g' | sed 's#<name>#\n#g' 分行后得到如下内容
            ################
            #454	884ver
            #455	<project id="50" name="010XX云平台V9-XX管理子系统"/>
            #456	XX-V9.7.4.1name
            ################
            #查找 XX-V9.7.4name,得到 456
            #）
            app_line_number=$(cat "${wiki_path}" | sed 's#</id>#ver\n#g' | sed 's#<id>#\n#g' | sed 's#</name>#name\n#g' | sed 's#<name>#\n#g' | cat -n | grep -i "${app_ver}name" | awk -F ' ' '{print $1}')
            
            #沙雕XX教学专用去除V(eg. 线上版本号为 xx-V9.3.2.3，redmine中版本为 xx-9.3.2.3 )
            if [ "1${app_name}" == "1etms" ];then
                #当找不到版本时，尝试去除V再查询一次
                echo "${app_line_number}" | grep -q '^[0-9][0-9]*$'
                if [ "$?" == "1" ];then 
                    app_ver1=$(echo $line_ver | sed 's#V##g')
                    app_line_number=$(cat "${wiki_path}" | sed 's#</id>#ver\n#g' | sed 's#<id>#\n#g' | sed 's#</name>#name\n#g' | sed 's#<name>#\n#g' | cat -n | grep -i -w "${app_ver1}name" | awk -F ' ' '{print $1}')
                fi
            fi
            
            # echo $app_line_number
            #防止多行获取，取最后一行内容
            #for val in `echo $app_line_number`;do app_line_number=$val;done
            # echo $app_line_number
            
            #当没有查到到版本时，行号不为数字
            echo "${app_line_number}" | grep -q '^[0-9][0-9]*$'
            if [ "$?" == "1" ];then
                #记录当前版本在版本汇总文件中获取失败 一般为版本号不规范
                log_ "ERROR\t地区: $title 应用 ${app_name} 版本 ${app_ver} 从 ${wiki_url} 获取版本号失败！"
                #修改尾部的on为off
                sed -i "${line_num}s/on\([^-]*-*\)$/off\1/" ${path0}/all_wiki.xml
            else
            #当获取到行号时
            
        
            
                #版本号所在行数为当前查找到的上两行，参考 #查找匹配版本汇总文件中当前版本所在行数 行内容
                # echo "找到的行数:"$app_line_number
                wiki_ver_num=$(($app_line_number-2))
                # echo "实际的行数:"$wiki_ver_num
                #根据版本号行数获取版本号
                wiki_ver=$(cat "${wiki_path}" | sed 's#</id>#\n#g' | sed 's#<id>#\n#g' | sed 's#</name>#name\n#g' | sed 's#<name>#\n#g' | cat -n | grep " ${wiki_ver_num}" | awk -F ' ' '{print $2}')
                # echo "找到的版本号："$wiki_ver
                #防止多行获取，取最后一行内容（改用查找行数时前面添加空格）
                #for val in `echo $wiki_ver`;do wiki_ver=$val;done
                
                #比较当前版本号是否有更新
                #wiki中旧的版本号 完整内容：$old_ver （eg. version#768|9.4.3.2|9.4.3） 对应版本号数字：$old_ver_num(eg. 768|0|0)
                #线上版本获取版本 完整内容：$app_ver （eg. XX1-V9.7.4|xx-V9.6.3.1）  
                #如果是version#768形式，到wiki文件中获取到版本号内容
                #非version#768形式，无需对比版本号，直接更新
                
                
                
            if [[ "$wiki_ver" != "$old_ver_num" ]];then
                
                #获取到的版本号行号（eg. 401 768ver）
                old_ver_tmp_num=$(cat "${wiki_path}" | sed 's#</id>#ver\n#g' | sed 's#<id>#\n#g' | sed 's#</name>#name\n#g' | sed 's#<name>#\n#g' | cat -n | grep -i -w "${old_ver_num}ver" | awk -F ' ' '{print $1}')
                #版本号所在行数为上面+2
                old_ver_tmp_name_ver=$(($old_ver_tmp_num+2))
                #版本号内容
                old_ver_tmp_name=$(cat "${wiki_path}" | sed 's#</id>#ver\n#g' | sed 's#<id>#\n#g' | sed 's#</name>#\n#g' | sed 's#<name>#\n#g' | cat -n | grep -i " ${old_ver_tmp_name_ver}" | awk -F ' ' '{print $2}')
            
                echo "$old_ver" | grep -q 'version'
                if [ "$?" == "0" ];then
                    #去除多余字符
                    old_ver_tmp_name_num=$old_ver_tmp_name
                    app_ver_tmp_name_num=$app_ver
                    #一下循环中的内容为去掉所有可能出现非数字版本信息的内容
                    for val in $(echo "XX xx XX1 xx1 - V");do
                        old_ver_tmp_name_num=$(echo ${old_ver_tmp_name_num} | sed "s#${val}##g")
                        app_ver_tmp_name_num=$(echo ${app_ver_tmp_name_num} | sed "s#${val}##g")
                    done
                    #生成邮件内容
                    mail_body="<tr><td>${title}</td><td>${app_name}</td><td>${old_ver_tmp_name}</td><td>${old_ver_num}</td><td>${app_ver}</td><td>${wiki_ver}</td></tr>"
                    #开始数组处理，版本号为1.1.1.1的形式，以.号为分隔符，切割成数组，逐一对比版本号大小
                    OLD_IFS="$IFS"
                    IFS="."
                    old_ver_array=($old_ver_tmp_name_num)
                    app_ver_array=($app_ver_tmp_name_num)
                    IFS="$OLD_IFS"
                    #不够4位的补充第4位为0
                    if [ "${#old_ver_array[@]}" == "3" ];then old_ver_array[3]=0;fi
                    if [ "${#app_ver_array[@]}" == "3" ];then app_ver_array[3]=0;fi
                    # gt_off=0
                    for((val=0;val<=3;val++));do
                        grep -q "$mail_body" ${mail_on}
                        if [ "$?" == "1" ];then
                            if [ ${app_ver_array[$val]} -gt ${old_ver_array[$val]} ];then
                                echo "$mail_body" >> ${mail_on}
                                # gt_off=1
                            elif [ ${app_ver_array[$val]} -lt ${old_ver_array[$val]} ];then
                                unset mail_body
                                echo "<tr><td><span style='color:red'>${title}</span></td><td>${app_name}</td><td>${old_ver_tmp_name}</td><td>${old_ver_num}</td><td><span style='color:red'>${app_ver}</span></td><td>${wiki_ver}</td></tr>" >> ${mail_on}
                            fi
                        fi
                    done
                    
                #下面这里又是沙雕XX教学产生的处理
                elif [ "$old_ver_num" == "0" ]; then
                    #生成邮件内容
                    mail_body="<tr><td>${title}</td><td>${app_name}</td><td>${old_ver_tmp_name}</td><td>${old_ver_num}</td><td>${app_ver}</td><td>${wiki_ver}</td></tr>"
                    grep -q "$mail_body" ${mail_on}
                    if [ "$?" == "1" ];then
                        echo "$mail_body" >> ${mail_on}
                    else
                        unset mail_body
                    fi
                fi
            fi
                
                # if [ "$wiki_ver" -gt "$old_ver_num" ];then
                # if grep -q "$mail_body" ${mail_on};then
                #当没有邮件内容时表示没有更新
                if [ -n "$mail_body" ];then
                    log_ "WARN\t$title 的 $app_name 需要更新！  wiki_ver=$wiki_ver old_ver_num=$old_ver_num"
                    #修改尾部的off为on
                    sed -i "${line_num}s/off\([^-]*-*\)$/on\1/" ${path0}/all_wiki.xml
                    #修改日期为今天
                    sed -i "${line_num}s/${line_date}/${today}/g" ${path0}/all_wiki.xml
                    #更新版本号，沙雕XX教学专用数字版本号处理
                    if [ "$old_ver_num" == "0" ];then
                        sed -i "${line_num}s/$old_ver/version#${wiki_ver}/g" ${path0}/all_wiki.xml
                    else
                        sed -i "${line_num}s/version#${old_ver_num}/version#${wiki_ver}/g" ${path0}/all_wiki.xml
                    fi
                    # echo "地区：${title} 的 ${app_name} 由原版本：${old_ver_num} 更新为：${wiki_ver}<br>" >> ${mail_on}
                else
                    log_ "INFO\twiki_ver=$wiki_ver old_ver_num=$old_ver_num"
                fi
                
            fi
            
        fi
    fi
    # read
done
# echo $mail_on
# read -p "mail"
if [ "$(cat ${mail_on})" != "" ];then
# echo .
    curl --connect-timeout $curl_time -v -X PUT -H 'Content-type:text/xml' -F "xml=@${path0}/all_wiki.xml" "http://${redmine_url}/projects/oss-all/wiki/系统及部署版本汇总.xml?key=${wiki_key}"
    if [ "$?" == 0 ];then
        echo "${mail_head} $(cat ${mail_on}) ${mail_foot}" | mutt -s "wiki版本更新成功 $(date +'%Y-%m-%d  %H:%M')" -e 'set content_type="text/html"' ${mail_list}
    else
        echo "${mail_head} $(cat ${mail_on}) ${mail_foot}" | mutt -s "wiki版本更新失败 $(date +'%Y-%m-%d  %H:%M')" -e 'set content_type="text/html"' ${mail_list}
    fi
fi



