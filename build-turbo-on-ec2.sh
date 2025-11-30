#!/bin/bash

# build-turbo-on-ec2.sh
# 在 EC2 服务器上仅编译 turbo 模块

set -e
set -o pipefail

# ========================================
# Configuration
# ========================================
REPO_USER="sunhaoSH"
REPO_NAME="pixels"
BRANCH="master"
SSH_KEY="$HOME/.ssh/pixels-key.pem"
EC2_INSTANCE_ID="i-0e01b0d7947291b0b"
EC2_REGION="us-east-1"
EC2_USER="ec2-user"
EC2_REPO_PATH="~/pixels"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

log_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📋 $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ========================================
# Get EC2 IP
# ========================================
get_ec2_ip() {
    log_step "获取 EC2 实例 IP"
    
    # Check if instance is running
    INSTANCE_STATE=$(aws ec2 describe-instances \
        --instance-ids "$EC2_INSTANCE_ID" \
        --region "$EC2_REGION" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)
    
    log_info "实例状态: $INSTANCE_STATE"
    
    if [ "$INSTANCE_STATE" != "running" ]; then
        log_error "EC2 实例未运行 (状态: $INSTANCE_STATE)"
        exit 1
    fi
    
    # Get public IP
    EC2_IP=$(aws ec2 describe-instances \
        --instance-ids "$EC2_INSTANCE_ID" \
        --region "$EC2_REGION" \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)
    
    if [ "$EC2_IP" == "None" ] || [ -z "$EC2_IP" ]; then
        log_error "无法获取 EC2 实例 IP"
        exit 1
    fi
    
    log_success "EC2 IP: $EC2_IP"
    EC2_HOST="$EC2_USER@$EC2_IP"
}

# ========================================
# Build Turbo Module on EC2
# ========================================
build_turbo_on_ec2() {
    log_step "在 EC2 上编译 Turbo 模块"
    
    ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        "$EC2_HOST" << EOF
        set -e
        
        echo "--- 检查代码仓库 ---"
        cd ~/pixels || {
            echo "❌ ERROR: 代码目录不存在"
            exit 1
        }
        
        echo "--- 拉取最新代码 ---"
        if ! git fetch origin 2>/dev/null; then
            echo "SSH 拉取失败，尝试 HTTPS..."
            HTTPS_REMOTE="https://github.com/${REPO_USER}/${REPO_NAME}.git"
            git remote set-url origin "\$HTTPS_REMOTE"
            git fetch origin || {
                echo "❌ ERROR: 无法拉取代码"
                exit 1
            }
        fi
        
        git checkout ${BRANCH} || {
            echo "❌ ERROR: 无法切换到分支 ${BRANCH}"
            exit 1
        }
        
        git pull origin ${BRANCH} || {
            echo "⚠️  WARNING: git pull 失败，但继续编译..."
        }
        
        echo "--- 编译 Turbo 模块 ---"
        echo "策略：跳过 flatbuffers 生成（因为 GLIBC++ 版本问题），直接编译依赖和 turbo 模块"
        
        # 跳过 flatbuffers 生成，因为 EC2 上 GLIBC++ 版本不兼容
        echo "编译命令: mvn package -DskipTests -Dmaven.antrun.skip=true -pl pixels-turbo/pixels-worker-lambda -am"
        
        if mvn package -DskipTests -Dmaven.antrun.skip=true -pl pixels-turbo/pixels-worker-lambda -am 2>&1 | tee /tmp/maven-build.log; then
            echo "✅ 编译成功"
            echo ""
            echo "编译输出位置:"
            find pixels-turbo/pixels-worker-lambda/target -name "*.jar" -type f 2>/dev/null | head -5
        else
            echo "⚠️  第一次编译失败，检查是否是 flatbuffers 问题..."
            
            # 如果是因为 flatbuffers 问题，尝试跳过它
            if grep -q "GLIBCXX_3.4.26" /tmp/maven-build.log 2>/dev/null || grep -q "flatc" /tmp/maven-build.log 2>/dev/null; then
                echo "检测到 flatbuffers 问题，尝试跳过 flatbuffers 生成步骤..."
                
                # 检查是否有已编译的依赖
                if [ -f "pixels-common/target/pixels-common-0.2.0-SNAPSHOT.jar" ]; then
                    echo "发现已编译的 pixels-common JAR，使用现有依赖编译..."
                    # 只编译 turbo，跳过依赖编译
                    if mvn package -DskipTests -pl pixels-turbo/pixels-worker-lambda -N -am; then
                        echo "✅ 使用现有依赖编译成功"
                    else
                        echo "❌ 编译失败，请检查依赖是否完整"
                        exit 1
                    fi
                else
                    echo "❌ 缺少 pixels-common JAR，无法编译"
                    echo "建议：在本地编译完成后上传 JAR 文件，或修复 flatbuffers 问题"
                    exit 1
                fi
            else
                echo "❌ 编译失败，错误信息:"
                tail -20 /tmp/maven-build.log
                exit 1
            fi
        fi
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Turbo 模块编译完成"
    else
        log_error "编译失败"
        exit 1
    fi
}

# ========================================
# Main
# ========================================
main() {
    log_info "开始编译 Turbo 模块..."
    
    # Check SSH key
    if [ ! -f "$SSH_KEY" ]; then
        log_error "SSH 密钥不存在: $SSH_KEY"
        exit 1
    fi
    
    chmod 600 "$SSH_KEY" 2>/dev/null || true
    
    # Get EC2 IP
    get_ec2_ip
    
    # Build on EC2
    build_turbo_on_ec2
    
    log_success "所有步骤完成！"
}

# Run main
main

