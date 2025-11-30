#!/bin/bash
# 上传测试数据文件到 S3

set -e
set -o pipefail

# 配置
BUCKET_NAME="home-sunhao"
LAMBDA_REGION="us-east-2"
REGION="$LAMBDA_REGION"
LOCAL_DATA_DIR="/Users/sunhao/Documents/pixels/test/test_datasource"
S3_TEST_DATA_PREFIX="test-data/workers-performance"

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

# 检查本地文件目录
if [ ! -d "$LOCAL_DATA_DIR" ]; then
    log_error "本地数据目录不存在: $LOCAL_DATA_DIR"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "上传测试数据到 S3"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 本地目录: $LOCAL_DATA_DIR"
echo "☁️  S3 路径: s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/"
echo "🌍 区域: $REGION"
echo ""

# 定义文件列表及说明（使用函数代替关联数组）
get_file_desc() {
    case "$1" in
        "AggregationWorker_data.pxl")
            echo "Aggregation Worker (56M)"
            ;;
        "BroadcastJoinWorker_data1.pxl")
            echo "Broadcast Join Worker - 大表 (5.1M)"
            ;;
        "BroadcastJoinWorker_data2.pxl")
            echo "Broadcast Join Worker - 小表 (1.4M)"
            ;;
        "PartitionWorker_data.pxl")
            echo "Partition Worker (54M)"
            ;;
        "PartitionedJoinWorker_data1.pxl")
            echo "Partitioned Join Worker - 大表 (4.8M)"
            ;;
        "PartitionedJoinWorker_data2.pxl")
            echo "Partitioned Join Worker - 小表 (1.2M)"
            ;;
        "ScanWorker_data.pxl")
            echo "Scan Worker (49M)"
            ;;
        *)
            echo "$1"
            ;;
    esac
}

FILES=(
    "AggregationWorker_data.pxl"
    "BroadcastJoinWorker_data1.pxl"
    "BroadcastJoinWorker_data2.pxl"
    "PartitionWorker_data.pxl"
    "PartitionedJoinWorker_data1.pxl"
    "PartitionedJoinWorker_data2.pxl"
    "ScanWorker_data.pxl"
)

# 统计变量
TOTAL_FILES=${#FILES[@]}
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TOTAL_SIZE=0

# 上传文件
for i in "${!FILES[@]}"; do
    FILE="${FILES[$i]}"
    LOCAL_PATH="$LOCAL_DATA_DIR/$FILE"
    S3_PATH="s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/$FILE"
    DESC=$(get_file_desc "$FILE")
    
    echo "[$((i+1))/$TOTAL_FILES] $DESC"
    
    # 检查本地文件是否存在
    if [ ! -f "$LOCAL_PATH" ]; then
        log_warning "  本地文件不存在，跳过: $FILE"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        echo ""
        continue
    fi
    
    # 获取文件大小
    if command -v stat > /dev/null 2>&1; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            FILE_SIZE=$(stat -f%z "$LOCAL_PATH" 2>/dev/null || echo "0")
        else
            FILE_SIZE=$(stat -c%s "$LOCAL_PATH" 2>/dev/null || echo "0")
        fi
    else
        FILE_SIZE=0
    fi
    
    if [ "$FILE_SIZE" -gt 0 ]; then
        FILE_SIZE_MB=$(echo "scale=2; $FILE_SIZE / 1024 / 1024" | bc 2>/dev/null || echo "0")
        log_info "  文件大小: ${FILE_SIZE_MB} MB"
        TOTAL_SIZE=$((TOTAL_SIZE + FILE_SIZE))
    fi
    
    # 检查 S3 是否已存在
    if aws s3 ls "$S3_PATH" --region "$REGION" > /dev/null 2>&1; then
        log_warning "  S3 文件已存在，自动覆盖"
    fi
    
    # 上传文件
    log_info "  上传中..."
    START_TIME=$(date +%s)
    
    if aws s3 cp "$LOCAL_PATH" "$S3_PATH" --region "$REGION" 2>&1 | tee /tmp/s3_upload.log; then
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        
        # 计算上传速度
        if [ "$DURATION" -gt 0 ] && [ "$FILE_SIZE" -gt 0 ]; then
            SPEED_MBPS=$(echo "scale=2; $FILE_SIZE_MB / $DURATION" | bc 2>/dev/null || echo "0")
            log_success "  上传完成: ${FILE_SIZE_MB} MB (耗时: ${DURATION}s, 速度: ${SPEED_MBPS} MB/s)"
        else
            log_success "  上传完成: ${FILE_SIZE_MB} MB"
        fi
        
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        log_error "  上传失败: $FILE"
        cat /tmp/s3_upload.log 2>/dev/null | tail -5
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    
    echo ""
done

# 总结
TOTAL_SIZE_MB=$(echo "scale=2; $TOTAL_SIZE / 1024 / 1024" | bc 2>/dev/null || echo "0")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "上传完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 成功: $SUCCESS_COUNT"
echo "⚠️  跳过: $SKIP_COUNT"
echo "❌ 失败: $FAIL_COUNT"
echo "📊 总大小: ${TOTAL_SIZE_MB} MB"
echo ""
echo "📁 S3 路径: s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/"
echo ""
echo "已上传的文件："
for FILE in "${FILES[@]}"; do
    S3_PATH="s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/$FILE"
    if aws s3 ls "$S3_PATH" --region "$REGION" > /dev/null 2>&1; then
        echo "  ✅ $FILE"
    fi
done

echo ""
log_info "数据上传完成，可以使用以下 S3 路径进行测试："
echo ""
echo "ScanWorker:"
echo "  s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/ScanWorker_data.pxl"
echo ""
echo "PartitionWorker:"
echo "  s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/PartitionWorker_data.pxl"
echo ""
echo "AggregationWorker:"
echo "  s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/AggregationWorker_data.pxl"
echo ""
echo "BroadcastJoinWorker:"
echo "  大表: s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/BroadcastJoinWorker_data1.pxl"
echo "  小表: s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/BroadcastJoinWorker_data2.pxl"
echo ""
echo "PartitionedJoinWorker:"
echo "  大表: s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/PartitionedJoinWorker_data1.pxl"
echo "  小表: s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/PartitionedJoinWorker_data2.pxl"
echo ""

