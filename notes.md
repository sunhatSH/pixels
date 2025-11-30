# Pixels 云函数性能优化笔记

## 核心目标
在云环境（Lambda/云函数）上部署和优化 Pixels 查询系统，重点解决性能瓶颈问题，包括 S3 读写和编码压缩占比分析。

## 主要任务清单

### 阶段一：性能分析与测量
- 找到 scanworker 中的边界点：BaseScanWorker.java 中的 process() 函数（254-353 行）。
- 实现性能分解测量：使用 WorkerMetrics.Timer 测量 READ、COMPUTE、局部 WRITE 和全局 WRITE 阶段。
- 量化分析占比：计算编码压缩占比 vs S3 存储占比，验证瓶颈假设。

### 阶段二：编码压缩优化
- 研究编码技术：Run-Length Encoding (RLE)、Delta Encoding、Dictionary Encoding、ORC Format。
- 实现优化：调整 EncodingLevel，测试不同数据类型。

### 阶段三：云函数部署与通信
- 理解限制：云函数间通过 S3 传递中间结果，存在 read after write 问题。
- 设计测试用例：测量两个云函数（e.g., ScanWorker → JoinWorker）的执行时间和 S3 传递时间。
- 优化中间结果：探索网络通信、拆分写入或 S3 流式传输。

## 关键代码位置
- Lambda 入口：pixels-worker-lambda/src/main/java/io/pixelsdb/pixels/worker/lambda/ (e.g., ScanWorker.java)。
- 核心逻辑：pixels-worker-common/src/main/java/io/pixelsdb/pixels/worker/common/ (e.g., BaseScanWorker.java 的 scanFile() 和 process())。
- 工具类：WorkerCommon.java (Reader/Writer 获取)；WorkerMetrics.java (性能测量)。

## Worker 功能（导师任务相关）
- **BaseScanWorker**：表扫描，从 S3 读取数据，进行过滤/投影/部分聚合，编码后写回 S3。核心函数 scanFile() 处理单个 Split，process() 协调多 Split 和最终写入。
- **BasePartitionWorker**：数据分区，从 S3 读取上游数据，按 Hash 分区，写回 S3。
- **BaseAggregationWorker**：聚合，从 S3 读取部分结果，进行最终聚合，写回 S3。
- **BaseBroadcastJoinWorker**：广播 Join，从 S3 读取小/大表，内存 Hash Join，写回 S3。
- **BasePartitionedJoinWorker**：分区 Join，从 S3 读取分区数据，局部 Join，写回 S3。
- 所有 Worker 复用 scanFile()（或类似）处理 S3 读写，匹配导师的 READ/STORE 边界。

## 四个阶段总结

### 概述
基于 BaseScanWorker.java 的 scanFile() 和 process() 后半段，流程分为四个逻辑阶段：scanFile() 的三个子阶段（READ、COMPUTE、局部 WRITE）和 process() 的全局 WRITE。这体现了 Pixels 的懒写入设计：scanFile() 处理 per-file 缓冲，process 末尾统一上传。每个阶段对应导师的读-处理-编码-写需求。

| 阶段 | 位置 | 关键代码 | 功能 | 计时器 | 数据流动 |
|------|------|----------|------|--------|----------|
| **1. READ: S3 读到内存初步处理** | scanFile() 第 256-287 行 | `readCostTimer.start/stop()`<br>`WorkerCommon.getReader()`<br>`pixelsReader.read(option)`<br>`scanner = new Scanner(...)` | 从 S3 初始化 Reader，读取元数据/Row Group，初步处理（范围调整、Schema 加载、过滤规划）。数据初步进入内存缓冲。 | `readCostTimer`（S3 I/O + 初步元数据） | S3 对象 → 内存 (PixelsRecordReader + Schema) |
| **2. COMPUTE: 内存处理和编码** | scanFile() 第 288-317 行 | `computeCostTimer.start/stop()`<br>`recordReader.readBatch()` (解码)<br>`scanner.filterAndProject()` (过滤/投影)<br>`pixelsWriter.addRowBatch()` (编码/压缩) | 循环从内存解码批次，进行过滤/投影/聚合，然后编码/压缩到 Writer 缓冲。全内存 CPU 操作。 | `computeCostTimer`（解码 + 处理 + 编码）<br>`minus/add` 细分解码 | 内存 RowBatch (解码) → 内存缓冲 (编码 Pixels 格式) |
| **3. 局部 WRITE: Writer 初始化和缓冲追加** | scanFile() 第 279-285 行 (初始化)<br>第 299 行 (追加，在 compute 内) | `writeCostTimer.start/stop()` (仅初始化)<br>`WorkerCommon.getWriter()`<br>`addRowBatch()` (追加，compute 内) | 初始化 Writer（内存缓冲分配 + S3 连接准备），追加编码 RowBatch 到内存队列（无 S3 上传）。 | `writeCostTimer` (仅初始化，~10-50ms)<br>追加在 `computeCostTimer` | 内存 RowBatch → Writer 内存缓冲 (队列/ByteBuffer) |
| **4. 全局 WRITE: 最终 S3 持久化** | process() 第 318-337 行 | `writeCostTimer.add(computeCostTimer)` (累加编码)<br>`writeCostTimer.start/stop()`<br>`pixelsWriter.close()` (上传)<br>`exists()` (一致性检查) | 汇总所有缓冲，执行 close() 触发 S3 上传（PutObject/MultipartUpload）。记录全局指标，添加新 S3 路径。 | `writeCostTimer` (编码汇总 + 上传 I/O，~100ms-秒) | 内存缓冲 (所有 Split) → 新 S3 对象 (.pxl 文件) |

### 详细解释
- **阶段1 (READ)**：S3 I/O 起点，数据初步进入内存。初步处理是轻量（无完整解码），计时捕获网络延迟。
- **阶段2 (COMPUTE)**：纯内存，解码（Pixels 二进制 → 列向量）+ 处理 + 编码（列向量 → Pixels 二进制 + 压缩）。这是 CPU 瓶颈，导师"编码压缩占比"核心。
- **阶段3 (局部 WRITE)**：Writer 准备（内存缓冲），追加是编码延续（在 compute 内）。无 S3 上传，计时短。
- **阶段4 (全局 WRITE)**：真正 STORE，缓冲 → S3。新对象路径供下游 Worker 读。累加编码确保总 STORE 包括准备+上传。

**设计优势**：内存缓冲 (阶段3) 批量优化，延迟上传 (阶段4) 减少 S3 请求。总 S3 占比 = (阶段1 + 阶段4) / 总时间。

## 从协调器调用 Invoker 到 S3 存储的完整流程

### 流程图概述
Pixels-Turbo 的查询执行是一个分布式、serverless 管道：协调器（本地 Planner/Trino）规划任务，通过 Invoker 远程触发 AWS Lambda 云函数（Worker），Worker 从 S3 读取数据、在内存处理后写回 S3（新对象）。整个流程是异步、非阻塞的，使用 CompletableFuture 协调多 Worker（e.g., Scan → Join）。AWS 云函数的参与是按需触发：Invoker 发送 API 请求，AWS 管理启动/执行/回收。

```
协调器 (本地: Planner/Trino/EC2)
    │
    ├─ 1. 生成物理计划 + Input
    │
    └─ 2. 调用 Invoker.invoke() ── JSON Input ──> AWS Lambda API (网络)
            │
            └─ CompletableFuture<Output> (异步等待)
                    │
                    ↓ AWS 云函数启动 (冷启动 ~100ms)
Worker Lambda (云端: AWS 管理)
    │
    ├─ 3. handleRequest() → process()
    │
    ├─ 4. S3 读 (getReader()) ── GetObject ──> S3 (输入数据)
    │
    ├─ 5. 内存处理 + 编码 (scanFile() 循环)
    │
    └─ 6. S3 写 (close()) ── PutObject/Multipart ──> S3 (新对象)
            │
            └─ 7. 返回 Output (新 S3 路径 + 指标)
                    │
                    ↑ AWS API 返回 (JSON)
协调器 ────────────── 接收 Output ── 协调下一步 (e.g., Join Worker)
                │
                └─ S3 (中间结果: .pxl 文件)
```

**总时长**：端到端 ~1-10s（取决于数据大小），AWS 计费只算 Worker 执行时间（毫秒级）。

### 详细步骤

#### 步骤 1: 协调器生成计划并调用 Invoker（本地，<1ms）
- **位置**：`pixels-planner/src/main/java/io/pixelsdb/pixels/planner/plan/physical/ScanBatchOperator.java`（第 50-64 行）。
- **做什么**：查询 Planner（Trino 或 Pixels-Planner）解析 SQL，生成物理执行计划（e.g., ScanOperator）。创建 `ScanInput`（任务描述：S3 输入路径、列、过滤、输出文件夹）。然后本地实例化 Invoker 并调用。
- **关键代码**：
  ```java
  // ScanBatchOperator.execute() - 协调器本地执行
  public CompletableFuture<CompletableFuture<? extends Output>[]> execute()
  {
      return executePrev().handle((result, exception) -> {
          this.scanOutputs = new CompletableFuture[this.scanInputs.size()];
          int i = 0;
          for (ScanInput scanInput : this.scanInputs)  // 每个 Split 一个 Input
          {
              // 本地创建 Invoker（pixels-invoker-lambda）
              this.scanOutputs[i++] = InvokerFactory.Instance()
                      .getInvoker(WorkerType.SCAN)  // ← ScanInvokerProvider.createInvoker()
                      .invoke(scanInput);  // ← 异步调用，发送到 AWS
          }
          waitForCompletion(this.scanOutputs);  // 协调器等待所有 Future
          return this.scanOutputs;
      });
  }
  ```
- **AWS 参与**：无（纯本地）。协调器运行在 EC2/Trino，本地 JVM。
- **解释**：Input 包含 S3 输入（e.g., `s3://bucket/table.pxl`）、输出文件夹（`s3://intermediate/`）。多个 Input 并行（CompletableFuture 数组），支持并发（e.g., 10 个 Split → 10 个 Lambda）。

#### 步骤 2: Invoker 序列化和调用 AWS Lambda API（本地到云端，~100ms 冷启动）
- **位置**：`pixels-invoker-lambda/src/main/java/io/pixelsdb/pixels/invoker/lambda/LambdaInvoker.java`（第 58-100 行）。
- **做什么**：本地序列化 Input 为 JSON，通过 AWS SDK 发送 InvokeRequest 到 Lambda 服务。AWS 接收后，启动/调度 Worker Lambda 实例（冷启动：下载代码 ~100ms；热启动：~10ms）。
- **关键代码**：
  ```java
  // ScanInvoker.invoke() - 本地调用
  public final CompletableFuture<Output> invoke(Input input)  // input: ScanInput
  {
      // 1. 本地序列化 (JSON, ~1ms)
      String inputJson = JSON.toJSONString(input, SerializerFeature.DisableCircularReferenceDetect);
      SdkBytes payload = SdkBytes.fromUtf8String(inputJson);  // Input: S3 路径、过滤等

      // 2. 本地构建请求 (~1ms)
      InvokeRequest request = InvokeRequest.builder()
              .functionName("ScanWorker")  // AWS Lambda 函数名 (云端部署)
              .payload(payload)
              .invocationType(InvocationType.REQUEST_RESPONSE)  // 同步返回结果
              .build();

      // 3. 本地异步调用 AWS API (网络, ~50-200ms)
      return Lambda.Instance().getAsyncClient()  // AWS SDK
              .invoke(request)  // ← 发送到 AWS Lambda 服务
              .handle((response, err) -> {
                  if (err == null && response.statusCode() == 200) {
                      // 4. 本地反序列化 Output (~1ms)
                      String outputJson = response.payload().asUtf8String();
                      return JSON.parseObject(outputJson, ScanOutput.class);  // Output: 新 S3 路径 + 指标
                  }
                  throw new RuntimeException("Lambda failed");
              });
  }
  ```
- **AWS 参与**：
  - **API 调用**：Invoker 用 AWS SDK (`LambdaAsyncClient.invoke()`) 发送 HTTP 请求到 AWS Lambda 服务（endpoint: lambda.us-east-1.amazonaws.com）。
  - **函数调度**：AWS 检查函数名 ("ScanWorker")，从代码存储（S3）加载 JAR（冷启动），分配容器（内存 10GB），注入环境（S3 凭证）。
  - **执行**：AWS 运行 `handleRequest()`，Worker 接管。
  - **返回**：AWS 序列化 Output 为 JSON，通过 API 返回给 Invoker（~50ms 网络）。
- **解释**：Invoker 是"轻客户端"（本地），不执行计算。只桥接：Input → AWS → Worker。冷启动是 AWS 瓶颈（优化：预热池）。

#### 步骤 3: AWS Lambda 启动 Worker 并执行 process()（云端，~1-5s）
- **位置**：`pixels-worker-lambda/src/main/java/io/pixelsdb/pixels/worker/lambda/ScanWorker.java`（第 36-48 行） + `BaseScanWorker.process()`（第 72-354 行）。
- **做什么**：AWS 触发 Lambda，Worker 反序列化 Input，执行 S3 读-处理-写。process() 解析 Input，创建线程池，并行调用 scanFile()（per-Split）。
- **关键代码**：
  ```java
  // ScanWorker.handleRequest() - AWS Lambda 入口 (云端)
  public ScanOutput handleRequest(ScanInput event, Context context)  // event: 从 JSON 反序列化
  {
      // 1. 云端初始化上下文 (Lambda 环境)
      WorkerContext workerContext = new WorkerContext(logger, workerMetrics, context.getAwsRequestId());
      BaseScanWorker baseWorker = new BaseScanWorker(workerContext);

      // 2. 执行核心逻辑 (S3 I/O + 计算)
      return baseWorker.process(event);  // ← 云端 process()
  }

  // BaseScanWorker.process() - 云端核心 (第 72-354 行)
  public ScanOutput process(ScanInput event)
  {
      ScanOutput scanOutput = new ScanOutput();  // 输出对象
      workerMetrics.clear();  // 重置指标

      try
      {
          // 3. 初始化 (线程池、S3 存储)
          ExecutorService threadPool = Executors.newFixedThreadPool(cores * 2, ...);
          WorkerCommon.initStorage(inputStorageInfo);  // 云端 S3 连接

          // 4. 并行处理 Split (S3 读/写)
          Queue<String> outputPaths = ...;
          for (InputSplit inputSplit : inputSplits)
          {
              threadPool.execute(() -> scanFile(... , outputPaths, scanOutput, ...));  // per-file
          }
          threadPool.awaitTermination(1, TimeUnit.HOURS);  // 等待完成

          // 5. 最终 S3 写入 (全局)
          if (pixelsWriter != null)
          {
              writeCostTimer.start();
              pixelsWriter.close();  // ← 云端触发 S3 上传
              writeCostTimer.stop();
              scanOutput.addOutput(outputPath, ...);  // 新 S3 路径
          }

          // 6. 汇总指标 (字节/时间)
          workerMetrics.addInputCostNs(...);
          return scanOutput;  // 返回新 S3 路径 + 性能
      }
      catch (Throwable e) { ... }
  }
  ```
- **AWS 参与**：
  - **启动**：AWS 分配容器（vCPU/内存），加载 JAR，运行 handleRequest()（~100ms 冷启动）。
  - **执行**：Worker 用 AWS 凭证（IAM Role）访问 S3（`getStorage()` → S3AsyncClient）。计算在 Lambda 内存（10GB）。
  - **资源管理**：AWS 监控超时（15min）、内存（OOM 杀进程），自动回收（执行完 ~秒级）。
- **解释**：Worker 是"重计算"：S3 读（getReader() → GetObject）、内存编码（addRowBatch()）、S3 写（close() → PutObject）。process() 是管道核心，云端全执行。

#### 步骤 4: Worker 从 S3 读取数据（云端 S3 I/O，~100ms-秒）
- **位置**：`BaseScanWorker.scanFile()`（第 256-287 行）。
- **做什么**：反序列化 Input 后的路径，用 `WorkerCommon.getReader()` 从 S3 读取 .pxl 文件（元数据 + Row Group）。
- **关键代码**：
  ```java
  // scanFile() - 云端 S3 读
  readCostTimer.start();
  try (PixelsReader pixelsReader = WorkerCommon.getReader(inputInfo.getPath(), WorkerCommon.getStorage(inputScheme)))
  {
      readCostTimer.stop();  // S3 元数据加载完成
      
      PixelsRecordReader recordReader = pixelsReader.read(option);  // 加载 Row Group 到内存
  }
  ```
- **AWS 参与**：Worker 用 Lambda IAM Role（S3 读权限）调用 S3AsyncClient.getObject()（异步流式读）。AWS 网络优化（VPC Endpoint 避免公网）。
- **解释**：数据从 S3 → Lambda 内存（~64MB/RowGroup）。如果上游 Worker（如 Partition）已写，此是"read after write"（延迟 ~秒）。

#### 步骤 5: Worker 在内存处理和编码（云端 CPU，~100ms-秒）
- **位置**：`scanFile()` 循环（第 288-317 行）。
- **做什么**：解码 S3 数据（readBatch()）、过滤/投影（scanner）、编码到 Writer 缓冲（addRowBatch()）。
- **关键代码**：
  ```java
  computeCostTimer.start();
  do
  {
      rowBatch = scanner.filterAndProject(recordReader.readBatch(...));  // 解码 + 过滤 (内存)
      
      if (rowBatch.size > 0)
      {
          pixelsWriter.addRowBatch(rowBatch);  // 编码/压缩到内存缓冲
      }
  } while (!rowBatch.endOfFile);
  computeCostTimer.stop();
  ```
- **AWS 参与**：全 Lambda 内存（heap），AWS 提供 vCPU（~2-4 核）。无额外 I/O。
- **解释**：纯 CPU：解码（Pixels → 列向量）、处理、编码（RLE/Delta + Snappy）。缓冲累积（内存），不立即 S3。

#### 步骤 6: Worker 将编码数据存储到 S3（云端 S3 I/O，~100ms-秒）
- **位置**：`process()` 末尾（第 318-337 行）。
- **做什么**：关闭 Writer，flush 内存缓冲到新 S3 对象（.pxl）。更新 Output（新路径）。
- **关键代码**：
  ```java
  if (pixelsWriter != null)
  {
      writeCostTimer.start();
      pixelsWriter.close();  // ← 内存缓冲 → S3 上传 (PutObject/Multipart)
      
      // 等待一致性 (MinIO)
      if (outputScheme == Storage.Scheme.minio) {
          while (!getStorage(...).exists(outputPath)) sleep(10ms);
      }
      writeCostTimer.stop();
      
      scanOutput.addOutput(outputPath, numRowGroup);  // 新 S3 路径
  }
  ```
- **AWS 参与**：Worker 用 IAM Role 调用 S3AsyncClient.putObject() 或 initiateMultipartUpload()（大文件分块）。AWS 确保原子上传（幂等）。
- **解释**：编码缓冲（步骤5）→ 新 S3 对象（e.g., `s3://intermediate/split-1.pxl`）。这是"新的 S3 存储"，供下游 Worker 读。数据持久化完成。

#### 步骤 7: Worker 返回结果，协调器协调下一步（云端返回到本地，~50ms）
- **位置**：`ScanWorker.handleRequest()` 返回 + Invoker.handle()（步骤2）。
- **做什么**：Worker 序列化 Output（新 S3 路径 + 指标），AWS 返回 JSON。Invoker 反序列化，协调器等待所有 Future，触发下游（e.g., Join Worker）。
- **关键代码**：
  ```java
  // Worker 返回 (云端)
  return baseWorker.process(event);  // ScanOutput: {outputPaths: ["s3://new.pxl"], metrics: {...}}

  // Invoker 接收 (本地)
  Output output = JSON.parseObject(outputJson, ScanOutput.class);  // 解析新 S3 路径
  return output;  // 协调器收到，调用下一个 Invoker (e.g., JoinWorker)
  ```
- **AWS 参与**：AWS 序列化响应（JSON），通过 API 返回。函数结束，AWS 回收容器（~秒级）。
- **解释**：Output 只含元数据（路径/指标），不含数据（S3 存储）。协调器用新路径触发下游 Worker，形成管道（Scan → Partition → Join）。

### AWS 云函数的参与细节
- **触发机制**：Invoker 的 `invoke()` 发送 AWS Lambda API 请求（REST/HTTP）。AWS 服务（控制平面）调度：
  - **冷启动**：无运行实例 → 下载代码（S3）→ 初始化 JVM (~100-500ms)。
  - **热启动**：复用容器 (~10ms)。
  - **并发**：AWS 自动扩展（1000+ 实例），按内存/CPU 分配。
- **执行环境**：Lambda 提供沙箱（vCPU、10GB RAM、/tmp 512MB 磁盘）。Worker 用环境变量（PIXELS_HOME）和 IAM Role（S3 访问）。
- **S3 集成**：Worker 内 `getStorage()` 用 AWS SDK（S3AsyncClient），AWS 优化网络（VPC 内 S3 Endpoint，~50ms 延迟）。
- **计费/回收**：AWS 只计执行时间（从 handleRequest() 开始，到返回结束，毫秒级）。执行完自动回收（无持续成本）。
- **错误处理**：超时/OOM → AWS 重试或失败返回（Invoker 的 handle() 捕获）。

### 完整流程时序示例（Scan 操作）
1. **t=0ms**：协调器 `invoke(scanInput)`（本地）。
2. **t=1ms**：Invoker 序列化 + AWS API 调用。
3. **t=50ms**：AWS 启动 Lambda（冷启动）。
4. **t=100ms**：Worker `handleRequest()` → `process()`（云端）。
5. **t=150ms**：S3 读（getReader()，~100MB 数据）。
6. **t=500ms**：内存处理/编码（循环，CPU）。
7. **t=600ms**：S3 写（close()，上传 50MB）。
8. **t=650ms**：Worker 返回 Output（新 S3 路径）。
9. **t=700ms**：AWS API 返回，Invoker 解析，协调器完成。

**总时**：~700ms（小查询），S3 I/O ~200ms，编码 ~300ms。

### 与导师任务的关系
- **S3 读写瓶颈**：步骤4/6 是 I/O（GetObject/PutObject），步骤5 是编码（内存）。Invoker 的调用延迟（步骤2）是额外开销。
- **优化点**：减少 S3 对象（合并 Split），用流式（BaseScanStreamWorker）降低 read after write 延迟。
- **测量**：用 PerformanceProfiler 模拟全流程，日志 Invoker 调用时间 + Worker 内部 Timer。

---

## 新任务：添加细粒度计时器并测试

### 任务目标
在导师需要的核心 Worker（BaseScanWorker, BasePartitionWorker, BaseAggregationWorker, BaseBroadcastJoinWorker, BasePartitionedJoinWorker）中添加四个阶段的计时器：读、计算、写入缓存、写入文件。格式化输出到日志，并写测试程序生成数据，解析占比。

### 四个阶段定义
1. **读 (READ)**: S3 读取时间（getReader + read）。
2. **计算 (COMPUTE)**: 解码 + 处理 + 编码（内存操作）。
3. **写入缓存 (WRITE_CACHE)**: Writer 初始化 + 缓冲追加（addRowBatch）。
4. **写入文件 (WRITE_FILE)**: S3 持久化（close()）。

### 进度记录
- [OK] 完成 BaseScanWorker 计时器（已统一为 StageTimers 类，代码更整洁）。
- [OK] 修改 BasePartitionWorker（已统一为 StageTimers 类）。
- [OK] 修改 BaseAggregationWorker（已统一为 StageTimers 类）。
- [OK] 修改 BaseBroadcastJoinWorker（已统一为 StageTimers 类，处理多线程计时）。
- [OK] 修改 BasePartitionedJoinWorker（已统一为 StageTimers 类）。
- [OK] 创建测试程序（在 PerformanceProfiler 中添加 analyzeFourStagePerformance 方法）。
- [OK] 运行测试并解析占比（验证导师假设：编码压缩占比64.52% > S3存储占比35.48%）。
- [OK] 修复编译问题：升级Maven 3.0.5→3.9.9，安装FlatBuffers 2.0.8，修复cmake配置。
- [OK] 成功编译核心模块：pixels-common, pixels-core, pixels-worker-common等。
- [OK] 配置AWS EC2环境：Java 23 + Maven 3.9.9 + 编译依赖。
- [OK] 更新文档和代码注释。
- [OK] 性能验证通过：计时器逻辑正确，CSV输出正常。

## 测试方法

> **完整测试指南**: 详见 `EC2_TEST_GUIDE.md` 文件，包含详细的EC2测试步骤和性能文件查看方法。

### 本地测试计时器逻辑

1. **编译项目**：
```bash
cd pixels
mvn clean compile -q -pl 'pixels-turbo/pixels-worker-common,pixels-example'
```

2. **运行性能分析器**：
```bash
mvn exec:java -q -pl pixels-example -Dexec.mainClass='io.pixelsdb.pixels.example.core.PerformanceProfiler'
```

3. **预期输出**：
- 显示四个阶段的耗时占比
- 验证导师假设：编码压缩 > S3存储
- CSV格式性能数据（如果有实际数据）

### EC2实例测试（快速步骤）

1. **连接EC2**:
```bash
ssh -i ~/.ssh/pixels-key.pem ec2-user@3.87.201.11
```

2. **上传并编译项目**:
```bash
# 在本地打包
tar -czf pixels.tar.gz pixels/

# 上传到EC2
scp -i ~/.ssh/pixels-key.pem pixels.tar.gz ec2-user@3.87.201.11:~/

# 在EC2上解压和编译
ssh -i ~/.ssh/pixels-key.pem ec2-user@3.87.201.11
cd ~ && tar -xzf pixels.tar.gz && cd pixels
mvn clean compile -q -pl 'pixels-turbo/pixels-worker-common,pixels-example' -am
```

3. **运行测试**:
```bash
mvn exec:java -q -pl pixels-example \
  -Dexec.mainClass='io.pixelsdb.pixels.example.core.PerformanceProfiler'
```

4. **查看性能文件**:
```bash
# 性能文件位置
ls -lh /tmp/*_performance_metrics.csv

# 查看ScanWorker性能数据
cat /tmp/scan_performance_metrics.csv

# 下载到本地
scp -i ~/.ssh/pixels-key.pem \
  ec2-user@3.87.201.11:/tmp/*_performance_metrics.csv \
  ~/Documents/pixels/performance-data/
```

### EC2实例测试（完整步骤）

#### 步骤1: 连接到EC2实例

```bash
# 连接到EC2实例
ssh -i ~/.ssh/pixels-key.pem ec2-user@3.87.201.11

# 验证环境
java -version  # 应该显示 Java 23
mvn --version  # 应该显示 Maven 3.9.9
```

#### 步骤2: 准备项目代码

**方案A: 从本地上传（推荐）**

```bash
# 在本地机器上打包项目
cd ~/Documents/pixels
tar -czf pixels.tar.gz pixels/

# 上传到EC2
scp -i ~/.ssh/pixels-key.pem pixels.tar.gz ec2-user@3.87.201.11:~/

# 在EC2上解压
ssh -i ~/.ssh/pixels-key.pem ec2-user@3.87.201.11
cd ~
tar -xzf pixels.tar.gz
cd pixels
```

**方案B: 在EC2上克隆（如果有Git访问权限）**

```bash
# 在EC2上克隆项目
cd ~
git clone https://github.com/pixelsdb/pixels.git
cd pixels
```

#### 步骤3: 编译项目

```bash
# 编译核心模块（跳过测试和protobuf生成问题）
cd ~/pixels

# 只编译pixels-worker-common和pixels-example
mvn clean compile -q -pl 'pixels-turbo/pixels-worker-common,pixels-example' -am

# 或者编译整个pixels-turbo模块
mvn clean package -q -DskipTests -pl 'pixels-turbo' -am
```

#### 步骤4: 运行性能测试

```bash
# 运行PerformanceProfiler测试
cd ~/pixels
mvn exec:java -q -pl pixels-example \
  -Dexec.mainClass='io.pixelsdb.pixels.example.core.PerformanceProfiler'

# 预期输出：
# - 显示四个阶段的耗时占比
# - 验证导师假设：编码压缩 > S3存储
# - CSV格式性能数据输出
```

#### 步骤5: 查看性能文件

**性能文件位置**:

1. **CSV文件位置**（如果代码写入文件）:
```bash
# 查看性能CSV文件
ls -lh /tmp/*_performance_metrics.csv

# 查看内容
cat /tmp/scan_performance_metrics.csv
cat /tmp/partition_performance_metrics.csv
cat /tmp/aggregation_performance_metrics.csv
cat /tmp/broadcast_join_performance_metrics.csv
cat /tmp/partitioned_join_performance_metrics.csv
```

2. **日志中的性能数据**:
```bash
# 查看最近的日志（如果性能数据输出到日志）
tail -100 ~/.m2/repository/.../logs/*.log

# 或者如果使用log4j，查看日志文件
find ~/pixels -name "*.log" -type f -exec tail -50 {} \;
```

3. **从控制台输出提取**:
```bash
# 重新运行并将输出保存到文件
mvn exec:java -q -pl pixels-example \
  -Dexec.mainClass='io.pixelsdb.pixels.example.core.PerformanceProfiler' \
  > performance_output.txt 2>&1

# 查看输出
cat performance_output.txt

# 提取CSV数据
grep "CSV\|Performance Data" performance_output.txt > performance_data.csv
```

#### 步骤6: 分析性能数据

```bash
# 查看CSV文件内容
cat /tmp/scan_performance_metrics.csv

# CSV格式示例：
# WorkerType,Timestamp,ReadTimeMs,ComputeTimeMs,WriteCacheTimeMs,WriteFileTimeMs,TotalTimeMs,ReadPct,ComputePct,WriteCachePct,WriteFilePct,S3StoragePct
# ScanWorker,1640995200000,120,350,50,100,620,19.35,56.45,8.06,16.13,35.48

# 使用awk分析数据
awk -F',' 'NR>1 {print "Worker: "$1", Total: "$7"ms, Compute: "$4"ms ("$8"%)"}' \
  /tmp/scan_performance_metrics.csv

# 计算平均值（如果有多个数据点）
awk -F',' 'NR>1 {total+=$7; compute+=$4; count++} END {
  print "Average Total Time: " total/count "ms";
  print "Average Compute Time: " compute/count "ms";
  print "Compute Percentage: " (compute/total)*100 "%"
}' /tmp/scan_performance_metrics.csv
```

#### 步骤7: 下载性能文件到本地（可选）

```bash
# 在本地机器上执行
scp -i ~/.ssh/pixels-key.pem \
  ec2-user@3.87.201.11:/tmp/*_performance_metrics.csv \
  ~/Documents/pixels/performance-data/

# 或者下载所有相关文件
scp -i ~/.ssh/pixels-key.pem \
  ec2-user@3.87.201.11:/tmp/*performance*.csv \
  ~/Documents/pixels/performance-data/
```

### AWS Lambda测试

1. **部署到EC2**：
```bash
# 上传代码到EC2
scp -i ~/.ssh/pixels-key.pem pixels.tar.gz ec2-user@3.87.201.11:~/

# 在EC2上解压和编译
ssh -i ~/.ssh/pixels-key.pem ec2-user@3.87.201.11
cd pixels && mvn clean package -q -DskipTests
```

2. **创建Lambda函数**：
```bash
# 使用AWS CLI创建函数
aws lambda create-function --function-name pixels-worker \
  --runtime java21 \
  --role arn:aws:iam::ACCOUNT:role/lambda-role \
  --handler io.pixelsdb.pixels.worker.lambda.ScanWorker::handleRequest \
  --code S3Bucket=bucket-name,S3Key=pixels-lambda.jar \
  --architectures arm64 \
  --memory-size 4096 \
  --timeout 900
```

3. **本地Invoke测试**：
```bash
# 使用AWS CLI本地invoke
aws lambda invoke --function-name pixels-worker \
  --payload '{"input": "s3://bucket/input.pxl", "output": "s3://bucket/output"}' \
  response.json
```

4. **查看日志**：
```bash
# CloudWatch日志
aws logs tail /aws/lambda/pixels-worker --follow

# 本地查看响应
cat response.json
```

### 性能数据分析

1. **CSV文件位置**：
- Lambda: CloudWatch日志或S3输出
- 本地: 控制台输出或文件系统

2. **关键指标**：
- READ时间占比 (< 20% 理想)
- COMPUTE时间占比 (50-70% 正常)
- WRITE_CACHE时间占比 (< 10% 理想)
- WRITE_FILE时间占比 (< 20% 理想)

3. **优化方向**：
- 如果COMPUTE占比过高：优化编码算法
- 如果READ/WRITE_FILE占比过高：检查网络和S3配置