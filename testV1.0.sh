#!/bin/bash
#DATE: 2022/3/11
#FUNC: collect remote machine info
#AUTHOR：hejing
#      1.获取每张网卡ipv4/ipv6/mac地址
#      2.获取内核版本/系统安装方式
#      3.获取磁盘/内存/CPU使用率


TIME=$(date "+%Y-%m-%d %H:%M:%S")
TIME_INTERVAL=5
NIC_NAME=(`ip a s | grep -E '^\<[0-9]\>:' | awk -F: '{print $2}' | awk '{gsub(/^\s+|s+$/, "");print}'`)

function collect_IPV4 {
        for i in ${NIC_NAME[@]}
        do
                IP4_ADD=(`ip a s | grep -i $i | grep -i inet | awk '{print $2}'`)
                printf "%-10s  %-10s %-10s %-10s\n" 网卡名称是:$i     ip4地址是:$IP4_ADD
        done
}

function collect_IPV6 {
        for i in ${NIC_NAME[@]}
        do
                 IP6_ADD=(`ip a s | grep -A2 $i | grep -i inet6 | awk '{print $2}' `)
                printf "%-10s  %-10s %-10s %-10s\n" 网卡名称是:$i      ip6地址是:$IP6_ADD
        done
}

function collect_MAC {
        for i in ${NIC_NAME[@]}
        do
                 MAC_ADD=(`ip a s | grep -A1 $i | grep -i "link/ether" | awk '{print $2}'`)
                printf "%-10s  %-10s %-10s %-10s\n" 网卡名称是:$i   mac地址是:$MAC_ADD
        done
}

function collect_kernel {
        printf "%-10s\n" 内核版本是:$(uname -r)
}

function collect_os_install {
        printf "%-10s\n" 当前系统安装方式是:$(if [ `rpm -qa | wc -l` -le 1000  ];then echo "最小化安装mini"; else echo "图形化安装graph"; fi)
}

function collect_disk_root_use {
         TOTAL_SPACE=100
         USED_SPACE=$(df -k | grep -vE "文件系统|Filesystem" | grep -w "/" | awk '{print int($5)}')
         USED_PERCENT=$(($TOTAL_SPACE-$USED_SPACE)).00%
         echo "当前系统根目录可用率:$USED_PERCENT"
}

function collect_cal_cpu {
        #关于/proc/stat参考文档链接:https://man7.org/linux/man-pages/man5/proc.5.html
        #根据/proc/stat文件获取并计算CPU使用率
        #CPU时间计算公式：CPU_TIME=user+nice+system+idle+irq+softirq+iowait
        #CPU使用率计算公式：CPU_USAGE=(idle2-idle1)/(cpu2-cpu1)@100
        #默认时间间隔

         LAST_CPU_INFO=$(cat /proc/stat | grep -w cpu | awk '{print $2,$3,$4,$5,$6,$7,$8}')
         LAST_SYS_IDLE=$(echo $LAST_CPU_INFO | awk '{print $4}' )
         LAST_TOTAL_CPU_TIME=$(echo $LAST_CPU_INFO | awk '{print $1+$2+$3+$4+$5+$6+$7}' )
        sleep ${TIME_INTERVAL}
         NEXT_CPU_INFO=$(cat /proc/stat | grep -w cpu | awk '{print $2,$3,$4,$5,$6,$7,$8}')
         NEXT_SYS_IDLE=$(echo $NEXT_CPU_INFO | awk '{print $4}' )
         NEXT_TOTAL_CPU_TIME=$(echo $NEXT_CPU_INFO | awk '{print $1+$2+$3+$4+$5+$6+$7}' )

        #计算系统空闲时间
         SYSTEM_IDLE=`echo ${NEXT_SYS_IDLE} ${LAST_SYS_IDLE} | awk '{print $1-$2}'`
         TOTAL_TIME=`echo ${NEXT_TOTAL_CPU_TIME} ${LAST_TOTAL_CPU_TIME} | awk '{print $1-$2}'`
         CPU_USAGE=`echo ${SYSTEM_IDLE} ${TOTAL_TIME} | awk '{printf "%.2f", 100-$1/$2*100}'`
        echo "CPU使用率是:${CPU_USAGE}%"
}

function collect_mem_use {
        TOTAL_MEM=$(free -m | sed -n '2p' | awk '{print $2}')
        USED_MEM=$(free -m | sed -n '2p' | awk '{print $3}')
        USED_PERCENT=$(echo ${USED_MEM} ${TOTAL_MEM} | awk '{printf "%.2f", $1/$2*100}')
        echo  "当前系统总内存是:${TOTAL_MEM}M,已使用内存是:${USED_MEM}M,使用率达:${USED_PERCENT}%"
}

echo "------------------------------------------------------------------------"
echo "------------------当前主机名:$HOSTNAME  当前时间:$TIME------------------"
echo "------------------------------------------------------------------------"

collect_IPV4
collect_IPV6
collect_MAC
collect_kernel
collect_os_install
collect_disk_root_use
collect_cal_cpu
collect_mem_use


# 获取根目录的磁盘使用情况
echo "根目录磁盘使用情况："
df -h /

# 查找带 StoragePath 字眼的磁盘，并获取它们的使用情况
echo "StoragePath 目录磁盘使用情况："
for disk in $(lsblk -o NAME,MOUNTPOINT | grep StoragePath | awk '{print $1}'); do
  echo "磁盘 $disk 使用情况："
  df -h /dev/$disk
done

# 获取更目录下的 user 目录的磁盘使用情况
echo "更目录下的 user 目录磁盘使用情况："
df -h /user


# 获取 `default` 命名空间下所有 Pod 的名称
PODS=$(kubectl get pods -n default -o=jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

# 创建一个空文件，用于存储异常 Pod 的名称
ERROR_FILE="error_pods.txt"
> $ERROR_FILE

# 针对每个 Pod，检查它的状态是否为 Running
for pod in $PODS; do
  status=$(kubectl get pod $pod -n default -o=jsonpath='{.status.phase}')
  if [ "$status" != "Running" ]; then
    echo "Pod $pod 状态异常：$status"
    echo $pod >> $ERROR_FILE
  fi
done

# 判断是否有异常 Pod，如果没有则输出提示信息，否则输出异常 Pod 的文件路径
if [ -s $ERROR_FILE ]; then
  echo "以下 Pod 状态异常，详细信息请查看 $ERROR_FILE 文件："
  cat $ERROR_FILE
else
  echo "所有 Pod 检查完成，没有发现异常。"
fi