#!/bin/bash
# 从 AWS EC2 下载测试数据文件

set -e
set -o pipefail

# 配置
EC2_INSTANCE_ID="i-0e01b0d7947291b0b"
EC2_REGION="us-east-1"
EC2_USER="ec2-user"
SSH_KEY="$HOME/.ssh/pixels-key.pem"
REMOTE_DIR="/home/ec2-user/test_data"
LOCAL_DIR="/Users/sunhao/Documents/pixels/test/test_datasource"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ [SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}❌ [ERROR]${NC} $1"
}

# 检查 SSH 密钥
if [ ! -f "$SSH_KEY" ]; then
    log_error "SSH 密钥不存在: $SSH_KEY"
    exit 1
fi

chmod 600 "$SSH_KEY"

# 获取 EC2 公网 IP
log_info "获取 EC2 实例公网 IP..."
EC2_IP=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --region "$EC2_REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

if [ -z "$EC2_IP" ] || [ "$EC2_IP" == "None" ]; then
    log_error "无法获取 EC2 实例 IP，请检查实例是否运行"
    exit 1
fi

log_success "EC2 实例 IP: $EC2_IP"

# 检查实例状态
INSTANCE_STATE=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --region "$EC2_REGION" \
    --query 'Reservations[0].Instances[0].State.Name' --output text)

if [ "$INSTANCE_STATE" != "running" ]; then
    log_warning "实例状态: $INSTANCE_STATE"
    log_info "启动实例..."
    aws ec2 start-instances --instance-ids "$EC2_INSTANCE_ID" --region "$EC2_REGION" > /dev/null
    log_info "等待实例启动..."
    aws ec2 wait instance-running --instance-ids "$EC2_INSTANCE_ID" --region "$EC2_REGION"
    sleep 10  # 等待 SSH 服务就绪
    EC2_IP=$(aws ec2 describe-instances --instance-ids "$EC2_INSTANCE_ID" --region "$EC2_REGION" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    log_success "实例已启动，新 IP: $EC2_IP"
fi

# 创建本地目录
mkdir -p "$LOCAL_DIR"
log_success "本地目录已创建: $LOCAL_DIR"

# 文件列表
FILES=(
    "AggregationWorker_data.pxl"
    "BroadcastJoinWorker_data1.pxl"
    "BroadcastJoinWorker_data2.pxl"
    "PartitionWorker_data.pxl"
    "PartitionedJoinWorker_data1.pxl"
    "PartitionedJoinWorker_data2.pxl"
    "ScanWorker_data.pxl"
)

# 下载文件
log_info "开始下载文件..."
TOTAL_FILES=${#FILES[@]}
SUCCESS_COUNT=0
FAIL_COUNT=0

for i in "${!FILES[@]}"; do
    FILE="${FILES[$i]}"
    REMOTE_PATH="$REMOTE_DIR/$FILE"
    LOCAL_PATH="$LOCAL_DIR/$FILE"
    
    echo ""
    log_info "[$((i+1))/$TOTAL_FILES] 下载: $FILE"
    
    # 检查远程文件是否存在
    if ! ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" \
        "test -f $REMOTE_PATH" 2>/dev/null; then
        log_warning "远程文件不存在，跳过: $FILE"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi
    
    # 获取远程文件大小
    REMOTE_SIZE=$(ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" \
        "stat -f%z $REMOTE_PATH 2>/dev/null || stat -c%s $REMOTE_PATH 2>/dev/null" 2>/dev/null || echo "0")
    
    if [ "$REMOTE_SIZE" -gt 0 ]; then
        REMOTE_SIZE_MB=$(echo "scale=2; $REMOTE_SIZE / 1024 / 1024" | bc)
        log_info "文件大小: ${REMOTE_SIZE_MB} MB"
    fi
    
    # 下载文件
    if scp -i "$SSH_KEY" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP:$REMOTE_PATH" "$LOCAL_PATH" 2>/dev/null; then
        LOCAL_SIZE=$(stat -f%z "$LOCAL_PATH" 2>/dev/null || stat -c%s "$LOCAL_PATH" 2>/dev/null)
        LOCAL_SIZE_MB=$(echo "scale=2; $LOCAL_SIZE / 1024 / 1024" | bc)
        log_success "下载完成: $FILE (${LOCAL_SIZE_MB} MB)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_error "下载失败: $FILE"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

# 总结
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "下载完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 成功: $SUCCESS_COUNT"
echo "❌ 失败: $FAIL_COUNT"
echo "📁 本地目录: $LOCAL_DIR"
echo ""

# 显示下载的文件列表
if [ $SUCCESS_COUNT -gt 0 ]; then
    echo "下载的文件："
    ls -lh "$LOCAL_DIR"/*.pxl 2>/dev/null | awk '{print "  " $9, "(" $5 ")"}'
fi

