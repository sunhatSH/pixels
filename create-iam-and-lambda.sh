#!/bin/bash
set -e

BUCKET_NAME="home-sunhao"
FUNCTION_NAME="pixels-scan-worker"
ROLE_NAME="pixels-lambda-execution-role"
POLICY_NAME="pixels-lambda-policy"
ACCOUNT_ID="970089764833"

echo "========================================="
echo "创建 IAM 角色和 Lambda 函数"
echo "========================================="

# 步骤1: 创建 IAM 角色
echo ""
echo "步骤1: 创建 IAM 角色"
echo "----------------------------------------"

# 检查角色是否已存在
if aws iam get-role --role-name $ROLE_NAME &>/dev/null; then
    echo "✅ 角色已存在: $ROLE_NAME"
    ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)
    echo "Role ARN: $ROLE_ARN"
else
    echo "创建信任策略..."
    cat > /tmp/trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    echo "创建角色..."
    aws iam create-role \
      --role-name $ROLE_NAME \
      --assume-role-policy-document file:///tmp/trust-policy.json
    
    ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)
    echo "✅ 角色创建成功: $ROLE_ARN"
fi

# 步骤2: 创建并附加策略
echo ""
echo "步骤2: 创建并附加 IAM 策略"
echo "----------------------------------------"

cat > /tmp/lambda-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::$BUCKET_NAME/*",
        "arn:aws:s3:::$BUCKET_NAME"
      ]
    }
  ]
}
EOF

POLICY_ARN="arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME"

# 检查策略是否存在
if aws iam get-policy --policy-arn $POLICY_ARN &>/dev/null; then
    echo "✅ 策略已存在: $POLICY_NAME"
else
    echo "创建策略..."
    aws iam create-policy \
      --policy-name $POLICY_NAME \
      --policy-document file:///tmp/lambda-policy.json
    echo "✅ 策略创建成功"
fi

# 附加策略到角色
echo "附加策略到角色..."
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn $POLICY_ARN 2>/dev/null || echo "策略已附加"

# 步骤3: 创建 Lambda 函数
echo ""
echo "步骤3: 创建 Lambda 函数"
echo "----------------------------------------"

if aws lambda get-function --function-name $FUNCTION_NAME &>/dev/null; then
    echo "函数已存在，更新代码..."
    aws lambda update-function-code \
      --function-name $FUNCTION_NAME \
      --s3-bucket $BUCKET_NAME \
      --s3-key lambda/pixels-worker-lambda.jar
    
    aws lambda wait function-updated --function-name $FUNCTION_NAME
    echo "✅ 函数代码已更新"
else
    echo "创建 Lambda 函数..."
    aws lambda create-function \
      --function-name $FUNCTION_NAME \
      --runtime java21 \
      --role $ROLE_ARN \
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
echo "========================================="
echo "✅ 部署完成！"
echo "========================================="
echo "函数名称: $FUNCTION_NAME"
echo "Role ARN: $ROLE_ARN"
