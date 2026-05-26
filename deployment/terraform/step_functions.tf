resource "aws_cloudwatch_log_group" "step_functions" {
  name              = "/aws/stepfunctions/${var.project}-processing"
  retention_in_days = 7
}

resource "aws_sfn_state_machine" "inpainting" {
  name     = "${var.project}-processing"
  role_arn = aws_iam_role.step_functions.arn

  # X-Ray tracing enabled
  tracing_configuration {
    enabled = true
  }

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.step_functions.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  definition = jsonencode({
    Comment = "INPAINTING processing state machine"
    StartAt = "ProcessCanvas"
    States = {
      ProcessCanvas = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.canvas_processor.arn
          Payload = {
            "jobId.$"             = "$.jobId"
            "modelImageS3Url.$"   = "$.modelImageS3Url"
            "productImageS3Url.$" = "$.productImageS3Url"
            "connectionId.$"      = "$.connectionId"
          }
        }
        Retry = [{
          ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
          IntervalSeconds = 2
          MaxAttempts     = 6
          BackoffRate     = 2
        }]
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
        Next = "UpdateCompletion"
      }

      UpdateCompletion = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.jobs.name
          Key = {
            id = { "S.$" = "$.Payload.jobId" }
          }
          UpdateExpression                = "SET #status = :status, #completed_at = :completed_at"
          ExpressionAttributeNames = {
            "#status"       = "status"
            "#completed_at" = "completed_at"
          }
          ExpressionAttributeValues = {
            ":status"       = { S = "completed" }
            ":completed_at" = { "S.$" = "$$.State.EnteredTime" }
          }
        }
        End = true
      }

      HandleError = {
        Type     = "Task"
        Resource = "arn:aws:states:::dynamodb:updateItem"
        Parameters = {
          TableName = aws_dynamodb_table.jobs.name
          Key = {
            id = { "S.$" = "$$.Execution.Input.jobId" }
          }
          UpdateExpression = "SET #status = :status, #error_message = :error_message"
          ExpressionAttributeNames = {
            "#status"        = "status"
            "#error_message" = "error_message"
          }
          ExpressionAttributeValues = {
            ":status"        = { S = "error" }
            ":error_message" = { "S.$" = "$.error.Cause" }
          }
        }
        ResultPath = "$.DynamoResult"
        Next       = "SendErrorNotification"
      }

      SendErrorNotification = {
        Type     = "Task"
        Resource = "arn:aws:states:::sqs:sendMessage"
        Parameters = {
          QueueUrl = aws_sqs_queue.results.url
          MessageBody = {
            "jobId.$"        = "$$.Execution.Input.jobId"
            "connectionId.$" = "$$.Execution.Input.connectionId"
            status           = "error"
            "error.$"        = "$.error.Cause"
            eventType        = "error"
          }
        }
        End = true
      }
    }
  })

  depends_on = [
    aws_lambda_function.canvas_processor,
    aws_dynamodb_table.jobs,
    aws_sqs_queue.results,
    aws_cloudwatch_log_group.step_functions,
  ]
}
