#!/bin/bash
set -e

echo 脚本更新时间2025-04-18


echo "开始进行前置准备："

echo "添加软件源..."
echo "deb https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main stable main" | tee $PREFIX/etc/apt/sources.list

echo "更新软件包..."
apt update && apt upgrade -y || { echo "更新失败"; exit 1; }

echo "安装工具包..."
pkg i root-repo -y
apt install sudo parted pv wget gptfdisk e2fsprogs -y || { echo "安装失败"; exit 1; }

LINUX_URL="https://1812853660.v.123pan.cn/1812853660/41516537"
echo "下载系统文件中..."

wget -c $LINUX_URL -O linux.zip

echo "开始解压..."
unzip -n linux.zip
echo "======================================================="
echo "检查是否存在linux分区..."
if sudo parted /dev/block/sda p | grep linux; then
   echo "linux分区已存在，跳过硬盘相关操作。"
else
    echo "开始配置分区..."
    sudo sgdisk --resize-table 64 /dev/block/sda
    UD=($(sudo parted /dev/block/sda p | grep userdata | xargs echo))
    Number=${UD[0]}
    Start=${UD[1]:0:-2}
    OriginEnd=${UD[2]:0:-2}
    Size=${UD[3]:0:-2}
    echo "获取数据分区信息成功!"
    echo "当前用户分区还有${Size}GB,不建议设置超过其一半的大小"
    echo "请设置Deepin系统使用空间大小(只输入数字，不要写单位GB，直接回车则默认30): "
    read LINUX_SIZE
    if [ -z "$LINUX_SIZE" ]; then
        LINUX_SIZE=30
    fi
    echo "是否划分「${LINUX_SIZE}GB」空间给Deepin23系统使用, 按「Enter」键继续, 按「Ctrl + C」键终止操作"
    read 
    echo "再次确认是否安装, 按「Enter」键开始安装, 按「Ctrl + C」键终止操作！"
    read
    Linux_Start=$(( $OriginEnd - $LINUX_SIZE ))
    sudo parted /dev/block/sda resizepart "$Number" "$Linux_Start"GB
    sudo parted /dev/block/sda mkpart linux ext4 "$Linux_Start"GB "$OriginEnd"GB
fi

LINUX_DISK=($(sudo parted /dev/block/sda p | grep linux | xargs echo))
sudo dd if=linux.img of=/dev/block/sda$LINUX_DISK bs=1M status=progress
sudo e2fsck -f /dev/block/sda$LINUX_DISK
sudo resize2fs /dev/block/sda$LINUX_DISK

echo 备份Android启动分区到Linux的S2A目录
install -d tmp
sudo mount -t ext4 /dev/block/sda$LINUX_DISK tmp
#Slot a 
sudo dd if=/dev/block/sde14 of=./tmp/opt/s2a/android.boot.img 
sudo dd if=/dev/block/sde20 of=./tmp/opt/s2a/android.dtbo.img

sudo install -d /sdcard/linux
sudo cp linux.boot.img /sdcard/linux/linux.boot.img

echo "系统安装完成，请下载S2L系统切换软件切换到Linux系统！"
echo "S2L系统切换APP下载地址「 https://www.123684.com/s/Y3R7Vv-H4VUd 」"
echo "请手动执行「rm -rf *.img *.zip」清理镜像"
