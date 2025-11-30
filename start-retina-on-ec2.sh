#!/bin/bash
# 在 EC2 上启动 Retina 服务

set -e

SSH_KEY="$HOME/.ssh/pixels-key.pem"
EC2_HOST="54.197.19.133"
EC2_USER="ec2-user"
PIXELS_HOME="/home/ec2-user/opt/pixels"
DAEMON_JAR="/home/ec2-user/pixels/pixels-daemon/target/pixels-daemon-0.2.0-SNAPSHOT-full.jar"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "在 EC2 上启动 Retina 服务"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查 SSH 连接
echo "1. 检查 SSH 连接..."
if ! ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$EC2_USER@$EC2_HOST" "echo 'SSH 连接成功'" 2>/dev/null; then
    echo "❌ 无法连接到 EC2 服务器"
    exit 1
fi
echo "✅ SSH 连接成功"

# 检查 JAR 文件是否存在
echo ""
echo "2. 检查 pixels-daemon JAR 文件..."
if ! ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" "test -f $DAEMON_JAR"; then
    echo "❌ JAR 文件不存在: $DAEMON_JAR"
    echo "   请先编译项目"
    exit 1
fi
echo "✅ JAR 文件存在"

# 检查端口是否被占用
echo ""
echo "3. 检查端口 18890 是否被占用..."
if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" "netstat -tlnp 2>/dev/null | grep -q ':18890 ' || ss -tlnp 2>/dev/null | grep -q ':18890 '"; then
    echo "⚠️  端口 18890 已被占用，尝试停止现有服务..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" "pkill -f 'PixelsRetina' || true"
    sleep 2
fi

# 启动 Retina 服务
echo ""
echo "4. 启动 Retina 服务..."
echo "   使用命令: java -Doperation=start -Drole=retina -jar $DAEMON_JAR"

# 设置 PIXELS_HOME 环境变量并启动服务
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" << 'SSH_EOF'
export PIXELS_HOME=/home/ec2-user/opt/pixels
cd ~/pixels

# 启动 Retina 服务（后台运行）
nohup java -Doperation=start -Drole=retina \
    -Dpixels.home=$PIXELS_HOME \
    -jar pixels-daemon/target/pixels-daemon-0.2.0-SNAPSHOT-full.jar \
    > /tmp/retina-server.log 2>&1 &

RETINA_PID=$!
echo $RETINA_PID > /tmp/retina-server.pid

# 等待几秒检查是否启动成功
sleep 5

if ps -p $RETINA_PID > /dev/null 2>&1; then
    echo "✅ Retina 服务已启动，PID: $RETINA_PID"
    echo "   日志文件: /tmp/retina-server.log"
else
    echo "❌ Retina 服务启动失败，查看日志:"
    tail -20 /tmp/retina-server.log 2>/dev/null || echo "无法读取日志文件"
    exit 1
fi
SSH_EOF

echo ""
echo "5. 验证服务状态..."
sleep 3
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_HOST" << 'SSH_EOF'
echo "检查进程:"
ps aux | grep -E 'PixelsRetina|retina' | grep -v grep || echo "未找到 Retina 进程"

echo ""
echo "检查端口监听:"
netstat -tlnp 2>/dev/null | grep ':18890 ' || ss -tlnp 2>/dev/null | grep ':18890 ' || echo "端口未监听"

echo ""
echo "最新日志 (最后 20 行):"
tail -20 /tmp/retina-server.log 2>/dev/null || echo "无法读取日志文件"
SSH_EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Retina 服务启动脚本执行完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "EC2 服务器 IP: $EC2_HOST"
echo "Retina 服务端口: 18890"
echo "查看日志: ssh -i $SSH_KEY $EC2_USER@$EC2_HOST 'tail -f /tmp/retina-server.log'"
