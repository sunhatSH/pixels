#!/bin/bash

# 修复 Lambda 角色的 S3 写入权限
# 允许写入 home-sunhao 桶的 output/ 路径

set -e

REGION="us-east-2"
ROLE_NAME="PixelsLambdaRole"
POLICY_NAME="PixelsSunhaoS3Write"
BUCKET_NAME="home-sunhao"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "修复 Lambda 角色的 S3 写入权限"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 创建策略文档
POLICY_DOC=$(cat <<EOF
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
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ]
    },
    {
      "Sid": "AllowS3ListBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}"
      ]
    }
  ]
}
EOF
)

# 检查策略是否已存在
if aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo "ℹ️  策略 $POLICY_NAME 已存在，正在更新..."
    echo "$POLICY_DOC" > /tmp/policy.json
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/policy.json \
        --region "$REGION"
    echo "✅ 策略已更新"
else
    echo "ℹ️  创建新策略 $POLICY_NAME..."
    echo "$POLICY_DOC" > /tmp/policy.json
    aws iam put-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/policy.json \
        --region "$REGION"
    echo "✅ 策略已创建"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ S3 权限修复完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "已添加的权限："
echo "  - s3:PutObject"
echo "  - s3:CreateMultipartUpload"
echo "  - s3:UploadPart"
echo "  - s3:CompleteMultipartUpload"
echo "  - s3:AbortMultipartUpload"
echo "  - s3:ListBucket"
echo ""
echo "允许的路径："
echo "  - arn:aws:s3:::${BUCKET_NAME}/*"
echo ""
echo "现在可以重新运行测试了！"

