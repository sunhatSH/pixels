# 分析 CSV 中大量 0 值的原因

## 问题现象

CSV 文件中有很多记录的指标值全为 0：
```
1764408274000,ScanWorker,0,0,0,0,0.00,0.00,0.00,0.00
1764409058000,ScanWorker,0,0,0,0,0.00,0.00,0.00,0.00
```

## 可能的原因

### 1. **异常情况** - 函数执行失败或提前返回

查看 `BaseScanWorker.java` 第 220-227 行：

```java
} catch (Throwable e)
{
    logger.error("error during scan", e);
    scanOutput.setSuccessful(false);
    scanOutput.setErrorMessage(e.getMessage());
    scanOutput.setDurationMs((int) (System.currentTimeMillis() - startTime));
    return scanOutput;  // ⬅️ 异常情况下直接返回，不会调用 writePerformanceToFile()
}
```

**但是**，在 `process()` 方法中，`writePerformanceToFile()` 在 try-catch 内部（第 217 行），所以即使有异常，也会执行。

### 2. **空数据或没有实际工作**

如果 `scanInputs` 为空，或者所有输入都跳过（例如 row group 范围超出），计时器可能没有启动。

### 3. **计时器未初始化或重置**

查看 `WorkerMetrics.java` 第 251-261 行：

```java
if (hasDetailedTiming) {
    // Use detailed stage timers
    computeTimeMsNew = stageTimers.getComputeTimeMs();
    writeCacheTimeMs = stageTimers.getWriteCacheTimeMs();
    writeFileTimeMs = stageTimers.getWriteFileTimeMs();
} else {
    // Fall back to basic WorkerMetrics
    computeTimeMsNew = computeTimeMs;
    writeCacheTimeMs = 0; // ⬅️ 如果没有详细计时，WRITE_CACHE 默认为 0
    writeFileTimeMs = outputTimeMs;
}
```

如果 `stageTimers` 是空的（`StageTimers.getEmpty()`），或者计时器从未启动，所有值都会是 0。

### 4. **测试调用 - Lambda 函数被调用但没有处理数据**

很多 0 值可能是：
- Lambda 冷启动测试
- 配置测试
- 空的测试调用

## 为什么只有 ScanWorker？

查看所有 Lambda 函数的 Log Group：

```
=== pixels-broadcastjoinworker ===
null  ⬅️ 没有 Log Group，说明从未被调用

=== pixels-aggregationworker ===
null  ⬅️ 没有 Log Group

=== pixels-partitionworker ===
null  ⬅️ 没有 Log Group

=== pixels-scan-worker ===
{
    "name": "/aws/lambda/pixels-scan-worker",
    "created": 1763923820384
}  ⬅️ 只有这个有 Log Group
```

**结论**：只有 `pixels-scan-worker` 被实际调用过，其他 Worker 还没有被执行。

## 验证方法

### 1. 检查异常日志

```bash
aws logs tail /aws/lambda/pixels-scan-worker --since 7d --region us-east-2 \
  | grep -B 5 "Four-Stage Performance Metrics.*0,0,0,0" \
  | grep -E "(ERROR|Exception|failed)"
```

### 2. 过滤掉 0 值记录

修改 `download-csv-metrics.py`，添加过滤条件：

```python
# 只输出有实际数据的记录
if 'read' in data and 'compute' in data:
    # 过滤掉全为 0 的记录（可能是测试调用）
    if (data.get('read', 0) > 0 or 
        data.get('compute', 0) > 0 or 
        data.get('cache', 0) > 0 or 
        data.get('file', 0) > 0):
        writer.writerow([...])
```

### 3. 查看实际的工作记录

从 CSV 中可以看到，有实际数据的记录：
```
1764489877000,ScanWorker,9913,1,13163,7762,0.00,42.68,25.17,57.31
1764490998000,ScanWorker,9856,9900,14387,4865,25.38,36.88,12.47,37.74
```

这些记录有正常的指标值，说明：
- 函数正常工作时有数据
- 0 值记录可能是失败或测试调用

## 建议

1. **过滤 0 值记录**：在 CSV 提取脚本中添加过滤
2. **分析失败原因**：查看 0 值记录的上下文日志
3. **测试其他 Worker**：调用其他 Worker 函数生成数据



