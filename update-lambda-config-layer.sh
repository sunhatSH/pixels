#!/bin/bash
# 更新 Lambda 配置层

set -e
set -o pipefail

LAYER_NAME="pixels-config-layer"
REGION="us-east-2"
CONFIG_DIR="lambda-layer/pixels"
ZIP_FILE="lambda-layer/pixels-config-layer.zip"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ️  [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ [SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}❌ [ERROR]${NC} $1"
}

log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "更新 Lambda 配置层"
log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查配置文件是否存在
if [ ! -f "$CONFIG_DIR/etc/pixels.properties" ]; then
    log_error "配置文件不存在: $CONFIG_DIR/etc/pixels.properties"
    exit 1
fi

# 验证必需的配置项
log_info "验证必需的配置项..."
REQUIRED_CONFIGS=(
    "row.batch.size"
    "pixel.stride"
    "row.group.size"
    "executor.worker.exchange.port"
    "worker.coordinate.server.port"
    "worker.coordinate.server.host"
)

MISSING_CONFIGS=()
for config in "${REQUIRED_CONFIGS[@]}"; do
    if ! grep -q "^$config=" "$CONFIG_DIR/etc/pixels.properties" 2>/dev/null; then
        MISSING_CONFIGS+=("$config")
    fi
done

if [ ${#MISSING_CONFIGS[@]} -gt 0 ]; then
    log_error "缺少必需的配置项:"
    for config in "${MISSING_CONFIGS[@]}"; do
        echo "  - $config"
    done
    exit 1
fi

log_success "所有必需的配置项都已存在"

# 创建 ZIP 文件
log_info "创建配置层 ZIP 文件..."
cd "$CONFIG_DIR" || exit 1
zip -r "../$(basename "$ZIP_FILE")" pixels/ 2>/dev/null || {
    # 如果 zip 命令失败，尝试使用其他方法
    cd ../..
    rm -f "$ZIP_FILE"
    cd "$CONFIG_DIR" || exit 1
    zip -r "../$(basename "$ZIP_FILE")" . 2>/dev/null
}
cd ../..

if [ ! -f "$ZIP_FILE" ]; then
    log_error "创建 ZIP 文件失败"
    exit 1
fi

ZIP_SIZE=$(ls -lh "$ZIP_FILE" | awk '{print $5}')
log_success "ZIP 文件已创建: $ZIP_FILE ($ZIP_SIZE)"

# 发布新的 Layer 版本
log_info "发布新的 Layer 版本到 AWS..."
DESCRIPTION="Pixels configuration with all required properties for Lambda workers"

LAYER_VERSION_ARN=$(aws lambda publish-layer-version \
    --layer-name "$LAYER_NAME" \
    --description "$DESCRIPTION" \
    --zip-file "fileb://$ZIP_FILE" \
    --region "$REGION" \
    --query 'LayerVersionArn' \
    --output text 2>&1)

if [ $? -eq 0 ] && [ -n "$LAYER_VERSION_ARN" ]; then
    log_success "Layer 版本已发布: $LAYER_VERSION_ARN"
    
    # 提取版本号
    VERSION=$(echo "$LAYER_VERSION_ARN" | grep -oP ':\d+$' | grep -oP '\d+')
    log_info "版本号: $VERSION"
    
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "下一步：更新 Lambda 函数以使用新的 Layer 版本"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "运行以下命令更新所有 Lambda 函数："
    echo ""
    echo "aws lambda update-function-configuration \\"
    echo "  --function-name <function-name> \\"
    echo "  --layers $LAYER_VERSION_ARN \\"
    echo "  --region $REGION"
    echo ""
    echo "或者使用以下脚本更新所有 Workers："
    echo ""
    echo "./update-all-lambda-layers.sh $VERSION"
    echo ""
else
    log_error "发布 Layer 失败"
    echo "$LAYER_VERSION_ARN"
    exit 1
fi

