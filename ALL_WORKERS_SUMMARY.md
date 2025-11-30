# 所有 Worker 测试和性能指标总结

## ✅ 已完成

1. **创建了性能指标提取脚本** (`test-workers-with-metrics.sh`)
   - 自动测试所有已部署的 Worker
   - 从 CloudWatch Logs 提取性能指标
   - 以与 `lambda-full-execution-log.txt` 相同的格式显示

2. **说明了性能指标文件位置**
   - 文件保存在 Lambda 运行时环境的 `/tmp` 目录
   - 不在 Mac 本地，无法直接访问
   - 但所有指标都输出到 CloudWatch Logs

3. **创建了文档**
   - `PERFORMANCE_METRICS_FILE_LOCATION.md` - 文件位置说明
   - `ALL_WORKERS_TEST_AND_METRICS.md` - 完整测试指南

## 📊 最新性能指标示例

从最新测试中提取的 ScanWorker 性能指标：

```
=== ScanWorker 性能指标摘要 ===
Worker: ScanWorker
READ: 9354 ms
COMPUTE: 9718 ms (27.21%)
WRITE_CACHE: 13110 ms (36.71%)
WRITE_FILE: 3533 ms (9.89%)
S3 Storage (READ + WRITE_FILE): 36.08% (12887 ms = 9354 ms + 3533 ms)
总耗时: 35715 ms (约 35.7 秒)
内存使用: 3068 MB / 4096 MB
```

## 📁 性能指标文件位置

### ⚠️ 重要说明

**性能指标 CSV 文件保存在 Lambda 函数的运行时环境中，不是您的 Mac！**

| Worker 类型 | Lambda 环境内文件路径 |
|------------|---------------------|
| ScanWorker | `/tmp/scan_performance_metrics.csv` |
| AggregationWorker | `/tmp/aggregation_performance_metrics.csv` |
| PartitionWorker | `/tmp/partition_performance_metrics.csv` |
| BroadcastJoinWorker | `/tmp/broadcast_join_performance_metrics.csv` |
| PartitionedJoinWorker | `/tmp/partitioned_join_performance_metrics.csv` |
| BroadcastChainJoinWorker | `/tmp/broadcast_chain_join_performance_metrics.csv` |
| PartitionedChainJoinWorker | `/tmp/partitioned_chain_join_performance_metrics.csv` |

**这些文件无法直接从 Mac 访问**，但所有性能指标都已经输出到 CloudWatch Logs。

## 🔧 使用方法

### 测试所有 Worker

```bash
# 运行测试脚本
./test-workers-with-metrics.sh
```

### 手动提取性能指标

```bash
# 从 CloudWatch Logs 提取最新的性能指标
aws logs tail /aws/lambda/pixels-scan-worker --since 10m --region us-east-2 \
  | grep -E "(Four-Stage|Percentages)"
```

## 📝 下一步

1. **部署其他 Worker** (如果需要)
   - AggregationWorker
   - PartitionWorker
   - Join Workers 等

2. **测试其他 Worker** (部署后)
   ```bash
   ./test-workers-with-metrics.sh
   ```

3. **修改代码将 CSV 上传到 S3** (如果需要 CSV 文件)
   - 修改 `WorkerMetrics.java` 中的 `writePerformanceToFile` 方法

## 💡 推荐做法

✅ **使用 CloudWatch Logs**: 所有性能指标都已输出，最简单可靠
✅ **使用提取脚本**: `test-workers-with-metrics.sh` 自动提取和格式化
❌ **不尝试访问 Lambda /tmp**: 这些文件在 Lambda 运行时环境中，无法直接访问

