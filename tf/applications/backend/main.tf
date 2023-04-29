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

resource "null_resource" "remove_docker" {
  provisioner "local-exec" {
    command     = "../docker-scripts/remove-images.sh"
    working_dir = path.module
    interpreter = ["/bin/bash", "-c"]
    on_failure = fail
  }
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

data "terraform_remote_state" "network" {
  backend = "local"

  config = {
    path = "../../modules/network/vpc/terraform.tfstate"
  }
}

resource "aws_security_group" "sg_pipe_timer_backend" {
  name   = "sg_pipe_timer_backend"
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

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
  template = file("../../scripts/add-ssh-web-app.yaml")
}

resource "aws_instance" "pipe-timer-backend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = data.terraform_remote_state.network.outputs.public_subnet_1_id
  vpc_security_group_ids      = [aws_security_group.sg_pipe_timer_backend.id]
  associate_public_ip_address = true
  user_data                   = data.template_file.user_data.rendered

  lifecycle {
    create_before_destroy = true
  }

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
    source      = "./certs"
    destination = var.cicd_path
  }

  provisioner "file" {
    source      = "${path.module}/../common-scripts"
    destination = var.cicd_path
  }

  provisioner "file" {
    source      = "${path.module}/shell-scripts"
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
