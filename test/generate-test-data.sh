#!/bin/bash
# 生成测试 CSV 数据并转换为 PXL

set -e

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NUM_ROWS=${1:-10000}  # 默认生成 10000 行
OUTPUT_CSV="$TEST_DIR/test_data.csv"
OUTPUT_PXL="$TEST_DIR/test_data.pxl"
SCHEMA="struct<col1:int,col2:string,col3:double>"

echo "========================================="
echo "生成测试数据"
echo "========================================="
echo "行数: $NUM_ROWS"
echo "输出 CSV: $OUTPUT_CSV"
echo "输出 PXL: $OUTPUT_PXL"
echo ""

# 生成 CSV 数据
echo "生成 CSV 数据..."
cat > "$OUTPUT_CSV" << EOF
col1,col2,col3
EOF

for i in $(seq 1 $NUM_ROWS); do
    # 生成测试数据：col1 是递增整数，col2 是字符串，col3 是浮点数
    echo "$i,value_$i,$(echo "scale=2; $i * 1.5" | bc)" >> "$OUTPUT_CSV"
done

echo "✅ CSV 数据已生成: $OUTPUT_CSV ($(wc -l < "$OUTPUT_CSV") 行)"

# 转换为 PXL
echo ""
echo "转换为 PXL 格式..."

# 检查是否在项目根目录
if [ -f "pom.xml" ]; then
    PIXELS_HOME="$(pwd)"
else
    PIXELS_HOME="$(cd "$TEST_DIR/../.." && pwd)"
fi

# 编译转换器（如果需要）
if [ ! -f "$PIXELS_HOME/pixels-example/target/classes/io/pixelsdb/pixels/test/CsvToPxlConverter.class" ]; then
    echo "编译项目..."
    cd "$PIXELS_HOME"
    mvn clean compile -DskipTests -pl pixels-example -am -q
    if [ $? -ne 0 ]; then
        echo "❌ 编译失败"
        exit 1
    fi
fi

# 运行转换器
echo "运行 CSV 到 PXL 转换器..."
cd "$TEST_DIR"

# 使用 Java 运行转换器
java -cp "$PIXELS_HOME/pixels-example/target/classes:$PIXELS_HOME/pixels-core/target/classes:$PIXELS_HOME/pixels-common/target/classes:$(find "$PIXELS_HOME" -name "*.jar" -type f | tr '\n' ':')" \
    io.pixelsdb.pixels.test.CsvToPxlConverter \
    "$OUTPUT_CSV" \
    "$OUTPUT_PXL" \
    "$SCHEMA" \
    ","

if [ -f "$OUTPUT_PXL" ]; then
    echo "✅ PXL 文件已生成: $OUTPUT_PXL ($(du -h "$OUTPUT_PXL" | cut -f1))"
else
    echo "❌ PXL 文件生成失败"
    exit 1
fi

echo ""
echo "========================================="
echo "✅ 测试数据生成完成！"
echo "========================================="

