# ---- Lambda zip packages ----
data "archive_file" "websocket_connect" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/websocket-connect"
  output_path = "${path.module}/../lambdas/websocket-connect.zip"
}

data "archive_file" "websocket_disconnect" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/websocket-disconnect"
  output_path = "${path.module}/../lambdas/websocket-disconnect.zip"
}

data "archive_file" "websocket_message" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/websocket-message"
  output_path = "${path.module}/../lambdas/websocket-message.zip"
}

data "archive_file" "canvas_processor" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/canvas-processor"
  output_path = "${path.module}/../lambdas/canvas-processor.zip"
}

data "archive_file" "stream_trigger" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/stream-trigger"
  output_path = "${path.module}/../lambdas/stream-trigger.zip"
}

data "archive_file" "s3_result_handler" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/s3-result-handler"
  output_path = "${path.module}/../lambdas/s3-result-handler.zip"
}

data "archive_file" "s3_products_handler" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/s3-products-handler"
  output_path = "${path.module}/../lambdas/s3-products-handler.zip"
}

data "archive_file" "s3_models_handler" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/s3-models-handler"
  output_path = "${path.module}/../lambdas/s3-models-handler.zip"
}

# ---- WebSocket Connect ----
resource "aws_lambda_function" "websocket_connect" {
  function_name    = "${var.project}-websocket-connect"
  filename         = data.archive_file.websocket_connect.output_path
  source_code_hash = data.archive_file.websocket_connect.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 30
  memory_size      = 128
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      CONNECTIONS_TABLE_NAME = aws_dynamodb_table.connections.name
    }
  }
}

resource "aws_lambda_permission" "apigw_connect" {
  statement_id  = "AllowAPIGatewayInvokeConnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_connect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.websocket.id}/*/*"
}

# ---- WebSocket Disconnect ----
resource "aws_lambda_function" "websocket_disconnect" {
  function_name    = "${var.project}-websocket-disconnect"
  filename         = data.archive_file.websocket_disconnect.output_path
  source_code_hash = data.archive_file.websocket_disconnect.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 30
  memory_size      = 128
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      CONNECTIONS_TABLE_NAME = aws_dynamodb_table.connections.name
    }
  }
}

resource "aws_lambda_permission" "apigw_disconnect" {
  statement_id  = "AllowAPIGatewayInvokeDisconnect"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_disconnect.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.websocket.id}/*/*"
}

# ---- WebSocket Message ----
resource "aws_lambda_function" "websocket_message" {
  function_name    = "${var.project}-websocket-message"
  filename         = data.archive_file.websocket_message.output_path
  source_code_hash = data.archive_file.websocket_message.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 30
  memory_size      = 128
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      CONNECTIONS_TABLE_NAME = aws_dynamodb_table.connections.name
      TABLE_NAME             = aws_dynamodb_table.jobs.name
      PRODUCTS_TABLE_NAME    = aws_dynamodb_table.products.name
      MODELS_TABLE_NAME      = aws_dynamodb_table.models.name
      BUCKET_NAME            = aws_s3_bucket.vto.bucket
      WEBSOCKET_API_ENDPOINT = "wss://${aws_apigatewayv2_api.websocket.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
    }
  }
}

resource "aws_lambda_permission" "apigw_message" {
  statement_id  = "AllowAPIGatewayInvokeMessage"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.websocket_message.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${aws_apigatewayv2_api.websocket.id}/*/*"
}

# ---- Canvas Processor (called by Step Functions) ----
resource "aws_lambda_function" "canvas_processor" {
  function_name    = "${var.project}-canvas-processor"
  filename         = data.archive_file.canvas_processor.output_path
  source_code_hash = data.archive_file.canvas_processor.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 300 # 5 minutes
  memory_size      = 1024
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      TABLE_NAME             = aws_dynamodb_table.jobs.name
      BUCKET_NAME            = aws_s3_bucket.vto.bucket
      WEBSOCKET_API_ENDPOINT = "wss://${aws_apigatewayv2_api.websocket.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
    }
  }
}

# ---- DynamoDB Stream Trigger ----
resource "aws_lambda_function" "stream_trigger" {
  function_name    = "${var.project}-stream-trigger"
  filename         = data.archive_file.stream_trigger.output_path
  source_code_hash = data.archive_file.stream_trigger.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 30
  memory_size      = 128
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      STATE_MACHINE_ARN = aws_sfn_state_machine.vto.arn
    }
  }
}

resource "aws_lambda_event_source_mapping" "stream_trigger" {
  event_source_arn              = aws_dynamodb_table.jobs.stream_arn
  function_name                 = aws_lambda_function.stream_trigger.arn
  starting_position             = "LATEST"
  batch_size                    = 10
  maximum_batching_window_in_seconds = 5
  maximum_retry_attempts        = 3
  depends_on                    = [aws_iam_role_policy.stream_trigger]
}

# ---- S3 Result Handler ----
resource "aws_lambda_function" "s3_result_handler" {
  function_name    = "${var.project}-s3-result-handler"
  filename         = data.archive_file.s3_result_handler.output_path
  source_code_hash = data.archive_file.s3_result_handler.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 120
  memory_size      = 128
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      TABLE_NAME             = aws_dynamodb_table.jobs.name
      WEBSOCKET_API_ENDPOINT = "wss://${aws_apigatewayv2_api.websocket.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
    }
  }
}

resource "aws_lambda_event_source_mapping" "results_queue" {
  event_source_arn                   = aws_sqs_queue.results.arn
  function_name                      = aws_lambda_function.s3_result_handler.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  depends_on                         = [aws_iam_role_policy.s3_result_handler]
}

# ---- S3 Products Handler ----
resource "aws_lambda_function" "s3_products_handler" {
  function_name    = "${var.project}-s3-products-handler"
  filename         = data.archive_file.s3_products_handler.output_path
  source_code_hash = data.archive_file.s3_products_handler.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 120
  memory_size      = 128
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      PRODUCTS_TABLE_NAME = aws_dynamodb_table.products.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "products_queue" {
  event_source_arn                   = aws_sqs_queue.products.arn
  function_name                      = aws_lambda_function.s3_products_handler.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  depends_on                         = [aws_iam_role_policy.s3_products_handler]
}

# ---- S3 Models Handler ----
resource "aws_lambda_function" "s3_models_handler" {
  function_name    = "${var.project}-s3-models-handler"
  filename         = data.archive_file.s3_models_handler.output_path
  source_code_hash = data.archive_file.s3_models_handler.output_base64sha256
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  timeout          = 120
  memory_size      = 128
  role             = aws_iam_role.lambda_exec.arn

  environment {
    variables = {
      MODELS_TABLE_NAME = aws_dynamodb_table.models.name
    }
  }
}

resource "aws_lambda_event_source_mapping" "models_queue" {
  event_source_arn                   = aws_sqs_queue.models.arn
  function_name                      = aws_lambda_function.s3_models_handler.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  depends_on                         = [aws_iam_role_policy.s3_models_handler]
}
