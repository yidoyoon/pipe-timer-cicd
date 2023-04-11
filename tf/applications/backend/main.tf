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
        "PATH"         = "../../../pipe-timer-backend"
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

resource "aws_security_group" "sg_pipe_timer_backend" {
  name = "sg_pipe_timer_backend"

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

data "template_file" "user_data" {
  template = file("${path.module}/../../scripts/add-ssh-web-app.yaml")
}

resource "aws_instance" "pipe-timer-backend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
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
    private_key = file("./backend-priv.pem")
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
      "chmod +x ${var.cicd_path}/shell-scripts/install-docker.sh",
      "${var.cicd_path}/shell-scripts/install-docker.sh",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x ${var.cicd_path}/shell-scripts/login-docker-registry.sh",
      "${var.cicd_path}/shell-scripts/login-docker-registry.sh ${var.registry_url} ${var.registry_id} ${var.registry_password}",
    ]
  }

  provisioner "remote-exec" {
    inline = [
      "docker pull ${var.registry_url}/pipe-timer-backend:staging",
      "docker run -itd -e NODE_ENV=staging --env-file ${var.cicd_path}/env/.staging.env -p 3000:3000 --name backend -v ${var.cicd_path}/certs:/certs:ro ${var.registry_url}/pipe-timer-backend:staging",
      "docker ps -a",
    ]
  }

  depends_on = [
    aws_db_instance.mysql,
    aws_elasticache_cluster.redis
  ]

  tags = {
    Name = "pipe-timer-api"
  }
}

# Add backend record to DNS
resource "cloudflare_record" "pipetimer_com" {
  zone_id = var.cf_zone_id
  name    = "api.pipetimer.com"
  value   = aws_instance.pipe-timer-backend.public_ip
  type    = "A"
}
