#!/bin/bash
# Lambda 函数执行和性能数据提取脚本

set -e

FUNCTION_NAME="pixels-scan-worker"
REGION="us-east-2"

echo "========================================="
echo "Lambda 函数执行和性能数据统计"
echo "========================================="
echo "函数名称: $FUNCTION_NAME"
echo "区域: $REGION"
echo ""

# 检查测试输入文件是否存在
if [ ! -f "test-scan-input.json" ]; then
    echo "❌ 测试输入文件不存在: test-scan-input.json"
    echo "请先创建测试输入文件"
    exit 1
fi

echo "========================================="
echo "步骤1: Invoke Lambda 函数"
echo "========================================="
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload file://test-scan-input.json \
  --cli-binary-format raw-in-base64-out \
  --region $REGION \
  lambda-response.json

echo ""
echo "响应结果:"
cat lambda-response.json | jq . 2>/dev/null || cat lambda-response.json

# 检查是否有错误
ERROR=$(cat lambda-response.json | jq -r '.errorMessage // empty' 2>/dev/null)
if [ -n "$ERROR" ]; then
    echo ""
    echo "⚠️  Lambda 执行出错: $ERROR"
    echo "查看完整日志获取详细信息"
else
    echo ""
    echo "✅ Lambda 调用成功"
fi

echo ""
echo "========================================="
echo "步骤2: 等待日志写入 CloudWatch..."
echo "========================================="
sleep 10

echo ""
echo "========================================="
echo "步骤3: 提取性能数据"
echo "========================================="

echo ""
echo "四个阶段性能指标:"
PERF_METRICS=$(aws logs filter-log-events \
  --log-group-name /aws/lambda/$FUNCTION_NAME \
  --filter-pattern "Four-Stage Performance Metrics" \
  --start-time $(($(date +%s) - 600))000 \
  --region $REGION \
  --query 'events[-1].message' \
  --output text 2>/dev/null)

if [ -n "$PERF_METRICS" ] && [ "$PERF_METRICS" != "None" ]; then
    echo "$PERF_METRICS"
else
    echo "未找到性能指标（可能函数执行失败或日志未写入）"
fi

echo ""
echo "百分比数据:"
PERCENTAGES=$(aws logs filter-log-events \
  --log-group-name /aws/lambda/$FUNCTION_NAME \
  --filter-pattern "Percentages" \
  --start-time $(($(date +%s) - 600))000 \
  --region $REGION \
  --query 'events[-1].message' \
  --output text 2>/dev/null)

if [ -n "$PERCENTAGES" ] && [ "$PERCENTAGES" != "None" ]; then
    echo "$PERCENTAGES"
else
    echo "未找到百分比数据"
fi

echo ""
echo "========================================="
echo "步骤4: 保存性能数据到文件"
echo "========================================="
aws logs filter-log-events \
  --log-group-name /aws/lambda/$FUNCTION_NAME \
  --start-time $(($(date +%s) - 600))000 \
  --region $REGION \
  --query 'events[*].message' \
  --output text > lambda_performance_logs.txt 2>/dev/null || echo "无法提取日志"

if [ -f "lambda_performance_logs.txt" ]; then
    echo "✅ 性能数据已保存到: lambda_performance_logs.txt"
    echo ""
    echo "文件大小:"
    ls -lh lambda_performance_logs.txt | awk '{print $5}'
    echo ""
    echo "性能数据摘要:"
    grep -E "Four-Stage|Percentages|Performance Metrics|READ=|COMPUTE=|WRITE_" lambda_performance_logs.txt | head -5 || echo "未找到性能数据"
else
    echo "⚠️  无法保存性能数据"
fi

echo ""
echo "========================================="
echo "✅ 测试完成！"
echo "========================================="
echo ""
echo "查看完整日志:"
echo "aws logs tail /aws/lambda/$FUNCTION_NAME --since 10m --region $REGION"
