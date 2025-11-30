# 测试所有 Worker 和性能指标提取指南

## 性能指标文件位置说明

### ⚠️ 重要：文件不在您的 Mac 上

**性能指标 CSV 文件保存在 AWS Lambda 函数的运行时环境中，不是您的 Mac 本地系统！**

### 文件实际位置

所有性能指标文件都保存在 **Lambda 函数的 `/tmp` 临时目录**中：

| Worker 类型 | 文件路径（Lambda 环境内） | 代码位置 |
|------------|-------------------------|---------|
| **ScanWorker** | `/tmp/scan_performance_metrics.csv` | `BaseScanWorker.java:393` |
| **AggregationWorker** | `/tmp/aggregation_performance_metrics.csv` | `BaseAggregationWorker.java:387` |
| **PartitionWorker** | `/tmp/partition_performance_metrics.csv` | `BasePartitionWorker.java:211` |
| **BroadcastJoinWorker** | `/tmp/broadcast_join_performance_metrics.csv` | `BaseBroadcastJoinWorker.java:657` |
| **PartitionedJoinWorker** | `/tmp/partitioned_join_performance_metrics.csv` | `BasePartitionedJoinWorker.java:747` |
| **BroadcastChainJoinWorker** | `/tmp/broadcast_chain_join_performance_metrics.csv` | `BaseBroadcastChainJoinWorker.java:551` |
| **PartitionedChainJoinWorker** | `/tmp/partitioned_chain_join_performance_metrics.csv` | `BasePartitionedChainJoinWorker.java:330` |

### 为什么找不到文件？

1. **Lambda 运行时环境**: `/tmp` 是 Lambda 函数运行时的临时目录（最多 512MB，10GB）
2. **临时性质**: 函数执行完成后可能会被清理
3. **无法直接访问**: Mac 无法直接访问 Lambda 函数内部的文件系统
4. **不在本地**: 这些文件**不存在于**您的 Mac 的 `/tmp` 目录

### 如何获取性能指标？

#### 方案 1: 从 CloudWatch Logs 提取（推荐）✅

所有性能指标都已经输出到 CloudWatch Logs，这是**推荐的方法**：

```bash
# 提取最新的性能指标
aws logs tail /aws/lambda/pixels-scan-worker --since 5m --region us-east-2 \
  | grep -E "(Four-Stage|Percentages)"

# 或使用脚本
./test-workers-with-metrics.sh
```

#### 方案 2: 修改代码上传到 S3（如果需要 CSV 文件）

如果您确实需要 CSV 文件，可以修改代码将文件上传到 S3。需要修改 `WorkerMetrics.java` 中的 `writePerformanceToFile` 方法。

#### 方案 3: 通过 Lambda 响应返回

修改代码将 CSV 内容作为响应的一部分返回。

## 测试所有 Worker

### 当前已部署的 Worker

根据检查，目前只部署了：
- ✅ `pixels-scan-worker` (ScanWorker)

### 其他可用的 Worker 类型

根据代码，还有以下 Worker 可以部署：

1. **AggregationWorker** - 聚合操作
2. **PartitionWorker** - 分区操作
3. **BroadcastJoinWorker** - 广播连接
4. **PartitionedJoinWorker** - 分区连接
5. **BroadcastChainJoinWorker** - 广播链式连接
6. **PartitionedChainJoinWorker** - 分区链式连接
7. **SortedJoinWorker** - 排序连接
8. **SortWorker** - 排序

### 部署其他 Worker

使用相同的 JAR 文件，创建不同的 Lambda 函数：

```bash
# 示例：部署 AggregationWorker
aws lambda create-function \
  --function-name pixels-aggregation-worker \
  --runtime java21 \
  --role <ROLE_ARN> \
  --handler io.pixelsdb.pixels.worker.lambda.AggregationWorker::handleRequest \
  --code S3Bucket=home-sunhao,S3Key=lambda/pixels-worker-lambda.jar \
  --architectures arm64 \
  --memory-size 4096 \
  --timeout 900 \
  --region us-east-2

# 部署 PartitionWorker
aws lambda create-function \
  --function-name pixels-partition-worker \
  --runtime java21 \
  --role <ROLE_ARN> \
  --handler io.pixelsdb.pixels.worker.lambda.PartitionWorker::handleRequest \
  --code S3Bucket=home-sunhao,S3Key=lambda/pixels-worker-lambda.jar \
  --architectures arm64 \
  --memory-size 4096 \
  --timeout 900 \
  --region us-east-2
```

## 性能指标格式说明

### 输出格式（与 lambda-full-execution-log.txt 相同）

```
=== ScanWorker 性能指标摘要 ===
Worker: ScanWorker
READ: 9856 ms
COMPUTE: 9900 ms (25.38%)
WRITE_CACHE: 14387 ms (36.88%)
WRITE_FILE: 4865 ms (12.47%)
S3 Storage (READ + WRITE_FILE): 37.74% (14721 ms = 9856 ms + 4865 ms)
总耗时: 39008 ms (约 39.0 秒)
内存使用: 2138 MB / 4096 MB
```

### 计算方法

1. **READ**: 从 S3 读取数据的时间（累加所有读取操作）
2. **COMPUTE**: 过滤、投影和编码的时间（累加所有计算操作）
3. **WRITE_CACHE**: 写入内存缓存的时间（累加所有缓存写入）
4. **WRITE_FILE**: 持久化到 S3 的时间（累加所有文件写入）

**百分比计算**:
- 各阶段百分比 = (阶段耗时 / 总耗时) × 100%
- S3 Storage 百分比 = ((READ + WRITE_FILE) / 总耗时) × 100%

## 使用测试脚本

```bash
# 测试所有已部署的 Worker 并提取性能指标
./test-workers-with-metrics.sh

# 输出将保存到 lambda-worker-metrics-summary.txt
```

## 代码位置参考

- **性能指标写入**: `WorkerMetrics.java` 第 273-277 行
- **ScanWorker 计时**: `BaseScanWorker.java` 第 267-368 行
- **AggregationWorker 计时**: `BaseAggregationWorker.java`
- **PartitionWorker 计时**: `BasePartitionWorker.java`

## 总结

✅ **性能指标已经可用**: 所有性能指标都输出到 CloudWatch Logs，可以通过脚本提取
❌ **CSV 文件无法直接访问**: 文件在 Lambda 运行时环境中，不在 Mac 上
💡 **推荐做法**: 使用 CloudWatch Logs 提取性能指标，这是最简单可靠的方法



