terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

resource "null_resource" "build-docker" {
  provisioner "local-exec" {
    command     = "./shell-scripts/login-docker-registry.sh ${var.registry_url} ${var.registry_id} ${var.registry_password}"
    working_dir = path.module
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    command = templatefile("./shell-scripts/build-push-registry.sh",
      {
        "REGISTRY_URL" = var.registry_url
        "ENV"          = "staging"
        "PATH"         = "../../../pipe-timer-backend"
      })
    working_dir = path.module
    interpreter = ["/bin/bash", "-c"]
  }
}

data "http" "ip" {
  url = "https://ifconfig.me/ip"
}

data "aws_ami" "ubuntu" {
  filter {
    name   = "image-id"
    values = ["ami-0e735aba742568824"] # AMI ID 지정
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "subnet_public" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = var.cidr_subnet
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_route_table" "rtb_public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "rta_subnet_public" {
  subnet_id      = aws_subnet.subnet_public.id
  route_table_id = aws_route_table.rtb_public.id
}

resource "aws_security_group" "sg_pipe_timer_backend" {
  name   = "sg_pipe_timer_backend"
  vpc_id = aws_vpc.vpc.id

  # SSH access from the VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.http.ip.response_body}/32"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
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

data "template_file" "user_data" {
  template = file("${path.module}/../../scripts/add-ssh-web-app.yaml")
}

# RDS(MySQL) security group 생성
resource "aws_security_group" "mysql" {
  name_prefix = "pipe-timer"

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

  tags = {
    Name = "pipe-timer-db"
  }
}

# Elasticache(Redis) 생성
resource "aws_elasticache_cluster" "redis" {
  cluster_id         = "pipe-timer-redis"
  engine             = "redis"
  node_type          = "cache.t2.micro"
  num_cache_nodes    = 1
  port               = 6379
  security_group_ids = [aws_security_group.redis.id]
  availability_zone  = data.aws_availability_zones.available.names[0]

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
        "ENV_PATH"       = "${path.module}/../../../../pipe-timer-backend/env"
        "ENV"            = "staging"
      })
    working_dir = path.module
    interpreter = ["/bin/bash", "-c"]
  }
}
