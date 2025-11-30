#!/bin/bash

# test-all-workers.sh
# Test all available Pixels Lambda Workers and extract performance metrics

set -e

# Configuration
BUCKET_NAME="home-sunhao"
REGION="us-east-2"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================="
echo "   测试所有 Pixels Lambda Workers"
echo "========================================="
echo ""

# Check which Lambda functions exist
echo "📋 检查已部署的 Lambda 函数..."
FUNCTIONS=$(aws lambda list-functions --region $REGION --query 'Functions[?contains(FunctionName, `pixels`) || contains(FunctionName, `worker`)].FunctionName' --output text)

if [ -z "$FUNCTIONS" ]; then
    echo "❌ 未找到任何 Pixels Worker Lambda 函数"
    echo "   请先部署 Worker 函数"
    exit 1
fi

echo "✅ 找到以下 Lambda 函数:"
echo "$FUNCTIONS" | tr '\t' '\n' | while read func; do
    echo "   - $func"
done

echo ""
echo "========================================="
echo ""

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
            /tmp/scan-response.json > /dev/null
        
        sleep 3
        
        # Extract performance metrics
        echo "提取性能指标..."
        extract_performance_metrics "pixels-scan-worker" "ScanWorker"
    else
        echo "⚠️  pixels-scan-worker 函数不存在，跳过"
    fi
    
    echo ""
}

# Extract performance metrics from CloudWatch Logs
extract_performance_metrics() {
    local FUNCTION_NAME=$1
    local WORKER_TYPE=$2
    local LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}=== ${WORKER_TYPE} 性能指标 ===${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Get recent log events with performance metrics
    METRICS=$(aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time $(($(date +%s) - 300))000 \
        --region $REGION \
        --filter-pattern "Four-Stage Performance Metrics" \
        --query 'events[-1].message' \
        --output text 2>/dev/null)
    
    PERCENTAGES=$(aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time $(($(date +%s) - 300))000 \
        --region $REGION \
        --filter-pattern "Percentages" \
        --query 'events[-1].message' \
        --output text 2>/dev/null)
    
    if [ -n "$METRICS" ] && [ "$METRICS" != "None" ]; then
        echo "$METRICS"
        if [ -n "$PERCENTAGES" ] && [ "$PERCENTAGES" != "None" ]; then
            echo "$PERCENTAGES"
        fi
        
        # Parse and format
        READ_MS=$(echo "$METRICS" | grep -oP 'READ=\K[0-9]+' || echo "0")
        COMPUTE_MS=$(echo "$METRICS" | grep -oP 'COMPUTE=\K[0-9]+' || echo "0")
        WRITE_CACHE_MS=$(echo "$METRICS" | grep -oP 'WRITE_CACHE=\K[0-9]+' || echo "0")
        WRITE_FILE_MS=$(echo "$METRICS" | grep -oP 'WRITE_FILE=\K[0-9]+' || echo "0")
        
        echo ""
        echo "Worker: ${WORKER_TYPE}"
        echo "READ: ${READ_MS} ms"
        echo "COMPUTE: ${COMPUTE_MS} ms"
        echo "WRITE_CACHE: ${WRITE_CACHE_MS} ms"
        echo "WRITE_FILE: ${WRITE_FILE_MS} ms"
        
        if [ -n "$PERCENTAGES" ] && [ "$PERCENTAGES" != "None" ]; then
            COMPUTE_PCT=$(echo "$PERCENTAGES" | grep -oP 'COMPUTE=\K[0-9.]+' || echo "0.00")
            WRITE_CACHE_PCT=$(echo "$PERCENTAGES" | grep -oP 'WRITE_CACHE=\K[0-9.]+' || echo "0.00")
            WRITE_FILE_PCT=$(echo "$PERCENTAGES" | grep -oP 'WRITE_FILE=\K[0-9.]+' || echo "0.00")
            S3_STORAGE_PCT=$(echo "$PERCENTAGES" | grep -oP 'S3 Storage=\K[0-9.]+' || echo "0.00")
            
            TOTAL_MS=$((READ_MS + COMPUTE_MS + WRITE_CACHE_MS + WRITE_FILE_MS))
            echo "COMPUTE: ${COMPUTE_MS} ms (${COMPUTE_PCT}%)"
            echo "WRITE_CACHE: ${WRITE_CACHE_MS} ms (${WRITE_CACHE_PCT}%)"
            echo "WRITE_FILE: ${WRITE_FILE_MS} ms (${WRITE_FILE_PCT}%)"
            echo "S3 Storage (READ + WRITE_FILE): ${S3_STORAGE_PCT}%"
            echo "总耗时: ${TOTAL_MS} ms"
        fi
    else
        echo "⚠️  未找到性能指标，可能函数尚未执行或日志尚未生成"
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main execution
test_scan_worker

echo ""
echo "========================================="
echo -e "${GREEN}✅ 测试完成${NC}"
echo "========================================="
echo ""
echo "📝 注意: 性能指标 CSV 文件保存在 Lambda 函数的 /tmp 目录中"
echo "   文件位置（Lambda 环境内）:"
echo "   - ScanWorker: /tmp/scan_performance_metrics.csv"
echo "   - AggregationWorker: /tmp/aggregation_performance_metrics.csv"
echo "   - PartitionWorker: /tmp/partition_performance_metrics.csv"
echo ""
echo "   这些文件无法直接从 Mac 访问，但性能指标已输出到 CloudWatch Logs"
echo "   使用上面的提取方法可以从日志中获取所有性能指标"



