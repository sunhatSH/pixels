#!/bin/bash

# auto-deploy.sh
# Automated deployment pipeline for Pixels Lambda function
# Git Push -> EC2 Build -> Download JAR -> Deploy Lambda -> Test

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Exit if any command in a pipeline fails

# ========================================
# Configuration
# ========================================
# Default values - will be verified and adjusted in git_sync function
REPO_USER="sunhaoSH"  # Will try this first, fallback to detected username if not accessible
REPO_NAME="pixels"
BRANCH="master"
SSH_KEY="$HOME/.ssh/pixels-key.pem"
EC2_INSTANCE_ID="i-0e01b0d7947291b0b"
EC2_REGION="us-east-1"
EC2_USER="ec2-user"
EC2_REPO_PATH="~/pixels"
BUCKET_NAME="home-sunhao"
LAMBDA_REGION="us-east-2"
FUNCTION_NAME="pixels-scan-worker"
LAMBDA_ROLE_NAME="PixelsLambdaRole"
LOCAL_JAR_PATH="./pixels-worker-lambda.jar"

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
    echo -e "${BLUE}📋 Step $1: $2${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# ========================================
# Pre-flight checks
# ========================================
preflight_checks() {
    log_step "0" "Pre-flight Checks"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    # Check SSH key
    if [ ! -f "$SSH_KEY" ]; then
        log_error "SSH key not found at $SSH_KEY"
        exit 1
    fi
    
    # Check SSH key permissions
    if [ "$(stat -f %A "$SSH_KEY" 2>/dev/null || stat -c %a "$SSH_KEY" 2>/dev/null)" != "600" ]; then
        log_warning "SSH key permissions should be 600. Fixing..."
        chmod 600 "$SSH_KEY"
    fi
    
    # Check jq (optional but recommended)
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed. JSON output will not be formatted."
    fi
    
    log_success "Pre-flight checks passed"
}

# ========================================
# Step 1: Git Sync
# ========================================
git_sync() {
    log_step "1" "Git Code Sync"
    
    # Auto-detect GitHub username and verify repository access
    log_info "Detecting GitHub username..."
    SSH_OUTPUT=$(ssh -T git@github.com 2>&1 || true)
    if echo "$SSH_OUTPUT" | grep -q "successfully authenticated"; then
        GITHUB_USER=$(echo "$SSH_OUTPUT" | sed -n 's/.*Hi \([^!]*\)!.*/\1/p' || echo "")
    else
        GITHUB_USER=""
    fi
    
    # Try requested username first, fallback to detected username if not accessible
    VERIFIED_USER="$REPO_USER"
    if ! git ls-remote "git@github.com:${REPO_USER}/${REPO_NAME}.git" >/dev/null 2>&1; then
        if [ -n "$GITHUB_USER" ] && git ls-remote "git@github.com:${GITHUB_USER}/${REPO_NAME}.git" >/dev/null 2>&1; then
            log_warning "Repository git@github.com:${REPO_USER}/${REPO_NAME}.git not accessible"
            log_info "Using detected username: $GITHUB_USER"
            VERIFIED_USER="$GITHUB_USER"
            REPO_USER="$GITHUB_USER"
        else
            log_error "Cannot access repository git@github.com:${REPO_USER}/${REPO_NAME}.git"
            if [ -n "$GITHUB_USER" ]; then
                log_error "Also tried git@github.com:${GITHUB_USER}/${REPO_NAME}.git - not accessible"
            fi
            log_error "Please check if the repository exists and you have access rights"
            exit 1
        fi
    fi
    
    log_info "Using repository: git@github.com:${REPO_USER}/${REPO_NAME}.git"
    
    # Check and fix Git remote URL
    CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
    EXPECTED_REMOTE="git@github.com:${REPO_USER}/${REPO_NAME}.git"
    
    if [ "$CURRENT_REMOTE" != "$EXPECTED_REMOTE" ]; then
        log_warning "Git remote URL is not correct."
        log_info "Current: $CURRENT_REMOTE"
        log_info "Expected: $EXPECTED_REMOTE"
        log_info "Updating remote URL..."
        git remote set-url origin "$EXPECTED_REMOTE"
        log_success "Git remote URL updated"
    else
        log_success "Git remote URL is correct"
    fi
    
    # Check for uncommitted changes
    if [[ -n $(git status -s) ]]; then
        log_info "Detected uncommitted changes. Committing..."
        git add .
        COMMIT_MSG="Auto-deploy: $(date '+%Y-%m-%d %H:%M:%S')"
        git commit -m "$COMMIT_MSG" || log_warning "Nothing to commit (may be .gitignore)"
        log_success "Changes committed"
    else
        log_info "No uncommitted changes"
    fi
    
    # Push to remote
    log_info "Pushing to origin/$BRANCH..."
    git push origin "$BRANCH" || {
        log_error "Failed to push to Git. Please check your credentials and network."
        exit 1
    }
    
    log_success "Code synced to GitHub (${REPO_USER}/${REPO_NAME})"
}

# ========================================
# Step 2: EC2 Instance Discovery & Start
# ========================================
ec2_discover_and_start() {
    log_step "2" "EC2 Instance Discovery"
    
    # Get instance status
    INSTANCE_STATE=$(aws ec2 describe-instances \
        --instance-ids "$EC2_INSTANCE_ID" \
        --region "$EC2_REGION" \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)
    
    log_info "Instance state: $INSTANCE_STATE"
    
    case "$INSTANCE_STATE" in
        "running")
            log_success "Instance is already running"
            ;;
        "stopped")
            log_info "Instance is stopped. Starting..."
            aws ec2 start-instances \
                --instance-ids "$EC2_INSTANCE_ID" \
                --region "$EC2_REGION" > /dev/null
            
            log_info "Waiting for instance to start (this may take a few minutes)..."
            aws ec2 wait instance-running \
                --instance-ids "$EC2_INSTANCE_ID" \
                --region "$EC2_REGION" \
                --max-attempts 60 \
                --delay 5 || {
                log_error "Instance failed to start within timeout period"
                exit 1
            }
            log_success "Instance started"
            ;;
        "pending"|"stopping")
            log_info "Instance state is $INSTANCE_STATE. Waiting for stable state..."
            aws ec2 wait instance-running \
                --instance-ids "$EC2_INSTANCE_ID" \
                --region "$EC2_REGION" \
                --max-attempts 60 \
                --delay 5 || {
                log_error "Instance did not reach running state"
                exit 1
            }
            log_success "Instance is now running"
            ;;
        "terminated"|"shutting-down")
            log_error "Instance is in $INSTANCE_STATE state. Cannot proceed."
            exit 1
            ;;
        *)
            log_error "Unknown instance state: $INSTANCE_STATE"
            exit 1
            ;;
    esac
    
    # Wait for SSH to be ready
    log_info "Waiting for SSH service to be ready..."
    MAX_SSH_RETRIES=60
    SSH_RETRY_COUNT=0
    
    while [ $SSH_RETRY_COUNT -lt $MAX_SSH_RETRIES ]; do
        # Get public IP
        EC2_IP=$(aws ec2 describe-instances \
            --instance-ids "$EC2_INSTANCE_ID" \
            --region "$EC2_REGION" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text)
        
        if [ "$EC2_IP" != "None" ] && [ -n "$EC2_IP" ]; then
            # Test SSH connection
            if ssh -i "$SSH_KEY" \
                -o ConnectTimeout=5 \
                -o StrictHostKeyChecking=no \
                -o BatchMode=yes \
                "$EC2_USER@$EC2_IP" \
                exit 2>/dev/null; then
                log_success "SSH connection ready"
                break
            fi
        fi
        
        SSH_RETRY_COUNT=$((SSH_RETRY_COUNT + 1))
        if [ $SSH_RETRY_COUNT -lt $MAX_SSH_RETRIES ]; then
            sleep 5
            echo -n "."
        fi
    done
    
    if [ $SSH_RETRY_COUNT -eq $MAX_SSH_RETRIES ]; then
        log_error "SSH connection timeout. Please check security group and instance status."
        exit 1
    fi
    
    log_info "EC2 Instance IP: $EC2_IP"
    EC2_HOST="$EC2_USER@$EC2_IP"
    log_success "EC2 instance ready: $EC2_HOST"
}

# ========================================
# Step 3: Remote Git Pull & Build
# ========================================
remote_build() {
    log_step "3" "Remote Build on EC2"
    
    ssh -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        "$EC2_HOST" << EOF
        set -e
        
        echo "--- Checking repository directory ---"
        if [ ! -d ~/pixels ]; then
            echo "Repository not found. Cloning..."
            git clone git@github.com:${REPO_USER}/${REPO_NAME}.git ~/pixels
        fi
        
        cd ~/pixels
        
        echo "--- Verifying Git remote URL ---"
        CURRENT_REMOTE=\$(git remote get-url origin 2>/dev/null || echo "")
        EXPECTED_REMOTE="git@github.com:${REPO_USER}/${REPO_NAME}.git"
        
        if [ "\$CURRENT_REMOTE" != "\$EXPECTED_REMOTE" ]; then
            echo "Updating Git remote URL..."
            git remote set-url origin "\$EXPECTED_REMOTE"
        fi
        
        echo "--- Pulling latest code ---"
        git fetch origin
        git checkout $BRANCH
        git pull origin $BRANCH
        
        echo "--- Building project ---"
        mvn clean package -DskipTests -pl pixels-turbo/pixels-worker-lambda -am
        
        echo "--- Preparing JAR file ---"
        cd pixels-turbo/pixels-worker-lambda/target
        
        # Check if deps JAR exists and merge if needed
        if [ -f "pixels-worker-lambda-deps.jar" ] && [ -f "pixels-worker-lambda.jar" ]; then
            echo "Merging JAR files..."
            rm -rf merge_temp
            mkdir -p merge_temp
            cd merge_temp
            
            # Extract dependencies first
            jar -xf ../pixels-worker-lambda-deps.jar 2>/dev/null || true
            # Extract main JAR (overwrite if conflicts)
            jar -xf ../pixels-worker-lambda.jar 2>/dev/null || true
            
            # Repackage
            jar -cf ../pixels-worker-lambda-fat.jar .
            cd ..
            rm -rf merge_temp
            
            # Use fat JAR
            cp pixels-worker-lambda-fat.jar pixels-worker-lambda.jar
            echo "✅ Merged JAR created: pixels-worker-lambda-fat.jar"
        else
            # Find the actual JAR file (may have version suffix)
            ACTUAL_JAR=\$(ls -t pixels-worker-lambda-*.jar 2>/dev/null | head -1)
            if [ -n "\$ACTUAL_JAR" ] && [ "\$ACTUAL_JAR" != "pixels-worker-lambda.jar" ]; then
                cp "\$ACTUAL_JAR" pixels-worker-lambda.jar
                echo "✅ Copied JAR: \$ACTUAL_JAR -> pixels-worker-lambda.jar"
            fi
        fi
        
        # Verify JAR exists
        if [ ! -f pixels-worker-lambda.jar ]; then
            echo "❌ ERROR: pixels-worker-lambda.jar not found!"
            ls -la
            exit 1
        fi
        
        JAR_SIZE=\$(ls -lh pixels-worker-lambda.jar | awk '{print \$5}')
        echo "✅ JAR file ready: \$(pwd)/pixels-worker-lambda.jar (\$JAR_SIZE)"
EOF
    
    log_success "Remote build completed"
}

# ========================================
# Step 4: Download JAR
# ========================================
download_jar() {
    log_step "4" "Download JAR from EC2"
    
    log_info "Downloading JAR from $EC2_HOST..."
    scp -i "$SSH_KEY" \
        -o StrictHostKeyChecking=no \
        "$EC2_HOST:~/pixels/pixels-turbo/pixels-worker-lambda/target/pixels-worker-lambda.jar" \
        "$LOCAL_JAR_PATH" || {
        log_error "Failed to download JAR file"
        exit 1
    }
    
    # Verify download
    if [ ! -f "$LOCAL_JAR_PATH" ]; then
        log_error "JAR file not found after download"
        exit 1
    fi
    
    JAR_SIZE=$(ls -lh "$LOCAL_JAR_PATH" | awk '{print $5}')
    log_success "JAR downloaded: $LOCAL_JAR_PATH ($JAR_SIZE)"
}

# ========================================
# Step 5: Upload to S3
# ========================================
upload_to_s3() {
    log_step "5" "Upload JAR to S3"
    
    log_info "Uploading to s3://${BUCKET_NAME}/lambda/pixels-worker-lambda.jar..."
    aws s3 cp "$LOCAL_JAR_PATH" \
        "s3://${BUCKET_NAME}/lambda/pixels-worker-lambda.jar" \
        --region "$LAMBDA_REGION" || {
        log_error "Failed to upload JAR to S3"
        exit 1
    }
    
    # Verify upload
    aws s3 ls "s3://${BUCKET_NAME}/lambda/pixels-worker-lambda.jar" \
        --region "$LAMBDA_REGION" --human-readable || {
        log_error "Failed to verify S3 upload"
        exit 1
    }
    
    log_success "JAR uploaded to S3"
}

# ========================================
# Step 6: Deploy Lambda
# ========================================
deploy_lambda() {
    log_step "6" "Deploy Lambda Function"
    
    # Check if function exists
    log_info "Checking if Lambda function exists..."
    if aws lambda get-function \
        --function-name "$FUNCTION_NAME" \
        --region "$LAMBDA_REGION" \
        > /dev/null 2>&1; then
        
        log_info "Function exists. Updating code..."
        aws lambda update-function-code \
            --function-name "$FUNCTION_NAME" \
            --s3-bucket "$BUCKET_NAME" \
            --s3-key lambda/pixels-worker-lambda.jar \
            --region "$LAMBDA_REGION" \
            > /dev/null
        
        log_info "Waiting for update to complete..."
        aws lambda wait function-updated \
            --function-name "$FUNCTION_NAME" \
            --region "$LAMBDA_REGION" \
            --max-attempts 60 \
            --delay 2 || {
            log_error "Lambda update timeout"
            exit 1
        }
        
        log_success "Lambda function updated"
    else
        log_info "Function does not exist. Creating new function..."
        
        # Get IAM role ARN
        ROLE_ARN=$(aws iam get-role \
            --role-name "$LAMBDA_ROLE_NAME" \
            --query 'Role.Arn' \
            --output text 2>/dev/null) || {
            log_error "Failed to get IAM role ARN. Please check if role '$LAMBDA_ROLE_NAME' exists."
            exit 1
        }
        
        log_info "Using IAM role: $ROLE_ARN"
        
        # Create function
        aws lambda create-function \
            --function-name "$FUNCTION_NAME" \
            --runtime java21 \
            --role "$ROLE_ARN" \
            --handler io.pixelsdb.pixels.worker.lambda.ScanWorker::handleRequest \
            --code "S3Bucket=${BUCKET_NAME},S3Key=lambda/pixels-worker-lambda.jar" \
            --architectures arm64 \
            --memory-size 4096 \
            --timeout 900 \
            --description "Pixels Scan Worker with performance metrics" \
            --region "$LAMBDA_REGION" \
            > /dev/null || {
            log_error "Failed to create Lambda function"
            exit 1
        }
        
        log_info "Waiting for function to be active..."
        aws lambda wait function-active \
            --function-name "$FUNCTION_NAME" \
            --region "$LAMBDA_REGION" \
            --max-attempts 60 \
            --delay 2 || {
            log_error "Lambda creation timeout"
            exit 1
        }
        
        log_success "Lambda function created"
    fi
}

# ========================================
# Step 7: Test Lambda
# ========================================
test_lambda() {
    log_step "7" "Test Lambda Function"
    
    # Prepare test input
    TEST_INPUT_FILE="/tmp/test-scan-input.json"
    cat > "$TEST_INPUT_FILE" << EOF
{
  "transId": 12345,
  "timestamp": -1,
  "requestId": "auto-test-$(date +%s)",
  "tableInfo": {
    "tableName": "test_table",
    "base": true,
    "columnsToRead": ["col1", "col2", "col3"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${LAMBDA_REGION}.amazonaws.com"
    },
    "inputSplits": [
      {
        "inputInfos": [
          {
            "inputId": 1,
            "path": "s3://${BUCKET_NAME}/test-data/large_test_data.pxl",
            "rgStart": 0,
            "rgLength": -1,
            "storageInfo": {
              "scheme": "s3",
              "endpoint": "https://s3.${LAMBDA_REGION}.amazonaws.com"
            }
          }
        ]
      }
    ],
    "filter": null
  },
  "scanProjection": [true, true, true],
  "partialAggregationPresent": false,
  "partialAggregationInfo": null,
  "output": {
    "path": "s3://${BUCKET_NAME}/output/",
    "fileNames": ["result.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.${LAMBDA_REGION}.amazonaws.com"
    },
    "encoding": true
  },
  "inputStorageInfo": {
    "scheme": "s3",
    "endpoint": "https://s3.${LAMBDA_REGION}.amazonaws.com"
  }
}
EOF
    
    log_info "Invoking Lambda function..."
    RESPONSE_FILE="/tmp/lambda-response.json"
    
    aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload "file://$TEST_INPUT_FILE" \
        --cli-binary-format raw-in-base64-out \
        --region "$LAMBDA_REGION" \
        "$RESPONSE_FILE" || {
        log_error "Lambda invocation failed"
        exit 1
    }
    
    log_info "Lambda response:"
    if command -v jq &> /dev/null; then
        cat "$RESPONSE_FILE" | jq .
    else
        cat "$RESPONSE_FILE"
    fi
    
    # Check for errors
    if command -v jq &> /dev/null; then
        ERROR_MSG=$(cat "$RESPONSE_FILE" | jq -r '.errorMessage // empty')
        if [ -n "$ERROR_MSG" ]; then
            log_warning "Lambda returned an error: $ERROR_MSG"
        else
            log_success "Lambda invocation completed"
        fi
    fi
    
    log_info "Waiting for logs to be available..."
    sleep 5
    
    # Try to get recent logs
    LOG_GROUP="/aws/lambda/${FUNCTION_NAME}"
    log_info "Checking CloudWatch Logs..."
    
    # Get recent log events
    aws logs filter-log-events \
        --log-group-name "$LOG_GROUP" \
        --start-time $(($(date +%s) - 300))000 \
        --region "$LAMBDA_REGION" \
        --max-items 10 \
        --query 'events[-5:].message' \
        --output text 2>/dev/null || {
        log_warning "Could not retrieve CloudWatch logs (this is normal if logs are not yet available)"
    }
}

# ========================================
# Main Execution
# ========================================
main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║     Pixels Lambda Automated Deployment Pipeline            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    START_TIME=$(date +%s)
    
    preflight_checks
    git_sync
    ec2_discover_and_start
    remote_build
    download_jar
    upload_to_s3
    deploy_lambda
    test_lambda
    
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║              🎉 Deployment Completed Successfully!         ║"
    echo "║              Duration: ${DURATION} seconds                  ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

# Run main function
main

