#!/bin/bash
set -e

echo "脚本更新时间2025-04-18"

echo "开始进行前置准备："

echo "添加软件源..."
# 注意：直接覆盖sources.list可能导致原有配置丢失，建议使用>>追加或先备份
echo "deb https://mirrors.tuna.tsinghua.edu.cn/termux/apt/termux-main stable main" | tee $PREFIX/etc/apt/sources.list

echo "更新软件包..."
apt update && apt upgrade -y || { echo "更新失败"; exit 1; }

echo "安装工具包..."
pkg i root-repo -y
apt install sudo parted pv wget gptfdisk e2fsprogs -y || { echo "安装失败"; exit 1; }

LINUX_URL="https://1812853660.v.123pan.cn/1812853660/41516537"
echo "下载系统文件中..."

# 建议添加检查文件是否已存在，避免重复下载
wget -c "$LINUX_URL" -O linux.zip

echo "开始解压..."
unzip -n linux.zip

echo "======================================================="
echo "检查是否存在linux分区..."

# 使用 -s 抑制 parted 的交互信息
if sudo parted -s /dev/block/sda p | grep -q linux; then
    echo "linux分区已存在，跳过硬盘相关操作。"
else
    echo "开始配置分区..."
    sudo sgdisk --resize-table 64 /dev/block/sda
    
    # 获取 userdata 分区信息
    # 注意：这行命令非常依赖 parted 的输出格式，如果 parted 输出警告信息，数组索引会错乱
    UD=($(sudo parted /dev/block/sda p | grep userdata | xargs echo))
    
    # 增加基本的错误检查
    if [ ${#UD[@]} -lt 4 ]; then
        echo "错误：无法正确获取分区信息，脚本终止。"
        exit 1
    fi

    Number=${UD[0]}
    # 去除单位字符 (假设是 GB/MB 等后缀)
    Start=${UD[1]%B}
    Start=${Start%G}
    Start=${Start%M}
    
    OriginEnd=${UD[2]%B}
    OriginEnd=${OriginEnd%G} 
    OriginEnd=${OriginEnd%M}
    
    Size=${UD[3]}

    echo "获取数据分区信息成功!"
    echo "当前用户分区还有 ${Size}，不建议设置超过其一半的大小"
    echo "请设置Deepin系统使用空间大小(只输入数字，不要写单位GB，直接回车则默认30): "
    read LINUX_SIZE
    
    if [ -z "$LINUX_SIZE" ]; then
        LINUX_SIZE=30
    fi
    
    echo "是否划分「${LINUX_SIZE}GB」空间给Deepin23系统使用"
    echo "按「Enter」键继续, 按「Ctrl + C」键终止操作"
    read dummy_var
    
    echo "再次确认是否安装, 按「Enter」键开始安装, 按「Ctrl + C」键终止操作！"
    read dummy_var
    
    # 计算新的结束点。注意：这里简单的数学运算假设单位完全一致且为整数，存在风险
    Linux_Start=$(( OriginEnd - LINUX_SIZE ))
    
    echo "正在调整分区大小..."
    sudo parted -s /dev/block/sda resizepart "$Number" "${Linux_Start}GB"
    sudo parted -s /dev/block/sda mkpart linux ext4 "${Linux_Start}GB" "${OriginEnd}GB"
fi

# 获取 Linux 分区号
LINUX_DISK_INFO=$(sudo parted /dev/block/sda p | grep linux)
# 提取分区号 (假设是第一列)
LINUX_PART_NUM=$(echo "$LINUX_DISK_INFO" | awk '{print $1}')

echo "检测到 Linux 分区号: $LINUX_PART_NUM"

# 刷入镜像
sudo dd if=linux.img of="/dev/block/sda${LINUX_PART_NUM}" bs=1M status=progress
sudo e2fsck -f "/dev/block/sda${LINUX_PART_NUM}"
sudo resize2fs "/dev/block/sda${LINUX_PART_NUM}"

echo "备份Android启动分区到Linux的S2A目录"
install -d tmp
sudo mount -t ext4 "/dev/block/sda${LINUX_PART_NUM}" tmp

# ⚠️⚠️⚠️ 高危区域 ⚠️⚠️⚠️
# /dev/block/sde14 和 sde20 是特定机型（通常是小米骁龙865系列）的硬编码路径
# 如果你的手机不是该特定机型，这会导致备份错误的分区！
echo "正在备份 Boot 和 DTBO..."
if [ -e /dev/block/sde14 ]; then
    sudo dd if=/dev/block/sde14 of=./tmp/opt/s2a/android.boot.img 
else
    echo "警告：未找到 /dev/block/sde14，跳过 boot 备份"
fi

if [ -e /dev/block/sde20 ]; then
    sudo dd if=/dev/block/sde20 of=./tmp/opt/s2a/android.dtbo.img
else
    echo "警告：未找到 /dev/block/sde20，跳过 dtbo 备份"
fi
# ⚠️⚠️⚠️ 结束 ⚠️⚠️⚠️

sudo install -d /sdcard/linux
if [ -f linux.boot.img ]; then
    sudo cp linux.boot.img /sdcard/linux/linux.boot.img
else
    echo "警告：当前目录下没有 linux.boot.img"
fi

# 卸载挂载点
sudo umount tmp || echo "卸载 tmp 失败，请手动卸载"
rm -rf tmp

echo "系统安装完成，请下载S2L系统切换软件切换到Linux系统！"
echo "S2L系统切换APP下载地址「 https://www.123684.com/s/Y3R7Vv-H4VUd 」"
echo "请手动执行「rm -rf *.img *.zip」清理镜像"
