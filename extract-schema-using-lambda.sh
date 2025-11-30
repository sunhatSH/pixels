#!/bin/bash
# 使用 Lambda 临时函数从 Pixels 文件读取 Schema

set -e

BUCKET_NAME="home-sunhao"
S3_TEST_DATA_PREFIX="test-data/workers-performance"
REGION="us-east-2"
FUNCTION_NAME="pixels-scan-worker"

FILES=(
    "ScanWorker_data.pxl"
    "PartitionWorker_data.pxl"
    "AggregationWorker_data.pxl"
    "BroadcastJoinWorker_data1.pxl"
    "BroadcastJoinWorker_data2.pxl"
    "PartitionedJoinWorker_data1.pxl"
    "PartitionedJoinWorker_data2.pxl"
)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "从 Lambda 日志提取 Schema 信息"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⚠️  注意：Schema 信息应该从文件本身读取"
echo "如果测试失败是因为列名不匹配，请提供正确的列名"
echo ""
echo "当前测试中使用的列名："
echo "  - columnsToRead: [\"col1\", \"col2\", \"col3\"]"
echo ""
echo "如果这些列名不匹配，请提供正确的列名列表"
echo ""

