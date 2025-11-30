#!/bin/bash

# download-csv-metrics.sh
# Download performance metrics CSV files from S3 or extract from CloudWatch Logs

set -e

# Configuration
BUCKET_NAME="home-sunhao"
REGION="us-east-2"
S3_PREFIX="lambda-metrics"
OUTPUT_DIR="./performance-metrics"

# Worker definitions: WorkerType:CSVName:LambdaFunctionName
WORKERS=(
    "ScanWorker:scan:pixels-scan-worker"
    "AggregationWorker:aggregation:pixels-aggregationworker"
    "PartitionWorker:partition:pixels-partitionworker"
    "BroadcastJoinWorker:broadcast_join:pixels-broadcastjoinworker"
    "PartitionedJoinWorker:partitioned_join:pixels-partitionedjoinworker"
    "BroadcastChainJoinWorker:broadcast_chain_join:pixels-broadcastchainjoinworker"
    "PartitionedChainJoinWorker:partitioned_chain_join:pixels-partitionedchainjoinworker"
)

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        下载性能指标 CSV 文件                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Function to download from S3
download_from_s3() {
    local WORKER_TYPE=$1
    local CSV_NAME=$2
    local S3_KEY="${S3_PREFIX}/${CSV_NAME}_performance_metrics.csv"
    local OUTPUT_FILE="${OUTPUT_DIR}/${CSV_NAME}_performance_metrics.csv"
    
    echo -e "${BLUE}[下载 ${WORKER_TYPE}]${NC}"
    echo "  S3 路径: s3://${BUCKET_NAME}/${S3_KEY}"
    echo "  本地路径: ${OUTPUT_FILE}"
    
    if aws s3 ls "s3://${BUCKET_NAME}/${S3_KEY}" --region $REGION > /dev/null 2>&1; then
        aws s3 cp "s3://${BUCKET_NAME}/${S3_KEY}" "$OUTPUT_FILE" --region $REGION
        echo -e "${GREEN}✅ 下载成功${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  S3 文件不存在${NC}"
        return 1
    fi
}

# Function to extract from CloudWatch Logs and save as CSV
extract_from_logs() {
    local WORKER_TYPE=$1
    local CSV_NAME=$2
    local LAMBDA_NAME=$3
    local LOG_GROUP="/aws/lambda/${LAMBDA_NAME}"
    local OUTPUT_FILE="${OUTPUT_DIR}/${CSV_NAME}_performance_metrics_from_logs.csv"
    
    echo -e "${BLUE}[从 CloudWatch Logs 提取 ${WORKER_TYPE}]${NC}"
    echo "  Log Group: ${LOG_GROUP}"
    echo "  输出文件: ${OUTPUT_FILE}"
    
    # Check if log group exists
    LOG_GROUP_EXISTS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/${LAMBDA_NAME}" --region $REGION --query 'logGroups[?logGroupName==`'"$LOG_GROUP"'`].logGroupName' --output text 2>/dev/null || echo "")
    if [ -z "$LOG_GROUP_EXISTS" ] || [ "$LOG_GROUP_EXISTS" = "None" ]; then
        echo -e "${YELLOW}⚠️  Log Group 不存在: ${LOG_GROUP}${NC}"
        echo "  提示: Lambda 函数可能尚未被调用"
        return 1
    fi
    
    # Get recent log events (last 24 hours)
    START_TIME=$(($(date +%s) - 86400))000
    
    # Create CSV file with header
    echo "Timestamp,WorkerType,ReadTimeMs,ComputeTimeMs,WriteCacheTimeMs,WriteFileTimeMs,ComputePct,WriteCachePct,WriteFilePct,S3StoragePct" > "$OUTPUT_FILE"
    
    # Extract metrics from logs
    LOG_EVENTS=$(aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time $START_TIME \
        --region $REGION \
        --filter-pattern "Four-Stage Performance Metrics" \
        --query 'events[*].[timestamp,message]' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$LOG_EVENTS" ] || [ "$LOG_EVENTS" = "None" ]; then
        echo -e "${YELLOW}⚠️  未找到性能指标日志${NC}"
        return 1
    fi
    
    COUNT=0
    echo "$LOG_EVENTS" | while IFS=$'\t' read -r timestamp message; do
        if [ -n "$timestamp" ] && [ -n "$message" ]; then
            # Parse metrics from log message
            READ_MS=$(echo "$message" | grep -oE 'READ=[0-9]+' | grep -oE '[0-9]+' || echo "0")
            COMPUTE_MS=$(echo "$message" | grep -oE 'COMPUTE=[0-9]+' | grep -oE '[0-9]+' || echo "0")
            WRITE_CACHE_MS=$(echo "$message" | grep -oE 'WRITE_CACHE=[0-9]+' | grep -oE '[0-9]+' || echo "0")
            WRITE_FILE_MS=$(echo "$message" | grep -oE 'WRITE_FILE=[0-9]+' | grep -oE '[0-9]+' || echo "0")
            
            # Get corresponding percentages
            REQUEST_ID=$(echo "$message" | grep -oE '\[[0-9a-f-]+\]' | head -1 | tr -d '[]')
            PERCENTAGES=$(aws logs filter-log-events \
                --log-group-name "$LOG_GROUP" \
                --start-time $START_TIME \
                --region $REGION \
                --filter-pattern "\"$REQUEST_ID\" Percentages" \
                --query 'events[0].message' \
                --output text 2>/dev/null || echo "")
            
            if [ -n "$PERCENTAGES" ] && [ "$PERCENTAGES" != "None" ]; then
                COMPUTE_PCT=$(echo "$PERCENTAGES" | grep -oE 'COMPUTE=[0-9.]+' | grep -oE '[0-9.]+' || echo "0.00")
                WRITE_CACHE_PCT=$(echo "$PERCENTAGES" | grep -oE 'WRITE_CACHE=[0-9.]+' | grep -oE '[0-9.]+' || echo "0.00")
                WRITE_FILE_PCT=$(echo "$PERCENTAGES" | grep -oE 'WRITE_FILE=[0-9.]+' | grep -oE '[0-9.]+' || echo "0.00")
                S3_STORAGE_PCT=$(echo "$PERCENTAGES" | grep -oE 'S3 Storage=[0-9.]+' | grep -oE '[0-9.]+' || echo "0.00")
            else
                # Calculate from raw values
                TOTAL_MS=$((READ_MS + COMPUTE_MS + WRITE_CACHE_MS + WRITE_FILE_MS))
                if [ $TOTAL_MS -gt 0 ]; then
                    COMPUTE_PCT=$(awk "BEGIN {printf \"%.2f\", ($COMPUTE_MS / $TOTAL_MS) * 100}")
                    WRITE_CACHE_PCT=$(awk "BEGIN {printf \"%.2f\", ($WRITE_CACHE_MS / $TOTAL_MS) * 100}")
                    WRITE_FILE_PCT=$(awk "BEGIN {printf \"%.2f\", ($WRITE_FILE_MS / $TOTAL_MS) * 100}")
                    S3_STORAGE_PCT=$(awk "BEGIN {printf \"%.2f\", (($READ_MS + $WRITE_FILE_MS) / $TOTAL_MS) * 100}")
                else
                    COMPUTE_PCT="0.00"
                    WRITE_CACHE_PCT="0.00"
                    WRITE_FILE_PCT="0.00"
                    S3_STORAGE_PCT="0.00"
                fi
            fi
            
            # Convert timestamp to milliseconds (if needed)
            TIMESTAMP_MS=$timestamp
            if [ ${#TIMESTAMP_MS} -eq 10 ]; then
                TIMESTAMP_MS=$((TIMESTAMP_MS * 1000))
            fi
            
            # Write CSV row
            echo "${TIMESTAMP_MS},${WORKER_TYPE},${READ_MS},${COMPUTE_MS},${WRITE_CACHE_MS},${WRITE_FILE_MS},${COMPUTE_PCT},${WRITE_CACHE_PCT},${WRITE_FILE_PCT},${S3_STORAGE_PCT}" >> "$OUTPUT_FILE"
            COUNT=$((COUNT + 1))
        fi
    done
    
    # Count actual lines (subtract header)
    ACTUAL_COUNT=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
    ACTUAL_COUNT=$((ACTUAL_COUNT - 1))
    
    if [ $ACTUAL_COUNT -gt 0 ]; then
        echo -e "${GREEN}✅ 提取成功: ${ACTUAL_COUNT} 条记录${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠️  未提取到数据${NC}"
        rm -f "$OUTPUT_FILE"
        return 1
    fi
}

# Try to download from S3 first, then extract from logs if not found
SUCCESS_COUNT=0
FAIL_COUNT=0

for WORKER_DEF in "${WORKERS[@]}"; do
    WORKER_TYPE="${WORKER_DEF%%:*}"
    REMAINING="${WORKER_DEF#*:}"
    CSV_NAME="${REMAINING%%:*}"
    LAMBDA_NAME="${REMAINING##*:}"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if download_from_s3 "$WORKER_TYPE" "$CSV_NAME"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "  尝试从 CloudWatch Logs 提取..."
        if extract_from_logs "$WORKER_TYPE" "$CSV_NAME" "$LAMBDA_NAME"; then
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                     下载完成                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "统计:"
echo -e "  ${GREEN}✅ 成功: $SUCCESS_COUNT${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "  ${RED}❌ 失败: $FAIL_COUNT${NC}"
fi
echo ""
echo "文件位置:"
echo "  ${OUTPUT_DIR}/"
echo ""
ls -lh "$OUTPUT_DIR"/*.csv 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
echo ""
echo "💡 提示:"
echo "  如果 CSV 文件在 S3 中不存在，脚本会从 CloudWatch Logs 提取数据"
echo "  要启用自动上传到 S3，请修改 WorkerMetrics.java 并重新部署"
echo ""

