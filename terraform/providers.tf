terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

locals {
  region = "ap-south-1"
}

provider "aws" {
  region = local.region

  default_tags {
    tags = {
      Project   = "site-watchdog"
      ManagedBy = "terraform"
      Owner     = "gokul"
    }
  }
}
