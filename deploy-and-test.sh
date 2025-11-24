#!/bin/bash
# Lambda 部署和测试脚本

set -e

BUCKET_NAME="home-sunhao"
FUNCTION_NAME="pixels-scan-worker"
EC2_HOST="ec2-user@3.87.201.11"
SSH_KEY="~/.ssh/pixels-key.pem"

echo "========================================="
echo "Lambda 部署和性能测试"
echo "========================================="

# 步骤1: 查找并上传 JAR 文件到 S3
echo ""
echo "步骤1: 上传 JAR 文件到 S3"
echo "----------------------------------------"

# 查找正确的 JAR 文件（使用 deps jar，包含所有依赖）
JAR_FILE=$(ssh -i $SSH_KEY $EC2_HOST "cd ~/pixels && find pixels-turbo/pixels-worker-lambda/target -name '*deps*.jar' | head -1")

if [ -z "$JAR_FILE" ]; then
    echo "❌ 未找到 JAR 文件，请检查编译是否成功"
    exit 1
fi

echo "找到 JAR 文件: $JAR_FILE"
echo "文件大小:"
ssh -i $SSH_KEY $EC2_HOST "ls -lh ~/pixels/$JAR_FILE"

# 下载到本地临时目录
echo "下载 JAR 文件到本地..."
scp -i $SSH_KEY $EC2_HOST:"~/pixels/$JAR_FILE" /tmp/pixels-worker-lambda.jar

# 上传到 S3
echo "上传到 S3..."
aws s3 cp /tmp/pixels-worker-lambda.jar s3://$BUCKET_NAME/lambda/pixels-worker-lambda.jar
echo "✅ JAR 已上传到: s3://$BUCKET_NAME/lambda/pixels-worker-lambda.jar"

# 步骤2: 检查或创建 Lambda 函数
echo ""
echo "步骤2: 检查 Lambda 函数"
echo "----------------------------------------"

# 检查函数是否存在
if aws lambda get-function --function-name $FUNCTION_NAME &>/dev/null; then
    echo "函数已存在，更新代码..."
    aws lambda update-function-code \
      --function-name $FUNCTION_NAME \
      --s3-bucket $BUCKET_NAME \
      --s3-key lambda/pixels-worker-lambda.jar
    
    echo "等待更新完成..."
    aws lambda wait function-updated --function-name $FUNCTION_NAME
    echo "✅ 函数代码已更新"
else
    echo "⚠️  函数不存在，需要先创建 Lambda 函数"
    echo ""
    echo "请先创建 IAM 角色，然后运行以下命令创建函数："
    echo ""
    echo "aws lambda create-function \\"
    echo "  --function-name $FUNCTION_NAME \\"
    echo "  --runtime java21 \\"
    echo "  --role arn:aws:iam::970089764833:role/pixels-lambda-execution-role \\"
    echo "  --handler io.pixelsdb.pixels.worker.lambda.ScanWorker::handleRequest \\"
    echo "  --code S3Bucket=$BUCKET_NAME,S3Key=lambda/pixels-worker-lambda.jar \\"
    echo "  --architectures arm64 \\"
    echo "  --memory-size 4096 \\"
    echo "  --timeout 900"
    echo ""
    exit 1
fi

# 步骤3: 准备测试输入
echo ""
echo "步骤3: 准备测试输入"
echo "----------------------------------------"

cat > /tmp/test-scan-input.json << 'EOF'
{
  "transId": 12345,
  "timestamp": 1640995200000,
  "requestId": "test-performance-001",
  "inputSplits": [
    {
      "inputInfos": [
        {
          "inputId": 1,
          "path": "s3://home-sunhao/test-data/input.pxl",
          "rgStart": 0,
          "rgLength": -1,
          "storageInfo": {
            "scheme": "s3",
            "endpoint": "https://s3.us-east-1.amazonaws.com"
          }
        }
      ]
    }
  ],
  "columnsToRead": ["col1", "col2", "col3"],
  "scanProjection": [true, true, true],
  "filter": null,
  "output": {
    "path": "s3://home-sunhao/output/",
    "fileNames": ["result.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.us-east-1.amazonaws.com"
    },
    "encoding": true
  },
  "inputStorageInfo": {
    "scheme": "s3",
    "endpoint": "https://s3.us-east-1.amazonaws.com"
  }
}
EOF

echo "✅ 测试输入已准备: /tmp/test-scan-input.json"
echo "注意: 请确保 S3 路径 s3://home-sunhao/test-data/input.pxl 存在，或修改为实际路径"

# 步骤4: Invoke Lambda 函数
echo ""
echo "步骤4: Invoke Lambda 函数"
echo "----------------------------------------"
echo "正在调用 Lambda 函数..."

aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload file:///tmp/test-scan-input.json \
  --cli-binary-format raw-in-base64-out \
  /tmp/lambda-response.json

echo ""
echo "响应结果:"
cat /tmp/lambda-response.json | jq . 2>/dev/null || cat /tmp/lambda-response.json

# 检查是否有错误
ERROR=$(cat /tmp/lambda-response.json | jq -r '.errorMessage // empty' 2>/dev/null)
if [ -n "$ERROR" ]; then
    echo ""
    echo "❌ Lambda 执行出错: $ERROR"
    echo "请查看 CloudWatch 日志获取详细信息"
else
    echo ""
    echo "✅ Lambda 执行成功"
fi

# 步骤5: 查看性能数据
echo ""
echo "步骤5: 从 CloudWatch 提取性能数据"
echo "----------------------------------------"

echo "等待 5 秒让日志写入..."
sleep 5

echo ""
echo "最近的性能指标日志:"
aws logs filter-log-events \
  --log-group-name /aws/lambda/$FUNCTION_NAME \
  --filter-pattern "Four-Stage Performance Metrics" \
  --start-time $(($(date +%s) - 300))000 \
  --query 'events[-1].message' \
  --output text 2>/dev/null || echo "未找到性能指标日志"

echo ""
echo "百分比数据:"
aws logs filter-log-events \
  --log-group-name /aws/lambda/$FUNCTION_NAME \
  --filter-pattern "Percentages" \
  --start-time $(($(date +%s) - 300))000 \
  --query 'events[-1].message' \
  --output text 2>/dev/null || echo "未找到百分比数据"

echo ""
echo "========================================="
echo "✅ 部署和测试完成！"
echo "========================================="
echo ""
echo "查看完整日志:"
echo "aws logs tail /aws/lambda/$FUNCTION_NAME --follow"
echo ""
echo "提取所有性能数据:"
echo "aws logs filter-log-events --log-group-name /aws/lambda/$FUNCTION_NAME --filter-pattern 'Performance Metrics' --start-time \$(date -d '1 hour ago' +%s)000"

