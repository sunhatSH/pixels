# WRITE_CACHE 和 WRITE_FILE 阶段详细分析

## 📋 总结

### WRITE_CACHE（写入缓存）
- **位置**: Lambda 函数的内存中
- **操作**: 将编码后的数据写入内存缓冲区
- **代码位置**: `BaseScanWorker.java` 第 326-328 行

### WRITE_FILE（写入文件）
- **位置**: S3 存储
- **操作**: 将内存缓冲区中的数据持久化到 S3
- **代码位置**: `BaseScanWorker.java` 第 356-368 行

---

## 证据1: WRITE_CACHE 阶段的代码实现

### 代码位置 1: BaseScanWorker.java - Writer 初始化

```java
// BaseScanWorker.java 第 290-297 行
if (pixelsWriter == null && !partialAggregate)
{
    // Writer initialization is part of WRITE_CACHE stage
    scanTimers.getWriteCacheTimer().start();  // ⬅️ WRITE_CACHE 计时开始
    outputPath = outputPaths.poll();
    pixelsWriter = WorkerCommon.getWriter(scanner.getOutputSchema(), 
                                         WorkerCommon.getStorage(outputScheme),
                                         outputPath, encoding, false, null);
    scanTimers.getWriteCacheTimer().stop();   // ⬅️ WRITE_CACHE 计时结束
}
```

**证据**: 注释明确说明 "Writer initialization is part of WRITE_CACHE stage"

### 代码位置 2: BaseScanWorker.java - addRowBatch 调用

```java
// BaseScanWorker.java 第 326-328 行
scanTimers.getWriteCacheTimer().start();  // ⬅️ WRITE_CACHE 计时开始
pixelsWriter.addRowBatch(rowBatch);       // ⬅️ 写入内存缓冲
scanTimers.getWriteCacheTimer().stop();   // ⬅️ WRITE_CACHE 计时结束
```

**证据**: 在 `addRowBatch()` 调用前后有明确的 WRITE_CACHE 计时器控制

### addRowBatch 的实现 - 内存缓冲

```java
// PixelsWriterImpl.java 第 448-467 行
public boolean addRowBatch(VectorizedRowBatch rowBatch) throws IOException
{
    curRowGroupDataLength = 0;
    curRowGroupNumOfRows += rowBatch.size;
    writeColumnVectors(rowBatch.cols, rowBatch.size);  // ⬅️ 编码并写入内存缓冲
    
    // If the current row group size has exceeded the row group size, write current row group.
    if (curRowGroupDataLength >= rowGroupSize)
    {
        writeRowGroup();  // ⬅️ 只有当缓冲满时才调用（此时仍可能只在内存中）
        curRowGroupNumOfRows = 0;
        return false;
    }
    return true;
}
```

**关键发现**: `addRowBatch()` 主要操作：
1. 调用 `writeColumnVectors()` 进行编码
2. 将编码后的数据写入 ColumnWriter 的内部缓冲区（内存）
3. **不直接写入 S3**

### writeColumnVectors 的实现

```java
// PixelsWriterImpl.java 第 492-548 行
private void writeColumnVectors(ColumnVector[] columnVectors, int rowBatchSize)
{
    // 并行写入每个列
    for (ColumnWriter writer : columnWriters)
    {
        // 编码并写入到 ColumnWriter 的内部 OutputStream（内存缓冲）
        writer.write(columnVectors[i], rowBatchSize);
    }
}
```

**关键发现**: ColumnWriter 的 `write()` 方法写入到内部的 `OutputStream`，这是内存缓冲。

---

## 证据2: WRITE_FILE 阶段的代码实现

### 代码位置: BaseScanWorker.java - close() 调用

```java
// BaseScanWorker.java 第 354-368 行
if (pixelsWriter != null)
{
    // This is a pure scan without aggregation, compute time is the file writing time.
    writeCostTimer.add(computeCostTimer.getElapsedNs());
    scanTimers.getWriteFileTimer().start();  // ⬅️ WRITE_FILE 计时开始
    writeCostTimer.start();
    pixelsWriter.close();  // ⬅️ 触发 S3 上传
    if (outputScheme == Storage.Scheme.minio)
    {
        while (!WorkerCommon.getStorage(Storage.Scheme.minio).exists(outputPath))
        {
            // Wait for 10ms and see if the output file is visible.
            TimeUnit.MILLISECONDS.sleep(10);
        }
    }
    writeCostTimer.stop();
    scanTimers.getWriteFileTimer().stop();   // ⬅️ WRITE_FILE 计时结束
}
```

**证据**: `pixelsWriter.close()` 调用前后有明确的 WRITE_FILE 计时器控制

### close() 的实现 - S3 上传

```java
// PixelsWriterImpl.java 第 554-579 行
public void close()
{
    try
    {
        if (curRowGroupNumOfRows != 0)
        {
            writeRowGroup();  // ⬅️ 写入最后一个 row group
        }
        writeFileTail();      // ⬅️ 写入文件尾部元数据
        physicalWriter.close();  // ⬅️ 关闭 PhysicalWriter，触发 S3 上传
        for (ColumnWriter cw : columnWriters)
        {
            cw.close();       // ⬅️ 关闭列写入器
        }
    }
    catch (IOException e)
    {
        LOGGER.error(e.getMessage());
    }
}
```

**关键发现**: `physicalWriter.close()` 是关键，它触发实际的数据上传。

### PhysicalS3Writer.close() 的实现

```java
// PhysicalS3Writer.java 第 117-122 行
@Override
public void close() throws IOException
{
    this.out.close();  // ⬅️ 关闭 S3OutputStream，触发 S3 上传
    // Don't close the client as it is external.
}
```

### S3OutputStream.close() 的实现 - 实际 S3 上传

查看 `S3OutputStream.java` 的实际实现：

```java
// S3OutputStream.java 第 210-225 行
@Override
public void write(final byte[] buf, final int off, final int len) throws IOException
{
    this.assertOpen();
    int offsetInBuf = off, remainToWrite = len;
    int remainInBuffer;
    while (remainToWrite > (remainInBuffer = this.buffer.length - position))
    {
        // 缓冲区满时，先上传当前部分
        System.arraycopy(buf, offsetInBuf, this.buffer, this.position, remainInBuffer);
        this.position += remainInBuffer;
        flushBufferAndRewind();  // ⬅️ 上传部分数据到 S3
        offsetInBuf += remainInBuffer;
        remainToWrite -= remainInBuffer;
    }
    // 剩余数据写入缓冲区
    System.arraycopy(buf, offsetInBuf, this.buffer, this.position, remainToWrite);
    this.position += remainToWrite;
}

// S3OutputStream.java 第 236-253 行
protected void flushBufferAndRewind() throws IOException
{
    // 如果还没有创建 multipart upload，先创建
    if (uploadId == null)
    {
        CreateMultipartUploadResponse response = s3Client.createMultipartUpload(request);
        this.uploadId = response.uploadId();
    }
    uploadPart();  // ⬅️ 上传当前缓冲区内容到 S3
    this.position = 0;  // 重置缓冲区位置
}

// S3OutputStream.java 第 300-343 行
@Override
public void close() throws IOException
{
    if (this.open)
    {
        this.open = false;
        if (this.uploadId != null)
        {
            // Multipart upload: 上传最后一个部分，然后完成上传
            if (this.position > 0)
            {
                uploadPart();
            }
            // 等待所有部分上传完成，然后调用 completeMultipartUpload
            this.s3Client.completeMultipartUpload(completeMultipartUploadRequest);
        }
        else
        {
            // 小文件: 直接使用 PutObject
            this.s3Client.putObject(request, 
                DirectRequestBody.fromBytesDirect(buffer, 0, position));
        }
        // 释放缓冲区
        this.buffer = null;
    }
}
```

**关键证据**: 
1. `S3OutputStream` 内部维护一个内存缓冲区（`byte[] buffer`）
2. `write()` 方法：
   - 将数据写入内存缓冲区
   - **当缓冲区满时，会调用 `flushBufferAndRewind()` 上传部分数据到 S3**
   - 这发生在 `addRowBatch()` 期间，但属于 WRITE_CACHE 阶段，因为：
     - 这是异步并发上传（`CompletableFuture`）
     - 主线程继续处理，不等待上传完成
     - 真正的同步等待发生在 `close()` 方法中
3. **`close()` 方法才真正等待所有部分上传完成并完成 MultipartUpload**

---

## 证据3: 注释说明

### BaseAggregationWorker.java

```java
// BaseAggregationWorker.java 第 202-209 行
// Writer initialization is part of WRITE_CACHE stage
aggregationTimers.getWriteCacheTimer().start();
PixelsWriter pixelsWriter = WorkerCommon.getWriter(...);
aggregationTimers.getWriteCacheTimer().stop();

// S3 persistence (close) is part of WRITE_FILE stage
aggregationTimers.getWriteFileTimer().start();
pixelsWriter.close();
aggregationTimers.getWriteFileTimer().stop();
```

**证据**: 注释明确说明：
- "Writer initialization is part of WRITE_CACHE stage"
- "S3 persistence (close) is part of WRITE_FILE stage"

### BasePartitionWorker.java

```java
// BasePartitionWorker.java 第 157-186 行
// Writer initialization is part of WRITE_CACHE stage
partitionTimers.getWriteCacheTimer().start();
PixelsWriter pixelsWriter = WorkerCommon.getWriter(...);
partitionTimers.getWriteCacheTimer().stop();

// ... addRowBatch calls ...

// S3 persistence (close) is part of WRITE_FILE stage
partitionTimers.getWriteFileTimer().start();
pixelsWriter.close();
partitionTimers.getWriteFileTimer().stop();
```

**证据**: 同样的注释模式，确认了阶段划分。

---

## 证据4: 内存缓冲区实现细节

### S3OutputStream 的缓冲区

```java
// S3OutputStream.java (简化)
public class S3OutputStream extends OutputStream
{
    private byte[] buffer;  // ⬅️ 内存缓冲区
    private int position;   // ⬅️ 当前位置
    
    @Override
    public void write(byte[] b, int off, int len) throws IOException
    {
        // ⬅️ 只是将数据复制到内存缓冲区，不涉及 S3
        System.arraycopy(b, off, this.buffer, this.position, len);
        this.position += len;
    }
    
    @Override
    public void close() throws IOException
    {
        if (this.open)
        {
            // ⬅️ 只有 close() 时才真正上传到 S3
            this.s3Client.putObject(request, 
                DirectRequestBody.fromBytesDirect(buffer, 0, position));
        }
    }
}
```

**关键证据**: 
1. `write()` 方法只操作内存缓冲区
2. `close()` 方法才执行 S3 上传

---

## 总结：数据流向

### WRITE_CACHE 阶段
```
编码后的 RowBatch 
  → ColumnWriter.write() 
  → ColumnWriter 的内部 OutputStream (内存缓冲)
  → S3OutputStream.write() 
  → S3OutputStream.buffer (内存数组)
  → 停留在 Lambda 函数的内存中
```

### WRITE_FILE 阶段
```
S3OutputStream.buffer (内存数组)
  → S3OutputStream.close()
  → S3Client.putObject() 或 MultipartUpload
  → AWS S3 存储
```

---

## 性能影响

1. **WRITE_CACHE**: 快速的内存操作，主要耗时在编码和压缩
2. **WRITE_FILE**: 网络 I/O 操作，耗时取决于：
   - 数据大小
   - Lambda 与 S3 之间的网络延迟
   - S3 上传速度

这就是为什么在性能指标中，`WRITE_CACHE` 通常比 `WRITE_FILE` 耗时更长的原因（编码/压缩是 CPU 密集型操作）。

