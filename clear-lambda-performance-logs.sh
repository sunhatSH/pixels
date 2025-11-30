#!/bin/bash

# clear-lambda-performance-logs.sh
# 清除 Lambda 环境中的性能统计数据（CloudWatch Logs）
# 保留表和其他文件

set -e

# Configuration
REGION="us-east-2"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  [INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ [SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  [WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}❌ [ERROR]${NC} $1"
}

# List of Lambda function names
LAMBDA_FUNCTIONS=(
    "pixels-scanworker"
    "pixels-partitionworker"
    "pixels-aggregationworker"
    "pixels-broadcastjoinworker"
    "pixels-partitionedjoinworker"
    "pixels-sortworker"
    "pixels-broadcastchainjoinworker"
    "pixels-partitionedchainjoinworker"
    "pixels-partitionstreamworker"
)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🧹 清理 Lambda 性能统计数据"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Function to delete log group
delete_log_group() {
    local log_group_name="$1"
    
    if aws logs describe-log-groups --log-group-name-prefix "$log_group_name" --region "$REGION" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$log_group_name"; then
        log_info "删除 Log Group: $log_group_name"
        if aws logs delete-log-group --log-group-name "$log_group_name" --region "$REGION" 2>/dev/null; then
            log_success "已删除: $log_group_name"
            return 0
        else
            log_warning "删除失败（可能不存在）: $log_group_name"
            return 1
        fi
    else
        log_warning "Log Group 不存在: $log_group_name"
        return 1
    fi
}

# Delete log groups for all Lambda functions
total_deleted=0
total_skipped=0

for func_name in "${LAMBDA_FUNCTIONS[@]}"; do
    log_group_name="/aws/lambda/$func_name"
    
    if delete_log_group "$log_group_name"; then
        ((total_deleted++))
    else
        ((total_skipped++))
    fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 清理结果统计"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "已删除 $total_deleted 个 Log Groups"
if [ $total_skipped -gt 0 ]; then
    log_warning "跳过 $total_skipped 个 Log Groups（不存在或删除失败）"
fi

echo ""
log_info "注意："
echo "  • Lambda 函数本身未受影响"
echo "  • S3 中的表和其他文件未受影响"
echo "  • 下次 Lambda 调用时会自动创建新的 Log Group"
echo ""
log_success "清理完成！现在可以重新运行测试以生成新的性能数据。"

