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
    command = templatefile("login-docker-registry.sh",
      {
        "REGISTRY_URL"      = var.registry_url
        "REGISTRY_ID"       = var.registry_id
        "REGISTRY_PASSWORD" = var.registry_password
      })
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.module
  }

  provisioner "local-exec" {
    command = templatefile("build-push-registry.sh",
      {
        "REGISTRY_URL" = var.registry_url
        "ENV"          = "staging"
        "PATH"         = "../../pipe-timer-backend"
      })
    interpreter = ["/bin/bash", "-c"]
    working_dir = path.module
  }
}

data "http" "ip" {
  url = "https://ifconfig.me/ip"
}

#data "aws_ami" "ubuntu" {
#  filter {
#    name   = "image-id"
#    values = ["ami-0e735aba742568824"] # AMI ID 지정
#  }
#}
#
#data "aws_availability_zones" "available" {
#  state = "available"
#}
#
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
#resource "aws_subnet" "subnet_public" {
#  vpc_id            = aws_vpc.vpc.id
#  cidr_block        = var.cidr_subnet
#  availability_zone = data.aws_availability_zones.available.names[0]
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
#  subnet_id      = aws_subnet.subnet_public.id
#  route_table_id = aws_route_table.rtb_public.id
#}
#
#resource "aws_security_group" "sg_pipe_timer_backend" {
#  name   = "sg_pipe_timer_backend"
#  vpc_id = aws_vpc.vpc.id
#
#  # SSH access from the VPC
#  ingress {
#    from_port   = 22
#    to_port     = 22
#    protocol    = "tcp"
#    cidr_blocks = ["${data.http.ip.response_body}/32"]
#  }
#
#  ingress {
#    from_port   = 443
#    to_port     = 443
#    protocol    = "tcp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#
#  ingress {
#    from_port   = 3000
#    to_port     = 3000
#    protocol    = "tcp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#
#  ingress {
#    from_port   = 3306
#    to_port     = 3306
#    protocol    = "tcp"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#
#  egress {
#    from_port   = 0
#    to_port     = 0
#    protocol    = "-1"
#    cidr_blocks = ["0.0.0.0/0"]
#  }
#}
#
#data "template_file" "user_data" {
#  template = file("../scripts/add-ssh-web-app.yaml")
#}
#
#resource "aws_instance" "pipe-timer-backend" {
#  ami                         = data.aws_ami.ubuntu.id
#  instance_type               = "t2.micro"
#  subnet_id                   = aws_subnet.subnet_public.id
#  vpc_security_group_ids      = [aws_security_group.sg_pipe_timer_backend.id]
#  associate_public_ip_address = true
#  user_data                   = data.template_file.user_data.rendered
#
#  root_block_device {
#    volume_size = 15
#    volume_type = "gp2"
#  }
#
#  connection {
#    type        = "ssh"
#    user        = "ubuntu"
#    private_key = file("./tf-cloud-init")
#    host        = aws_instance.pipe-timer-backend.public_ip
#  }
#
#  provisioner "remote-exec" {
#    inline = [
#      "sudo apt update",
#      "sudo apt upgrade -y",
#      "curl -fsSL https://get.docker.com -o get-scripts.sh",
#      "sh get-scripts.sh",
#      "sudo systemctl enable scripts",
#      "sudo systemctl start scripts",
#      "sudo groupadd -f scripts",
#      "sudo usermod -aG scripts ubuntu",
#      "sudo curl -L https://github.com/docker/compose/releases/download/1.29.2/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/scripts-compose",
#      "sudo chmod +x /usr/local/bin/scripts-compose",
#      "mkdir -p /home/ubuntu/app/cicd",
#      "chmod 755 /home/ubuntu/app/cicd",
#    ]
#  }
#
#  provisioner "file" {
#    source      = "${path.cwd}/../certs"
#    destination = "/home/ubuntu/app/cicd"
#  }
#
#  provisioner "file" {
#    source      = "${path.cwd}/../../pipe-timer-backend/certs"
#    destination = "/home/ubuntu/app/cicd"
#  }
#
#  #  provisioner "local-exec" {
#  #    command = "aws ec2 reboot-instances --instance-ids ${self.id} --region ${var.region}"
#  #  }
#
#  provisioner "remote-exec" {
#    inline = [
#      "echo ${var.registry_password} | scripts login -u ${var.registry_username} --password-stdin ${var.registry_url}",
#      "scripts pull pipe-timer-backend",
#    ]
#  }
#
#  tags = {
#    Name = "pipe-timer-api"
#  }
#}
#
#output "public_ip" {
#  value = aws_instance.pipe-timer-backend.public_ip
#}
