#!/bin/bash

# download-csv-simple.sh
# Simple script to extract performance metrics from CloudWatch Logs to CSV

set -e

REGION="us-east-2"
OUTPUT_DIR="./performance-metrics"
mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="${OUTPUT_DIR}/scan_performance_metrics.csv"

echo ""
echo "从 CloudWatch Logs 提取 ScanWorker 性能指标..."
echo "输出文件: $OUTPUT_FILE"
echo ""

# Create CSV header
cat > "$OUTPUT_FILE" << 'EOF'
Timestamp,WorkerType,ReadTimeMs,ComputeTimeMs,WriteCacheTimeMs,WriteFileTimeMs,ComputePct,WriteCachePct,WriteFilePct,S3StoragePct
EOF

# Extract metrics from logs using aws logs tail
aws logs tail /aws/lambda/pixels-scan-worker --since 24h --region $REGION --format short 2>/dev/null | \
  grep -E "Four-Stage Performance Metrics|Percentages" | \
  awk '
  BEGIN {
    OFS=","
    FS="[=,()]"
  }
  /Four-Stage Performance Metrics/ {
    # Extract timestamp (first field from ISO format)
    match($0, /([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})/, ts)
    timestamp = mktime(substr(ts[1], 1, 4) " " substr(ts[1], 6, 2) " " substr(ts[1], 9, 2) " " substr(ts[1], 12, 2) " " substr(ts[1], 15, 2) " " substr(ts[1], 18, 2)) * 1000
    
    # Extract metrics
    read = 0; compute = 0; cache = 0; file = 0
    if (match($0, /READ=([0-9]+)/, arr)) read = arr[1]
    if (match($0, /COMPUTE=([0-9]+)/, arr)) compute = arr[1]
    if (match($0, /WRITE_CACHE=([0-9]+)/, arr)) cache = arr[1]
    if (match($0, /WRITE_FILE=([0-9]+)/, arr)) file = arr[1]
    
    # Store metrics
    metrics_line = timestamp ",ScanWorker," read "," compute "," cache "," file
    next
  }
  /Percentages/ {
    compute_pct = "0.00"; cache_pct = "0.00"; file_pct = "0.00"; s3_pct = "0.00"
    if (match($0, /COMPUTE=([0-9.]+)%/, arr)) compute_pct = arr[1]
    if (match($0, /WRITE_CACHE=([0-9.]+)%/, arr)) cache_pct = arr[1]
    if (match($0, /WRITE_FILE=([0-9.]+)%/, arr)) file_pct = arr[1]
    if (match($0, /S3 Storage=([0-9.]+)%/, arr)) s3_pct = arr[1]
    
    # Print complete row if we have metrics_line
    if (metrics_line != "") {
      print metrics_line "," compute_pct "," cache_pct "," file_pct "," s3_pct >> "'"$OUTPUT_FILE"'"
      metrics_line = ""
    }
  }
  '

ROW_COUNT=$(tail -n +2 "$OUTPUT_FILE" | wc -l | tr -d ' ')

echo ""
if [ "$ROW_COUNT" -gt 0 ]; then
    echo "✅ 提取成功: $ROW_COUNT 条记录"
    echo ""
    echo "文件内容预览:"
    head -5 "$OUTPUT_FILE" | column -t -s,
    echo ""
    echo "完整文件: $OUTPUT_FILE"
else
    echo "⚠️  未提取到数据"
    echo ""
    echo "提示: 可能需要先调用 Lambda 函数生成日志"
fi
echo ""



