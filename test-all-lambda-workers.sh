#!/bin/bash

# test-all-lambda-workers.sh
# Test all deployed Lambda Worker functions

set -e

REGION="us-east-2"
BUCKET_NAME="home-sunhao"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        测试所有 Pixels Lambda Workers                     ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Get all worker functions
FUNCTIONS=$(aws lambda list-functions --region $REGION \
    --query 'Functions[?contains(FunctionName, `pixels`) && contains(FunctionName, `worker`)].FunctionName' \
    --output text)

if [ -z "$FUNCTIONS" ]; then
    echo -e "${RED}❌ 未找到任何 Lambda Worker 函数${NC}"
    exit 1
fi

echo "找到以下 Lambda 函数:"
echo "$FUNCTIONS" | tr '\t' '\n' | nl
echo ""

# Test results
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Test ScanWorker (we know this works)
test_scan_worker() {
    local FUNC_NAME="pixels-scan-worker"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}[测试 $FUNC_NAME]${NC}"
    
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
    "fileNames": ["scan_test_$(date +%s).pxl"],
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

    if aws lambda invoke \
        --function-name "$FUNC_NAME" \
        --payload file:///tmp/test-scan-input.json \
        --cli-binary-format raw-in-base64-out \
        --region $REGION \
        /tmp/response-scan.json > /dev/null 2>&1; then
        
        # Check response
        if grep -q '"successful":true' /tmp/response-scan.json 2>/dev/null; then
            echo -e "${GREEN}✅ 成功${NC}"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        elif grep -q '"successful":false' /tmp/response-scan.json 2>/dev/null; then
            ERROR_MSG=$(grep -o '"errorMessage":"[^"]*"' /tmp/response-scan.json 2>/dev/null || echo "Unknown error")
            echo -e "${YELLOW}⚠️  执行失败: $ERROR_MSG${NC}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        else
            echo -e "${YELLOW}⚠️  响应格式异常${NC}"
            cat /tmp/response-scan.json | head -5
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        echo -e "${RED}❌ 调用失败${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Test AggregationWorker
test_aggregation_worker() {
    local FUNC_NAME="pixels-aggregationworker"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}[测试 $FUNC_NAME]${NC}"
    echo "  ⚠️  需要输入文件路径，暂时跳过"
    echo -e "${YELLOW}⚠️  跳过（需要有效的输入文件）${NC}"
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

# Test PartitionWorker
test_partition_worker() {
    local FUNC_NAME="pixels-partitionworker"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}[测试 $FUNC_NAME]${NC}"
    echo "  ⚠️  需要输入文件路径，暂时跳过"
    echo -e "${YELLOW}⚠️  跳过（需要有效的输入文件）${NC}"
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

# Test a worker function (generic)
test_worker_generic() {
    local FUNC_NAME=$1
    local WORKER_TYPE=$2
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}[测试 $FUNC_NAME]${NC}"
    
    # Create a minimal test payload
    cat > /tmp/test-${WORKER_TYPE}-input.json << JSON
{
  "transId": 12345,
  "timestamp": -1,
  "requestId": "test-${WORKER_TYPE}-$(date +%s)"
}
JSON

    echo "  调用函数..."
    if aws lambda invoke \
        --function-name "$FUNC_NAME" \
        --payload file:///tmp/test-${WORKER_TYPE}-input.json \
        --cli-binary-format raw-in-base64-out \
        --region $REGION \
        /tmp/response-${WORKER_TYPE}.json > /dev/null 2>&1; then
        
        # Wait a moment for logs
        sleep 2
        
        # Check response
        if [ -f "/tmp/response-${WORKER_TYPE}.json" ]; then
            RESPONSE_SIZE=$(wc -c < /tmp/response-${WORKER_TYPE}.json | tr -d ' ')
            if [ "$RESPONSE_SIZE" -gt 10 ]; then
                if grep -q '"successful":true' /tmp/response-${WORKER_TYPE}.json 2>/dev/null; then
                    echo -e "${GREEN}✅ 成功${NC}"
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                elif grep -q '"successful":false\|errorMessage\|errorType' /tmp/response-${WORKER_TYPE}.json 2>/dev/null; then
                    ERROR_MSG=$(grep -o '"errorMessage":"[^"]*"' /tmp/response-${WORKER_TYPE}.json 2>/dev/null | head -1 || echo "Unknown error")
                    echo -e "${YELLOW}⚠️  执行失败: $ERROR_MSG${NC}"
                    echo "  响应预览:"
                    cat /tmp/response-${WORKER_TYPE}.json | head -3 | sed 's/^/    /'
                    FAIL_COUNT=$((FAIL_COUNT + 1))
                else
                    echo -e "${GREEN}✅ 函数可调用（响应: ${RESPONSE_SIZE} bytes）${NC}"
                    echo "  响应预览:"
                    cat /tmp/response-${WORKER_TYPE}.json | head -5 | sed 's/^/    /'
                    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
                fi
            else
                echo -e "${RED}❌ 响应为空${NC}"
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
        else
            echo -e "${RED}❌ 响应文件不存在${NC}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        echo -e "${RED}❌ 调用失败${NC}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Test all functions
echo "开始测试..."
echo ""

# Test ScanWorker first (known to work)
test_scan_worker
sleep 1

# Test other workers
for FUNC in $FUNCTIONS; do
    if [ "$FUNC" != "pixels-scan-worker" ]; then
        # Extract worker type from function name
        WORKER_TYPE=$(echo "$FUNC" | sed 's/pixels-//;s/-worker//;s/worker$//')
        test_worker_generic "$FUNC" "$WORKER_TYPE"
        sleep 1
    fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                     测试完成                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "统计:"
echo -e "  ${GREEN}✅ 成功/可调用: $SUCCESS_COUNT${NC}"
echo -e "  ${RED}❌ 失败: $FAIL_COUNT${NC}"
echo -e "  ${YELLOW}⚠️  跳过: $SKIP_COUNT${NC}"
echo ""

# Check log groups
echo "检查 Log Groups（函数被调用后会创建）:"
for FUNC in $FUNCTIONS; do
    LOG_GROUP="/aws/lambda/$FUNC"
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --region $REGION --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP"; then
        echo -e "  ${GREEN}✅ $FUNC${NC}"
    else
        echo -e "  ${YELLOW}⚠️  $FUNC (Log Group 不存在)${NC}"
    fi
done
echo ""



