terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 3.0"
    }
  }

  required_version = ">= 1.2.0"
}

provider "cloudflare" {
  api_token = var.cf_token
}

provider "aws" {
  region = var.region
}

## Build
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
        "PATH"         = "../../../../pipe-timer-backend"
      })
    working_dir = path.module
    interpreter = ["/bin/bash", "-c"]
  }
}

# EC2 Essentials
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

## Networks
#resource "aws_vpc" "vpc" {
#  cidr_block           = var.cidr_vpc
#  enable_dns_support   = true
#  enable_dns_hostnames = true
#}
#
#resource "aws_internet_gateway" "igw" {
#  vpc_id = aws_vpc.vpc.id
#}
#
#resource "aws_subnet" "public_1" {
#  vpc_id            = aws_vpc.vpc.id
#  cidr_block        = var.cidr_subnet_1
#  availability_zone = data.aws_availability_zones.available.names[0]
#}
#
#resource "aws_subnet" "public_2" {
#  vpc_id            = aws_vpc.vpc.id
#  cidr_block        = var.cidr_subnet_2
#  availability_zone = data.aws_availability_zones.available.names[1]
#}
#
#resource "aws_route_table" "rtb_public" {
#  vpc_id = aws_vpc.vpc.id
#
#  route {
#    cidr_block = "0.0.0.0/0"
#    gateway_id = aws_internet_gateway.igw.id
#  }
#}
#
#resource "aws_route_table_association" "rta_subnet_public" {
#  subnet_id      = aws_subnet.public_1.id
#  route_table_id = aws_route_table.rtb_public.id
#}

module "staging_vpc" {
  source = "../../modules/network/vpc"
}

resource "aws_security_group" "sg_pipe_timer_backend" {
  name   = "sg_pipe_timer_backend"
  vpc_id = module.staging_vpc.vpc_id

  # SSH access from the VPC
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.http.ip.response_body}/32"]
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

# RDS(MySQL) security group 생성
resource "aws_security_group" "mysql" {
  name_prefix = "pipe-timer"
  vpc_id = module.staging_vpc.vpc_id

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
  vpc_id = module.staging_vpc.vpc_id

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
  subnet_ids = [module.staging_vpc.public_subnet_1_id, module.staging_vpc.public_subnet_2_id]
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
  subnet_ids = [module.staging_vpc.public_subnet_1_id, module.staging_vpc.public_subnet_2_id]
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
  subnet_group_name  = aws_elasticache_subnet_group.pipe-timer.name

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

data "template_file" "user_data" {
  template = file("${path.module}/../../scripts/add-ssh-web-app.yaml")
}

resource "aws_instance" "pipe-timer-backend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = module.staging_vpc.public_subnet_1_id
  vpc_security_group_ids      = [aws_security_group.sg_pipe_timer_backend.id]
  associate_public_ip_address = true
  user_data                   = data.template_file.user_data.rendered

  root_block_device {
    volume_size = 15
    volume_type = "gp2"
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("../../scripts/ssh")
    host        = aws_instance.pipe-timer-backend.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${var.cicd_path}",
      "chmod 755 ${var.cicd_path}",
    ]
  }

  provisioner "file" {
    source      = "${path.module}/shell-scripts"
    destination = var.cicd_path
  }

  provisioner "file" {
    source      = "${path.module}/../../../certs"
    destination = var.cicd_path
  }

  provisioner "file" {
    source      = "${path.module}/../../../../pipe-timer-backend/env"
    destination = "${var.cicd_path}/env"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod -R +x ${var.cicd_path}/shell-scripts/*",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "${var.cicd_path}/shell-scripts/install-docker.sh",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "${var.cicd_path}/shell-scripts/login-docker-registry.sh ${var.registry_url} ${var.registry_id} ${var.registry_password}",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "${var.cicd_path}/shell-scripts/run-docker.sh ${var.registry_url} ${var.cicd_path} ${var.env}",
    ]
  }

  depends_on = [
    aws_db_instance.mysql,
    aws_elasticache_cluster.redis
  ]

  tags = {
    Name = "pipe-timer-backend"
  }
}

# Add backend record to DNS
resource "cloudflare_record" "api_pipetimer_com" {
  zone_id = var.cf_zone_id
  name    = "api.pipetimer.com"
  value   = aws_instance.pipe-timer-backend.public_ip
  type    = "A"
  proxied = true

}
