variable "aws_region" {
  description = "AWS region for the state bucket and lock table"
  type        = string
  default     = "us-east-1"
}

variable "bucket_name" {
  description = "S3 bucket name for Terraform state"
  type        = string
  default     = "baasilmirza-tfstate-us-east-1"
}

variable "lock_table" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "terraform-locks"
}

variable "tags" {
  description = "Tags applied to all bootstrap resources"
  type        = map(string)
  default = {
    Project   = "project10"
    ManagedBy = "terraform"
  }
}
