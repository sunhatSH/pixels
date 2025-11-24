# RetinaService Initialization Failure in AWS Lambda Environment

## Problem Description

When running Pixels Scan Worker in AWS Lambda environment, `RetinaService` fails during static initialization phase, causing the entire scan operation to fail.

## Error Message

```
java.lang.ExceptionInInitializerError
	at io.pixelsdb.pixels.core.reader.PixelsRecordReaderImpl.<init>(PixelsRecordReaderImpl.java:60)
	at io.pixelsdb.pixels.core.PixelsReaderImpl.read(PixelsReaderImpl.java:249)
	at io.pixelsdb.pixels.worker.common.BaseScanWorker.scanFile(BaseScanWorker.java:281)
	at io.pixelsdb.pixels.worker.common.BaseScanWorker.lambda$process$0(BaseScanWorker.java:164)
	at java.util.concurrent.ThreadPoolExecutor.runWorker(Unknown Source)
	at java.util.concurrent.ThreadPoolExecutor$Worker.run(Unknown Source)
	at java.lang.Thread.run(Unknown Source)

Caused by: java.lang.IllegalArgumentException: Address types of NameResolver 'unix' for 'localhost:18890' not supported by transport
	at io.grpc.internal.ManagedChannelImplBuilder.getNameResolverProvider(ManagedChannelImplBuilder.java:869)
	at io.grpc.internal.ManagedChannelImplBuilder.build(ManagedChannelImplBuilder.java:721)
	at io.grpc.ForwardingChannelBuilder2.build(ForwardingChannelBuilder2.java:278)
	at io.pixelsdb.pixels.common.retina.RetinaService.<init>(RetinaService.java:112)
	at io.pixelsdb.pixels.common.retina.RetinaService.<clinit>(RetinaService.java:54)
	at io.pixelsdb.pixels.core.reader.PixelsRecordReaderImpl.<init>(PixelsRecordReaderImpl.java:60)
```

## Root Cause

1. **Static Initialization Issue**: `RetinaService` attempts to create a gRPC connection to Retina server in the static initialization block (`<clinit>`)
2. **Configuration Issue**: The configured Retina server address is `localhost:18890`, but there is no Retina server running in the Lambda environment
3. **gRPC Limitation**: gRPC attempts to use 'unix' NameResolver in Lambda environment, but the transport layer in this environment does not support this address type
4. **Initialization Timing**: The error occurs when `PixelsRecordReaderImpl` constructor calls `RetinaService.Instance()`

## Related Code Locations

- `RetinaService.java:54` - Static initialization block, creates default instance
- `RetinaService.java:112` - Constructor, creates gRPC ManagedChannel
- `PixelsRecordReaderImpl.java:60` - Calls `RetinaService.Instance()`

## Environment Information

- **Runtime Environment**: AWS Lambda
- **Runtime**: Java 21
- **Region**: us-east-2
- **Function**: pixels-scan-worker
- **Memory**: 4096 MB
- **Configuration**: `retina.server.host=localhost`, `retina.server.port=18890` in `pixels.properties`

## Reproduction Steps

1. Deploy Pixels Worker to AWS Lambda
2. Execute scan operation, calling `PixelsReaderImpl.read()`
3. Trigger `RetinaService` static initialization when creating `PixelsRecordReaderImpl`
4. gRPC attempts to connect to `localhost:18890` and fails

## 影响

- **严重性**: 高 - 导致所有扫描操作失败
- **影响范围**: 所有在 Lambda 环境中使用 `PixelsRecordReaderImpl` 的操作
- **性能指标**: 由于扫描失败，所有性能指标为 0

## 预期行为

在 Lambda 环境中，如果 Retina 服务器不可用，应该：
1. 优雅地处理初始化失败
2. 允许扫描操作继续进行（不使用 visibility query）
3. 记录警告而不是抛出异常

## 建议解决方案

### 方案 1: 延迟初始化 RetinaService（推荐）

将 `RetinaService` 从静态初始化改为延迟初始化，只在需要时（且仅在 `hasValidTransTimestamp()` 为 true 时）才尝试初始化。

**优点**: 
- 不影响不需要 visibility query 的场景
- 可以优雅地处理初始化失败

**缺点**: 
- 需要修改代码

### 方案 2: 配置禁用 RetinaService

添加配置选项来禁用 RetinaService 的初始化。

**优点**: 
- 简单直接
- 不需要修改业务逻辑

**缺点**: 
- 需要添加新的配置项

### 方案 3: 异常处理

在 `RetinaService` 的静态初始化块中捕获异常，记录警告但不抛出。

**优点**: 
- 修改最小
- 向后兼容

**缺点**: 
- 如果初始化失败，`RetinaService.Instance()` 返回 null，需要在使用处处理

### 方案 4: 使用 Lambda Layer 配置

通过 Lambda Layer 提供正确的 `pixels.properties` 配置，但此方案已尝试过，问题仍然存在（gRPC 不支持 'unix' NameResolver）。

## 当前状态

- Lambda 函数可以执行，但扫描过程在初始化阶段失败
- 性能指标全为 0（因为扫描未实际执行）
- 错误被捕获但导致整个扫描操作失败

## 相关文件

- `pixels-common/src/main/java/io/pixelsdb/pixels/common/retina/RetinaService.java`
- `pixels-core/src/main/java/io/pixelsdb/pixels/core/reader/PixelsRecordReaderImpl.java`
- `pixels-common/src/main/resources/pixels.properties`

## 附加信息

- 完整的错误日志已保存在 `retina_error_log.txt`
- 测试环境：Lambda 函数 `pixels-scan-worker` 在 `us-east-2` 区域
- 测试文件：`s3://home-sunhao/test-data/example.pxl` (790 bytes)

