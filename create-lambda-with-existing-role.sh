#!/bin/bash
set -e

BUCKET_NAME="home-sunhao"
FUNCTION_NAME="pixels-scan-worker"

echo "========================================="
echo "创建 Lambda 函数（使用现有角色）"
echo "========================================="

# 尝试查找可用的 Lambda 执行角色
echo "查找可用的 IAM 角色..."
ROLES=$(aws iam list-roles --query 'Roles[].RoleName' --output text 2>/dev/null || echo "")

# 尝试常见的角色名称
POSSIBLE_ROLES=(
    "lambda-execution-role"
    "LambdaExecutionRole"
    "AWSLambdaBasicExecutionRole"
    "pixels-lambda-execution-role"
)

ROLE_ARN=""
for role in "${POSSIBLE_ROLES[@]}"; do
    if echo "$ROLES" | grep -qi "$role"; then
        ROLE_ARN=$(aws iam get-role --role-name "$role" --query 'Role.Arn' --output text 2>/dev/null)
        if [ -n "$ROLE_ARN" ]; then
            echo "✅ 找到角色: $role"
            echo "Role ARN: $ROLE_ARN"
            break
        fi
    fi
done

if [ -z "$ROLE_ARN" ]; then
    echo "❌ 未找到合适的 IAM 角色"
    echo ""
    echo "请提供 IAM 角色的 ARN，或联系管理员创建角色。"
    echo "需要的权限："
    echo "  - CloudWatch Logs: logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents"
    echo "  - S3: s3:GetObject, s3:PutObject, s3:ListBucket (for bucket: $BUCKET_NAME)"
    echo ""
    read -p "请输入 IAM 角色 ARN (或按 Enter 跳过): " ROLE_ARN
    if [ -z "$ROLE_ARN" ]; then
        echo "跳过创建 Lambda 函数"
        exit 0
    fi
fi

# 创建 Lambda 函数
echo ""
echo "创建 Lambda 函数..."
if aws lambda get-function --function-name $FUNCTION_NAME &>/dev/null; then
    echo "函数已存在，更新代码..."
    aws lambda update-function-code \
      --function-name $FUNCTION_NAME \
      --s3-bucket $BUCKET_NAME \
      --s3-key lambda/pixels-worker-lambda.jar
    
    aws lambda wait function-updated --function-name $FUNCTION_NAME
    echo "✅ 函数代码已更新"
else
    echo "创建新函数..."
    aws lambda create-function \
      --function-name $FUNCTION_NAME \
      --runtime java21 \
      --role "$ROLE_ARN" \
      --handler io.pixelsdb.pixels.worker.lambda.ScanWorker::handleRequest \
      --code S3Bucket=$BUCKET_NAME,S3Key=lambda/pixels-worker-lambda.jar \
      --architectures arm64 \
      --memory-size 4096 \
      --timeout 900 \
      --description "Pixels Scan Worker with four-stage performance metrics"
    
    aws lambda wait function-active --function-name $FUNCTION_NAME
    echo "✅ Lambda 函数创建成功"
fi

echo ""
echo "函数名称: $FUNCTION_NAME"
echo "Role ARN: $ROLE_ARN"
