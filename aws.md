# AWS Pixels 部署指南

## 概述

Pixels系统采用AWS Lambda + S3的云原生架构，实现高弹性、高可用的数据查询处理能力。

## AWS服务架构

### 核心服务
- **Lambda**: 无服务器计算，执行Pixels查询逻辑
- **S3**: 对象存储，存放数据文件和查询结果
- **EC2**: 开发/部署环境，编译和测试
- **CloudWatch**: 监控、日志和告警

### 网络架构
- **VPC**: 私有网络环境
- **Security Group**: 安全组控制访问
- **Internet Gateway**: 公网访问

## EC2实例管理

### 当前实例规格

| 实例ID | 类型 | CPU | 内存 | 存储 | 公网IP | Region | 可用区 | 状态 |
|--------|------|-----|------|------|--------|--------|--------|------|
| i-0e01b0d7947291b0b | r5.4xlarge | 16核 | 128GB | 200GB gp3 | 3.87.201.11 | us-east-1 | us-east-1a | running |

### 查看实例地区（Region）

有多种方法可以查看实例所在的地区：

**方法1: 通过可用区判断（最简单）**
```bash
# 查看实例的可用区（Availability Zone）
aws ec2 describe-instances --instance-ids i-0e01b0d7947291b0b \
  --query 'Reservations[*].Instances[*].Placement.AvailabilityZone' \
  --output text

# 输出示例: us-east-1a
# 可用区格式: region-字母，例如 us-east-1a 表示 us-east-1 地区
```

**方法2: 查看AWS CLI配置的默认region**
```bash
# 查看当前配置的默认region
aws configure get region

# 输出示例: us-east-1
```

**方法3: 查看实例完整信息**
```bash
# 查看实例的详细信息，包括可用区和region
aws ec2 describe-instances --instance-ids i-0e01b0d7947291b0b \
  --query 'Reservations[*].Instances[*].[InstanceId,Placement.AvailabilityZone,PublicIpAddress,InstanceType]' \
  --output table

# 输出示例:
# +----------------------+-------------+--------------+--------------+
# |  i-0e01b0d7947291b0b |  us-east-1a |  3.87.201.11 |  r5.4xlarge  |
# +----------------------+-------------+--------------+--------------+
# 可用区 us-east-1a 表示 region 是 us-east-1
```

**方法4: 查看所有实例及其region**
```bash
# 列出所有实例及其可用区
aws ec2 describe-instances \
  --query 'Reservations[*].Instances[*].[InstanceId,Placement.AvailabilityZone,State.Name]' \
  --output table
```

**常见AWS Region代码**:
- `us-east-1`: 美国东部（弗吉尼亚北部）- N. Virginia
- `us-west-2`: 美国西部（俄勒冈）- Oregon
- `ap-southeast-1`: 亚太地区（新加坡）- Singapore
- `eu-west-1`: 欧洲（爱尔兰）- Ireland
- `cn-north-1`: 中国（北京）- Beijing

### 连接信息

```bash
# SSH连接
ssh -i ~/.ssh/pixels-key.pem ec2-user@13.221.233.250

# 或使用配置
Host pixels-large
    HostName 13.221.233.250
    User ec2-user
    IdentityFile ~/.ssh/pixels-key.pem
```

### 实例操作

#### 停止实例（暂停/关机，不销毁）

**用途**: 暂停实例但保留数据和配置，类似电脑关机

```bash
# 停止实例（暂停但不销毁）
aws ec2 stop-instances --instance-ids i-0e01b0d7947291b0b

# 查看停止状态
aws ec2 describe-instances --instance-ids i-0e01b0d7947291b0b --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' --output table
```

**停止实例的特点**:
- ✅ **数据保留**: EBS卷上的数据完全保留
- ✅ **可恢复**: 随时可以重新启动
- ✅ **节省成本**: 停止后不收取计算费用，只收取EBS存储费用
- ⚠️ **IP变化**: 公网IP会释放（除非使用弹性IP）
- ⚠️ **状态保持**: 实例ID不变，但需要重新启动

**适用场景**:
- 暂时不需要使用实例时
- 需要保留数据和配置
- 节省计算成本

#### 启动实例（从停止状态恢复）

```bash
# 启动已停止的实例
aws ec2 start-instances --instance-ids i-0e01b0d7947291b0b

# 等待实例启动（约30-60秒）
sleep 30

# 获取新的公网IP
aws ec2 describe-instances --instance-ids i-0e01b0d7947291b0b --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress]' --output table
```

**启动后的变化**:
- 公网IP可能变化（除非使用弹性IP）
- 所有数据和配置保持不变
- 需要重新连接SSH

#### 终止实例（永久销毁）

**⚠️ 警告**: 终止操作不可逆，数据可能丢失！

```bash
# 终止实例（永久销毁）
aws ec2 terminate-instances --instance-ids i-0e01b0d7947291b0b
```

**终止实例的特点**:
- ❌ **数据丢失**: 如果EBS卷设置为DeleteOnTermination，数据会被删除
- ❌ **不可恢复**: 无法恢复已终止的实例
- ❌ **完全销毁**: 实例ID失效，无法再使用
- ✅ **完全免费**: 不收取任何费用

**适用场景**:
- 确定不再需要该实例
- 测试环境清理
- 成本优化（长期不使用）

#### 其他常用操作

```bash
# 查看实例状态
aws ec2 describe-instances --instance-ids i-0e01b0d7947291b0b --query 'Reservations[*].Instances[*].[InstanceId,State.Name,PublicIpAddress,InstanceType]' --output table

# 查看所有停止的实例
aws ec2 describe-instances --filters "Name=instance-state-name,Values=stopped" --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' --output table

# 重启实例（不停止，直接重启）
aws ec2 reboot-instances --instance-ids i-0e01b0d7947291b0b
```

#### 停止 vs 终止对比

| 操作 | 停止 (Stop) | 终止 (Terminate) |
|------|------------|-----------------|
| **数据保留** | ✅ 保留 | ❌ 可能丢失 |
| **可恢复** | ✅ 可启动 | ❌ 不可恢复 |
| **计算费用** | ❌ 不收费 | ❌ 不收费 |
| **存储费用** | ✅ 收取EBS费用 | ❌ 不收费（如果删除卷） |
| **实例ID** | ✅ 保持不变 | ❌ 失效 |
| **公网IP** | ⚠️ 可能变化 | ❌ 释放 |
| **适用场景** | 暂时不用 | 永久删除 |

# 编译项目
cd pixels
mvn clean package -DskipTests
```

### 3. 运行测试程序

```bash
# 运行性能分析程序
mvn exec:java -Dexec.mainClass="io.pixelsdb.pixels.example.core.PerformanceProfiler"
```

## Lambda函数部署

### 构建部署包

```bash
# 编译Lambda模块
mvn clean package -DskipTests -pl pixels-turbo/pixels-worker-lambda

# 生成的JAR文件
pixels/pixels-turbo/pixels-worker-lambda/target/pixels-worker-lambda-*.jar
```

### 创建Lambda函数

```bash
# 创建ScanWorker
aws lambda create-function \
  --function-name PixelsScanWorker \
  --runtime java11 \
  --role arn:aws:iam::ACCOUNT_ID:role/lambda-execution-role \
  --handler io.pixelsdb.pixels.worker.lambda.ScanWorker::handleRequest \
  --memory-size 4096 \
  --timeout 900 \
  --zip-file fileb://pixels-worker-lambda.jar

# 创建其他Worker（PartitionWorker, AggregationWorker, JoinWorker等）
```

### 配置环境变量

```bash
# 设置存储和区域配置
aws lambda update-function-configuration \
  --function-name PixelsScanWorker \
  --environment '{
    "PIXELS_STORAGE_SCHEME": "s3",
    "AWS_REGION": "us-east-1",
    "S3_BUCKET": "pixels-data-bucket"
  }'
```

## Lambda函数调用

### AWS CLI调用

```bash
# Scan Worker示例
aws lambda invoke \
  --function-name PixelsScanWorker \
  --payload '{
    "transId": 12345,
    "timestamp": 1703123456789,
    "scanInput": {
      "tableInfo": {
        "tableName": "test_table",
        "columnsToRead": ["col1", "col2"],
        "inputFiles": ["s3://bucket/path/to/file1.pxl"]
      },
      "output": {
        "path": "s3://bucket/output/",
        "storage": {"scheme": "s3"}
      }
    }
  }' \
  response.json
```

### Java SDK调用

```java
// 在PerformanceProfiler中使用
ScanWorkerRequest request = new ScanWorkerRequest();
request.setTransId(transId);
request.setTimestamp(timestamp);
// 设置查询参数...

AWSLambda lambda = AWSLambdaClientBuilder.defaultClient();
InvokeRequest invokeRequest = new InvokeRequest()
    .withFunctionName("PixelsScanWorker")
    .withPayload(objectMapper.writeValueAsString(request));

InvokeResult result = lambda.invoke(invokeRequest);
```

## 监控和日志

### CloudWatch日志

```bash
# 查看Lambda日志
aws logs tail /aws/lambda/PixelsScanWorker --follow

# 搜索特定日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/PixelsScanWorker \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "Performance Metrics"
```

### 性能指标文件

Lambda函数会生成性能指标文件，通常输出到：
- 本地测试：`/tmp/*.csv`
- Lambda环境：CloudWatch Logs

## 成本分析

### Lambda成本
- **按需付费**: 只在函数执行时收费
- **计费单位**: GB-秒 ($0.0000166667/GB-秒)
- **免费额度**: 每月400,000 GB-秒

### 存储成本
- **S3存储**: $0.023/GB/月
- **S3请求**: $0.0004/1000次GET请求
- **数据传输**: $0.09/GB出站流量

### EC2成本
- **r5.4xlarge**: $1.152/小时 (≈$828/月)
- **建议**: 使用时启动，不用时停止

### 成本优化建议

1. **Lambda优化**:
   - 合理设置内存大小
   - 优化代码执行时间
   - 使用预置并发减少冷启动

2. **存储优化**:
   - 及时清理临时文件
   - 使用S3生命周期策略
   - 选择合适的存储层级

3. **EC2优化**:
   - 按需使用，及时停止
   - 考虑竞价实例

## 完整部署和测试教程（从零开始）

### 前置准备

> **重要概念理解**:
> 
> **"创建" vs "执行"的区别**:
> - **创建Lambda函数** (`aws lambda create-function`): 这是AWS**管理操作**，在本地通过AWS CLI执行，作用是告诉AWS"我要创建一个函数，代码在S3的xxx位置"。函数本身创建在AWS云端。
> - **执行Lambda函数** (`aws lambda invoke`): 这是**触发执行**，在本地通过AWS CLI调用，但函数代码实际在**AWS云端运行**。
> 
> **类比**: 
> - 就像你用`git push`把代码推送到GitHub，代码最终在GitHub服务器上，但你可以在本地执行push命令
> - Lambda函数创建后，代码和运行都在AWS云端，你只是用本地命令来**管理**它（创建、更新、调用）
> 
> **执行位置说明**: 以下所有AWS CLI命令（创建S3、IAM角色、Lambda函数等）都可以在**本地机器**或**EC2实例**上执行，只要安装了AWS CLI并配置了凭据即可。**推荐在本地执行**，因为通常本地已经配置好了AWS CLI。

#### 1. 创建S3存储桶

**执行位置**: 本地机器（推荐）或EC2实例

**方案A: 创建新bucket（需要权限）**

```bash
# 在本地机器上执行（推荐）
# 确保已安装并配置AWS CLI: aws configure

# 创建S3 bucket用于存储Lambda代码和测试数据
BUCKET_NAME="pixels-lambda-deploy-$(date +%s)"
aws s3 mb s3://$BUCKET_NAME

# 如果遇到权限错误，见下面的"权限问题解决
```

**方案B: 使用已有bucket（推荐，如果没有创建权限）**

```bash
# 查看所有可用的bucket
aws s3 ls

# 输出格式：创建时间  bucket名称
# 例如：
# 2025-09-13 15:52:09 home-sunhao
# 2025-08-26 11:51:43 home-haoyue

# 查看某个bucket的内容（检查是否有权限）
aws s3 ls s3://home-sunhao/

# 选择一个已有的bucket（推荐使用你自己的bucket）
BUCKET_NAME="home-sunhao"  # 使用你自己的bucket，或替换为其他可用的bucket名称

# 创建目录结构（如果bucket已存在，只需要创建目录）
aws s3api put-object --bucket $BUCKET_NAME --key lambda/ || echo "目录可能已存在"
aws s3api put-object --bucket $BUCKET_NAME --key test-data/ || echo "目录可能已存在"
aws s3api put-object --bucket $BUCKET_NAME --key output/ || echo "目录可能已存在"

# 保存bucket名称（后续步骤会用到）
echo "S3 Bucket: $BUCKET_NAME" > bucket-name.txt
echo $BUCKET_NAME

# 验证bucket可访问
aws s3 ls s3://$BUCKET_NAME/
```

**权限问题解决**:

> **重要理解**: 
> - 在本地执行 `aws s3 mb` 命令，实际上是在**调用AWS API**
> - AWS API需要你的IAM用户有相应的权限
> - 这不是"本地"vs"云端"的问题，而是**AWS权限管理**的问题
> - 即使你在本地执行，AWS也会检查你的IAM用户是否有权限执行这个操作
> 
> **类比**: 
> - 就像你用手机APP转账，虽然操作在手机上，但银行会检查你的账户权限
> - AWS CLI = 你的命令工具，但执行的是AWS API调用，需要AWS权限

如果遇到 `AccessDenied` 错误（没有创建bucket权限），有以下解决方案：

1. **使用已有bucket**（最简单，推荐）:
   ```bash
   # 查看可用bucket
   aws s3 ls
   
   # 使用已有的bucket（你已经有访问权限）
   BUCKET_NAME="your-existing-bucket-name"
   ```

2. **请求AWS账户管理员添加权限**:
   ```bash
   # 需要AWS账户管理员（或IAM管理员）执行以下命令
   # 这不是"本地权限"，而是AWS账户的IAM权限
   # aws iam attach-user-policy \
   #   --user-name sunhao \
   #   --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
   ```
   
   **为什么需要管理员**:
   - 你的IAM用户 `sunhao` 目前只有修改密码的权限
   - 创建S3 bucket需要额外的IAM权限
   - 只有IAM管理员可以给用户添加权限
   - 这是AWS的安全机制，防止用户随意创建资源

3. **使用AWS控制台创建**（如果控制台有权限）:
   - 登录AWS控制台 (https://console.aws.amazon.com)
   - 进入S3服务
   - 点击"创建bucket"
   - 创建后使用该bucket名称

**注意事项**:
- S3 bucket名称必须全局唯一（不能与其他AWS账户重复）
- 如果名称冲突，会报错，可以手动指定一个唯一名称
- 建议使用带时间戳的名称确保唯一性
- 如果没有创建权限，使用已有bucket是最快的解决方案

#### 2. 创建IAM角色和策略

```bash
# 创建Lambda执行角色
ROLE_NAME="pixels-lambda-execution-role"

# 创建信任策略文档
cat > trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# 创建角色
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://trust-policy.json

# 创建策略文档（S3访问权限）
cat > lambda-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::$BUCKET_NAME/*",
        "arn:aws:s3:::$BUCKET_NAME"
      ]
    }
  ]
}
EOF

# 创建策略
POLICY_NAME="pixels-lambda-policy"
aws iam create-policy \
  --policy-name $POLICY_NAME \
  --policy-document file://lambda-policy.json

# 获取账户ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 附加策略到角色
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME

# 获取角色ARN
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text)
echo "Role ARN: $ROLE_ARN"
```

### 步骤1: 编译和打包

#### 在EC2实例上操作

```bash
# 1. 连接到EC2实例
ssh -i ~/.ssh/pixels-key.pem ec2-user@3.87.201.11

# 2. 进入Pixels项目目录
cd ~/pixels

# 3. 编译pixels-turbo模块（包含所有Worker）
mvn clean package -DskipTests -pl 'pixels-turbo' -am

# 4. 检查生成的JAR文件
ls -lh pixels-turbo/pixels-worker-lambda/target/*.jar
```

**打包说明**:
- **主JAR**: `pixels-worker-lambda-0.2.0-SNAPSHOT.jar` (包含所有依赖)
- **位置**: `pixels-turbo/pixels-worker-lambda/target/`
- **大小**: 通常100-200MB（包含所有依赖）

### 步骤2: 上传到S3

```bash
# 在EC2实例上执行
BUCKET_NAME="your-bucket-name"  # 替换为你的bucket名称
JAR_FILE="pixels-turbo/pixels-worker-lambda/target/pixels-worker-lambda-0.2.0-SNAPSHOT.jar"

# 上传JAR文件
aws s3 cp $JAR_FILE s3://$BUCKET_NAME/lambda/pixels-worker-lambda.jar

# 验证上传
aws s3 ls s3://$BUCKET_NAME/lambda/
```

### 步骤3: 创建Lambda函数

> **重要说明**: 
> - **创建Lambda函数** = AWS管理操作（类似在AWS控制台点击"创建函数"按钮），可以在**本地**通过AWS CLI执行
> - **执行Lambda函数** = 实际运行代码，在**AWS云端**执行
> - 创建Lambda函数只是告诉AWS"我要创建一个函数，代码在S3的某个位置"，函数本身还是在AWS云端运行的

**执行位置**: 本地机器（推荐）或EC2实例

```bash
# 在本地机器上执行（推荐）
# 这是AWS管理操作，就像在AWS控制台创建资源一样

FUNCTION_NAME="pixels-scan-worker"
BUCKET_NAME="your-bucket-name"  # 替换为你的bucket名称
ROLE_ARN="arn:aws:iam::ACCOUNT_ID:role/pixels-lambda-execution-role"  # 替换为你的角色ARN

# 创建Lambda函数（这只是注册/创建函数配置，函数代码在AWS云端）
aws lambda create-function \
  --function-name $FUNCTION_NAME \
  --runtime java21 \
  --role $ROLE_ARN \
  --handler io.pixelsdb.pixels.worker.lambda.ScanWorker::handleRequest \
  --code S3Bucket=$BUCKET_NAME,S3Key=lambda/pixels-worker-lambda.jar \
  --architectures arm64 \
  --memory-size 4096 \
  --timeout 900 \
  --description "Pixels Scan Worker with performance metrics" \
  --environment Variables={PIXELS_CONFIG=/tmp/pixels.properties}

# 等待函数创建完成
aws lambda wait function-active --function-name $FUNCTION_NAME

# 查看函数信息（确认创建成功）
aws lambda get-function --function-name $FUNCTION_NAME
```

**类比理解**:
- 创建Lambda函数 = 在AWS云端"注册"一个函数，告诉AWS"代码在这里，运行时配置是这样"
- 就像你在GitHub上创建一个仓库，仓库本身在GitHub服务器上，但你可以在本地用`git`命令创建它
- Lambda函数创建后，代码和运行都在AWS云端，你只是用本地命令来管理它

**Lambda配置说明**:
- **Runtime**: `java21` (Java 21)
- **Architecture**: `arm64` (ARM架构，成本更低) 或 `x86_64`
- **Memory**: `4096 MB` (可根据需要调整)
- **Timeout**: `900秒` (15分钟，最大15分钟)
- **Handler**: Worker类的`handleRequest`方法

### 步骤4: 准备测试数据

```bash
# 上传测试数据到S3（如果有）
aws s3 cp test-data/input.pxl s3://$BUCKET_NAME/test-data/input.pxl

# 或者使用已有的Pixels文件
aws s3 ls s3://your-existing-bucket/pixels-data/
```

### 步骤5: 测试Invoke

#### 5.1 准备测试Payload

```bash
# 创建测试输入文件
cat > test-scan-input.json << 'EOF'
{
  "transId": 12345,
  "timestamp": 1640995200000,
  "requestId": "test-request-001",
  "inputInfos": [
    {
      "inputId": 1,
      "path": "s3://your-bucket/test-data/input.pxl",
      "storageInfo": {
        "scheme": "s3",
        "endpoint": "https://s3.us-east-1.amazonaws.com"
      },
      "columnsToRead": ["col1", "col2", "col3"],
      "keyColumnIds": [0]
    }
  ],
  "output": {
    "path": "s3://your-bucket/output/result.pxl",
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.us-east-1.amazonaws.com"
    }
  },
  "scanProjection": ["col1", "col2", "col3"]
}
EOF
```

#### 5.2 执行Invoke

```bash
FUNCTION_NAME="pixels-scan-worker"

# 同步调用（等待结果）
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --payload file://test-scan-input.json \
  --cli-binary-format raw-in-base64-out \
  response.json

# 查看响应
cat response.json | jq .

# 检查是否有错误
cat response.json | jq -r '.errorMessage // "No error"'
```

#### 5.3 异步调用（长时间任务）

```bash
# 异步调用（不等待结果）
aws lambda invoke \
  --function-name $FUNCTION_NAME \
  --invocation-type Event \
  --payload file://test-scan-input.json \
  --cli-binary-format raw-in-base64-out \
  async-response.json
```

### 步骤6: 查看日志和性能数据

#### 6.1 实时查看日志

```bash
# 实时跟踪日志
aws logs tail /aws/lambda/$FUNCTION_NAME --follow

# 查看最近的日志
aws logs tail /aws/lambda/$FUNCTION_NAME --since 10m

# 查看特定时间段的日志
aws logs tail /aws/lambda/$FUNCTION_NAME \
  --since "2025-11-23T10:00:00" \
  --until "2025-11-23T11:00:00"
```

#### 6.2 提取性能数据

```bash
# 搜索性能指标日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/$FUNCTION_NAME \
  --filter-pattern "Performance Data" \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --output text

# 提取CSV格式的性能数据
aws logs filter-log-events \
  --log-group-name /aws/lambda/$FUNCTION_NAME \
  --filter-pattern "Performance Data" \
  --query 'events[*].message' \
  --output text | grep "CSV" > performance_data.csv
```

#### 6.3 查看Lambda指标

```bash
# 查看函数执行情况
aws lambda get-function --function-name $FUNCTION_NAME

# 查看函数配置
aws lambda get-function-configuration --function-name $FUNCTION_NAME
```

### 步骤7: 测试其他Worker类型

#### 7.1 Partition Worker

```bash
# 创建Partition Worker函数
aws lambda create-function \
  --function-name pixels-partition-worker \
  --runtime java21 \
  --role $ROLE_ARN \
  --handler io.pixelsdb.pixels.worker.lambda.PartitionWorker::handleRequest \
  --code S3Bucket=$BUCKET_NAME,S3Key=lambda/pixels-worker-lambda.jar \
  --architectures arm64 \
  --memory-size 4096 \
  --timeout 900
```

#### 7.2 Aggregation Worker

```bash
aws lambda create-function \
  --function-name pixels-aggregation-worker \
  --runtime java21 \
  --role $ROLE_ARN \
  --handler io.pixelsdb.pixels.worker.lambda.AggregationWorker::handleRequest \
  --code S3Bucket=$BUCKET_NAME,S3Key=lambda/pixels-worker-lambda.jar \
  --architectures arm64 \
  --memory-size 4096 \
  --timeout 900
```

### 步骤8: 批量测试脚本

```bash
#!/bin/bash
# test-all-workers.sh

FUNCTIONS=(
  "pixels-scan-worker"
  "pixels-partition-worker"
  "pixels-aggregation-worker"
)

INPUT_FILES=(
  "test-scan-input.json"
  "test-partition-input.json"
  "test-aggregation-input.json"
)

for i in "${!FUNCTIONS[@]}"; do
  FUNCTION_NAME="${FUNCTIONS[$i]}"
  INPUT_FILE="${INPUT_FILES[$i]}"
  
  echo "Testing $FUNCTION_NAME..."
  
  aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload file://$INPUT_FILE \
    --cli-binary-format raw-in-base64-out \
    "response-${FUNCTION_NAME}.json"
  
  # 检查结果
  if [ $? -eq 0 ]; then
    echo "✅ $FUNCTION_NAME completed successfully"
    cat "response-${FUNCTION_NAME}.json" | jq .
  else
    echo "❌ $FUNCTION_NAME failed"
  fi
  
  sleep 2
done

echo "All tests completed!"
```

### 故障排除

#### 常见问题

1. **权限错误**:
```bash
# 检查IAM角色权限
aws iam get-role-policy --role-name pixels-lambda-execution-role --policy-name pixels-lambda-policy

# 添加S3权限
aws iam attach-role-policy --role-name pixels-lambda-execution-role --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
```

2. **超时错误**:
```bash
# 增加超时时间
aws lambda update-function-configuration \
  --function-name pixels-scan-worker \
  --timeout 900
```

3. **内存不足**:
```bash
# 增加内存
aws lambda update-function-configuration \
  --function-name pixels-scan-worker \
  --memory-size 8192
```

4. **查看详细错误**:
```bash
# 查看最近的错误日志
aws logs filter-log-events \
  --log-group-name /aws/lambda/pixels-scan-worker \
  --filter-pattern "ERROR" \
  --start-time $(date -d '1 hour ago' +%s)000
```

### 更新函数代码

```bash
# 重新编译和上传
cd pixels
mvn clean package -DskipTests -pl 'pixels-turbo'
aws s3 cp pixels-turbo/pixels-worker-lambda/target/pixels-worker-lambda-0.2.0-SNAPSHOT.jar \
  s3://$BUCKET_NAME/lambda/pixels-worker-lambda.jar

# 更新Lambda函数代码
aws lambda update-function-code \
  --function-name pixels-scan-worker \
  --s3-bucket $BUCKET_NAME \
  --s3-key lambda/pixels-worker-lambda.jar

# 等待更新完成
aws lambda wait function-updated --function-name pixels-scan-worker
```

## 测试和Invoke指南

### 本地测试

1. **验证计时器逻辑**:
```bash
# 在本地编译并运行性能测试
cd pixels
mvn clean compile -q -pl 'pixels-turbo/pixels-worker-common,pixels-example'
mvn exec:java -q -pl pixels-example -Dexec.mainClass='io.pixelsdb.pixels.example.core.PerformanceProfiler'
```

2. **预期结果**:
   - 显示四个阶段耗时占比
   - 验证编码压缩 > S3存储的假设
   - CSV格式性能数据输出

### Lambda函数部署

1. **打包应用**:
```bash
# 在EC2上打包
cd pixels
mvn clean package -q -DskipTests -pl 'pixels-turbo'
```

2. **上传到S3**:
```bash
aws s3 cp pixels-turbo/pixels-worker-lambda/target/pixels-worker-lambda.jar s3://your-bucket/lambda/
```

3. **创建Lambda函数**:
```bash
aws lambda create-function \
  --function-name pixels-scan-worker \
  --runtime java21 \
  --role arn:aws:iam::ACCOUNT:role/pixels-lambda-role \
  --handler io.pixelsdb.pixels.worker.lambda.ScanWorker::handleRequest \
  --code S3Bucket=your-bucket,S3Key=lambda/pixels-worker-lambda.jar \
  --architectures arm64 \
  --memory-size 4096 \
  --timeout 900 \
  --environment Variables={PIXELS_CONFIG=/tmp/pixels.properties}
```

### Invoke Lambda函数

1. **使用AWS CLI**:
```bash
# 准备输入payload
cat > input.json << EOF
{
  "transId": 12345,
  "timestamp": 1640995200000,
  "inputInfos": [
    {
      "inputId": 1,
      "path": "s3://pixels-test/input/table.pxl",
      "storageInfo": {
        "scheme": "s3",
        "endpoint": "https://s3.ap-southeast-1.amazonaws.com"
      }
    }
  ],
  "output": {
    "path": "s3://pixels-test/output/result.pxl",
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.ap-southeast-1.amazonaws.com"
    }
  },
  "scanProjection": ["col1", "col2", "col3"]
}
EOF

# Invoke函数
aws lambda invoke \
  --function-name pixels-scan-worker \
  --payload file://input.json \
  --cli-binary-format raw-in-base64-out \
  response.json
```

2. **查看执行结果**:
```bash
# 查看响应
cat response.json

# 查看CloudWatch日志
aws logs tail /aws/lambda/pixels-scan-worker --follow --format short
```

3. **性能数据分析**:
```bash
# 从日志中提取CSV数据
aws logs filter-log-events \
  --log-group-name /aws/lambda/pixels-scan-worker \
  --filter-pattern "Performance Data" \
  --output text
```

### 批量测试

1. **创建测试脚本**:
```bash
#!/bin/bash
# test_pixels_lambda.sh

FUNCTION_NAME="pixels-scan-worker"
TEST_FILES=("test1.pxl" "test2.pxl" "test3.pxl")

for file in "${TEST_FILES[@]}"; do
  echo "Testing $file..."
  
  # 准备payload
  sed "s/table.pxl/$file/g" input.json > test_payload.json
  
  # Invoke
  aws lambda invoke \
    --function-name $FUNCTION_NAME \
    --payload file://test_payload.json \
    --cli-binary-format raw-in-base64-out \
    "response_$file.json"
    
  echo "Completed $file"
  sleep 2
done

echo "All tests completed"
```

2. **运行批量测试**:
```bash
chmod +x test_pixels_lambda.sh
./test_pixels_lambda.sh
```

## 最佳实践

### 开发环境
- 在EC2上进行代码编译和测试
- 使用PerformanceProfiler验证性能
- 确保所有依赖正确配置

### 生产部署
- 使用CI/CD自动化部署
- 配置监控和告警
- 实施日志轮转策略

### 安全考虑
- 使用最小权限IAM角色
- 定期轮换访问密钥
- 配置VPC和安全组

### 故障排除
- 检查CloudWatch日志定位问题
- 监控Lambda执行时间和错误率
- 验证S3权限和网络连接

---

**最后更新**: 2025年11月23日
**实例ID**: i-0e01b0d7947291b0b
**实例IP**: 3.87.201.11
**实例类型**: r5.4xlarge (16 vCPU, 128GB RAM, 高性能实例)
**实例名称**: Pixels-Dev-Large
**SSH用户**: ec2-user (不是sunhao，EC2 Linux默认用户名)
**SSH连接**: `ssh -i ~/.ssh/pixels-key.pem ec2-user@3.87.201.11`
**Java版本**: Java 23.0.2 ✅
**Maven版本**: Maven 3.9.9 ✅
**FlatBuffers版本**: 2.0.8 ✅
**其他工具**: git, wget, cmake3, gcc-c++ ✅
**联系方式**: 如有问题请及时反馈

**性能验证结果**:
- ✅ 编码压缩占比: 64.52%
- ✅ S3存储占比: 35.48%
- ✅ 计时器逻辑正确，CSV输出正常
- ✅ 编译问题已修复，支持所有Worker模块