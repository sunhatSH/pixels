#!/bin/bash

# deploy-all-workers.sh
# Deploy all Pixels Lambda Workers

set -e

# Configuration
BUCKET_NAME="home-sunhao"
REGION="us-east-2"
ROLE_ARN="arn:aws:iam::970089764833:role/PixelsLambdaRole"
JAR_S3_KEY="lambda/pixels-worker-lambda.jar"
RUNTIME="java21"
ARCHITECTURE="arm64"
MEMORY_SIZE=4096
TIMEOUT=900

# Worker definitions (WorkerName:Handler)
WORKERS=(
    "AggregationWorker:io.pixelsdb.pixels.worker.lambda.AggregationWorker"
    "PartitionWorker:io.pixelsdb.pixels.worker.lambda.PartitionWorker"
    "BroadcastJoinWorker:io.pixelsdb.pixels.worker.lambda.BroadcastJoinWorker"
    "PartitionedJoinWorker:io.pixelsdb.pixels.worker.lambda.PartitionedJoinWorker"
    "BroadcastChainJoinWorker:io.pixelsdb.pixels.worker.lambda.BroadcastChainJoinWorker"
    "PartitionedChainJoinWorker:io.pixelsdb.pixels.worker.lambda.PartitionedChainJoinWorker"
    "SortedJoinWorker:io.pixelsdb.pixels.worker.lambda.SortedJoinWorker"
    "SortWorker:io.pixelsdb.pixels.worker.lambda.SortWorker"
)

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        部署所有 Pixels Lambda Workers                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "配置信息:"
echo "  - Region: $REGION"
echo "  - Bucket: $BUCKET_NAME"
echo "  - JAR 文件: s3://$BUCKET_NAME/$JAR_S3_KEY"
echo "  - Runtime: $RUNTIME"
echo "  - Architecture: $ARCHITECTURE"
echo "  - Memory: ${MEMORY_SIZE} MB"
echo "  - Timeout: ${TIMEOUT} 秒"
echo "  - Role: $ROLE_ARN"
echo ""

# Check if JAR file exists in S3
echo "📦 检查 JAR 文件..."
if ! aws s3 ls "s3://$BUCKET_NAME/$JAR_S3_KEY" --region $REGION > /dev/null 2>&1; then
    echo -e "${RED}❌ JAR 文件不存在: s3://$BUCKET_NAME/$JAR_S3_KEY${NC}"
    echo "   请先上传 JAR 文件到 S3"
    exit 1
fi
echo -e "${GREEN}✅ JAR 文件存在${NC}"
echo ""

# Function to deploy a single worker
deploy_worker() {
    local FUNCTION_NAME=$1
    local HANDLER=$2
    # Convert to lowercase with hyphen format: pixels-{lowercase-name}-worker
    # Example: AggregationWorker -> pixels-aggregation-worker
    local LOWER_NAME=$(echo "$FUNCTION_NAME" | tr '[:upper:]' '[:lower:]')
    local LAMBDA_NAME="pixels-${LOWER_NAME}"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}[部署 $FUNCTION_NAME]${NC}"
    echo "  Lambda 函数名: $LAMBDA_NAME"
    echo "  Handler: $HANDLER"
    echo ""
    
    # Check if function already exists
    if aws lambda get-function --function-name "$LAMBDA_NAME" --region $REGION > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  函数已存在，更新配置和代码...${NC}"
        
        # Update function code
        echo "  更新代码..."
        aws lambda update-function-code \
            --function-name "$LAMBDA_NAME" \
            --s3-bucket "$BUCKET_NAME" \
            --s3-key "$JAR_S3_KEY" \
            --region $REGION \
            > /dev/null
        
        # Wait for update to complete
        echo "  等待更新完成..."
        aws lambda wait function-updated \
            --function-name "$LAMBDA_NAME" \
            --region $REGION
        
        # Update configuration
        echo "  更新配置..."
        aws lambda update-function-configuration \
            --function-name "$LAMBDA_NAME" \
            --runtime "$RUNTIME" \
            --memory-size $MEMORY_SIZE \
            --timeout $TIMEOUT \
            --handler "$HANDLER::handleRequest" \
            --architectures "$ARCHITECTURE" \
            --region $REGION \
            > /dev/null
        
        echo -e "${GREEN}✅ $FUNCTION_NAME 更新成功${NC}"
    else
        echo "  创建新函数..."
        
        # Create function
        aws lambda create-function \
            --function-name "$LAMBDA_NAME" \
            --runtime "$RUNTIME" \
            --role "$ROLE_ARN" \
            --handler "$HANDLER::handleRequest" \
            --code "S3Bucket=$BUCKET_NAME,S3Key=$JAR_S3_KEY" \
            --architectures "$ARCHITECTURE" \
            --memory-size $MEMORY_SIZE \
            --timeout $TIMEOUT \
            --environment "Variables={PIXELS_HOME=/opt/pixels}" \
            --region $REGION \
            > /dev/null
        
        echo -e "${GREEN}✅ $FUNCTION_NAME 创建成功${NC}"
    fi
    
    echo ""
}

# Deploy all workers
SUCCESS_COUNT=0
FAIL_COUNT=0

for WORKER_DEF in "${WORKERS[@]}"; do
    WORKER_NAME="${WORKER_DEF%%:*}"
    HANDLER="${WORKER_DEF##*:}"
    
    if deploy_worker "$WORKER_NAME" "$HANDLER"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo -e "${RED}❌ $WORKER_NAME 部署失败${NC}"
    fi
done

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                     部署完成                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "统计:"
echo -e "  ${GREEN}✅ 成功: $SUCCESS_COUNT${NC}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "  ${RED}❌ 失败: $FAIL_COUNT${NC}"
fi
echo ""

# List all deployed functions
echo "已部署的 Lambda 函数:"
aws lambda list-functions --region $REGION \
    --query 'Functions[?contains(FunctionName, `pixels`) && contains(FunctionName, `worker`)].FunctionName' \
    --output table

echo ""
echo "下一步:"
echo "  1. 运行 ./test-workers-with-metrics.sh 测试所有 Worker"
echo "  2. 查看 CloudWatch Logs 验证部署"
echo ""

