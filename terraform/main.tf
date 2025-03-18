resource "aws_iam_role" "MSEventbridgeRole" {
  name               = "MSEventbridgeRole"
  assume_role_policy = jsonencode({
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

resource "aws_iam_role" "LambdaExecutionRole" {
  name               = "LambdaExecutionRole"
  assume_role_policy = jsonencode({
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

# Define the policy separately and attach it using aws_iam_role_policy
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

resource "aws_lambda_function" "MSEC2BackupTagManager" {
  function_name = "MSEC2BackupTagManager"
  role          = aws_iam_role.LambdaExecutionRole.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  filename      = "C:\\Users\\ahassan\\OneDrive - MetService\\Desktop\\MetService\\AWS\\ms-terraform\\Terraform\\ec2tagchange\\lambda_function.zip"
  timeout       = 300
}

resource "aws_cloudwatch_log_group" "LambdaLogGroup" {
  name              = "/aws/lambda/MSEC2BackupTagManager"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "EventBridgeLogGroup" {
  name              = "/aws/events/EC2StateChangeRule"
  retention_in_days = 30
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

  depends_on = [
    aws_iam_role.MSEventbridgeRole,
    aws_lambda_function.MSEC2BackupTagManager
  ]
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
