resource "aws_iam_role" "lambda_role" {
  name = "AutoProcessSQSRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_sqs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
}

resource "aws_lambda_function" "auto_process" {
  function_name    = "AutoProcessEventsQueue"
  role             = aws_iam_role.lambda_role.arn
  runtime          = "python3.11"
  handler          = "lambda_function.lambda_handler"
  filename         = "lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/lambda.zip")
  environment {
    variables = {
      QUEUE_URL = module.events_queue.queue_url
    }
  }
}
