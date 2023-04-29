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

provider "cloudflare" {
  api_token = var.cf_token
}

resource "null_resource" "remove_docker" {
  provisioner "local-exec" {
    command     = "../docker-scripts/remove-images.sh"
    working_dir = path.module
    interpreter = ["/bin/bash", "-c"]
    on_failure = fail
  }
}

resource "null_resource" "build-docker" {
  provisioner "local-exec" {
    command = "./shell-scripts/login-docker-registry.sh ${var.registry_url} ${var.registry_id} ${var.registry_password}"

    working_dir = path.module
    interpreter = ["/bin/bash", "-c"]
  }

  provisioner "local-exec" {
    command = templatefile("./shell-scripts/build-push-registry.sh", {
      "REGISTRY_URL" = var.registry_url
      "ENV"          = "staging"
      "PATH"         = "../../../../pipe-timer-front"
      "FRONT_URL"    = "pipetimer.com"
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

resource "aws_security_group" "sg_pipe_timer_frontend" {
  name   = "sg_pipe_timer_frontend"
  vpc_id = data.terraform_remote_state.backend.outputs.vpc_id

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

data "terraform_remote_state" "backend" {
  backend = "local"

  config = {
    path = "../backend/terraform.tfstate"
  }
}

resource "aws_instance" "pipe-timer-frontend" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  subnet_id                   = data.terraform_remote_state.backend.outputs.subnet_1
  vpc_security_group_ids      = [aws_security_group.sg_pipe_timer_frontend.id]
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
    host        = aws_instance.pipe-timer-frontend.public_ip
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
    source      = "${path.module}/../../../../pipe-timer-front/templates/nginx.conf"
    destination = "${var.cicd_path}/nginx.conf"
  }

  provisioner "file" {
    source      = "${path.module}/../../../../pipe-timer-front/env"
    destination = "${var.cicd_path}/env"
  }

  provisioner "file" {
    source      = "${path.module}/../../../../pipe-timer-front/public"
    destination = "${var.cicd_path}/public"
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
    Name = "pipe-timer-frontend"
  }
}

# Add frontend record to DNS
resource "cloudflare_record" "pipetimer_com" {
  zone_id = var.cf_zone_id
  name    = "*.pipetimer.com"
  value   = aws_instance.pipe-timer-frontend.public_ip
  type    = "A"
  proxied = true
}

resource "cloudflare_record" "root_pipetimer_com" {
  zone_id = var.cf_zone_id
  name    = "@"
  value   = aws_instance.pipe-timer-frontend.public_ip
  type    = "A"
  proxied = true
}


