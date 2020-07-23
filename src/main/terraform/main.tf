terraform {
  backend "s3" {
    bucket = "bucket-name-for-state"
    key    = "hello-lambda-spring-boot/terraform.tfstate"
    region = "aws-region-of-choice"
  }

  # keep this in sync with the image tag in .gitlab-ci.yml
  required_version = "~> 0.12.28"

  required_providers {
    aws = "~> 2.69"
    dns = "~> 2.2"
  }
}

provider "aws" {
  region = "aws-region-of-choice"
}

provider "dns" {
  update {
    server = "10.1.1.30"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "iam_for_lambda_hello_lambda_spring_boot" {
  name                 = "iam_for_lambda_hello_lambda_spring_boot"
  path                 = "/team-roles/"
  permissions_boundary = "arn:aws-us-gov:iam::${data.aws_caller_identity.current.account_id}:policy/ServiceBoundary"
  assume_role_policy   = <<EOF
{
                          "Version": "2012-10-17",
                          "Statement": [
                            {
                              "Action": "sts:AssumeRole",
                              "Principal": {
                                "Service": "lambda.amazonaws.com"
                              },
                              "Effect": "Allow",
                              "Sid": ""
                            }
                          ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "iam_attachment" {
  policy_arn = "arn:aws-us-gov:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.iam_for_lambda_hello_lambda_spring_boot.name
}

data "aws_subnet" "subnet_name" {
  tags = {
    Name = "some_private_subnet"
  }
}

# TODO make this more restrictive
resource "aws_security_group" "main" {
  name   = "hello-lambda-spring-boot"
  vpc_id = data.aws_subnet.subnet_name.vpc_id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
    "0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = [
    "0.0.0.0/0"]
  }

  tags = {
    Name = "hello-lambda-spring-boot"
    # TODO add system and env tags (to all resources)
  }
}

locals {
  lambda_filepath = "${path.module}/../../../target/hello-lambda-spring-boot-1.0-SNAPSHOT.jar"
}

resource "aws_lambda_function" "lambda_hello_lambda_spring_boot" {
  filename      = local.lambda_filepath
  function_name = "lambda_hello_lambda_spring_boot"
  role          = aws_iam_role.iam_for_lambda_hello_lambda_spring_boot.arn
  handler       = "example.Handler::handleRequest"
  runtime       = "java8"
  timeout       = 900
  memory_size   = 3000

  source_code_hash = filebase64sha256(local.lambda_filepath)

  vpc_config {
    subnet_ids = [
    data.aws_subnet.subnet_name.id]
    security_group_ids = [
    aws_security_group.main.id]
  }

  environment {
    variables = {
      SPRING_DATASOURCE_URL      = var.DB_URL
      SPRING_DATASOURCE_USERNAME = var.DB_USERNAME
      SPRING_DATASOURCE_PASSWORD = var.DB_PASSWORD
      S3_BUCKET_NAME             = aws_s3_bucket.main.bucket
    }
  }
}

resource "aws_vpc_endpoint" "vpce" {
  vpc_endpoint_type = "Interface"
  service_name      = "com.amazonaws.aws-region-of-choice.execute-api"
  vpc_id            = data.aws_subnet.subnet_name.vpc_id
  security_group_ids = [
  aws_security_group.main.id]
  subnet_ids = [
  data.aws_subnet.subnet_name.id]
}

resource "aws_api_gateway_rest_api" "gateway" {
  name   = "gateway"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": "*",
            "Action": "execute-api:Invoke",
            "Resource": [
                "execute-api:/*"
            ]
        },
        {
            "Effect": "Deny",
            "Principal": "*",
            "Action": "execute-api:Invoke",
            "Resource": [
                "execute-api:/*"
            ],
            "Condition" : {
                "StringNotEquals": {
                   "aws:SourceVpc": "${data.aws_subnet.subnet_name.vpc_id}"
                }
            }
        }
    ]
}
EOF

  endpoint_configuration {
    types = [
    "PRIVATE"]
    vpc_endpoint_ids = [
    aws_vpc_endpoint.vpce.id]
  }
}

resource "aws_api_gateway_resource" "proxy" {
  parent_id   = aws_api_gateway_rest_api.gateway.root_resource_id
  path_part   = "{proxy+}"
  rest_api_id = aws_api_gateway_rest_api.gateway.id
}

resource "aws_api_gateway_method" "proxy" {
  http_method   = "ANY"
  resource_id   = aws_api_gateway_resource.proxy.id
  rest_api_id   = aws_api_gateway_rest_api.gateway.id
  authorization = ""
}

resource "aws_api_gateway_integration" "gateway_lambda_integration" {
  http_method             = aws_api_gateway_method.proxy.http_method
  resource_id             = aws_api_gateway_method.proxy.resource_id
  rest_api_id             = aws_api_gateway_rest_api.gateway.id
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.lambda_hello_lambda_spring_boot.invoke_arn
  passthrough_behavior    = "WHEN_NO_MATCH"
  request_templates = {
    "application/json" = <<REQUEST_TEMPLATE
{
  "body" : $input.json('$'),
  "headers": {
    #foreach($param in $input.params().header.keySet())
    "$param": "$util.escapeJavaScript($input.params().header.get($param))" #if($foreach.hasNext),#end

    #end
  },
  "stage" : "$context.stage"
  }
  REQUEST_TEMPLATE
  }
}

resource "aws_api_gateway_method" "proxy_root" {
  authorization = "NONE"
  http_method   = "ANY"
  resource_id   = aws_api_gateway_rest_api.gateway.root_resource_id
  rest_api_id   = aws_api_gateway_rest_api.gateway.id
}

resource "aws_api_gateway_integration" "lambda_root" {
  http_method             = aws_api_gateway_method.proxy_root.http_method
  resource_id             = aws_api_gateway_method.proxy_root.resource_id
  rest_api_id             = aws_api_gateway_rest_api.gateway.id
  type                    = "AWS_PROXY"
  integration_http_method = "POST"
  uri                     = aws_lambda_function.lambda_hello_lambda_spring_boot.invoke_arn
  passthrough_behavior    = "WHEN_NO_MATCH"
  request_templates = {
    "application/json" = <<REQUEST_TEMPLATE
{
  "body" : $input.json('$'),
  "headers": {
    #foreach($param in $input.params().header.keySet())
    "$param": "$util.escapeJavaScript($input.params().header.get($param))" #if($foreach.hasNext),#end

    #end
  },
  "stage" : "$context.stage"
  }
  REQUEST_TEMPLATE
  }
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.gateway_lambda_integration,
    aws_api_gateway_integration.lambda_root,
  ]

  rest_api_id = aws_api_gateway_rest_api.gateway.id
  stage_name  = "demo"
}

resource "aws_lambda_permission" "lambda_permission" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_hello_lambda_spring_boot.function_name
  principal     = "apigateway.amazonaws.com"

  # The "/*/*" portion grants access from any method on any resource
  # within the API Gateway REST API.
  source_arn = "${aws_api_gateway_rest_api.gateway.execution_arn}/*/*"
}

resource "dns_cname_record" "lambda_hello_lambda_spring_boot" {
  zone  = "HOST.com."
  name  = "hello-lambda-spring-boot"
  cname = "${aws_api_gateway_rest_api.gateway.id}-${aws_vpc_endpoint.vpce.id}.execute-api.aws-region-of-choice.amazonaws.com."
}

output "endpoint" {
  # Derive the endpoint from the cname.
  # Also set the path to the stage name (e.g. "/demo")
  value = "https://${dns_cname_record.lambda_hello_lambda_spring_boot.name}.HOST.com/${aws_api_gateway_deployment.deployment.stage_name}"
}
