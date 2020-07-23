resource "aws_s3_bucket" "main" {
  bucket = "hello-lambda-spring-boot"
  acl    = "private"

  tags = {
    Name    = "hello-lambda-spring-boot"
    env     = "demo"
    system  = "demo"
    project = "https://some.host.com/path/to/project"
  }

  lifecycle_rule {
    id      = "expire"
    enabled = true

    expiration {
      days = 7
    }
  }
}

resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.main.id

  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "IPAllow",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws-us-gov:s3:::${aws_s3_bucket.main.id}/*",
            "Condition": {
                "IpAddress": {
                    "aws:SourceIp": [
                        "72.165.233.64/27",
                        "50.236.178.192/27",
                        "192.16.76.1/22"
                    ]
                }
            }
        }
    ]
}
POLICY
}

resource "aws_iam_policy" "s3" {
  name = "hello-extracts-s3"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ExampleStmt",
      "Action": [
        "s3:*"
      ],
      "Effect": "Allow",
      "Resource": [
        "arn:aws-us-gov:s3:::${aws_s3_bucket.main.bucket}/*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "s3" {
  policy_arn = aws_iam_policy.s3.arn
  role       = aws_iam_role.iam_for_lambda_hello_lambda_spring_boot.name
}
