# S3 权限问题修复指南

## 问题描述

Lambda 函数执行时遇到错误：
```
Failed to initiate multipart upload.
User: arn:aws:sts::970089764833:assumed-role/PixelsLambdaRole/pixels-partitionworker 
is not authorized to perform: s3:PutObject on resource: "arn:aws:s3:::home-sunhao/output/"
```

**原因**：`PixelsLambdaRole` 缺少写入 `home-sunhao` S3 桶的权限。

## 当前权限状态

Lambda 角色当前有以下 S3 权限：
- ✅ `pixels-turbo-intermediate` 桶：完全权限（s3:*）
- ✅ `home-wenbo` 桶：完全权限（s3:*）
- ✅ `home-sunhao` 桶：**只读权限**（AmazonS3ReadOnlyAccess）
- ❌ `home-sunhao` 桶：**缺少写入权限**

## 解决方案

### 方案 1：添加 IAM 策略（推荐）

为 `PixelsLambdaRole` 添加内联策略，允许写入 `home-sunhao` 桶：

#### 步骤

1. 登录 [AWS IAM 控制台](https://console.aws.amazon.com/iam/)
2. 导航到 **Roles** → **PixelsLambdaRole**
3. 点击 **Add permissions** → **Create inline policy**
4. 选择 **JSON** 标签
5. 粘贴以下策略文档：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3WriteToHomeSunhao",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:GetObject",
        "s3:GetObjectAcl",
        "s3:DeleteObject",
        "s3:CreateMultipartUpload",
        "s3:UploadPart",
        "s3:CompleteMultipartUpload",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ],
      "Resource": [
        "arn:aws:s3:::home-sunhao/*"
      ]
    },
    {
      "Sid": "AllowS3ListBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::home-sunhao"
      ]
    }
  ]
}
```

6. 策略名称：`PixelsSunhaoS3Write`
7. 点击 **Create policy**

#### 所需权限说明

| 权限 | 用途 |
|------|------|
| `s3:PutObject` | 写入单个对象（小文件） |
| `s3:CreateMultipartUpload` | 启动分片上传（大文件） |
| `s3:UploadPart` | 上传分片 |
| `s3:CompleteMultipartUpload` | 完成分片上传 |
| `s3:AbortMultipartUpload` | 取消分片上传 |
| `s3:ListBucket` | 列出桶内容 |

### 方案 2：使用已有权限的桶（临时方案）

我已经将测试脚本的输出路径修改为 `pixels-turbo-intermediate/output/`，这样可以使用已有的写入权限。

**注意**：如果选择此方案，测试结果会写入到 `pixels-turbo-intermediate` 桶而不是 `home-sunhao` 桶。

## 验证修复

修复后，重新运行测试脚本：

```bash
./test-all-workers-performance.sh
```

如果权限已正确配置，应该不再出现 "Failed to initiate multipart upload" 错误。

## 相关文件

- `fix-s3-permissions.sh` - 自动修复脚本（需要 IAM 管理员权限）
- `test-all-workers-performance.sh` - 测试脚本（已临时修改为使用 `pixels-turbo-intermediate` 桶）

