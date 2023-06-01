terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.64"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.4"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

data "terraform_remote_state" "network" {
  backend = "local"

  config = {
    path = "../../modules/network/vpc/terraform.tfstate"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# RDS(MySQL) security group 생성
resource "aws_security_group" "mysql" {
  name_prefix = "pipe-timer"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port   = 3306
    to_port     = 3306
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

# Redis security group 생성
resource "aws_security_group" "redis" {
  name_prefix = "pipe-timer"
  vpc_id      = data.terraform_remote_state.network.outputs.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
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

resource "aws_db_subnet_group" "pipe-timer" {
  name       = "pipe-timer"
  subnet_ids = [
    data.terraform_remote_state.network.outputs.public_subnet_1_id,
    data.terraform_remote_state.network.outputs.public_subnet_2_id
  ]
}

# RDS(MySQL)
resource "aws_db_instance" "mysql" {
  db_name                = var.mysql_db_name
  engine                 = "mysql"
  engine_version         = "8.0.32"
  instance_class         = "db.t2.micro"
  username               = var.mysql_username
  password               = var.mysql_password
  allocated_storage      = 20
  parameter_group_name   = "default.mysql8.0"
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.mysql.id]
  availability_zone      = data.aws_availability_zones.available.names[0]
  db_subnet_group_name   = aws_db_subnet_group.pipe-timer.name

  tags = {
    Name = "pipe-timer-db"
  }
}

resource "aws_elasticache_subnet_group" "pipe-timer" {
  name       = "redis"
  subnet_ids = [
    data.terraform_remote_state.network.outputs.public_subnet_1_id,
    data.terraform_remote_state.network.outputs.public_subnet_2_id
  ]
}

resource "aws_elasticache_parameter_group" "notify" {
  name   = "notify"
  family = "redis7"

  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }
}

# Elasticache(Redis) 생성
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "pipe-timer-redis"
  engine               = "redis"
  engine_version       = "7.0"
  node_type            = "cache.t2.micro"
  num_cache_nodes      = 1
  port                 = 6379
  security_group_ids   = [aws_security_group.redis.id]
  availability_zone    = data.aws_availability_zones.available.names[0]
  subnet_group_name    = aws_elasticache_subnet_group.pipe-timer.name
  parameter_group_name = aws_elasticache_parameter_group.notify.name
  apply_immediately    = true

  tags = {
    Name = "pipe-redis"
  }
}

# env 파일 갱신
resource "null_resource" "update_env" {
  provisioner "local-exec" {
    command = templatefile("./shell-scripts/update-env.sh",
      {
        "MYSQL_HOST"     = aws_db_instance.mysql.address
        "MYSQL_DB_NAME"  = var.mysql_db_name
        "MYSQL_USERNAME" = var.mysql_username
        "MYSQL_PASSWORD" = var.mysql_password
        "REDIS_URL"      = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
        "ENV_PATH"       = "../../../../pipe-timer-backend/env"
        "ENV"            = var.env
      })
    working_dir = path.module
    interpreter = ["/bin/bash", "-c"]
  }
}
