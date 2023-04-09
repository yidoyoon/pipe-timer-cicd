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

resource "aws_instance" "pipe-timer-backend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.subnet_public.id
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
    source      = "${path.module}/../../../pipe-timer-backend/env"
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
      "docker run -it -e NODE_ENV=staging --env-file ${var.cicd_path}/env/.staging.env -p 3000:3000 --name backend -v ${var.cicd_path}/certs:/certs:ro ${var.registry_url}/pipe-timer-backend:staging",
      "docker images",
      "docker ps -a",
    ]
  }

  tags = {
    Name = "pipe-timer-api"
  }
}

output "public_ip" {
  value = aws_instance.pipe-timer-backend.public_ip
}
