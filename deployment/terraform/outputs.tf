output "bucket_name" {
  description = "S3 bucket name (upload models/ and products/ here)"
  value       = aws_s3_bucket.inpainting.bucket
}

output "websocket_api_endpoint" {
  description = "WebSocket API endpoint — connect with wscat"
  value       = "wss://${aws_apigatewayv2_api.websocket.id}.execute-api.${var.aws_region}.amazonaws.com/prod"
}

output "websocket_api_id" {
  description = "WebSocket API ID"
  value       = aws_apigatewayv2_api.websocket.id
}

output "websocket_api_key_id" {
  description = "API Key ID — run: aws apigateway get-api-key --api-key <ID> --include-value --query value --output text"
  value       = aws_api_gateway_api_key.websocket.id
}

output "jobs_table_name" {
  description = "DynamoDB jobs table"
  value       = aws_dynamodb_table.jobs.name
}

output "connections_table_name" {
  description = "DynamoDB WebSocket connections table"
  value       = aws_dynamodb_table.connections.name
}

output "products_table_name" {
  description = "DynamoDB products catalog table"
  value       = aws_dynamodb_table.products.name
}

output "models_table_name" {
  description = "DynamoDB models catalog table"
  value       = aws_dynamodb_table.models.name
}

output "state_machine_arn" {
  description = "Step Functions state machine ARN"
  value       = aws_sfn_state_machine.inpainting.arn
}

output "results_queue_url" {
  description = "SQS results queue URL"
  value       = aws_sqs_queue.results.url
}

output "products_queue_url" {
  description = "SQS products queue URL"
  value       = aws_sqs_queue.products.url
}

output "models_queue_url" {
  description = "SQS models queue URL"
  value       = aws_sqs_queue.models.url
}
