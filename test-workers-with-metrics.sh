#!/bin/bash

# test-workers-with-metrics.sh
# Test all Pixels Lambda Workers and extract performance metrics in the same format

set -e

# Configuration
BUCKET_NAME="home-sunhao"
REGION="us-east-2"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║    测试所有 Pixels Lambda Workers 并提取性能指标          ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check which Lambda functions exist
echo "📋 检查已部署的 Lambda 函数..."
FUNCTIONS=$(aws lambda list-functions --region $REGION \
    --query 'Functions[?contains(FunctionName, `pixels`) || contains(FunctionName, `worker`)].FunctionName' \
    --output text 2>/dev/null || echo "")

if [ -z "$FUNCTIONS" ]; then
    echo -e "${RED}❌ 未找到任何 Pixels Worker Lambda 函数${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 找到以下 Lambda 函数:${NC}"
echo "$FUNCTIONS" | tr '\t' '\n' | while read func; do
    echo "   - $func"
done
echo ""

# Extract performance metrics from CloudWatch Logs
extract_performance_metrics() {
    local FUNCTION_NAME=$1
    local WORKER_TYPE=$2
    local LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}=== ${WORKER_TYPE} 性能指标摘要 ===${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get recent log events with performance metrics (last 10 minutes)
    START_TIME=$(($(date +%s) - 600))000
    
    # Get the most recent performance metrics log entry
    METRICS_LINE=$(aws logs tail "$LOG_GROUP" --since 10m --region $REGION --format short 2>/dev/null \
        | grep "Four-Stage Performance Metrics" | tail -1)
    
    # Get the most recent percentages log entry
    PERCENTAGES_LINE=$(aws logs tail "$LOG_GROUP" --since 10m --region $REGION --format short 2>/dev/null \
        | grep "Percentages:" | tail -1)
    
    # Extract the message part (after timestamp and request ID)
    METRICS=$(echo "$METRICS_LINE" | sed -n 's/.*Four-Stage Performance Metrics (ms): //p' || echo "")
    PERCENTAGES=$(echo "$PERCENTAGES_LINE" | sed -n 's/.*Percentages: //p' || echo "")
    
    if [ -n "$METRICS" ] && [ -n "$METRICS_LINE" ]; then
        # Parse metrics
        READ_MS=$(echo "$METRICS" | grep -oE 'READ=[0-9]+' | grep -oE '[0-9]+' || echo "0")
        COMPUTE_MS=$(echo "$METRICS" | grep -oE 'COMPUTE=[0-9]+' | grep -oE '[0-9]+' || echo "0")
        WRITE_CACHE_MS=$(echo "$METRICS" | grep -oE 'WRITE_CACHE=[0-9]+' | grep -oE '[0-9]+' || echo "0")
        WRITE_FILE_MS=$(echo "$METRICS" | grep -oE 'WRITE_FILE=[0-9]+' | grep -oE '[0-9]+' || echo "0")
        
        # Parse percentages
        if [ -n "$PERCENTAGES" ] && [ "$PERCENTAGES" != "None" ] && [ "$PERCENTAGES" != "null" ]; then
            COMPUTE_PCT=$(echo "$PERCENTAGES" | grep -oE 'COMPUTE=[0-9.]+' | grep -oE '[0-9.]+' || echo "0.00")
            WRITE_CACHE_PCT=$(echo "$PERCENTAGES" | grep -oE 'WRITE_CACHE=[0-9.]+' | grep -oE '[0-9.]+' || echo "0.00")
            WRITE_FILE_PCT=$(echo "$PERCENTAGES" | grep -oE 'WRITE_FILE=[0-9.]+' | grep -oE '[0-9.]+' || echo "0.00")
            S3_STORAGE_PCT=$(echo "$PERCENTAGES" | grep -oE 'S3 Storage=[0-9.]+' | grep -oE '[0-9.]+' || echo "0.00")
        else
            # Calculate percentages if not found in log
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
        
        TOTAL_MS=$((READ_MS + COMPUTE_MS + WRITE_CACHE_MS + WRITE_FILE_MS))
        S3_STORAGE_MS=$((READ_MS + WRITE_FILE_MS))
        
        # Display in the same format as lambda-full-execution-log.txt
        echo "Worker: ${WORKER_TYPE}"
        echo "READ: ${READ_MS} ms"
        echo "COMPUTE: ${COMPUTE_MS} ms (${COMPUTE_PCT}%)"
        echo "WRITE_CACHE: ${WRITE_CACHE_MS} ms (${WRITE_CACHE_PCT}%)"
        echo "WRITE_FILE: ${WRITE_FILE_MS} ms (${WRITE_FILE_PCT}%)"
        echo "S3 Storage (READ + WRITE_FILE): ${S3_STORAGE_PCT}% (${S3_STORAGE_MS} ms = ${READ_MS} ms + ${WRITE_FILE_MS} ms)"
        TOTAL_SEC=$(echo "scale=1; $TOTAL_MS / 1000" | bc 2>/dev/null || echo "$(($TOTAL_MS / 1000)).0")
        echo "总耗时: ${TOTAL_MS} ms (约 ${TOTAL_SEC} 秒)"
        
        # Get memory usage from REPORT log
        MEMORY_INFO=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --start-time $START_TIME \
            --region $REGION \
            --filter-pattern "REPORT" \
            --query 'events[-1].message' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$MEMORY_INFO" ] && [ "$MEMORY_INFO" != "None" ]; then
            MEMORY_USED=$(echo "$MEMORY_INFO" | grep -oE 'Max Memory Used: [0-9]+' | grep -oE '[0-9]+' || echo "")
            MEMORY_SIZE=$(echo "$MEMORY_INFO" | grep -oE 'Memory Size: [0-9]+' | grep -oE '[0-9]+' || echo "")
            if [ -n "$MEMORY_USED" ] && [ -n "$MEMORY_SIZE" ]; then
                echo "内存使用: ${MEMORY_USED} MB / ${MEMORY_SIZE} MB"
            fi
        fi
        
    else
        echo -e "${YELLOW}⚠️  未找到最近的性能指标${NC}"
        echo "   可能的原因:"
        echo "   1. 函数尚未执行"
        echo "   2. 执行时间超过 5 分钟"
        echo "   3. 日志尚未生成"
        echo ""
        echo "   提示: 先调用函数，然后立即运行此脚本提取指标"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Test ScanWorker
test_scan_worker() {
    echo -e "${BLUE}[测试 ScanWorker]${NC}"
    
    if echo "$FUNCTIONS" | grep -q "pixels-scan-worker"; then
        echo "调用 ScanWorker..."
        
        cat > /tmp/test-scan-input.json << JSON
{
  "transId": 12345,
  "timestamp": -1,
  "requestId": "test-scan-$(date +%s)",
  "tableInfo": {
    "tableName": "test_table",
    "base": true,
    "columnsToRead": ["col1", "col2", "col3"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "inputSplits": [
      {
        "inputInfos": [
          {
            "inputId": 1,
            "path": "s3://${BUCKET_NAME}/test-data/large_test_data.pxl",
            "rgStart": 0,
            "rgLength": -1,
            "storageInfo": {
              "scheme": "s3",
              "endpoint": "https://s3.${REGION}.amazonaws.com"
            }
          }
        ]
      }
    ],
    "filter": "{\"schemaName\":\"test\",\"tableName\":\"test_table\",\"columnFilters\":{}}"
  },
  "scanProjection": [true, true, true],
  "partialAggregationPresent": false,
  "partialAggregationInfo": null,
  "output": {
    "path": "s3://${BUCKET_NAME}/output/",
    "fileNames": ["scan_result.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${REGION}.amazonaws.com"
    },
    "encoding": true
  },
  "inputStorageInfo": {
    "scheme": "s3",
    "endpoint": "https://s3.${REGION}.amazonaws.com"
  }
}
JSON

        aws lambda invoke \
            --function-name pixels-scan-worker \
            --payload file:///tmp/test-scan-input.json \
            --cli-binary-format raw-in-base64-out \
            --region $REGION \
            /tmp/scan-response.json > /dev/null 2>&1
        
        echo "等待日志生成..."
        sleep 5
        
        # Extract performance metrics
        extract_performance_metrics "pixels-scan-worker" "ScanWorker"
        
        # Save to file
        OUTPUT_FILE="lambda-worker-metrics-summary.txt"
        {
            echo "=== ScanWorker 性能指标摘要 ==="
            echo "Worker: ScanWorker"
            echo "提取时间: $(date)"
            echo ""
        } > "$OUTPUT_FILE"
        extract_performance_metrics "pixels-scan-worker" "ScanWorker" >> "$OUTPUT_FILE" 2>&1 || true
        
    else
        echo -e "${YELLOW}⚠️  pixels-scan-worker 函数不存在，跳过${NC}"
    fi
}

# Main execution
test_scan_worker

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo -e "${GREEN}✅ 测试完成${NC}"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "📝 关于性能指标文件位置:"
echo ""
echo "   ⚠️  性能指标 CSV 文件保存在 Lambda 函数的运行时环境中，不是您的 Mac！"
echo ""
echo "   文件位置（在 Lambda 运行环境内）:"
echo "   - ScanWorker: /tmp/scan_performance_metrics.csv"
echo "   - AggregationWorker: /tmp/aggregation_performance_metrics.csv"
echo "   - PartitionWorker: /tmp/partition_performance_metrics.csv"
echo "   - BroadcastJoinWorker: /tmp/broadcast_join_performance_metrics.csv"
echo "   - PartitionedJoinWorker: /tmp/partitioned_join_performance_metrics.csv"
echo ""
echo "   💡 这些文件无法直接从 Mac 访问，但性能指标已输出到 CloudWatch Logs"
echo "   您可以:"
echo "   1. 从 CloudWatch Logs 提取（已在此脚本中实现）"
echo "   2. 修改代码将 CSV 文件上传到 S3"
echo "   3. 在 AWS Console 中查看 CloudWatch Logs"
echo ""

