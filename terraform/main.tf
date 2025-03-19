# Check if the MSEventbridgeRole IAM Role exists
data "aws_iam_role" "MSEventbridgeRole" {
  name = "MSEventbridgeRole"
}

resource "aws_iam_role" "MSEventbridgeRole" {
  count               = data.aws_iam_role.MSEventbridgeRole != null ? 0 : 1
  name                = "MSEventbridgeRole"
  assume_role_policy  = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = ["events.amazonaws.com"]
        }
        Action   = "sts:AssumeRole"
      }
    ]
  })
  max_session_duration = 3600
}

# Check if the LambdaExecutionRole IAM Role exists
data "aws_iam_role" "LambdaExecutionRole" {
  name = "LambdaExecutionRole"
}

resource "aws_iam_role" "LambdaExecutionRole" {
  count               = data.aws_iam_role.LambdaExecutionRole != null ? 0 : 1
  name                = "LambdaExecutionRole"
  assume_role_policy  = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = ["lambda.amazonaws.com", "events.amazonaws.com"]
        }
        Action   = "sts:AssumeRole"
      }
    ]
  })
}

# Check if the Lambda Log Group already exists
data "aws_cloudwatch_log_group" "LambdaLogGroup" {
  name = "/aws/lambda/MSEC2BackupTagManager"
}

resource "aws_cloudwatch_log_group" "LambdaLogGroup" {
  count              = data.aws_cloudwatch_log_group.LambdaLogGroup != null ? 0 : 1
  name               = "/aws/lambda/MSEC2BackupTagManager"
  retention_in_days  = 30
}

# Check if the EventBridge Log Group already exists
data "aws_cloudwatch_log_group" "EventBridgeLogGroup" {
  name = "/aws/events/EC2StateChangeRule"
}

resource "aws_cloudwatch_log_group" "EventBridgeLogGroup" {
  count              = data.aws_cloudwatch_log_group.EventBridgeLogGroup != null ? 0 : 1
  name               = "/aws/events/EC2StateChangeRule"
  retention_in_days  = 30
}

# IAM Role Policies for MSEventbridgeRole
resource "aws_iam_role_policy" "MSEventbridgeRolePolicy" {
  count   = data.aws_iam_role.MSEventbridgeRole != null ? 0 : 1
  name    = "MSEventbridgeRolePolicy"
  role    = aws_iam_role.MSEventbridgeRole.id
  policy  = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = aws_lambda_function.MSEC2BackupTagManager.arn
      },
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogGroup"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "logs:CreateLogStream"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "logs:PutLogEvents"
        Resource = "*"
      }
    ]
  })
}

# IAM Role Policies for LambdaExecutionRole
resource "aws_iam_role_policy" "LambdaExecutionPolicy" {
  count   = data.aws_iam_role.LambdaExecutionRole != null ? 0 : 1
  name    = "LambdaExecutionPolicy"
  role    = aws_iam_role.LambdaExecutionRole.id
  policy  = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["backup:ListBackupPlans", "backup:GetBackupPlan", "backup:ListBackupSelections", "backup:GetBackupSelection"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

# Lambda Function
resource "aws_lambda_function" "MSEC2BackupTagManager" {
  function_name = "MSEC2BackupTagManager"
  role          = aws_iam_role.LambdaExecutionRole.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  filename      = "lambda/lambda_function.zip"
  timeout       = 300
}

# EventBridge Rule
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
  depends_on = [
    aws_iam_role.MSEventbridgeRole,
    aws_lambda_function.MSEC2BackupTagManager
  ]
}

# EventBridge Target
resource "aws_cloudwatch_event_target" "EventBridgeTarget" {
  rule      = aws_cloudwatch_event_rule.EventBridgeRule.name
  target_id = "TargetLambda"
  arn       = aws_lambda_function.MSEC2BackupTagManager.arn
  role_arn  = aws_iam_role.MSEventbridgeRole.arn
}

# Lambda Permission for EventBridge
resource "aws_lambda_permission" "EventBridgeInvokePermission" {
  function_name = aws_lambda_function.MSEC2BackupTagManager.function_name
  action        = "lambda:InvokeFunction"
  principal     = "events.amazonaws.com"
  statement_id  = "AllowEventBridgeInvoke"
}
