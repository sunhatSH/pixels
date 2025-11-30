# 性能指标计算说明

## 概述

Pixels Lambda Worker 使用四个阶段的性能指标来衡量查询执行性能：
- **READ**: 数据读取时间
- **COMPUTE**: 数据计算时间（过滤、投影、编码）
- **WRITE_CACHE**: 写入缓存时间（数据编码后写入内存缓存）
- **WRITE_FILE**: 写入文件时间（将缓存数据持久化到 S3）

## 代码位置

### 1. 计时器定义
**文件**: `pixels-turbo/pixels-worker-common/src/main/java/io/pixelsdb/pixels/worker/common/WorkerMetrics.java`

```java
// 计时器基础类
public static class Timer {
    private final AtomicLong elapsedNs = new AtomicLong(0);
    private long startTime = 0L;
    
    public Timer start() {
        startTime = System.nanoTime();  // 使用纳秒精度
        return this;
    }
    
    public long stop() {
        long endTime = System.nanoTime();
        elapsedNs.addAndGet(endTime - startTime);  // 累加耗时
        return elapsedNs.get();
    }
    
    public long getElapsedNs() {
        return elapsedNs.get();
    }
}

// 四个阶段的计时器集群
public static class StageTimers {
    private final Timer readTimer = new Timer();           // READ 阶段
    private final Timer computeTimer = new Timer();        // COMPUTE 阶段
    private final Timer writeCacheTimer = new Timer();     // WRITE_CACHE 阶段
    private final Timer writeFileTimer = new Timer();      // WRITE_FILE 阶段
    
    // 转换为毫秒
    public long getReadTimeMs() {
        return readTimer.getElapsedNs() / 1_000_000;
    }
    // ... 其他类似方法
}
```

### 2. 计时逻辑实现
**文件**: `pixels-turbo/pixels-worker-common/src/main/java/io/pixelsdb/pixels/worker/common/BaseScanWorker.java`

#### READ 阶段计时

```java
// 行 267-272: PixelsReader 初始化
scanTimers.getReadTimer().start();
readCostTimer.start();
try (PixelsReader pixelsReader = WorkerCommon.getReader(...)) {
    readCostTimer.stop();
    scanTimers.getReadTimer().stop();
}

// 行 305-307: 每次读取数据批次
scanTimers.getReadTimer().start();
rowBatch = recordReader.readBatch(WorkerCommon.rowBatchSize);
scanTimers.getReadTimer().stop();
```

**计时范围**:
- S3 文件读取器的初始化
- 从 S3 读取每个数据批次（rowBatch）
- **不包括**: 数据解码时间（属于 COMPUTE 阶段）

#### COMPUTE 阶段计时

```java
// 行 314-316: 过滤和投影操作
scanTimers.getComputeTimer().start();
rowBatch = scanner.filterAndProject(rowBatch);  // 包括数据编码
scanTimers.getComputeTimer().stop();
```

**计时范围**:
- 数据过滤（filter）操作
- 列投影（projection）操作
- **数据编码（encoding）**: `pixelsWriter.addRowBatch(rowBatch)` 的编码部分

**注意**: 根据之前的修复，数据编码时间从 WRITE_CACHE 移到了 COMPUTE 阶段。

#### WRITE_CACHE 阶段计时

```java
// 行 293-297: Writer 初始化
scanTimers.getWriteCacheTimer().start();
outputPath = outputPaths.poll();
pixelsWriter = WorkerCommon.getWriter(...);
scanTimers.getWriteCacheTimer().stop();

// 行 326-328: 写入数据批次到缓存（已移除编码部分）
// 注意：根据最新代码，addRowBatch 现在在 COMPUTE 阶段计时
// 如果仍有 WRITE_CACHE 计时，可能是在某些特定场景下
```

**计时范围**:
- Writer 初始化（创建输出流）
- 数据写入内存缓存（不包括编码）

#### WRITE_FILE 阶段计时

```java
// 行 356-368: 关闭 Writer，持久化到 S3
scanTimers.getWriteFileTimer().start();
writeCostTimer.start();
pixelsWriter.close();  // 触发 S3 multipart upload
if (outputScheme == Storage.Scheme.minio) {
    // 等待文件可见
    while (!WorkerCommon.getStorage(Storage.Scheme.minio).exists(outputPath)) {
        TimeUnit.MILLISECONDS.sleep(10);
    }
}
writeCostTimer.stop();
scanTimers.getWriteFileTimer().stop();
```

**计时范围**:
- 关闭 Writer（触发 S3 multipart upload）
- 等待文件在 S3 上可见（如果使用 MinIO）

### 3. 百分比计算
**文件**: `pixels-turbo/pixels-worker-common/src/main/java/io/pixelsdb/pixels/worker/common/WorkerMetrics.java`

```java
// 行 263-269: 计算总时间和百分比
long totalTimeMs = readTimeMs + computeTimeMsNew + writeCacheTimeMs + writeFileTimeMs;

// 计算百分比
double computePct = totalTimeMs > 0 ? ((double) computeTimeMsNew / totalTimeMs) * 100 : 0;
double writeCachePct = totalTimeMs > 0 ? ((double) writeCacheTimeMs / totalTimeMs) * 100 : 0;
double writeFilePct = totalTimeMs > 0 ? ((double) writeFileTimeMs / totalTimeMs) * 100 : 0;
double s3StoragePct = totalTimeMs > 0 ? ((double) (readTimeMs + writeFileTimeMs) / totalTimeMs) * 100 : 0;
```

**S3 Storage 百分比**: `(READ + WRITE_FILE) / 总时间 * 100`
- 表示所有与 S3 存储相关的操作占比
- 包括从 S3 读取和写入到 S3

### 4. 日志输出
**文件**: `pixels-turbo/pixels-worker-common/src/main/java/io/pixelsdb/pixels/worker/common/WorkerMetrics.java`

```java
// 行 273-277: 输出性能指标
logger.info("Four-Stage Performance Metrics (ms): READ={}, COMPUTE={}, WRITE_CACHE={}, WRITE_FILE={}",
        readTimeMs, computeTimeMsNew, writeCacheTimeMs, writeFileTimeMs);
logger.info("Percentages: COMPUTE={}%, WRITE_CACHE={}%, WRITE_FILE={}%, S3 Storage={}%",
        String.format("%.2f", computePct), String.format("%.2f", writeCachePct),
        String.format("%.2f", writeFilePct), String.format("%.2f", s3StoragePct));
```

## 执行流程示例

基于您的执行结果：
- **READ**: 9,856 ms
- **COMPUTE**: 9,900 ms (25.38%)
- **WRITE_CACHE**: 14,387 ms (36.88%)
- **WRITE_FILE**: 4,865 ms (12.47%)

### 总时间计算

```
totalTimeMs = 9856 + 9900 + 14387 + 4865 = 39,008 ms
```

### 百分比验证

```
COMPUTE:     9900 / 39008 * 100 = 25.38% ✓
WRITE_CACHE: 14387 / 39008 * 100 = 36.88% ✓
WRITE_FILE:  4865 / 39008 * 100 = 12.47% ✓
S3 Storage:  (9856 + 4865) / 39008 * 100 = 37.74% ✓
```

## 关键代码位置总结

| 阶段 | 开始位置 | 结束位置 | 代码文件 |
|------|---------|---------|---------|
| **READ** | `BaseScanWorker.java:267`<br>`BaseScanWorker.java:305` | `BaseScanWorker.java:272`<br>`BaseScanWorker.java:307` | `BaseScanWorker.java` |
| **COMPUTE** | `BaseScanWorker.java:314` | `BaseScanWorker.java:316` | `BaseScanWorker.java` |
| **WRITE_CACHE** | `BaseScanWorker.java:293`<br>`BaseScanWorker.java:326` | `BaseScanWorker.java:297`<br>`BaseScanWorker.java:328` | `BaseScanWorker.java` |
| **WRITE_FILE** | `BaseScanWorker.java:356` | `BaseScanWorker.java:368` | `BaseScanWorker.java` |
| **百分比计算** | - | - | `WorkerMetrics.java:266-269` |
| **日志输出** | - | - | `WorkerMetrics.java:273-277` |

## 注意事项

1. **时间单位**: 所有计时器使用纳秒（nanoseconds）精度，最终转换为毫秒输出
2. **累加机制**: 每个阶段的计时是累加的，如果在循环中多次执行，会累加所有时间
3. **线程安全**: 使用 `AtomicLong` 确保多线程环境下的准确性
4. **初始化**: 在每次处理请求前，调用 `scanTimers.clear()` 重置所有计时器（行 77 附近）

## 相关文件

- `pixels-turbo/pixels-worker-common/src/main/java/io/pixelsdb/pixels/worker/common/WorkerMetrics.java`
- `pixels-turbo/pixels-worker-common/src/main/java/io/pixelsdb/pixels/worker/common/BaseScanWorker.java`
- `pixels-turbo/pixels-worker-common/src/main/java/io/pixelsdb/pixels/worker/common/BaseScanWorker.java:77` (scanTimers 初始化)



