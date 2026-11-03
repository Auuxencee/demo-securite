# Infrastructure de démonstration VOLONTAIREMENT mal configurée (scan IaC).
# Ce fichier n'est jamais appliqué : il sert uniquement à générer des alertes.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-3"
}

# Vulnérable : bucket lisible publiquement, sans chiffrement ni versioning.
resource "aws_s3_bucket" "demo" {
  bucket = "demo-template-bucket"
}

resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Vulnérable : SSH ouvert à tout Internet.
resource "aws_security_group" "demo" {
  name        = "demo-sg"
  description = "Demo security group"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Vulnérable : disque non chiffré.
resource "aws_ebs_volume" "demo" {
  availability_zone = "eu-west-3a"
  size              = 10
  encrypted         = false
}
