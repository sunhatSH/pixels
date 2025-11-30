#!/bin/zsh
# 运行所有测试的主脚本

set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$TEST_DIR"

echo "========================================="
echo "Pixels Lambda Workers 测试套件"
echo "========================================="
echo "测试目录: $TEST_DIR"
echo ""

# 步骤 1: 生成测试数据
echo "步骤 1: 生成测试数据"
echo "----------------------------------------"
if [ ! -f "test_data.pxl" ]; then
    echo "生成测试数据..."
    chmod +x generate-test-data.sh
    ./generate-test-data.sh 10000
else
    echo "✅ 测试数据已存在: test_data.pxl"
fi

# 步骤 2: 上传测试数据到 S3
echo ""
echo "步骤 2: 上传测试数据到 S3"
echo "----------------------------------------"
BUCKET_NAME="home-sunhao"
REGION="us-east-2"

if [ -f "test_data.pxl" ]; then
    echo "上传 test_data.pxl 到 S3..."
    aws s3 cp test_data.pxl \
        s3://$BUCKET_NAME/test-data/test_data.pxl \
        --region $REGION
    echo "✅ 测试数据已上传"
else
    echo "❌ 测试数据文件不存在"
    exit 1
fi

# 步骤 3: 更新测试 JSON 文件中的路径
echo ""
echo "步骤 3: 更新测试输入文件"
echo "----------------------------------------"

# 更新 BroadcastJoin 测试文件
if [ -f "test-broadcast-join-self.json" ]; then
    # 使用 sed 或 jq 更新路径
    if command -v jq &> /dev/null; then
        jq '.smallTable.inputSplits[0].inputInfos[0].path = "s3://home-sunhao/test-data/test_data.pxl" | .largeTable.inputSplits[0].inputInfos[0].path = "s3://home-sunhao/test-data/test_data.pxl"' \
            test-broadcast-join-self.json > test-broadcast-join-self.json.tmp
        mv test-broadcast-join-self.json.tmp test-broadcast-join-self.json
    fi
    echo "✅ BroadcastJoin 测试文件已更新"
fi

# 更新 PartitionedJoin 测试文件
if [ -f "test-partitioned-join-self.json" ]; then
    if command -v jq &> /dev/null; then
        jq '.smallTable.inputFiles[0] = "s3://home-sunhao/test-data/test_data.pxl" | .largeTable.inputFiles[0] = "s3://home-sunhao/test-data/test_data.pxl"' \
            test-partitioned-join-self.json > test-partitioned-join-self.json.tmp
        mv test-partitioned-join-self.json.tmp test-partitioned-join-self.json
    fi
    echo "✅ PartitionedJoin 测试文件已更新"
fi

# 步骤 4: 运行 Join Workers 测试
echo ""
echo "步骤 4: 运行 Join Workers 测试"
echo "----------------------------------------"
if [ -f "test-join-workers.sh" ]; then
    chmod +x test-join-workers.sh
    ./test-join-workers.sh
else
    echo "⚠️  测试脚本不存在，跳过"
fi

# 步骤 5: 提取性能数据
echo ""
echo "步骤 5: 提取性能数据"
echo "----------------------------------------"
if [ -f "../extract-performance-data.sh" ]; then
    chmod +x ../extract-performance-data.sh
    cd ..
    ./extract-performance-data.sh
    cd "$TEST_DIR"
else
    echo "⚠️  性能数据提取脚本不存在，跳过"
fi

echo ""
echo "========================================="
echo "✅ 所有测试完成！"
echo "========================================="

