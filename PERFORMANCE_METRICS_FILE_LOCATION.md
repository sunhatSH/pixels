# 性能指标文件位置说明

## ⚠️ 重要说明

**性能指标 CSV 文件是写入到 Lambda 函数的运行时环境，不是您的 Mac 本地！**

### 文件实际位置

这些文件都保存在 **AWS Lambda 函数的临时目录** (`/tmp`) 中：

| Worker 类型 | 文件路径（Lambda 环境内） |
|------------|------------------------|
| ScanWorker | `/tmp/scan_performance_metrics.csv` |
| AggregationWorker | `/tmp/aggregation_performance_metrics.csv` |
| PartitionWorker | `/tmp/partition_performance_metrics.csv` |
| BroadcastJoinWorker | `/tmp/broadcast_join_performance_metrics.csv` |
| PartitionedJoinWorker | `/tmp/partitioned_join_performance_metrics.csv` |
| BroadcastChainJoinWorker | `/tmp/broadcast_chain_join_performance_metrics.csv` |
| PartitionedChainJoinWorker | `/tmp/partitioned_chain_join_performance_metrics.csv` |

### 为什么找不到文件？

1. **Lambda 临时目录**: `/tmp` 是 Lambda 函数运行时的临时目录（最多 512MB，10GB），不是您 Mac 的 `/tmp`
2. **临时性质**: Lambda 函数的 `/tmp` 目录在函数执行完成后可能会被清理
3. **无法直接访问**: 您无法直接从 Mac 访问 Lambda 函数内部的文件系统

## 解决方案

### 方案 1: 从 CloudWatch Logs 提取（推荐）

性能指标已经在 CloudWatch Logs 中输出，可以直接从日志中提取：

```bash
# 提取 ScanWorker 性能指标
aws logs filter-log-events \
  --log-group-name /aws/lambda/pixels-scan-worker \
  --filter-pattern "Four-Stage Performance Metrics" \
  --region us-east-2 \
  --query 'events[-1].message' \
  --output text
```

### 方案 2: 修改代码将文件上传到 S3

如果需要 CSV 文件，可以修改代码将文件上传到 S3。这需要修改 `WorkerMetrics.java` 中的 `writePerformanceToFile` 方法。

### 方案 3: 在 Lambda 函数中返回文件内容

修改代码将 CSV 内容作为响应的一部分返回。

## 当前可用的性能指标获取方式

所有性能指标都已经在 **CloudWatch Logs** 中以日志形式输出，包括：

```
Four-Stage Performance Metrics (ms): READ=9856, COMPUTE=9900, WRITE_CACHE=14387, WRITE_FILE=4865
Percentages: COMPUTE=25.38%, WRITE_CACHE=36.88%, WRITE_FILE=12.47%, S3 Storage=37.74%
```

这些信息可以通过 CloudWatch Logs API 或 AWS Console 查看。



