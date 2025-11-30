#!/bin/bash

# download-csv-from-logs.sh
# Extract performance metrics from CloudWatch Logs and save as CSV

set -e

# Configuration
REGION="us-east-2"
OUTPUT_DIR="./performance-metrics"
LAMBDA_NAME="pixels-scan-worker"
LOG_GROUP="/aws/lambda/${LAMBDA_NAME}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║    从 CloudWatch Logs 提取性能指标为 CSV                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="${OUTPUT_DIR}/scan_performance_metrics.csv"

# Create CSV header
echo "Timestamp,WorkerType,ReadTimeMs,ComputeTimeMs,WriteCacheTimeMs,WriteFileTimeMs,ComputePct,WriteCachePct,WriteFilePct,S3StoragePct" > "$OUTPUT_FILE"

echo -e "${BLUE}[提取 ScanWorker 性能指标]${NC}"
echo "  Log Group: ${LOG_GROUP}"
echo "  输出文件: ${OUTPUT_FILE}"
echo ""

# Get log stream names from last 24 hours
START_TIME=$(($(date +%s) - 86400))000

echo "获取日志流..."
LOG_STREAMS=$(aws logs describe-log-streams \
    --log-group-name "$LOG_GROUP" \
    --start-time $START_TIME \
    --order-by LastEventTime \
    --descending \
    --max-items 10 \
    --region $REGION \
    --query 'logStreams[*].logStreamName' \
    --output text 2>/dev/null || echo "")

if [ -z "$LOG_STREAMS" ]; then
    echo -e "${YELLOW}⚠️  未找到日志流${NC}"
    exit 1
fi

echo "找到 $(echo "$LOG_STREAMS" | wc -w | tr -d ' ') 个日志流"
echo ""

# Extract metrics from each log stream
COUNT=0
for STREAM in $LOG_STREAMS; do
    echo "处理日志流: $STREAM"
    
    # Get log events with performance metrics
    EVENTS=$(aws logs get-log-events \
        --log-group-name "$LOG_GROUP" \
        --log-stream-name "$STREAM" \
        --start-time $START_TIME \
        --region $REGION \
        --query 'events[?contains(message, `Four-Stage Performance Metrics`) || contains(message, `Percentages`)].{timestamp:timestamp,message:message}' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$EVENTS" = "[]" ] || [ -z "$EVENTS" ]; then
        continue
    fi
    
    # Process events in pairs (metrics + percentages)
    echo "$EVENTS" | python3 -c "
import json
import sys
import re

events = json.load(sys.stdin)
metrics_by_request = {}

for event in events:
    msg = event['message']
    ts = event['timestamp']
    
    # Extract request ID
    request_id_match = re.search(r'\[([0-9a-f-]+)\]', msg)
    if not request_id_match:
        continue
    request_id = request_id_match.group(1)
    
    if 'Four-Stage Performance Metrics' in msg:
        # Extract metrics
        read_match = re.search(r'READ=(\d+)', msg)
        compute_match = re.search(r'COMPUTE=(\d+)', msg)
        cache_match = re.search(r'WRITE_CACHE=(\d+)', msg)
        file_match = re.search(r'WRITE_FILE=(\d+)', msg)
        
        if request_id not in metrics_by_request:
            metrics_by_request[request_id] = {'timestamp': ts}
        
        if read_match:
            metrics_by_request[request_id]['read'] = read_match.group(1)
        if compute_match:
            metrics_by_request[request_id]['compute'] = compute_match.group(1)
        if cache_match:
            metrics_by_request[request_id]['cache'] = cache_match.group(1)
        if file_match:
            metrics_by_request[request_id]['file'] = file_match.group(1)
    
    elif 'Percentages' in msg:
        # Extract percentages
        if request_id not in metrics_by_request:
            continue
        
        compute_pct_match = re.search(r'COMPUTE=([0-9.]+)%', msg)
        cache_pct_match = re.search(r'WRITE_CACHE=([0-9.]+)%', msg)
        file_pct_match = re.search(r'WRITE_FILE=([0-9.]+)%', msg)
        s3_pct_match = re.search(r'S3 Storage=([0-9.]+)%', msg)
        
        if compute_pct_match:
            metrics_by_request[request_id]['compute_pct'] = compute_pct_match.group(1)
        if cache_pct_match:
            metrics_by_request[request_id]['cache_pct'] = cache_pct_match.group(1)
        if file_pct_match:
            metrics_by_request[request_id]['file_pct'] = file_pct_match.group(1)
        if s3_pct_match:
            metrics_by_request[request_id]['s3_pct'] = s3_pct_match.group(1)

# Output CSV rows
for req_id, data in metrics_by_request.items():
    if 'read' in data and 'compute' in data:
        ts = data.get('timestamp', 0)
        read = data.get('read', '0')
        compute = data.get('compute', '0')
        cache = data.get('cache', '0')
        file = data.get('file', '0')
        compute_pct = data.get('compute_pct', '0.00')
        cache_pct = data.get('cache_pct', '0.00')
        file_pct = data.get('file_pct', '0.00')
        s3_pct = data.get('s3_pct', '0.00')
        
        print(f\"{ts},ScanWorker,{read},{compute},{cache},{file},{compute_pct},{cache_pct},{file_pct},{s3_pct}\")
" >> "$OUTPUT_FILE" 2>/dev/null && COUNT=$((COUNT + 1)) || true
done

# Count actual data rows (excluding header)
ACTUAL_COUNT=$(tail -n +2 "$OUTPUT_FILE" | grep -v "^$" | wc -l | tr -d ' ')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $ACTUAL_COUNT -gt 0 ]; then
    echo -e "${GREEN}✅ 提取成功: ${ACTUAL_COUNT} 条记录${NC}"
    echo ""
    echo "文件位置: ${OUTPUT_FILE}"
    echo ""
    echo "前几行数据:"
    head -5 "$OUTPUT_FILE" | column -t -s,
else
    echo -e "${YELLOW}⚠️  未提取到数据${NC}"
    rm -f "$OUTPUT_FILE"
fi
echo ""



