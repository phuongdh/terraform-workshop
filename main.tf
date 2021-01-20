terraform {
  required_providers {
    aws = "~> 2.50"
  }
}

provider "aws" {
  region = "us-east-1"
}
