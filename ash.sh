#!/bin/sh

# ============================================================
# Alpine Linux Xray 多实例安装脚本
#
# 功能：
#   1. 安装 Xray
#   2. 创建实例配置
#   3. 创建 OpenRC 服务
#   4. 设置开机自启
#
# 注意：
#   本脚本不会：
#   - 检查证书
#   - 检查 Xray 配置
#   - 启动 Xray
#
# 安装完成后，需要手动上传证书，然后手动检查并启动。
# ============================================================

set -e

echo
echo "=============================================="
echo " Alpine Linux Xray 安装程序"
echo "=============================================="
echo

# ------------------------------------------------------------
# 1. Root 检查
# ------------------------------------------------------------

if [ "$(id -u)" != "0" ]; then
    echo "错误：请使用 root 用户运行。"
    exit 1
fi

# ------------------------------------------------------------
# 2. 输入实例名称
# ------------------------------------------------------------

printf "Instance name: "
read INSTANCE

if [ -z "$INSTANCE" ]; then
    echo "错误：实例名称不能为空。"
    exit 1
fi

# ------------------------------------------------------------
# 3. 路径
# ------------------------------------------------------------

BASE="/usr/local"

BIN="$BASE/bin/xray"

CONF="$BASE/etc/xray/$INSTANCE"

DATA="$BASE/share/xray"

LOG="/var/log/xray/$INSTANCE"

SERVICE="/etc/init.d/xray.$INSTANCE"

TMP="/tmp/xray-install-$INSTANCE"

CONFIG="$CONF/config.json"

echo
echo "实例名称 : $INSTANCE"
echo "程序     : $BIN"
echo "配置目录 : $CONF"
echo "日志目录 : $LOG"
echo "服务     : xray.$INSTANCE"
echo

# ------------------------------------------------------------
# 4. 检查是否已经存在
# ------------------------------------------------------------

if [ -e "$SERVICE" ]; then
    echo "错误：实例 xray.$INSTANCE 已经存在。"
    echo
    echo "查看状态："
    echo "  rc-service xray.$INSTANCE status"
    echo
    exit 1
fi

# ------------------------------------------------------------
# 5. 安装依赖
# ------------------------------------------------------------

echo "[1/6] 安装依赖..."

apk update
apk add --no-cache curl unzip

# ------------------------------------------------------------
# 6. 创建目录
# ------------------------------------------------------------

echo "[2/6] 创建目录..."

mkdir -p "$CONF"
mkdir -p "$DATA"
mkdir -p "$LOG"
mkdir -p "$TMP"

# ------------------------------------------------------------
# 7. 下载 Xray
# ------------------------------------------------------------

echo "[3/6] 下载 Xray..."

cd "$TMP"

curl -fL \
    -o Xray-linux-64.zip \
    "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip"

echo "解压 Xray..."

unzip -o Xray-linux-64.zip

if [ ! -f "$TMP/xray" ]; then
    echo "错误：解压后没有找到 xray 可执行文件。"
    exit 1
fi

# ------------------------------------------------------------
# 8. 安装 Xray 程序
# ------------------------------------------------------------

install -m 755 "$TMP/xray" "$BIN"

install -m 644 "$TMP/geoip.dat" "$DATA/geoip.dat"

install -m 644 "$TMP/geosite.dat" "$DATA/geosite.dat"

# ------------------------------------------------------------
# 9. 创建配置文件
# ------------------------------------------------------------

echo "[4/6] 创建 Xray 配置文件..."

cat > "$CONFIG" <<EOF2
{
  "log": {
    "loglevel": "error",
    "error": "$LOG/error.log"
  },

  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",

      "settings": {
        "clients": [
          {
            "id": "ec69b11b-4db6-427e-ab0e-6eb10d528244",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "mlkem768x25519plus.native.600s.VHDZsT7dwE2Z8RnfPD2mWYkuHcXokLIrjkdCriPz1hXmiWIVrN1K2HNyiW0nnRFaAG_KFQiDn-j5_28iHCnVJw"
      },

      "streamSettings": {
        "network": "raw",
        "security": "tls",

        "tlsSettings": {
          "certificates": [
            {
              "ocspStapling": 3600,
              "certificateFile": "/usr/local/etc/xray/vtcdn-fullchain.cer",
              "keyFile": "/usr/local/etc/xray/vtcdn-private.key"
            }
          ],
          "rejectUnknownSni": true,
          "minVersion": "1.2"
        }
      },

      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],

  "routing": {
    "rules": [
      {
        "type": "field",
        "protocol": [
          "bittorrent"
        ],
        "outboundTag": "block"
      },

      {
        "type": "field",
        "ip": [
          "geoip:cn"
        ],
        "outboundTag": "block"
      },

      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      }
    ]
  },

  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    },

    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ]
}
EOF2

# 创建日志文件
touch "$LOG/access.log"
touch "$LOG/error.log"

# ------------------------------------------------------------
# 10. 创建 OpenRC 服务
# ------------------------------------------------------------

echo "[5/6] 创建 OpenRC 服务..."

cat > "$SERVICE" <<EOF2
#!/sbin/openrc-run

description="Xray Instance $INSTANCE"

command="$BIN"
command_args="run -config $CONFIG"

command_background=true

pidfile="/run/xray.$INSTANCE.pid"

# 最大文件描述符
rc_ulimit="-n 1048576"

depend() {
    need net
    after firewall
}
EOF2

chmod +x "$SERVICE"

# ------------------------------------------------------------
# 11. 设置开机自启
# ------------------------------------------------------------

echo "[6/6] 设置 OpenRC 开机自启..."

rc-update add "xray.$INSTANCE" default

# ------------------------------------------------------------
# 12. 清理临时文件
# ------------------------------------------------------------

rm -rf "$TMP"

# ------------------------------------------------------------
# 13. 安装完成
# ------------------------------------------------------------

echo
echo "=============================================="
echo " Xray 安装完成"
echo "=============================================="
echo

echo "实例名称："
echo "  $INSTANCE"
echo

echo "配置文件："
echo "  $CONFIG"
echo

echo "OpenRC 服务："
echo "  xray.$INSTANCE"
echo

echo "日志目录："
echo "  $LOG"
echo

echo "=============================================="
echo " 下一步：上传 TLS 证书"
echo "=============================================="
echo

echo "证书目录："
echo "  /usr/local/etc/xray/"
echo

echo "需要上传："
echo "  vtcdn-fullchain.cer"
echo "  vtcdn-private.key"
echo

echo "例如："
echo "  /usr/local/etc/xray/vtcdn-fullchain.cer"
echo "  /usr/local/etc/xray/vtcdn-private.key"
echo

echo "=============================================="
echo " 证书上传完成后"
echo "=============================================="
echo

echo "1. 检查 Xray 配置："
echo "  $BIN run -test -config $CONFIG"
echo

echo "2. 启动 Xray："
echo "  rc-service xray.$INSTANCE start"
echo

echo "3. 查看状态："
echo "  rc-service xray.$INSTANCE status"
echo

echo "4. 查看错误日志："
echo "  tail -f $LOG/error.log"
echo

echo "5. 重启 Xray："
echo "  rc-service xray.$INSTANCE restart"
echo

echo "6. 停止 Xray："
echo "  rc-service xray.$INSTANCE stop"
echo

echo "7. 查看开机自启："
echo "  rc-update show | grep xray"
echo

echo "=============================================="
echo " 注意：本脚本不会检查证书，也不会启动 Xray"
echo "=============================================="
echo
