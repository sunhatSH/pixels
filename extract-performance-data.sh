#!/bin/bash
# 提取性能数据脚本

FUNCTION_NAME="pixels-scan-worker"
REGION="us-east-2"
TIME_WINDOW=3600  # 1小时内的日志

echo "========================================="
echo "提取 Lambda 性能数据"
echo "========================================="
echo "函数: $FUNCTION_NAME"
echo "区域: $REGION"
echo "时间窗口: 最近 $TIME_WINDOW 秒"
echo ""

# 提取日志
echo "正在提取日志..."
aws logs filter-log-events \
  --log-group-name /aws/lambda/$FUNCTION_NAME \
  --start-time $(($(date +%s) - $TIME_WINDOW))000 \
  --region $REGION \
  --query 'events[*].message' \
  --output text > performance_data.txt 2>/dev/null

if [ ! -s performance_data.txt ]; then
    echo "⚠️  未找到日志数据"
    echo "可能原因："
    echo "  1. Lambda 函数未执行"
    echo "  2. 函数执行失败"
    echo "  3. 日志时间窗口太小"
    exit 1
fi

echo "✅ 日志已提取"
echo ""

# 查找性能指标
echo "========================================="
echo "四个阶段性能指标:"
echo "========================================="
FOUR_STAGE=$(grep "Four-Stage Performance Metrics" performance_data.txt | tail -1)
if [ -n "$FOUR_STAGE" ]; then
    echo "$FOUR_STAGE"
else
    echo "未找到"
fi

echo ""
echo "========================================="
echo "百分比数据:"
echo "========================================="
PERCENTAGES=$(grep "Percentages" performance_data.txt | tail -1)
if [ -n "$PERCENTAGES" ]; then
    echo "$PERCENTAGES"
else
    echo "未找到"
fi

echo ""
echo "========================================="
echo "所有性能相关日志:"
echo "========================================="
grep -E -i "performance|metrics|read|compute|write|percentage|stage" performance_data.txt | head -20

echo ""
echo "========================================="
echo "✅ 完整数据已保存到: performance_data.txt"
echo "文件大小: $(ls -lh performance_data.txt | awk '{print $5}')"
