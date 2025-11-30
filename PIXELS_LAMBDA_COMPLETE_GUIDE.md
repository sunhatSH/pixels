# Pixels Lambda 完整操作指南

## 一、AWS 和 Lambda 操作

### 环境配置

**AWS 资源信息**：
- S3 Bucket: `home-sunhao` (区域: `us-east-2`)
- EC2 实例: `i-0e01b0d7947291b0b` (IP: `52.201.234.106`, 区域: `us-east-1`)
- Lambda 函数: `pixels-scan-worker` (区域: `us-east-2`)
- IAM 角色: `PixelsLambdaRole`

**SSH 连接**：
```bash
ssh -i ~/.ssh/pixels-key.pem ec2-user@52.201.234.106
```

### S3 操作

**上传 JAR 到 S3**：
```bash
aws s3 cp ./pixels-worker-lambda.jar \
  s3://home-sunhao/lambda/pixels-worker-lambda.jar \
  --region us-east-2
```

**验证上传**：
```bash
aws s3 ls s3://home-sunhao/lambda/ --region us-east-2 --human-readable
```

### Lambda 函数操作

**更新 Lambda 函数代码**：
```bash
aws lambda update-function-code \
  --function-name pixels-scan-worker \
  --s3-bucket home-sunhao \
  --s3-key lambda/pixels-worker-lambda.jar \
  --region us-east-2

aws lambda wait function-updated \
  --function-name pixels-scan-worker \
  --region us-east-2
```

**调用 Lambda 函数**：
```bash
aws lambda invoke \
  --function-name pixels-scan-worker \
  --region us-east-2 \
  --cli-binary-format raw-in-base64-out \
  --payload "$(cat test-scan-input.json)" \
  lambda-response.json
```

**查看 Lambda 日志**：
```bash
aws logs tail /aws/lambda/pixels-scan-worker \
  --region us-east-2 \
  --follow
```

**提取性能数据**：
```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/pixels-scan-worker \
  --region us-east-2 \
  --filter-pattern "Performance" \
  --start-time $(($(date +%s) - 300))000 \
  --query 'events[*].message' \
  --output text > performance_data.txt
```

### IAM 角色查询

```bash
aws iam get-role --role-name PixelsLambdaRole --query 'Role.Arn' --output text
```

---

## 二、从编写代码到测试的完整流程

### 步骤 1: 代码修改

在本地 Mac 上修改代码，主要涉及：
- `pixels-turbo/pixels-worker-lambda/pom.xml`: 添加 gRPC 依赖
- `pixels-common/pom.xml`: 移除 `grpc-netty` 依赖（避免与 `grpc-netty-shaded` 冲突）
- `pixels-core/src/main/java/io/pixelsdb/pixels/core/reader/PixelsRecordReaderImpl.java`: 代码逻辑修改
- `pixels-common/src/main/java/io/pixelsdb/pixels/common/retina/RetinaService.java`: 服务初始化逻辑
- `pixels-common/src/main/java/io/pixelsdb/pixels/common/metadata/MetadataService.java`: 服务初始化逻辑

### 步骤 2: 提交代码到 Git

```bash
git add .
git commit -m "Fix gRPC NameResolver and service initialization issues"
git push origin master
```

### 步骤 3: 在 EC2 上更新代码

```bash
ssh -i ~/.ssh/pixels-key.pem ec2-user@52.201.234.106
cd ~/pixels
git pull origin master
```

### 步骤 4: 编译项目

```bash
cd ~/pixels
mvn clean package -DskipTests -pl 'pixels-turbo/pixels-worker-lambda' -am
```

**生成的 JAR 文件**：
- `pixels-turbo/pixels-worker-lambda/target/pixels-worker-lambda-complete.jar` (约 53MB)
- 包含所有依赖的完整 uber JAR

### 步骤 5: 下载 JAR 到本地 Mac

```bash
scp -i ~/.ssh/pixels-key.pem \
  ec2-user@52.201.234.106:~/pixels/pixels-turbo/pixels-worker-lambda/target/pixels-worker-lambda-complete.jar \
  ./pixels-worker-lambda.jar
```

### 步骤 6: 上传 JAR 到 S3

```bash
aws s3 cp ./pixels-worker-lambda.jar \
  s3://home-sunhao/lambda/pixels-worker-lambda.jar \
  --region us-east-2
```

### 步骤 7: 更新 Lambda 函数

```bash
aws lambda update-function-code \
  --function-name pixels-scan-worker \
  --s3-bucket home-sunhao \
  --s3-key lambda/pixels-worker-lambda.jar \
  --region us-east-2

aws lambda wait function-updated \
  --function-name pixels-scan-worker \
  --region us-east-2
```

### 步骤 8: 准备测试输入

创建 `test-scan-input.json`：
```json
{
  "transId": 12345,
  "timestamp": 1640995200000,
  "tableInfo": {
    "tableName": "test_table",
    "base": true,
    "columnsToRead": ["col1", "col2", "col3"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.us-east-2.amazonaws.com"
    },
    "inputSplits": [{
      "inputInfos": [{
        "inputId": 1,
        "path": "s3://home-sunhao/test-data/large_test_data.pxl",
        "rgStart": 0,
        "rgLength": -1,
        "storageInfo": {
          "scheme": "s3",
          "endpoint": "https://s3.us-east-2.amazonaws.com"
        }
      }]
    }],
    "filter": "{}"
  },
  "scanProjection": [true, true, true],
  "partialAggregationPresent": false,
  "partialAggregationInfo": null,
  "output": {
    "path": "s3://home-sunhao/output/",
    "fileNames": ["result.pxl"],
    "storageInfo": {
      "scheme": "s3",
      "endpoint": "https://s3.us-east-2.amazonaws.com"
    },
    "encoding": true
  }
}
```

### 步骤 9: 执行 Lambda 测试

```bash
aws lambda invoke \
  --function-name pixels-scan-worker \
  --region us-east-2 \
  --cli-binary-format raw-in-base64-out \
  --payload "$(cat test-scan-input.json)" \
  lambda-response.json

cat lambda-response.json | jq .
```

### 步骤 10: 获取性能数据

```bash
sleep 10
aws logs filter-log-events \
  --log-group-name /aws/lambda/pixels-scan-worker \
  --region us-east-2 \
  --filter-pattern "Four-Stage Performance Metrics" \
  --start-time $(($(date +%s) - 300))000 \
  --query 'events[-1].message' \
  --output text
```

---

## 三、启动 AWS 服务器服务的完整流程

### MySQL 8 数据库启动

**安装 MySQL 8**：
```bash
sudo yum install -y https://dev.mysql.com/get/mysql80-community-release-el7-3.noarch.rpm
sudo yum install -y mysql-community-server mysql-community-client
```

**初始化 MySQL**：
```bash
sudo systemctl start mysqld
sudo mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
sudo chown -R mysql:mysql /var/lib/mysql
sudo chmod 750 /var/lib/mysql
sudo systemctl start mysqld
sudo systemctl enable mysqld
```

**配置数据库和用户**：
```bash
sudo mysql -uroot -e "
ALTER USER 'root'@'localhost' IDENTIFIED BY 'pixels_cds';
CREATE DATABASE IF NOT EXISTS pixels_metadata;
CREATE USER IF NOT EXISTS 'pixels'@'%' IDENTIFIED BY 'pixels_cds';
GRANT ALL PRIVILEGES ON pixels_metadata.* TO 'pixels'@'%';
FLUSH PRIVILEGES;
"
```

**导入 Schema**：
```bash
scp -i ~/.ssh/pixels-key.pem scripts/sql/metadata_schema.sql ec2-user@52.201.234.106:/tmp/
ssh -i ~/.ssh/pixels-key.pem ec2-user@52.201.234.106 "sudo mysql -u pixels -ppixels_cds pixels_metadata < /tmp/metadata_schema.sql"
```

### Pixels Daemon 服务启动

**创建配置目录**：
```bash
mkdir -p ~/opt/pixels/etc
mkdir -p ~/opt/pixels/var
cp ~/pixels/pixels-common/src/main/resources/pixels.properties ~/opt/pixels/etc/
```

**更新配置文件**：
```bash
sed -i 's|metadata.db.password=password|metadata.db.password=pixels_cds|g' ~/opt/pixels/etc/pixels.properties
sed -i 's|pixels.var.dir=/home/pixels/opt/pixels/var/|pixels.var.dir=/home/ec2-user/opt/pixels/var/|g' ~/opt/pixels/etc/pixels.properties
```

**启动 Daemon 服务**：
```bash
cd ~/pixels
nohup java -Doperation=start -Drole=coordinator -jar pixels-daemon/target/pixels-daemon-0.2.0-SNAPSHOT-full.jar > /tmp/pixels-daemon.log 2>&1 &
```

**验证服务启动**：
```bash
sleep 15
ss -tlnp | grep -E '18888|18889|18890|18893|18894'
tail -50 /tmp/pixels-daemon.log
```

**服务端口说明**：
- 18888: Metadata Server
- 18889: Transaction Server
- 18890: Retina Server
- 18893: Query Schedule Server
- 18894: Worker Coordinate Server

**停止服务**：
```bash
java -Doperation=stop -Drole=coordinator -jar pixels-daemon/target/pixels-daemon-0.2.0-SNAPSHOT-full.jar
# 或
pkill -f 'pixels-daemon.*coordinator'
```

---

## 四、修复 Bug 的完整流程

### Bug 1: NoClassDefFoundError - Log4j

**问题**：Lambda 执行时出现 `NoClassDefFoundError: org/apache/logging/log4j/LogManager`

**原因**：`pixels-worker-lambda-deps.jar` 只包含依赖，不包含应用代码

**解决方案**：
1. 创建包含所有依赖的完整 uber JAR
2. 使用 `maven-shade-plugin` 配置生成 `pixels-worker-lambda-complete.jar`
3. 合并 `pixels-worker-lambda.jar` 和 `pixels-worker-lambda-deps.jar`

**修复步骤**：
```bash
# 在 EC2 上合并 JAR
cd ~/pixels/pixels-turbo/pixels-worker-lambda/target
jar -xf pixels-worker-lambda.jar
jar -xf pixels-worker-lambda-deps.jar
jar -cf pixels-worker-lambda-complete.jar *
```

### Bug 2: NoClassDefFoundError - gRPC

**问题**：Lambda 执行时出现 `NoClassDefFoundError: io/grpc/Channel`

**原因**：`pixels-common` 中的 gRPC 依赖被标记为 `<optional>true</optional>`，未传递到 Lambda Worker

**解决方案**：
在 `pixels-turbo/pixels-worker-lambda/pom.xml` 中显式添加 gRPC 依赖：
```xml
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-netty-shaded</artifactId>
</dependency>
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-protobuf</artifactId>
</dependency>
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-stub</artifactId>
</dependency>
<!-- 其他 gRPC 依赖 -->
```

### Bug 3: gRPC NameResolver 格式错误

**问题**：`IllegalArgumentException: Address types of NameResolver 'unix' for 'localhost:18890' not supported by transport`

**原因**：
1. `pixels-common/pom.xml` 中同时存在 `grpc-netty` 和 `grpc-netty-shaded`
2. 导致 `NameResolverProvider` 加载冲突，选择了错误的 NameResolver

**解决方案**：
1. 从 `pixels-common/pom.xml` 中移除 `grpc-netty` 依赖
2. 只保留 `grpc-netty-shaded`
3. 确保 `maven-shade-plugin` 正确合并 `META-INF/services` 文件

**修复步骤**：
```xml
<!-- 在 pixels-common/pom.xml 中注释或删除 -->
<!--
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-netty</artifactId>
    <optional>true</optional>
</dependency>
-->
```

### Bug 4: MySQL 启动失败

**问题**：MySQL 8 启动失败，错误 `Unsupported redo log format (v0)`

**原因**：数据目录包含旧版本 MariaDB 5.5 的数据文件

**解决方案**：
```bash
# 停止 MySQL
sudo systemctl stop mysqld
sudo pkill -9 mysqld

# 备份并删除旧数据目录
sudo mv /var/lib/mysql /var/lib/mysql.backup.$(date +%s)
sudo mkdir -p /var/lib/mysql
sudo chown mysql:mysql /var/lib/mysql
sudo chmod 750 /var/lib/mysql

# 重新初始化
sudo mysqld --initialize-insecure --user=mysql --datadir=/var/lib/mysql
sudo chown -R mysql:mysql /var/lib/mysql
sudo systemctl start mysqld
```

### Bug 5: Daemon 服务 Lock 文件错误

**问题**：`java.io.IOException: No such file or directory` 创建 lock 文件失败

**原因**：`pixels.properties` 中的 `pixels.var.dir` 路径指向不存在的目录

**解决方案**：
```bash
# 创建目录
mkdir -p ~/opt/pixels/var

# 更新配置
sed -i 's|pixels.var.dir=/home/pixels/opt/pixels/var/|pixels.var.dir=/home/ec2-user/opt/pixels/var/|g' ~/opt/pixels/etc/pixels.properties
```

### Bug 6: Filter 为 null 错误

**问题**：`java.lang.NullPointerException: filter is null`

**原因**：`test-scan-input.json` 中 `filter` 字段为 `null`

**解决方案**：
将 `test-scan-input.json` 中的 `"filter": null` 改为 `"filter": "{}"`

---

## 快速参考命令

**完整测试流程**：
```bash
# 1. SSH 到 EC2 更新代码并编译
ssh -i ~/.ssh/pixels-key.pem ec2-user@52.201.234.106
cd ~/pixels && git pull && mvn clean package -DskipTests -pl 'pixels-turbo/pixels-worker-lambda' -am

# 2. 下载 JAR 到本地
scp -i ~/.ssh/pixels-key.pem ec2-user@52.201.234.106:~/pixels/pixels-turbo/pixels-worker-lambda/target/pixels-worker-lambda-complete.jar ./pixels-worker-lambda.jar

# 3. 上传到 S3 并更新 Lambda
aws s3 cp ./pixels-worker-lambda.jar s3://home-sunhao/lambda/pixels-worker-lambda.jar --region us-east-2
aws lambda update-function-code --function-name pixels-scan-worker --s3-bucket home-sunhao --s3-key lambda/pixels-worker-lambda.jar --region us-east-2

# 4. 执行测试
aws lambda invoke --function-name pixels-scan-worker --region us-east-2 --cli-binary-format raw-in-base64-out --payload "$(cat test-scan-input.json)" lambda-response.json

# 5. 查看性能数据
aws logs filter-log-events --log-group-name /aws/lambda/pixels-scan-worker --region us-east-2 --filter-pattern "Performance" --start-time $(($(date +%s) - 300))000 --query 'events[*].message' --output text
```

