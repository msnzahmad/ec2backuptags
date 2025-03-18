provider "aws" {
  region  = "ap-southeast-2"
  profile = "AWS-OU-ALL-Admin-199988137734"
}

resource "aws_iam_role" "MSEventbridgeRole" {
  name               = "MSEventbridgeRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = ["events.amazonaws.com"] }
        Action   = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "MSEventbridgeRolePolicy" {
  name   = "MSEventbridgeRolePolicy"
  role   = aws_iam_role.MSEventbridgeRole.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.MSEC2BackupTagManager.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "LambdaExecutionRole" {
  name               = "LambdaExecutionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = ["lambda.amazonaws.com"] }
        Action   = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "LambdaExecutionPolicy" {
  name   = "LambdaExecutionPolicy"
  role   = aws_iam_role.LambdaExecutionRole.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "MSEC2BackupTagManager" {
  function_name = "MSEC2BackupTagManager"
  role          = aws_iam_role.LambdaExecutionRole.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  filename      = "../lambda/lambda_function.zip"
  timeout       = 300
}

resource "aws_cloudwatch_event_rule" "EventBridgeRule" {
  name          = "EC2StateChangeRule"
  event_pattern = <<EOF
{
  "source": ["aws.ec2"],
  "detail-type": ["EC2 Instance State-change Notification"],
  "detail": {
    "state": ["running", "stopped", "stopping"]
  }
}
EOF
}

resource "aws_cloudwatch_event_target" "EventBridgeTarget" {
  rule      = aws_cloudwatch_event_rule.EventBridgeRule.name
  target_id = "TargetLambda"
  arn       = aws_lambda_function.MSEC2BackupTagManager.arn
  role_arn  = aws_iam_role.MSEventbridgeRole.arn
}

resource "aws_lambda_permission" "EventBridgeInvokePermission" {
  function_name = aws_lambda_function.MSEC2BackupTagManager.function_name
  action        = "lambda:InvokeFunction"
  principal     = "events.amazonaws.com"
  statement_id  = "AllowEventBridgeInvoke"
}
