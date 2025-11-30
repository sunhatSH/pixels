#!/bin/bash
# 从 Pixels 文件中提取 Schema 信息

set -e

LOCAL_DATA_DIR="/Users/sunhao/Documents/pixels/test/test_datasource"
BUCKET_NAME="home-sunhao"
S3_TEST_DATA_PREFIX="test-data/workers-performance"
REGION="us-east-2"

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
echo "从 Pixels 文件提取 Schema 信息"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

for FILE in "${FILES[@]}"; do
    LOCAL_PATH="$LOCAL_DATA_DIR/$FILE"
    
    if [ ! -f "$LOCAL_PATH" ]; then
        echo "⚠️  文件不存在，跳过: $FILE"
        continue
    fi
    
    echo "📄 文件: $FILE"
    echo "   S3 路径: s3://$BUCKET_NAME/$S3_TEST_DATA_PREFIX/$FILE"
    
    # 尝试使用 Java 读取 schema（如果有 pixels-cli 或类似工具）
    # 这里提供一个说明，用户可以使用 Java 代码读取
    echo "   ⚠️  需要 Java 工具读取 Schema"
    echo ""
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "请提供以下信息以生成正确的测试输入："
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "对于每个 .pxl 文件，请提供："
echo "1. 列名列表（column names）"
echo "2. 列类型列表（column types）"
echo "3. 列的数量"
echo ""
echo "或者您可以使用 Java 代码读取："
echo "  PixelsReader reader = ...getReader(...);"
echo "  TypeDescription schema = reader.getFileSchema();"
echo "  List<String> columnNames = schema.getFieldNames();"
echo ""

