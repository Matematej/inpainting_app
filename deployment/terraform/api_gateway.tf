# ---- WebSocket API ----
resource "aws_apigatewayv2_api" "websocket" {
  name                       = "vto-websocket-api"
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
}

# ---- CloudWatch Log Group for WebSocket access logs ----
resource "aws_cloudwatch_log_group" "websocket_access" {
  name              = "/aws/apigateway/vto-websocket-access-logs"
  retention_in_days = 30
}

# ---- Integrations ----
resource "aws_apigatewayv2_integration" "connect" {
  api_id           = aws_apigatewayv2_api.websocket.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.websocket_connect.invoke_arn
}

resource "aws_apigatewayv2_integration" "disconnect" {
  api_id           = aws_apigatewayv2_api.websocket.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.websocket_disconnect.invoke_arn
}

resource "aws_apigatewayv2_integration" "message" {
  api_id           = aws_apigatewayv2_api.websocket.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.websocket_message.invoke_arn
}

# ---- Routes ----
# $connect requires API key authentication
resource "aws_apigatewayv2_route" "connect" {
  api_id             = aws_apigatewayv2_api.websocket.id
  route_key          = "$connect"
  api_key_required   = true
  target             = "integrations/${aws_apigatewayv2_integration.connect.id}"
}

resource "aws_apigatewayv2_route" "disconnect" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect.id}"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.websocket.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.message.id}"
}

# ---- Stage ----
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.websocket.id
  name        = "prod"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.websocket_access.arn
    format = "$context.requestId $context.ip $context.requestTime $context.routeKey $context.status $context.error.message $context.error.messageString $context.integrationRequestId $context.integrationStatus $context.integrationLatency $context.responseLatency"
  }

  depends_on = [
    aws_api_gateway_account.main,
    aws_apigatewayv2_route.connect,
    aws_apigatewayv2_route.disconnect,
    aws_apigatewayv2_route.default,
  ]
}

# ---- API Key & Usage Plan (REST API v1 resources — WebSocket API keys use v1 plane) ----
# Note: WebSocket API key support uses the REST API key infrastructure
resource "aws_api_gateway_api_key" "websocket" {
  name    = "vto-websocket-api-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "websocket" {
  name = "vto-websocket-usage-plan"

  api_stages {
    api_id = aws_apigatewayv2_api.websocket.id
    stage  = aws_apigatewayv2_stage.prod.name
  }

  throttle_settings {
    burst_limit = 100
    rate_limit  = 50
  }

  depends_on = [aws_apigatewayv2_stage.prod]
}

resource "aws_api_gateway_usage_plan_key" "websocket" {
  key_id        = aws_api_gateway_api_key.websocket.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.websocket.id
}

# ---- WAF Web ACL ----
resource "aws_wafv2_web_acl" "websocket" {
  name  = "VTO-WebSocket-Waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "VTO-AWSManagedRulesCommonRuleSet"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "VTO-AWSManagedRulesCommonRuleSet"
    }
  }

  rule {
    name     = "VTO-RateLimitRule"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = 2000
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "VTO-RateLimitRule"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "VTOWebSocketWebAcl"
  }
}
