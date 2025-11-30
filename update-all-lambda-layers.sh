#!/bin/bash
# 更新所有 Lambda Workers 的配置层版本

set -e

if [ -z "$1" ]; then
    echo "用法: $0 <layer-version-number>"
    echo "示例: $0 4"
    exit 1
fi

LAYER_VERSION=$1
REGION="us-east-2"
LAYER_ARN="arn:aws:lambda:${REGION}:970089764833:layer:pixels-config-layer:${LAYER_VERSION}"

WORKERS=(
    "pixels-scan-worker"
    "pixels-partitionworker"
    "pixels-aggregationworker"
    "pixels-broadcastjoinworker"
    "pixels-partitionedjoinworker"
    "pixels-sortedjoinworker"
    "pixels-broadcastchainjoinworker"
    "pixels-partitionedchainjoinworker"
    "pixels-sortworker"
)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "更新所有 Lambda Workers 的配置层"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Layer ARN: $LAYER_ARN"
echo ""

for worker in "${WORKERS[@]}"; do
    echo "更新: $worker"
    
    # 获取当前的 Layers
    CURRENT_LAYERS=$(aws lambda get-function-configuration \
        --function-name "$worker" \
        --region "$REGION" \
        --query 'Layers[*].Arn' \
        --output text 2>/dev/null || echo "None")
    
    if [ "$CURRENT_LAYERS" == "None" ] || [ -z "$CURRENT_LAYERS" ]; then
        # 如果没有现有层，直接添加配置层
        echo "  当前无 Layers，添加配置层..."
        if aws lambda update-function-configuration \
            --function-name "$worker" \
            --layers "$LAYER_ARN" \
            --region "$REGION" > /dev/null 2>&1; then
            echo "  ✅ 更新成功"
        else
            echo "  ❌ 更新失败"
        fi
        continue
    fi
    
    # 检查是否已有配置层，如果有则替换，如果没有则添加
    HAS_CONFIG_LAYER=false
    NEW_LAYERS=""
    
    for layer in $CURRENT_LAYERS; do
        if [[ "$layer" == *"pixels-config-layer"* ]]; then
            # 替换为新的配置层
            HAS_CONFIG_LAYER=true
            if [ -z "$NEW_LAYERS" ]; then
                NEW_LAYERS="$LAYER_ARN"
            else
                NEW_LAYERS="$NEW_LAYERS $LAYER_ARN"
            fi
        else
            # 保留其他层（如依赖层）
            if [ -z "$NEW_LAYERS" ]; then
                NEW_LAYERS="$layer"
            else
                NEW_LAYERS="$NEW_LAYERS $layer"
            fi
        fi
    done
    
    # 如果没有找到配置层，添加新的
    if [ "$HAS_CONFIG_LAYER" = false ]; then
        if [ -z "$NEW_LAYERS" ]; then
            NEW_LAYERS="$LAYER_ARN"
        else
            NEW_LAYERS="$NEW_LAYERS $LAYER_ARN"
        fi
    fi
    
    # 更新函数
    if aws lambda update-function-configuration \
        --function-name "$worker" \
        --layers $NEW_LAYERS \
        --region "$REGION" > /dev/null 2>&1; then
        echo "  ✅ 更新成功"
    else
        ERROR_MSG=$(aws lambda update-function-configuration \
            --function-name "$worker" \
            --layers $NEW_LAYERS \
            --region "$REGION" 2>&1 | grep -i error || echo "Unknown error")
        echo "  ❌ 更新失败: $ERROR_MSG"
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Lambda Workers 更新完成"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "等待 Lambda 函数更新完成（约 10 秒）..."
sleep 10
echo "✅ 可以开始测试了！"
