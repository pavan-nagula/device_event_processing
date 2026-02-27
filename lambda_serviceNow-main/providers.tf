provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = merge(
      {
        Project     = var.project
        Environment = var.environment
        ManagedBy   = "terraform"
      },
      var.tags
    )
  }
}