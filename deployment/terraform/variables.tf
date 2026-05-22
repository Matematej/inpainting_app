variable "aws_region" {
  description = "AWS region to deploy into (Nova Canvas required)"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project prefix used for all resource names"
  type        = string
  default     = "vto"
}
