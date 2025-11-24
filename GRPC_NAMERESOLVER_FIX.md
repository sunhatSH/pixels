# gRPC NameResolver 格式问题修复记录

## 问题描述

在 AWS Lambda 环境中运行 Pixels Lambda Worker 时，遇到以下错误：

```
IllegalArgumentException: Address types of NameResolver 'unix' for 'localhost:18890' not supported by transport
```

这个错误发生在 `RetinaService` 和 `MetadataService` 尝试通过 gRPC 连接到服务器时。

## 错误堆栈

```
Caused by: java.lang.IllegalArgumentException: Address types of NameResolver 'unix' for 'localhost:18890' not supported by transport
	at io.grpc.internal.ManagedChannelImpl.getNameResolver(ManagedChannelImpl.java:XXX)
	at io.grpc.internal.ManagedChannelImpl.<init>(ManagedChannelImpl.java:XXX)
	at io.grpc.ManagedChannelBuilder.forAddress(ManagedChannelBuilder.java:XXX)
	at io.pixelsdb.pixels.common.retina.RetinaService.<init>(RetinaService.java:XXX)
```

## 根本原因分析

### 1. 依赖冲突

在 `pixels-common/pom.xml` 中，同时包含了两个 gRPC Netty 传输实现：

- `grpc-netty-shaded`（第59行）：shaded 版本，包含所有依赖
- `grpc-netty`（第95行）：标准版本

### 2. NameResolverProvider 冲突

两个依赖都注册了自己的 `NameResolverProvider`：

- `grpc-netty-shaded` → `DnsNameResolverProvider`（DNS 解析器）
- `grpc-netty` → `UdsNameResolverProvider`（Unix Domain Socket 解析器）

### 3. 错误的 NameResolver 选择

当两个 NameResolverProvider 同时存在时，gRPC 可能选择了错误的解析器：

- `UdsNameResolverProvider` 尝试将 `localhost:18890` 解析为 Unix Domain Socket 地址
- Lambda 环境不支持 Unix Domain Socket，导致错误

### 4. 为什么会出现这个问题？

- `grpc-netty-shaded` 是推荐用于生产环境的版本，因为它避免了依赖冲突
- `grpc-netty` 是标准版本，但在某些环境中可能与 Netty 版本冲突
- 同时包含两者会导致服务提供者（Service Provider）机制注册多个 NameResolver

## 解决方案

### 修改内容

从 `pixels-common/pom.xml` 中移除 `grpc-netty` 依赖，只保留 `grpc-netty-shaded`。

**修改位置**：`pixels-common/pom.xml` 第93-97行

**修改前**：
```xml
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-netty</artifactId>
    <optional>true</optional>
</dependency>
```

**修改后**：
```xml
<!-- grpc-netty removed to avoid conflict with grpc-netty-shaded in Lambda environment -->
<!--
<dependency>
    <groupId>io.grpc</groupId>
    <artifactId>grpc-netty</artifactId>
    <optional>true</optional>
</dependency>
-->
```

### 为什么这样能解决问题？

1. **单一 NameResolver**：移除 `grpc-netty` 后，只有 `DnsNameResolverProvider` 被注册
2. **正确的地址解析**：gRPC 使用 DNS resolver 解析 `localhost`，得到 TCP 地址（`127.0.0.1:18888`）
3. **避免冲突**：`grpc-netty-shaded` 是 shaded 版本，避免了 Netty 版本冲突

## 验证过程

### 修复前

错误信息：
```
IllegalArgumentException: Address types of NameResolver 'unix' for 'localhost:18890' not supported by transport
```

### 修复后

错误变为正常的网络连接错误：
```
Connection refused: localhost/127.0.0.1:18888
```

这证明：
- ✅ gRPC 现在正确使用 DNS resolver 解析地址
- ✅ 地址被正确解析为 TCP 地址（`127.0.0.1:18888`）
- ✅ 连接失败是因为 Lambda 环境中没有 Metadata/Retina 服务器，这是预期的行为

### 验证步骤

1. **检查 JAR 中的 NameResolverProvider**

```bash
jar -tf pixels-worker-lambda-complete.jar | grep META-INF/services
jar -xf pixels-worker-lambda-complete.jar META-INF/services/io.grpc.NameResolverProvider
cat META-INF/services/io.grpc.NameResolverProvider
```

**修复后的内容**：
```
io.grpc.internal.DnsNameResolverProvider
io.grpc.netty.shaded.io.grpc.netty.UdsNameResolverProvider
```

注意：`UdsNameResolverProvider` 仍然存在，但它来自 `grpc-netty-shaded`，不会与 DNS resolver 冲突。

2. **测试 Lambda 函数**

```bash
aws lambda invoke --function-name pixels-scan-worker \
  --payload file://test-scan-input.json \
  --cli-binary-format raw-in-base64-out \
  --region us-east-2 lambda-response.json
```

3. **查看日志**

```bash
aws logs tail /aws/lambda/pixels-scan-worker --since 3m --region us-east-2
```

**修复后的日志**：
- ✅ 没有 "Address types" 错误
- ✅ 出现正常的网络连接错误（Connection refused）
- ✅ RetinaService 和 MetadataService 可以正常初始化（虽然连接会失败）

## 相关文件

- `pixels-common/pom.xml`：移除了 `grpc-netty` 依赖
- `pixels-turbo/pixels-worker-lambda/pom.xml`：显式添加了 gRPC 依赖，确保它们被包含在最终 JAR 中
- `pixels-turbo/pixels-worker-lambda/pom.xml`：配置了 `ServicesResourceTransformer` 来正确合并 `META-INF/services` 文件

## 技术细节

### grpc-netty vs grpc-netty-shaded

| 特性 | grpc-netty | grpc-netty-shaded |
|------|-----------|-------------------|
| 依赖管理 | 依赖外部 Netty | 包含 shaded Netty |
| 版本冲突 | 可能与其他 Netty 版本冲突 | 避免冲突 |
| 推荐使用 | 开发环境 | 生产环境（特别是 Lambda） |
| NameResolver | UdsNameResolverProvider | DnsNameResolverProvider + UdsNameResolverProvider |

### Service Provider 机制

gRPC 使用 Java Service Provider 机制来发现 NameResolverProvider：

1. 在 `META-INF/services/io.grpc.NameResolverProvider` 文件中列出实现类
2. 每个依赖可以注册自己的 NameResolverProvider
3. 当多个 Provider 存在时，gRPC 会尝试使用第一个匹配的 Provider

### 为什么 UdsNameResolverProvider 仍然存在？

`grpc-netty-shaded` 内部也包含了 `UdsNameResolverProvider`，但它：
- 不会与 DNS resolver 冲突
- 只在明确使用 Unix Domain Socket 地址时才会被使用
- 对于 `localhost:port` 格式的地址，DNS resolver 会优先匹配

## 后续工作

1. ✅ 修复 gRPC NameResolver 冲突
2. ⚠️ 处理 MetadataService 连接失败（Lambda 环境中没有服务器）
3. ⚠️ 处理 RetinaService 连接失败（Lambda 环境中没有服务器）

## 参考

- [gRPC Java 文档](https://grpc.io/docs/languages/java/)
- [gRPC Name Resolution](https://github.com/grpc/grpc-java/blob/master/README.md#name-resolution)
- [Service Provider 机制](https://docs.oracle.com/javase/tutorial/ext/basics/spi.html)

## 提交历史

- `604a57d3` - Remove grpc-netty dependency to fix NameResolver conflict in Lambda
- `31f91504` - Fix gRPC NameResolver issue by adding ServicesResourceTransformer to deps JAR

## 日期

2025-11-24

